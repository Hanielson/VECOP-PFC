library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library osvvm;
use osvvm.RandomPkg.all;

use work.neorv32_vpackage.all;

use std.textio.all;
use std.env.finish;

entity vecop_flex_tb is
end vecop_flex_tb;

architecture tb of vecop_flex_tb is
    component neorv32_vecop is
        port(
            clk            : in std_ulogic;
            rst            : in std_ulogic;
            vinst_in       : in std_ulogic_vector(XLEN-1 downto 0);
            scal2_in       : in std_ulogic_vector(XLEN-1 downto 0);
            scal1_in       : in std_ulogic_vector(XLEN-1 downto 0);
            vinst_valid_in : in std_ulogic;
            viq_full       : out std_ulogic;
            viq_empty      : out std_ulogic
        );
    end component neorv32_vecop;

    shared variable CYC_COUNTER : integer := 0;

    signal CLK         : std_ulogic                         := '0';
    signal RST         : std_ulogic                         := '0';
    signal VINST       : std_ulogic_vector(XLEN-1 downto 0) := (others => '0');
    signal SCAL2       : std_ulogic_vector(XLEN-1 downto 0) := (others => '0');
    signal SCAL1       : std_ulogic_vector(XLEN-1 downto 0) := (others => '0');
    signal VINST_VALID : std_ulogic                         := '0';
    signal VQ_FULL     : std_ulogic;
    signal VQ_EMPTY    : std_ulogic;

    signal vregfile_i : vregfile_t;
    signal mockmem_i  : mockmem_t;
    
    file result_logger : text open write_mode is "vecop_flex_logger.log";

    function get_opname(instruction: std_ulogic_vector) return string is
        variable opcode : std_ulogic_vector(6 downto 0) := (others => '0');
        variable funct6 : std_ulogic_vector(5 downto 0) := (others => '0');
        variable funct3 : std_ulogic_vector(2 downto 0) := (others => '0');
        variable vs1    : std_ulogic_vector(4 downto 0) := (others => '0');
    begin
        opcode := instruction(6 downto 0);
        funct6 := instruction(31 downto 26);
        funct3 := instruction(14 downto 12);
        vs1    := instruction(19 downto 15);

        case opcode is
            -- LOAD INSTRUCTION --
            when vop_load => return "VLOAD";
            
            -- STORE INSTRUCTION --
            when vop_store => return "VSTORE";

            -- ARITHMETIC INSTRUCTIONS --
            when vop_arith_cfg =>
                if (funct3 = "111") then
                    return "VCONFIG";
                else
                    case funct6 is
                        when "000000" => return "VADD";
                        when "000010" => return "VSUB";
                        when "000011" => return "VRSUB";
                        when "110000" => return "VWADDU";
                        when "110010" => return "VWSUBU";
                        when "110001" => return "VWADD";
                        when "110011" => return "VWSUB";
                        when "110100" => return "VWADDU_2SEW";
                        when "110110" => return "VWSUBU_2SEW";
                        when "110101" => return "VWADD_2SEW";
                        when "110111" => return "VWSUB_2SEW";
                        when "010010" =>
                            case vs1 is
                                when "00110"  => return "VZEXT_VF2";
                                when "00111"  => return "VSEXT_VF2";
                                when "00100"  => return "VZEXT_VF4";
                                when "00101"  => return "VSEXT_VF4";
                                when others   => report "VS1 NOT VALID" severity error; return "INVALID";
                            end case;
                        when "001001" => return "VAND";
                        when "001010" => return "VOR";
                        when "001011" => return "VXOR";
                        when "100101" => return "VSLL";
                        when "101000" => return "VSRL";
                        when "101001" => return "VSRA";
                        when "011000" => 
                            case funct3 is
                                when "000"  => return "VSE";
                                when "010"  => return "VMANDN";
                                when others => report "FUNCT3 NOT VALID" severity error; return "INVALID";
                            end case;
                        when "011001" => 
                            case funct3 is
                                when "000"  => return "VSNE";
                                when "010"  => return "VMAND";
                                when others => report "FUNCT3 NOT VALID" severity error; return "INVALID";
                            end case;
                        when "011010" => 
                            case funct3 is
                                when "000"  => return "VSLTU";
                                when "010"  => return "VMOR";
                                when others => report "FUNCT3 NOT VALID" severity error; return "INVALID";
                            end case;
                        when "011011" => 
                            case funct3 is
                                when "000"  => return "VSLT";
                                when "010"  => return "VMXOR";
                                when others => report "FUNCT3 NOT VALID" severity error; return "INVALID";
                            end case;
                        when "011100" => 
                            case funct3 is
                                when "000"  => return "VSLEU";
                                when "010"  => return "VMORN";
                                when others => report "FUNCT3 NOT VALID" severity error; return "INVALID";
                            end case;
                        when "011101" => 
                            case funct3 is
                                when "000"  => return "VSLE";
                                when "010"  => return "VMNAND";
                                when others => report "FUNCT3 NOT VALID" severity error; return "INVALID";
                            end case;
                        when "011110" => 
                            case funct3 is
                                when "011"  => return "VSGTU";
                                when "010"  => return "VMNOR";
                                when others => report "FUNCT3 NOT VALID" severity error; return "INVALID";
                            end case;
                        when "011111" => 
                            case funct3 is
                                when "011"  => return "VSGT";
                                when "010"  => return "VMXNOR";
                                when others => report "FUNCT3 NOT VALID" severity error; return "INVALID";
                            end case;
                        when "000100" => return "VMINU";
                        when "000101" => return "VMIN";
                        when "000110" => return "VMAXU";
                        when "000111" => return "VMAX";
                        when "010111" => return "VMERGE";
                        when "010000" => 
                            case vs1 is
                                when "10000" => return "VCPOP";
                                when "10001" => return "VFIRST";
                                when others  => report "VS1 NOT VALID" severity error; return "INVALID";
                            end case;
                        when "010100" => 
                            case vs1 is
                                when "00001" => return "VMSBF";
                                when "00010" => return "VMSOF";
                                when "00011" => return "VMSIF";
                                when "10000" => return "VIOTA";
                                when "10001" => return "VID";
                                when others  => report "VS1 NOT VALID" severity error; return "INVALID";
                            end case;

                        when others => report "FUNCT6 NOT VALID" severity error; return "INVALID";
                    end case;
                end if;

                -- INVALID OPCODE --
                when others => report "OPCODE NOT VALID" severity error; return "INVALID";
        end case;
    end function;

    procedure send_instruction_and_wait(signal empty : in std_ulogic; signal valid : out std_ulogic) is
    begin
        -- Send Instruction to FIFO and wait for it to complete (FIFO empty again) --
        while (empty = '0') loop
            wait for CLK_PERIOD;
        end loop;
        -- Send out the instruction to the V-IQ FIFO --
        valid <= '1';
        wait for CLK_PERIOD;
        valid <= '0';
        CYC_COUNTER := CYC_COUNTER + 1;
        wait for CLK_PERIOD;
        -- Wait until the instruction is completed by checking FIFO status --
        while (empty = '0') loop
            CYC_COUNTER := CYC_COUNTER + 1;
            wait for CLK_PERIOD;
        end loop;
    end procedure send_instruction_and_wait;

    procedure run_test(
        constant file_name : in string;
        signal vinst       : out std_ulogic_vector(XLEN-1 downto 0);
        signal scal2       : out std_ulogic_vector(XLEN-1 downto 0);
        signal scal1       : out std_ulogic_vector(XLEN-1 downto 0);
        signal viq_full    : in  std_ulogic;
        signal viq_empty   : in  std_ulogic;
        signal viq_valid   : out std_ulogic
    ) is
        file     test_file    : text;
        variable read_buffer  : line;
        variable write_buffer : line;
        variable val_type     : string(1 to 6);
        
        variable vinst_i : std_ulogic_vector(XLEN-1 downto 0) := (others => '0');
        variable scal2_i : integer := 0;
        variable scal1_i : integer := 0;

        variable SEW  : integer := 0;
        variable LMUL : integer := 0;
    begin
        file_open(test_file, file_name, read_mode);

        while not endfile(test_file) loop
            -- Read Line and extract routine --
            readline(test_file, read_buffer);
            -- If line is not empty, process it --
            if read_buffer'length > 0 then
                -- Skip comments --
                next when read_buffer.all(1) = '#';
                -- Extract value type from line --
                read(read_buffer, val_type);
                -- Parse line for instruction/scal2/scal1 values
                case val_type is
                    when "VINST=" => read(read_buffer, vinst_i);
                    when "SCAL2=" => read(read_buffer, scal2_i);
                    when "SCAL1=" => read(read_buffer, scal1_i);
                    when others => null;
                end case;
            -- If line is empty, send out the instruction --
            else
                -- Send Instruction/Scal2/Scal1 and wait for completion --
                vinst <= vinst_i;
                scal2 <= std_ulogic_vector(to_unsigned(scal2_i, scal2'length));
                scal1 <= std_ulogic_vector(to_unsigned(scal1_i, scal1'length));
                send_instruction_and_wait(viq_empty, viq_valid);

                -- If instruction is VCONFIG, get the configured value for VSEW and LMUL (kind of workaround for now... the ideal would be too get directly from HW)
                if (vinst_i(6 downto 0) = vop_arith_cfg) and (vinst_i(14 downto 12) = "111") then
                    -- VSEW --
                    case vinst_i(25 downto 23) is
                        when "000"  => SEW := 8;
                        when "001"  => SEW := 16;
                        when "010"  => SEW := 32;
                        when others => SEW := 0;
                    end case;

                    -- LMUL --
                    case vinst_i(22 downto 20) is
                        when "000"  => LMUL := 1;
                        when "001"  => LMUL := 2;
                        when "010"  => LMUL := 4;
                        when "011"  => LMUL := 8;
                        when others => LMUL := 0;
                    end case;
                end if;

                -- Write result to logger --
                write(write_buffer, get_opname(vinst_i));
                write(write_buffer, string'(","));
                write(write_buffer, integer'image(SEW));
                write(write_buffer, string'(","));
                write(write_buffer, integer'image(LMUL));
                write(write_buffer, string'(","));
                write(write_buffer, integer'image(CYC_COUNTER));
                writeline(result_logger, write_buffer);

                -- report get_opname(vinst_i) & "," & integer'image(SEW) & "," & integer'image(LMUL) & "," & integer'image(CYC_COUNTER);

                -- Re-Initialize Variable Values --
                vinst_i     := (others => '0');
                scal2_i     := 0;
                scal1_i     := 0;
                CYC_COUNTER := 0;
            end if;
        end loop;

        file_close(test_file);
    end procedure run_test;
begin

    CLK <= not CLK after 10 ns;

    vecop: entity work.neorv32_vecop port map (
        clk            => CLK,
        rst            => RST,
        vinst_in       => VINST,
        scal2_in       => SCAL2,
        scal1_in       => SCAL1,
        vinst_valid_in => VINST_VALID,
        viq_full       => VQ_FULL,
        viq_empty      => VQ_EMPTY
    );

    monitor: process(all) begin
        vregfile_i <= << signal .vecop_flex_tb.vecop.vrf.vregfile_0 : vregfile_t >>;
        mockmem_i  <= << signal .vecop_flex_tb.vecop.vmockmem.mockmem : mockmem_t >>;
    end process;

    stimuli: process
        alias vregfile : vregfile_t is << signal .vecop_flex_tb.vecop.vrf.vregfile_0 : vregfile_t >>;
        alias mockmem  : mockmem_t is << signal .vecop_flex_tb.vecop.vmockmem.mockmem : mockmem_t >>;

        variable vadd_kernel         : string(1 to 66) := "D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/kernels/vadd_kernel.txt";
        variable vadd_mask_kernel    : string(1 to 73) := "D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/kernels/vadd_masked_kernel.txt";
        variable vmem_strided_kernel : string(1 to 74) := "D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/kernels/vmem_strided_kernel.txt";
        variable vmask_kernel        : string(1 to 67) := "D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/kernels/vmask_kernel.txt";
        variable vwiden_kernel       : string(1 to 68) := "D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/kernels/vwiden_kernel.txt";

        variable simple_add   : string(1 to 65) := "D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/kernels/simple_add.txt";
        variable depend_chain : string(1 to 67) := "D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/kernels/depend_chain.txt";
        variable strided_test : string(1 to 67) := "D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/kernels/strided_test.txt";
        variable arith_chain  : string(1 to 66) := "D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/kernels/arith_chain.txt";
        variable saxpy        : string(1 to 60) := "D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/kernels/saxpy.txt";
    begin

        -- Simulation starts at negative edge of clock --
        wait for (CLK_PERIOD / 2);
        RST <= '0';
        wait for (2 * CLK_PERIOD);
        RST <= '1';
        wait for (2 * CLK_PERIOD);
        RST <= '0';
        wait for (2 * CLK_PERIOD);

        run_test(vmem_strided_kernel, VINST, SCAL2, SCAL1, VQ_FULL, VQ_EMPTY, VINST_VALID);

        -- Wait until FIFO is empty --
        while (VQ_EMPTY = '0') loop
            wait for CLK_PERIOD;
        end loop;

        file_close(result_logger);

        finish;
    end process;

end architecture tb;