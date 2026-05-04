library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library osvvm;
use osvvm.RandomPkg.all;

use work.neorv32_vpackage.all;

use std.textio.all;
use std.env.finish;

entity vecop_vmask_tb is
end vecop_vmask_tb;

architecture tb of vecop_vmask_tb is
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

    shared variable ITERATIONS  : integer := 64;
    shared variable PASS_COUNT  : integer := 0;
    shared variable FAIL_COUNT  : integer := 0;
    shared variable TOTAL_COUNT : integer := 0;

    shared variable RV : RandomPType;

    signal CLK         : std_ulogic                         := '0';
    signal RST         : std_ulogic                         := '0';
    signal VINST       : std_ulogic_vector(XLEN-1 downto 0) := (others => '0');
    signal SCAL2       : std_ulogic_vector(XLEN-1 downto 0) := (others => '0');
    signal SCAL1       : std_ulogic_vector(XLEN-1 downto 0) := (others => '0');
    signal VINST_VALID : std_ulogic                         := '0';
    signal VQ_FULL     : std_ulogic                         := '0';
    signal VQ_EMPTY    : std_ulogic                         := '0';

    shared variable avl   : integer;

    file result_logger : text open write_mode is "vecop_mask_logger.log";

    function get_opname(testop: std_ulogic_vector) return string is
    begin
        case testop is
                when valu_cpop  => return "VCPOP";
                when valu_first => return "VFIRST";
                when valu_msbf  => return "VMSBF";
                when valu_msof  => return "VMSOF";
                when valu_msif  => return "VMSIF";
                when valu_iota  => return "VIOTA";
                when valu_id    => return "VID";
                when valu_mandn => return "VMANDN";
                when valu_mand  => return "VMAND";
                when valu_mor   => return "VMOR";
                when valu_mxor  => return "VMXOR";
                when valu_morn  => return "VMORN";
                when valu_mnand => return "VMNAND";
                when valu_mnor  => return "VMNOR";
                when valu_mxnor => return "VMXNOR";
                when others     => report "INVALID";
            end case;
    end function;

    procedure send_instruction_and_wait(signal empty : in std_ulogic; signal valid : out std_ulogic) is
    begin
        -- Send Instruction to FIFO and wait for it to complete (FIFO empty again) --
        while (empty = '0') loop
            wait for 20 ns;
        end loop;
        -- Send out the instruction to the V-IQ FIFO --
        valid <= '1';
        wait for 20 ns;
        valid <= '0';
        wait for 20 ns;
        -- Wait until the instruction is completed by checking FIFO status --
        while (empty = '0') loop
            wait for 20 ns;
        end loop;
    end procedure send_instruction_and_wait;

    procedure check_result_mask(
        constant LMUL      : in integer;
        constant DEST_SEW  : in integer;
        constant DEST_LMUL : in integer;
        constant INDEX     : in integer;
        constant SEW       : in integer;
        constant VM        : in std_ulogic_vector;
        constant VL        : in integer;
        constant alu_op    : in std_ulogic_vector;
        constant vs2       : in std_ulogic_vector;
        constant vs1       : in std_ulogic_vector;
        constant vd        : in std_ulogic_vector;
        constant vmask     : in std_ulogic_vector
    ) is
        constant DEST_ELEM  : integer := (VLEN/DEST_SEW);
        variable cycle_i    : integer := 0;

        variable vs2_i : std_ulogic_vector(VLEN-1 downto 0);
        variable vs1_i : std_ulogic_vector(VLEN-1 downto 0);

        variable vlmask : std_ulogic_vector(VLEN-1 downto 0) := (others => '0');

        variable found_first : std_ulogic := '0';
        
        variable check      : expand_t((VLEN/DEST_SEW)-1 downto 0)(DEST_SEW-1 downto 0) := (others => (others => '0'));
        variable check_vlen : std_ulogic_vector(VLEN-1 downto 0)                        := (others => '0');
        variable full_check : std_ulogic_vector(VLEN-1 downto 0)                        := (others => '0');

        variable msg : string(1 to 512);
        variable line_buffer : line;
    begin
        -- If masking is enabled, apply mask to operands --
        vs2_i := (vs2 and vmask) when (VM = "1") else vs2;
        vs1_i := (vs1 and vmask) when (VM = "1") else vs1;

        -- Calculate VL Mask --
        vlmask := not std_ulogic_vector((to_unsigned(1, vlmask'length) sll VL) - 1);

        -- Calculate expected value and check --
        case alu_op is
            -- Scalar Generating Instruction --
            when valu_cpop | valu_first => null;

            -- Element Generating Instruction --
            when valu_iota | valu_id =>
                case alu_op is
                    when valu_iota => null;

                    when valu_id => null;

                    when others => null;
                end case;

            -- Mask Generating Instruction --
            when others =>
                case alu_op is
                    when valu_msbf => 
                        for ii in 0 to VLEN-1 loop
                            found_first    := '1' when (found_first = '1') or (vs2_i(ii) = '1') else '0';
                            check_vlen(ii) := '1' when (found_first = '1') else '0';
                        end loop;
                        check_vlen := not check_vlen;

                    when valu_msof =>
                        for ii in 0 to VLEN-1 loop
                            check_vlen(ii) := '1' when (found_first = '0') and (vs2_i(ii) = '1') else '0';
                            found_first    := '1' when (found_first = '1') or (vs2_i(ii) = '1') else '0';
                        end loop;

                    when valu_msif =>
                        for ii in 0 to VLEN-1 loop
                            check_vlen(ii) := '1' when (found_first = '1') else '0';
                            found_first    := '1' when (found_first = '1') or (vs2_i(ii) = '1') else '0';
                        end loop;
                        check_vlen := not check_vlen;

                    when valu_mandn => check_vlen := vs2_i and (not vs1_i);
                    when valu_mand  => check_vlen := vs2_i and vs1_i;
                    when valu_mor   => check_vlen := vs2_i or vs1_i;
                    when valu_mxor  => check_vlen := vs2_i xor vs1_i;
                    when valu_morn  => check_vlen := vs2_i or (not vs1_i);
                    when valu_mnand => check_vlen := not (vs2_i and vs1_i);
                    when valu_mnor  => check_vlen := not (vs2_i or vs1_i);
                    when valu_mxnor => check_vlen := not (vs2_i xor vs1_i);
                    when others     => check_vlen := (others => '0');
                end case;
                -- Apply VL mask to calculated output --
                check_vlen := vlmask or check_vlen;

                write(line_buffer, get_opname(alu_op));
                write(line_buffer, string'(","));
                write(line_buffer, integer'image(SEW));
                write(line_buffer, string'(","));
                write(line_buffer, integer'image(LMUL));
                write(line_buffer, string'(","));
                write(line_buffer, to_hstring(vd));
                write(line_buffer, string'(","));
                write(line_buffer, to_hstring(check_vlen));

                -- Check calculated expected value against what is read from the VRF --
                if (check_vlen = vd) then
                    report get_opname(alu_op) & "...PASSED";
                    PASS_COUNT := PASS_COUNT + 1;
                    write(line_buffer, string'(",PASSED"));
                else
                    report get_opname(alu_op) & " -- ACTUAL: " & to_hstring(vd) & " EXPECTED: " & to_hstring(check_vlen) & "...FAILED";
                    FAIL_COUNT := FAIL_COUNT + 1;
                    write(line_buffer, string'(",FAILED"));
                end if;

                writeline(result_logger, line_buffer);
        end case;
    end procedure check_result_mask;

    procedure run_mask(
        constant LMUL        : in  integer;
        constant VSEW        : in  integer;
        constant VM          : in  std_ulogic_vector;
        constant VL          : in  integer;
        constant alu_op      : in  std_ulogic_vector;
        constant vs2         : in  integer;
        constant vs1         : in  integer;
        constant vd          : in  integer;
        constant funct6      : in  std_ulogic_vector;
        constant funct3      : in  std_ulogic_vector;
        constant scalar      : in  integer;
        signal   vregfile    : in  vregfile_t;
        signal   viq_full    : in  std_ulogic;
        signal   viq_empty   : in  std_ulogic;
        signal   instr_valid : out std_ulogic
    ) is
        -- LMUL must be either [1, 2, 4, 8], so we have the vector with MAX_SIZE = 8 --
        type lmul_array_t is array (natural range <>) of std_ulogic_vector(VLEN-1 downto 0);
        variable vs2_data : std_ulogic_vector(VLEN-1 downto 0);
        variable vs1_data : std_ulogic_vector(VLEN-1 downto 0);
        variable vd_data  : lmul_array_t(0 to 7);

        variable DEST_LMUL : integer := 0;

        variable vmask : std_ulogic_vector(VLEN-1 downto 0) := (others => '1');

        variable vs2_type8  : expand_t((VLEN/8)-1 downto 0)(7 downto 0)   := (others => (others => '0'));
        variable vs1_type8  : expand_t((VLEN/8)-1 downto 0)(7 downto 0)   := (others => (others => '0'));
        variable vs2_type16 : expand_t((VLEN/16)-1 downto 0)(15 downto 0) := (others => (others => '0')); 
        variable vs1_type16 : expand_t((VLEN/16)-1 downto 0)(15 downto 0) := (others => (others => '0'));
        variable vs2_type32 : expand_t((VLEN/32)-1 downto 0)(31 downto 0) := (others => (others => '0'));
        variable vs1_type32 : expand_t((VLEN/32)-1 downto 0)(31 downto 0) := (others => (others => '0'));
    begin
        -- Read operands vs2/vs1 values before dispatching the instruction (in case of destination overlap) --
        -- TODO: there can be no overflow in register address for LMUL > 1, so when generating the instruction this needs to be respected --
        vs2_data := vregfile(vs2 mod 32);
        vs1_data := vregfile(vs1 mod 32);
        vmask    := vregfile(0);

        -- Send Instruction to FIFO and wait for it to complete (FIFO empty again) --
        -- TODO: add support for FIFO backpressure --
        send_instruction_and_wait(viq_empty, instr_valid);

        -- Classify the instructions according to Destination Effective LMUL (EMUL), if it is Widening and/or Multi-Width --
        case alu_op is
            -- Widening Operations, but with same width operands --
            when valu_iota | valu_id =>
                DEST_LMUL := LMUL;
            -- Other Operations --
            when others =>
                DEST_LMUL := 1;
        end case;

        -- Extract the destination value and calculate/check the operation results --
        for ii in 0 to DEST_LMUL-1 loop
            vd_data(ii) := vregfile(vd + ii);
        end loop;

        -- Check the result of the instruction, according to VSEW configuration and type of instruction --
        for ii in 0 to DEST_LMUL-1 loop
            if (VSEW = 8) or (VSEW = 16) or (VSEW = 32) then
                check_result_mask(LMUL, VSEW, DEST_LMUL, ii, VSEW, VM, VL, alu_op, vs2_data, vs1_data, vd_data(ii), vmask);
            else
                report "Unsupported VSEW value: " & integer'image(VSEW) severity error;
            end if;
        end loop;
    end procedure run_mask;

    procedure test_mask(
        constant LMUL        : in std_ulogic_vector(2 downto 0);
        constant VSEW        : in std_ulogic_vector(2 downto 0);
        constant VL          : in std_ulogic_vector;
        signal   vregfile    : in vregfile_t;
        signal   viq_full    : in std_ulogic;
        signal   viq_empty   : in std_ulogic;
        signal   instruction : out std_ulogic_vector(XLEN-1 downto 0);
        signal   instr_valid : out std_ulogic
    ) is
        -- List of V-ALU Operations --
        type vmask_op_t is array (natural range <>) of std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
        variable vmask_op_pool : vmask_op_t(0 to 10) := (
            -- valu_cpop, valu_first,
            valu_msbf, valu_msof, valu_msif,
            -- valu_iota, valu_id,
            valu_mandn, valu_mand, valu_mor, valu_mxor, valu_morn, valu_mnand, valu_mnor, valu_mxnor
        );
        variable opname : string(1 to 11);

        variable testop : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);

        variable funct6 : std_ulogic_vector(5 downto 0);
        variable funct3 : std_ulogic_vector(2 downto 0);
        variable vm     : std_ulogic_vector(0 downto 0);

        variable VSEW_i : integer;
        variable LMUL_i : integer;

        variable vlmax : integer;
        -- variable avl   : integer;

        variable scalar : integer;

        variable vs2 : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable vs1 : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable vd  : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

        variable vs2_value : std_ulogic_vector(VLEN-1 downto 0);
        variable vs1_value : std_ulogic_vector(VLEN-1 downto 0);
        variable vd_value  : std_ulogic_vector(VLEN-1 downto 0);
    begin

        -- DECODE VSEW values --
        case VSEW is
            -- TODO: add support for fractional VLMUL values --
            when "000"  => VSEW_i := 8;
            when "001"  => VSEW_i := 16;
            when "010"  => VSEW_i := 32;
            when others => VSEW_i := 0;
        end case;

        -- DECODE LMUL values --
        case LMUL is
            -- TODO: add support for fractional VLMUL values --
            when "000"  => LMUL_i := 1;
            when "001"  => LMUL_i := 2;
            when "010"  => LMUL_i := 4;
            when "011"  => LMUL_i := 8;
            when others => LMUL_i := 0;
        end case;

        -- Based on VSEW and LMUL, define VLMAX --
        vlmax := LMUL_i * (VLEN / VSEW_i);
        avl   := vlmax when (unsigned(VL) > to_unsigned(vlmax, VL'length)) else to_integer(unsigned(VL));
    
        -- TODO: add support for masked operations --
        vm := RV.RandSlv(0, 1, 1);

        -- TODO: add support for scalar operand --
        scalar := 0;

        for ii in vmask_op_pool'range loop
            -- TODO: some restriction needs to be set for widening operations and some others --
            --       that don't support overlap between source and destination registers      --
            if (LMUL_i >= 1) then
                vs2 := std_ulogic_vector(to_unsigned((RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1)/LMUL_i)*LMUL_i, VREF_ADDR_WIDTH));
                vs1 := std_ulogic_vector(to_unsigned((RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1)/LMUL_i)*LMUL_i, VREF_ADDR_WIDTH));
                -- TODO: for now, I'm restricting so that no destination overlap happens with source operands... This needs to be checked in hardware and in TB --
                vd  := std_ulogic_vector(to_unsigned((RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1)/LMUL_i)*LMUL_i, VREF_ADDR_WIDTH));
                while ((vd = vs2) or (vd = vs1)) loop
                    vd  := std_ulogic_vector(to_unsigned((RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1)/LMUL_i)*LMUL_i, VREF_ADDR_WIDTH));
                end loop;
            else
                vs2 := std_ulogic_vector(to_unsigned(RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1), VREF_ADDR_WIDTH));
                vs1 := std_ulogic_vector(to_unsigned(RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1), VREF_ADDR_WIDTH));
                -- TODO: for now, I'm restricting so that no destination overlap happens with source operands... This needs to be checked in hardware and in TB --
                vd  := std_ulogic_vector(to_unsigned(RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1), VREF_ADDR_WIDTH));
                while ((vd = vs2) or (vd = vs1)) loop
                    vd  := std_ulogic_vector(to_unsigned(RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1), VREF_ADDR_WIDTH));
                end loop;
            end if;

            -- Get current operation to be tested from the pool --
            testop := vmask_op_pool(ii);

            -- TODO: increase supported combination of funct6 and funct3 to test more operation types --
            -- Operation FUNCT6 / FUNCT3 Lookup Table --
            case testop is
                when valu_cpop  => funct6 := "010000"; funct3 := "010"; vs1 := "10000"; vm := vm;
                when valu_first => funct6 := "010000"; funct3 := "010"; vs1 := "10001"; vm := vm;
                when valu_msbf  => funct6 := "010100"; funct3 := "010"; vs1 := "00001"; vm := vm;
                when valu_msof  => funct6 := "010100"; funct3 := "010"; vs1 := "00010"; vm := vm;
                when valu_msif  => funct6 := "010100"; funct3 := "010"; vs1 := "00011"; vm := vm;
                when valu_iota  => funct6 := "010100"; funct3 := "010"; vs1 := "10000"; vm := vm;
                when valu_id    => funct6 := "010100"; funct3 := "010"; vs1 := "10001"; vm := vm;
                when valu_mandn => funct6 := "011000"; funct3 := "010"; vs1 := vs1    ; vm := "0";
                when valu_mand  => funct6 := "011001"; funct3 := "010"; vs1 := vs1    ; vm := "0";
                when valu_mor   => funct6 := "011010"; funct3 := "010"; vs1 := vs1    ; vm := "0";
                when valu_mxor  => funct6 := "011011"; funct3 := "010"; vs1 := vs1    ; vm := "0";
                when valu_morn  => funct6 := "011100"; funct3 := "010"; vs1 := vs1    ; vm := "0";
                when valu_mnand => funct6 := "011101"; funct3 := "010"; vs1 := vs1    ; vm := "0";
                when valu_mnor  => funct6 := "011110"; funct3 := "010"; vs1 := "00110"; vm := "0";
                when valu_mxnor => funct6 := "011111"; funct3 := "010"; vs1 := "00111"; vm := "0";
                when others     => report "Selected V-MASK Operation " & to_string(testop) & " is not supported" severity error;
            end case;

            -- Construct the instruction word --
            instruction <= funct6 & vm & vs2 & vs1 & funct3 & vd & vop_arith_cfg;

            run_mask(LMUL_i, VSEW_i, vm, avl, testop, to_integer(unsigned(vs2)), to_integer(unsigned(vs1)), to_integer(unsigned(vd)), funct6, funct3, scalar, vregfile, viq_full, viq_empty, instr_valid);
            
            wait for 80 ns;
        end loop;
    end procedure test_mask;

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

    stimuli: process
        alias vregfile : vregfile_t is << signal .vecop_vmask_tb.vecop.vrf.vregfile_0 : vregfile_t >>;
        alias mockmem  : mockmem_t is << signal .vecop_vmask_tb.vecop.vmockmem.mockmem : mockmem_t >>;

        variable VSEW   : std_ulogic_vector(2 downto 0)  := (others => '0');
        variable VLMUL  : std_ulogic_vector(2 downto 0)  := (others => '0');
        variable VTYPEI : std_ulogic_vector(10 downto 0) := (others => '0');
    begin

        -- Initialize seed for random number generator --
        RV.InitSeed(RV'instance_name);

        for ii in 0 to ITERATIONS-1 loop

            -- RESET VECOP --
            RST <= '0';
            wait for 40 ns;
            RST <= '1';
            wait for 40 ns;
            RST <= '0';
            wait for 40 ns;

            -- Randomize VSEW value to be used --
            case RV.RandInt(0, 2) is
                -- TODO: implement fractional VLMULs --
                when 0      => VSEW := "000";
                when 1      => VSEW := "001";
                when 2      => VSEW := "010";
                when others => VSEW := (others => '0');
            end case;

            -- Randomize VLMUL value to be used --
            case RV.RandInt(0, 3) is
                -- TODO: implement fractional VLMULs --
                when 0      => VLMUL := "000";
                when 1      => VLMUL := "001";
                when 2      => VLMUL := "010";
                when 3      => VLMUL := "011";
                when others => VLMUL := (others => '0');
            end case;

            -- VTYPEI -->   | VMA | VTA | VSEW | VLMUL |
            VTYPEI := "000" & "0" & "0" & VSEW & VLMUL;
            --------     | VTYPEI |  RS1    |  F3   |  RD     |  OPCODE  |
            VINST <= "0" & VTYPEI & "11111" & "111" & "11111" & "1010111";
            SCAL1 <= std_ulogic_vector(to_signed(RV.RandInt(-2147483648, 2147483647), SCAL1'length));
            send_instruction_and_wait(VQ_EMPTY, VINST_VALID);

            test_mask(VLMUL, VSEW, SCAL1, vregfile, VQ_FULL, VQ_EMPTY, VINST, VINST_VALID);

            -- Wait until FIFO is empty --
            while (VQ_EMPTY = '0') loop
                wait for 20 ns;
            end loop;
            wait for 160 ns;
        
        end loop;

        report "SUMMARY => PASSES=" & integer'image(PASS_COUNT) & " FAILS=" & integer'image(FAIL_COUNT) severity note;

        file_close(result_logger);

        finish;
    end process;

end architecture tb;