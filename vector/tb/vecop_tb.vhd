library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library osvvm;
use osvvm.RandomPkg.all;

use work.neorv32_vpackage.all;

use std.env.finish;

entity vecop_tb is
end vecop_tb;

architecture tb of vecop_tb is
    component neorv32_vecop is
        port(
            clk            : in std_ulogic;
            rst            : in std_ulogic;
            vinst_in       : in std_ulogic_vector(XLEN-1 downto 0);
            vinst_valid_in : in std_ulogic;
            viq_full       : out std_ulogic;
            viq_empty      : out std_ulogic
        );
    end component neorv32_vecop;

    signal CLK         : std_ulogic                      := '0';
    signal RST         : std_ulogic                      := '0';
    signal VINST       : std_ulogic_vector(XLEN-1 downto 0);
    signal VINST_VALID : std_ulogic;
    signal VQ_FULL     : std_ulogic;
    signal VQ_EMPTY    : std_ulogic;

    procedure send_instruction(signal full : in std_ulogic; signal valid : out std_ulogic) is
    begin
        valid <= '1';
        wait for 20 ns;
        -- Wait for a free slot in the FIFO --
        while (full = '1') loop
            wait for 20 ns;
        end loop;
        valid <= '0';
        wait for 80 ns;
    end procedure send_instruction;

begin

    CLK <= not CLK after 10 ns;

    vecop: entity work.neorv32_vecop port map (
        clk            => CLK,
        rst            => RST,
        vinst_in       => VINST,
        vinst_valid_in => VINST_VALID,
        viq_full       => VQ_FULL,
        viq_empty      => VQ_EMPTY
    );

    stimuli: process begin
        RST <= '1';
        wait for 40 ns;
        RST <= '0';

        -- VSETVLI --> VLMUL = 1 | VSEW = 8 | VTA=VMA=0 | VL=MAXVL 
        --------     |    VTYPEI     |  RS1    |  F3   |  RD     |  OPCODE  |
        VINST <= "0" & "00000000000" & "00000" & "111" & "11111" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        -- VADD --> V9 = V0 + V1
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "000000" & "0" & "00000" & "00001" & "000" & "01001" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        -- VADD --> V10 = V3 + V4
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "000000" & "0" & "00011" & "00100" & "000" & "01010" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        -- VSE --> V11 = (V9 == V10)
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "011000" & "0" & "01010" & "01001" & "000" & "01011" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------

        -- VSETVLI --> VLMUL = 1 | VSEW = 16 | VTA=VMA=0 | VL=MAXVL 
        --------     |    VTYPEI     |  RS1    |  F3   |  RD     |  OPCODE  |
        VINST <= "0" & "00000001000" & "00000" & "111" & "11111" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        -- VADD --> V13 = V0 + V1
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "000000" & "0" & "00000" & "00001" & "000" & "01101" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        -- VADD --> V14 = V3 + V4
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "000000" & "0" & "00011" & "00100" & "000" & "01110" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        -- VSE --> V15 = (V13 == V14)
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "011000" & "0" & "01110" & "01101" & "000" & "01111" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------

        -- VSETVLI --> VLMUL = 1 | VSEW = 32 | VTA=VMA=0 | VL=MAXVL 
        --------     |    VTYPEI     |  RS1    |  F3   |  RD     |  OPCODE  |
        VINST <= "0" & "00000010000" & "00000" & "111" & "11111" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        -- VADD --> V17 = V0 + V1
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "000000" & "0" & "00000" & "00001" & "000" & "10001" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        -- VADD --> V18 = V3 + V4
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "000000" & "0" & "00011" & "00100" & "000" & "10010" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        -- VSE --> V19 = (V17 == V18)
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "011000" & "0" & "10010" & "10001" & "000" & "10011" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        while (VQ_EMPTY = '0') loop
            wait for 20 ns;
        end loop;
        wait for 160 ns;

        finish;
    end process;
end architecture tb;