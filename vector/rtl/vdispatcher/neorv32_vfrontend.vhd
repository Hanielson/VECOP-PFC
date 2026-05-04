library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_frontend is
    port(
        -- Clock and Reset --
        clk : in std_ulogic;
        rst : in std_ulogic;

        -- Scalar Core Interface --
        vinst_in       : in std_ulogic_vector(XLEN-1 downto 0);
        scal2_in       : in std_ulogic_vector(XLEN-1 downto 0);
        scal1_in       : in std_ulogic_vector(XLEN-1 downto 0);
        vinst_valid_in : in std_ulogic;

        -- VI-Queue Interface --
        vinst_out       : out std_ulogic_vector(XLEN-1 downto 0);
        scal2_out       : out std_ulogic_vector(XLEN-1 downto 0);
        scal1_out       : out std_ulogic_vector(XLEN-1 downto 0);
        vinst_valid_out : out std_ulogic;

        -- Outputs to Scalar Core --
        cp_result : out std_ulogic_vector(XLEN-1 downto 0);
        cp_valid  : out std_ulogic
    );
end neorv32_frontend;

architecture neorv32_frontend_rtl of neorv32_frontend is 
begin

    -----------------------
    --- FRONTEND IS WIP ---
    -----------------------

    vinst_out       <= vinst_in;
    vinst_valid_out <= vinst_valid_in;
    scal2_out       <= scal2_in;
    scal1_out       <= scal1_in;

    cp_result <= (others => '0');
    cp_valid  <= '0';

end neorv32_frontend_rtl;