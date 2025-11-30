library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package neorv32_vpackage is

    --------------------------
    -- V-ALU Operations IDs --
    --------------------------
    constant valu_add        : std_ulogic_vector(7 downto 0) := "00000000";
    constant valu_sub        : std_ulogic_vector(7 downto 0) := "00000001";
    constant valu_rsub       : std_ulogic_vector(7 downto 0) := "00000010";

    constant valu_waddu      : std_ulogic_vector(7 downto 0) := "00000011";
    constant valu_wsubu      : std_ulogic_vector(7 downto 0) := "00000100";
    constant valu_wadd       : std_ulogic_vector(7 downto 0) := "00000101";
    constant valu_wsub       : std_ulogic_vector(7 downto 0) := "00000110";

    constant valu_waddu_2sew : std_ulogic_vector(7 downto 0) := "00000111";
    constant valu_wsubu_2sew : std_ulogic_vector(7 downto 0) := "00001000";
    constant valu_wadd_2sew  : std_ulogic_vector(7 downto 0) := "00001001";
    constant valu_wsub_2sew  : std_ulogic_vector(7 downto 0) := "00001010";

    constant valu_zext_vf2   : std_ulogic_vector(7 downto 0) := "00001011";
    constant valu_sext_vf2   : std_ulogic_vector(7 downto 0) := "00001100";
    constant valu_zext_vf4   : std_ulogic_vector(7 downto 0) := "00001101";
    constant valu_sext_vf4   : std_ulogic_vector(7 downto 0) := "00001110";
    constant valu_zext_vf8   : std_ulogic_vector(7 downto 0) := "00001111";
    constant valu_sext_vf8   : std_ulogic_vector(7 downto 0) := "00010000";

end neorv32_vpackage;
