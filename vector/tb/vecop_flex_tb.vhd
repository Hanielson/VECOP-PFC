library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use ieee.std_logic_textio.all;

use std.textio.all;

library osvvm;
use osvvm.RandomPkg.all;

use work.neorv32_vpackage.all;

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

    procedure send_instruction(signal full : in std_ulogic; signal valid : out std_ulogic) is
    begin
        valid <= '1';
        wait for 20 ns;
        -- Wait for a free slot in the FIFO --
        while (full = '1') loop
            wait for 20 ns;
        end loop;
        valid <= '0';
        wait for 40 ns;
    end procedure send_instruction;

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

    procedure run_test(
        constant file_name: in string;
        signal vinst      : out std_ulogic_vector(XLEN-1 downto 0);
        signal scal2      : out std_ulogic_vector(XLEN-1 downto 0);
        signal scal1      : out std_ulogic_vector(XLEN-1 downto 0);
        signal viq_full   : in  std_ulogic;
        signal viq_empty  : in  std_ulogic;
        signal viq_valid  : out std_ulogic
    ) is
        file     test_file   : text;
        variable line_buffer : line;
        variable val_type    : string(1 to 6);

        variable vinst_i : std_ulogic_vector(XLEN-1 downto 0) := (others => '0');
        variable scal2_i : integer := 0;
        variable scal1_i : integer := 0;
    begin
        file_open(test_file, file_name, read_mode);

        while not endfile(test_file) loop
            -- Read Line and extract routine --
            readline(test_file, line_buffer);
            -- If line is not empty, process it --
            if line_buffer'length > 0 then
                -- Skip comments --
                next when line_buffer.all(1) = '#';
                -- Extract value type from line --
                read(line_buffer, val_type);
                -- Parse line for instruction/scal2/scal1 values
                case val_type is
                    when "VINST=" => read(line_buffer, vinst_i);
                    when "SCAL2=" => read(line_buffer, scal2_i);
                    when "SCAL1=" => read(line_buffer, scal1_i);
                    when others => null;
                end case;
            -- If line is empty, send out the instruction --
            else
                -- Send Instruction/Scal2/Scal1 and wait for completion --
                vinst <= vinst_i;
                scal2 <= std_ulogic_vector(to_unsigned(scal2_i, scal2'length));
                scal1 <= std_ulogic_vector(to_unsigned(scal1_i, scal1'length));
                send_instruction_and_wait(viq_empty, viq_valid);

                -- Re-Initialize Variable Values --
                vinst_i := (others => '0');
                scal2_i := 0;
                scal1_i := 0;
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

        variable test_file : string(1 to 57) := "D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/simple_add.txt";
    begin
        RST <= '0';
        wait for 40 ns;
        RST <= '1';
        wait for 40 ns;
        RST <= '0';
        wait for 40 ns;

        run_test(test_file, VINST, SCAL2, SCAL1, VQ_FULL, VQ_EMPTY, VINST_VALID);

        while (VQ_EMPTY = '0') loop
            wait for 20 ns;
        end loop;
        wait for 160 ns;

        finish;
    end process;

end architecture tb;