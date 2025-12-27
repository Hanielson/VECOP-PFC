library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package neorv32_vpackage is

    --------------------------
    -- V-ALU Operations IDs --
    --------------------------
    constant VALU_ID_SIZE    : natural := 8;

    constant valu_add        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"00";
    constant valu_sub        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"01";
    constant valu_rsub       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"02";

    constant valu_waddu      : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"03";
    constant valu_wsubu      : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"04";
    constant valu_wadd       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"05";
    constant valu_wsub       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"06";

    constant valu_waddu_2sew : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"07";
    constant valu_wsubu_2sew : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"08";
    constant valu_wadd_2sew  : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"09";
    constant valu_wsub_2sew  : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"0A";

    constant valu_zext_vf2   : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"0B";
    constant valu_sext_vf2   : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"0C";
    constant valu_zext_vf4   : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"0D";
    constant valu_sext_vf4   : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"0E";
    constant valu_zext_vf8   : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"0F";
    constant valu_sext_vf8   : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"10";

    constant valu_and        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"11";
    constant valu_or         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"12";
    constant valu_xor        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"13";

    constant valu_sll        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"14";
    constant valu_srl        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"15";
    constant valu_sra        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"16";

    constant valu_seq        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"17";
    constant valu_sne        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"18";
    constant valu_sltu       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"19";
    constant valu_slt        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"1A";
    constant valu_sleu       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"1B";
    constant valu_sle        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"1C";
    constant valu_sgtu       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"1D";
    constant valu_sgt        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"1E";
    constant valu_sgeu       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"1F";
    constant valu_sge        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"20";

    constant valu_adc        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"21";
    constant valu_madc       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"22";
    constant valu_sbc        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"23";
    constant valu_msbc       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"24";

    constant valu_minu       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"25";
    constant valu_min        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"26";
    constant valu_maxu       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"27";
    constant valu_max        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"28";

    constant valu_merge      : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"29";

    constant valu_nsrl       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"2A";
    constant valu_nsra       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := x"2B";

end neorv32_vpackage;