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

        -- VADD --> V2 = V0 + V1
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "000000" & "0" & "00000" & "00001" & "000" & "00010" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 80 ns;

        -- VADD --> V5 = V3 + V4
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "000000" & "0" & "00011" & "00100" & "000" & "00101" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 80 ns;

        -- VSEQ --> V0 = (V2 == V5)
        --------    F6    | VM  |   VS2   |   VS1   |  F3   |  VD/RD  |  OPCODE  |
        VINST <= "011000" & "0" & "00010" & "00101" & "000" & "00000" & "1010111";
        VINST_VALID <= '1';
        wait for 20 ns;
        VINST_VALID <= '0';
        wait for 80 ns;

        finish;
    end process;

end tb;