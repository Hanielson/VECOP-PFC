library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

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

    type expand_t is array (natural range <>) of std_ulogic_vector;
    signal op2_type8   : expand_t(31 downto 0)(7 downto 0) := (others => (others => '0'));
    signal op1_type8   : expand_t(31 downto 0)(7 downto 0) := (others => (others => '0'));
    signal out_type8   : expand_t(31 downto 0)(7 downto 0) := (others => (others => '0'));
    signal check_type8 : expand_t(31 downto 0)(7 downto 0) := (others => (others => '0'));
    
    signal op2_type16   : expand_t(15 downto 0)(15 downto 0) := (others => (others => '0')); 
    signal op1_type16   : expand_t(15 downto 0)(15 downto 0) := (others => (others => '0'));
    signal out_type16   : expand_t(15 downto 0)(15 downto 0) := (others => (others => '0'));
    signal check_type16 : expand_t(15 downto 0)(15 downto 0) := (others => (others => '0'));
    
    signal op2_type32   : expand_t(7 downto 0)(31 downto 0) := (others => (others => '0'));
    signal op1_type32   : expand_t(7 downto 0)(31 downto 0) := (others => (others => '0'));
    signal out_type32   : expand_t(7 downto 0)(31 downto 0) := (others => (others => '0'));
    signal check_type32 : expand_t(7 downto 0)(31 downto 0) := (others => (others => '0'));

    procedure test_op(constant op_i    : in  std_ulogic_vector;
                      signal   op_o    : out std_ulogic_vector;
                      signal   vsew_o  : out std_ulogic_vector;
                      signal   valid_o : out std_ulogic;
                      signal   rst_o   : out std_ulogic) is
    begin
        op_o <= op_i;
        valid_o <= '1';
        
        -- SEW = 8 bits --
        vsew_o <= "000";
        rst_o <= '1';
        wait for 20 ns;
        rst_o <= '0';
        if check_type8 /= out_type8 then
            report "SEW = 8 || INSTRUCTION " & to_hstring(op_i) & " || MISMATCH: " severity error;
            for ii in check_type8'range loop
                if check_type8(ii) /= out_type8(ii) then
                    report "INDEX " & integer'image(ii) & " | EXPECTED " & to_hstring(check_type8(ii)) & " | ACTUAL " & to_hstring(out_type8(ii));
                end if;
            end loop;
        else
            report "SEW = 8 || INSTRUCTION " & to_hstring(op_i) & " || MATCH";
        end if;
        wait for 80 ns;

        -- SEW = 16 bits --
        vsew_o <= "001";
        rst_o <= '1';
        wait for 20 ns;
        rst_o <= '0';
        if check_type16 /= out_type16 then
            report "SEW = 16 || INSTRUCTION " & to_hstring(op_i) & " || MISMATCH: " severity error;
            for ii in check_type16'range loop
                if check_type16(ii) /= out_type16(ii) then
                    report "INDEX " & integer'image(ii) & " | EXPECTED " & to_hstring(check_type16(ii)) & " | ACTUAL " & to_hstring(out_type16(ii));
                end if;
            end loop;
        else
            report "SEW = 16 || INSTRUCTION " & to_hstring(op_i) & " || MATCH";
        end if;
        wait for 80 ns;

        -- SEW = 32 bits --
        vsew_o <= "010";
        rst_o <= '1';
        wait for 20 ns;
        rst_o <= '0';
        if check_type32 /= out_type32 then
            report "SEW = 32 || INSTRUCTION " & to_hstring(op_i) & " || MISMATCH: " severity error;
            for ii in check_type32'range loop
                if check_type32(ii) /= out_type32(ii) then
                    report "INDEX " & integer'image(ii) & " | EXPECTED " & to_hstring(check_type32(ii)) & " | ACTUAL " & to_hstring(out_type32(ii));
                end if;
            end loop;
        else
            report "SEW = 32 || INSTRUCTION " & to_hstring(op_i) & " || MATCH";
        end if;
        wait for 80 ns;
        
        valid_o <= '0';
    end procedure test_op;

    procedure check_output(constant op_i   : in  std_ulogic_vector;
                           signal   check  : out expand_t;
                           signal   opA    : in  expand_t;
                           signal   opB    : in  expand_t) is
        constant ELEM : integer := opA'length;
        constant SEW  : integer := opA(opA'low)'length;
        variable shift_bits : integer;
    begin
        assert (opA'length = opB'length) and (check'length = opB'length) report "ERROR - check_output operands/check signals do not have the same size" severity error;

        shift_bits := integer(ceil(log2(real(SEW)))) - 1;
        for ii in 0 to ELEM-1 loop
            check(ii) <= (check(ii)'range => '0');
            case ALU_OP is
                when valu_add        => check(ii) <= std_ulogic_vector(unsigned(opA(ii)) + unsigned(opB(ii)));
                when valu_sub        => check(ii) <= std_ulogic_vector(unsigned(opA(ii)) - unsigned(opB(ii)));
                when valu_rsub       => check(ii) <= std_ulogic_vector(unsigned(opB(ii)) - unsigned(opA(ii)));
                when valu_waddu      => check(ii) <= (check(ii)'range => '0');
                when valu_wsubu      => check(ii) <= (check(ii)'range => '0');
                when valu_wadd       => check(ii) <= (check(ii)'range => '0');
                when valu_wsub       => check(ii) <= (check(ii)'range => '0');
                when valu_waddu_2sew => check(ii) <= (check(ii)'range => '0');
                when valu_wsubu_2sew => check(ii) <= (check(ii)'range => '0');
                when valu_wadd_2sew  => check(ii) <= (check(ii)'range => '0');
                when valu_wsub_2sew  => check(ii) <= (check(ii)'range => '0');
                when valu_zext_vf2   => check(ii) <= (check(ii)'range => '0');
                when valu_sext_vf2   => check(ii) <= (check(ii)'range => '0');
                when valu_zext_vf4   => check(ii) <= (check(ii)'range => '0');
                when valu_sext_vf4   => check(ii) <= (check(ii)'range => '0');
                when valu_and        => check(ii) <= (opA(ii) and opB(ii));
                when valu_or         => check(ii) <= (opA(ii) or  opB(ii));
                when valu_xor        => check(ii) <= (opA(ii) xor opB(ii));
                when valu_sll        => check(ii) <= std_ulogic_vector(shift_left(unsigned(opA(ii)), to_integer(unsigned(opB(ii)(shift_bits downto 0)))));
                when valu_srl        => check(ii) <= std_ulogic_vector(shift_right(unsigned(opA(ii)), to_integer(unsigned(opB(ii)(shift_bits downto 0)))));
                when valu_sra        => check(ii) <= std_ulogic_vector(shift_right(signed(opA(ii)), to_integer(unsigned(opB(ii)(shift_bits downto 0)))));
                when valu_seq        => check(ii/SEW)(ii mod SEW) <= '1' when (opA(ii)  = opB(ii)) else '0';
                when valu_sne        => check(ii/SEW)(ii mod SEW) <= '1' when (opA(ii) /= opB(ii)) else '0';
                when valu_sltu       => check(ii/SEW)(ii mod SEW) <= '1' when (unsigned(opA(ii)) < unsigned(opB(ii))) else '0';
                when valu_slt        => check(ii/SEW)(ii mod SEW) <= '1' when (signed(opA(ii)) < signed(opB(ii))) else '0';
                when valu_sleu       => check(ii/SEW)(ii mod SEW) <= '1' when (unsigned(opA(ii)) <= unsigned(opB(ii))) else '0';
                when valu_sle        => check(ii/SEW)(ii mod SEW) <= '1' when (signed(opA(ii)) <= signed(opB(ii))) else '0';
                when valu_sgtu       => check(ii/SEW)(ii mod SEW) <= '1' when (unsigned(opA(ii)) > unsigned(opB(ii))) else '0';
                when valu_sgt        => check(ii/SEW)(ii mod SEW) <= '1' when (signed(opA(ii)) > signed(opB(ii))) else '0';
                when valu_sgeu       => check(ii/SEW)(ii mod SEW) <= '1' when (unsigned(opA(ii)) >= unsigned(opB(ii))) else '0';
                when valu_sge        => check(ii/SEW)(ii mod SEW) <= '1' when (signed(opA(ii)) >= signed(opB(ii))) else '0';
                when others          => check(ii) <= (check(ii)'range => '0');
            end case;
        end loop; 
    end procedure check_output;

begin

    process(all) begin
        for ii in 0 to 31 loop
            op2_type8(ii)   <= OP2(8*ii+7 downto 8*ii);
            op1_type8(ii)   <= OP1(8*ii+7 downto 8*ii);
            out_type8(ii)   <= ALU_OUT(8*ii+7 downto 8*ii);
            check_output(ALU_OP, check_type8, op2_type8, op1_type8);
        end loop;

        for ii in 0 to 15 loop
            op2_type16(ii) <= OP2(16*ii+15 downto 16*ii);
            op1_type16(ii) <= OP1(16*ii+15 downto 16*ii);
            out_type16(ii) <= ALU_OUT(16*ii+15 downto 16*ii);
            check_output(ALU_OP, check_type16, op2_type16, op1_type16);
        end loop;

        for ii in 0 to 7 loop
            op2_type32(ii) <= OP2(32*ii+31 downto 32*ii);
            op1_type32(ii) <= OP1(32*ii+31 downto 32*ii);
            out_type32(ii) <= ALU_OUT(32*ii+31 downto 32*ii);
            check_output(ALU_OP, check_type32, op2_type32, op1_type32);
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
        -- test_op(valu_waddu,      ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_wsubu,      ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_wadd,       ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_wsub,       ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_waddu_2sew, ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_wsubu_2sew, ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_wadd_2sew,  ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_wsub_2sew,  ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_zext_vf2,   ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_sext_vf2,   ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_zext_vf4,   ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_sext_vf4,   ALU_OP, VSEW, VALID, RST);
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
        -- test_op(valu_adc,        ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_madc,       ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_sbc,        ALU_OP, VSEW, VALID, RST);
        -- test_op(valu_msbc,       ALU_OP, VSEW, VALID, RST);

        finish;
    end process;

end tb;