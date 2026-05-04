library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library osvvm;
use osvvm.RandomPkg.all;

use work.neorv32_vpackage.all;

use std.env.finish;

entity vecop_sld_tb is
end vecop_sld_tb;

architecture tb of vecop_sld_tb is
    component neorv32_vecop is
        port(
            clk         : in std_ulogic;
            rst         : in std_ulogic;
            vinst       : in std_ulogic_vector(XLEN-1 downto 0);
            vinst_valid : in std_ulogic
        );
    end component neorv32_vecop;

    signal CLK         : std_ulogic                      := '0';
    signal RST         : std_ulogic                      := '0';
    signal VINST       : std_ulogic_vector(XLEN-1 downto 0);
    signal VINST_VALID : std_ulogic;
begin
    CLK <= not CLK after 10 ns;

    vecop: entity work.neorv32_vecop port map (
        clk         => CLK,
        rst         => RST,
        vinst       => VINST,
        vinst_valid => VINST_VALID
    );

    stimuli: process begin
        RST <= '1';
        wait for 40 ns;
        RST <= '0';
        -- VSETVLI --> VLMUL = 1 | VSEW = 8 | VTA=VMA=0 | VL=MAXVL 
        --------     |    VTYPEI     |  RS1    |  F3   |  RD     |  OPCODE  |
        VINST <= "0" & "00000000000" & "00000" & "111" & "11111" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 80 ns;
        -- VSLIDEUP --> V0[i+5] = V24[i]
        --------    F6    | VM  |   VS2   |   IMM   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "001110" & "0" & "11000" & "00101" & "011" & "00000" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 600 ns;
        -- VSLIDEDN --> V2[i] = V24[i+10]
        --------    F6    | VM  |   VS2   |   IMM   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "001111" & "0" & "11000" & "01010" & "011" & "00010" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 600 ns;

        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------

        -- VSETVLI --> VLMUL = 2 | VSEW = 8 | VTA=VMA=0 | VL=MAXVL 
        --------     |    VTYPEI     |  RS1    |  F3   |  RD     |  OPCODE  |
        VINST <= "0" & "00000000001" & "00000" & "111" & "11111" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 80 ns;
        -- VSLIDEUP --> V4[i+5] = V24[i]
        --------    F6    | VM  |   VS2   |   IMM   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "001110" & "0" & "11000" & "00101" & "011" & "00100" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 600 ns;
        -- VSLIDEDN --> V8[i] = V24[i+10]
        --------    F6    | VM  |   VS2   |   IMM   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "001111" & "0" & "11000" & "01010" & "011" & "01000" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 600 ns;

        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------

        -- VSETVLI --> VLMUL = 4 | VSEW = 8 | VTA=VMA=0 | VL=MAXVL 
        --------     |    VTYPEI     |  RS1    |  F3   |  RD     |  OPCODE  |
        VINST <= "0" & "00000000011" & "00000" & "111" & "11111" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 80 ns;
        -- VSLIDEUP --> V10[i+5] = V24[i]
        --------    F6    | VM  |   VS2   |   IMM   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "001110" & "0" & "11000" & "00101" & "011" & "01010" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 600 ns;
        -- VSLIDEDN --> V18[i] = V24[i+10]
        --------    F6    | VM  |   VS2   |   IMM   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "001111" & "0" & "11000" & "01010" & "011" & "10010" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 600 ns;

        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------

        -- VSETVLI --> VLMUL = 1 | VSEW = 16 | VTA=VMA=0 | VL=MAXVL 
        --------     |    VTYPEI     |  RS1    |  F3   |  RD     |  OPCODE  |
        -- VINST <= "0" & "00000001000" & "00000" & "111" & "11111" & "1010111";

        -- VSETVLI --> VLMUL = 1 | VSEW = 32 | VTA=VMA=0 | VL=MAXVL 
        --------     |    VTYPEI     |  RS1    |  F3   |  RD     |  OPCODE  |
        -- VINST <= "0" & "00000010000" & "00000" & "111" & "11111" & "1010111";

        finish;
    end process;
end architecture tb;