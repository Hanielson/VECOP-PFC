library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package neorv32_vpackage is

    --------------------------
    -- V-ALU Operations IDs --
    --------------------------
    constant VALU_ID_SIZE     : natural := 8;
    constant valu_add         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00000000";
    constant valu_sub         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00000001";
    constant valu_rsub        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00000010";

    constant valu_waddu       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00000011";
    constant valu_wsubu       : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00000100";
    constant valu_wadd        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00000101";
    constant valu_wsub        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00000110";

    constant valu_waddu_2sew  : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00000111";
    constant valu_wsubu_2sew  : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00001000";
    constant valu_wadd_2sew   : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00001001";
    constant valu_wsub_2sew   : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00001010";

    constant valu_zext_vf2    : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00001011";
    constant valu_sext_vf2    : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00001100";
    constant valu_zext_vf4    : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00001101";
    constant valu_sext_vf4    : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00001110";
    constant valu_zext_vf8    : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00001111";
    constant valu_sext_vf8    : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00010000";

    constant valu_and         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00010001";
    constant valu_or          : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00010010";
    constant valu_xor         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00010011";

    constant valu_sll         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00010100";
    constant valu_srl         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00010101";
    constant valu_sra         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00010110";

    constant valu_seq         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00010111";
    constant valu_sne         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00011000";
    constant valu_sltu        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00011001";
    constant valu_slt         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00011010";
    constant valu_sleu        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00011011";
    constant valu_sle         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00011100";
    constant valu_sgtu        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00011101";
    constant valu_sgt         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00011110";
    constant valu_sgeu        : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00011111";
    constant valu_sge         : std_ulogic_vector(VALU_ID_SIZE-1 downto 0) := "00100000";

end neorv32_vpackage;