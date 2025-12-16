library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.neorv32_vpackage.all;

use std.env.finish;

entity valu_tb is
end valu_tb;

architecture tb of valu_tb is

    component neorv32_valu is
        generic(
            VLEN : natural := 256;
            XLEN : natural := 32
        );
        port(
            clk     : in std_ulogic;
            rst     : in std_ulogic;
            valid   : in std_ulogic;
            op2     : in std_ulogic_vector(VLEN-1 downto 0);
            op1     : in std_ulogic_vector(VLEN-1 downto 0);
            op0     : in std_ulogic_vector(VLEN-1 downto 0);
            alu_op  : in std_ulogic_vector(7 downto 0);
            vmask   : in std_ulogic_vector(XLEN-1 downto 0);
            vsew    : in std_ulogic_vector(2 downto 0);
            alu_out : out std_ulogic_vector(VLEN-1 downto 0)
        );
    end component neorv32_valu;

    signal CLK     : std_ulogic                      := '0';
    signal RST     : std_ulogic                      := '0';
    signal VALID   : std_ulogic                      := '0';
    signal VSEW    : std_ulogic_vector(2 downto 0)   := (others => '0');
    signal OP2     : std_ulogic_vector(255 downto 0) := (others => '0');
    signal OP1     : std_ulogic_vector(255 downto 0) := (others => '0');
    signal OP0     : std_ulogic_vector(255 downto 0) := (others => '0');
    signal ALU_OP  : std_ulogic_vector(7 downto 0)   := (others => '0');
    signal ALU_OUT : std_ulogic_vector(255 downto 0) := (others => '0');

    type type_8 is array (31 downto 0) of std_ulogic_vector(7 downto 0);
    signal op2_type8 : type_8;
    signal op1_type8 : type_8;
    signal out_type8 : type_8;
    
    type type_16 is array (15 downto 0) of std_ulogic_vector(15 downto 0);
    signal op2_type16 : type_16;
    signal op1_type16 : type_16;
    signal out_type16 : type_16;
    
    type type_32 is array (7 downto 0)  of std_ulogic_vector(31 downto 0);
    signal op2_type32 : type_32;
    signal op1_type32 : type_32;
    signal out_type32 : type_32;

    procedure test_op(constant op_i    : in  std_ulogic_vector;
                      signal   op_o    : out std_ulogic_vector;
                      signal   vsew_o  : out std_ulogic_vector;
                      signal   valid_o : out std_ulogic;
                      signal   rst_o   : out std_ulogic) is
    begin
        op_o <= op_i;
        valid_o <= '1';
        
        vsew_o <= "000";
        rst_o <= '1';
        wait for 20 ns;
        rst_o <= '0';
        wait for 80 ns;

        vsew_o <= "001";
        rst_o <= '1';
        wait for 20 ns;
        rst_o <= '0';
        wait for 80 ns;

        vsew_o <= "010";
        rst_o <= '1';
        wait for 20 ns;
        rst_o <= '0';
        wait for 80 ns;
        
        valid_o <= '0';
    end procedure test_op;

begin

    process(all) begin
        for ii in 0 to 31 loop
            op2_type8(ii) <= OP2(8*ii+7 downto 8*ii);
            op1_type8(ii) <= OP1(8*ii+7 downto 8*ii);
            out_type8(ii) <= ALU_OUT(8*ii+7 downto 8*ii);
        end loop;

        for ii in 0 to 15 loop
            op2_type16(ii) <= OP2(16*ii+15 downto 16*ii);
            op1_type16(ii) <= OP1(16*ii+15 downto 16*ii);
            out_type16(ii) <= ALU_OUT(16*ii+15 downto 16*ii);
        end loop;

        for ii in 0 to 7 loop
            op2_type32(ii) <= OP2(32*ii+31 downto 32*ii);
            op1_type32(ii) <= OP1(32*ii+31 downto 32*ii);
            out_type32(ii) <= ALU_OUT(32*ii+31 downto 32*ii);
        end loop;
    end process;

    valu: entity work.neorv32_valu port map(
        clk     => CLK,
        rst     => RST,
        valid   => VALID,
        op2     => OP2,
        op1     => OP1,
        op0     => OP0,
        alu_op  => ALU_OP,
        vmask   => (others => '0'),
        vsew    => VSEW,
        alu_out => ALU_OUT
    );

    CLK <= not CLK after 10 ns;

    stimuli: process
    begin
        
        OP2 <= x"89D78A2589B24E1E1B68CFAF954C2180511B495314841AF1E2572911A6A622F8";
        OP1 <= x"E4C398F170669F2452AA55724D4281BD6D08E715B65CC010B9E163CECAFE1707";
        
        test_op(valu_add,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_sub,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_rsub,       ALU_OP, VSEW, VALID, RST);
        test_op(valu_waddu,      ALU_OP, VSEW, VALID, RST);
        test_op(valu_wsubu,      ALU_OP, VSEW, VALID, RST);
        test_op(valu_wadd,       ALU_OP, VSEW, VALID, RST);
        test_op(valu_wsub,       ALU_OP, VSEW, VALID, RST);
        test_op(valu_waddu_2sew, ALU_OP, VSEW, VALID, RST);
        test_op(valu_wsubu_2sew, ALU_OP, VSEW, VALID, RST);
        test_op(valu_wadd_2sew,  ALU_OP, VSEW, VALID, RST);
        test_op(valu_wsub_2sew,  ALU_OP, VSEW, VALID, RST);
        test_op(valu_zext_vf2,   ALU_OP, VSEW, VALID, RST);
        test_op(valu_sext_vf2,   ALU_OP, VSEW, VALID, RST);
        test_op(valu_zext_vf4,   ALU_OP, VSEW, VALID, RST);
        test_op(valu_sext_vf4,   ALU_OP, VSEW, VALID, RST);
        test_op(valu_zext_vf8,   ALU_OP, VSEW, VALID, RST);
        test_op(valu_sext_vf8,   ALU_OP, VSEW, VALID, RST);
        test_op(valu_and,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_or,         ALU_OP, VSEW, VALID, RST);
        test_op(valu_xor,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_sll,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_srl,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_sra,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_seq,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_sne,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_sltu,       ALU_OP, VSEW, VALID, RST);
        test_op(valu_slt,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_sleu,       ALU_OP, VSEW, VALID, RST);
        test_op(valu_sle,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_sgtu,       ALU_OP, VSEW, VALID, RST);
        test_op(valu_sgt,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_sgeu,       ALU_OP, VSEW, VALID, RST);
        test_op(valu_sge,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_adc,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_madc,       ALU_OP, VSEW, VALID, RST);
        test_op(valu_sbc,        ALU_OP, VSEW, VALID, RST);
        test_op(valu_msbc,       ALU_OP, VSEW, VALID, RST);

        finish;

    end process;

end tb;