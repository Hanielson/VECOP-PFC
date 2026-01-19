library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library osvvm;
use osvvm.RandomPkg.all;

use work.neorv32_vpackage.all;

use std.env.finish;

entity valu_tb is
end valu_tb;

architecture tb of valu_tb is
    component neorv32_valu is
        port(
            clk      : in std_ulogic;
            rst      : in std_ulogic;
            alu_op   : in std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
            valid    : in std_ulogic;
            op2      : in std_ulogic_vector(VLEN-1 downto 0);
            op1      : in std_ulogic_vector(VLEN-1 downto 0);
            op0      : in std_ulogic_vector(VLEN-1 downto 0);
            vmask    : in std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
            vsew     : in std_ulogic_vector(2 downto 0);
            alu_out  : out std_ulogic_vector(VLEN-1 downto 0);
            alu_done : out std_ulogic
        );
    end component neorv32_valu;

    signal CLK      : std_ulogic                                  := '1';
    signal RST      : std_ulogic                                  := '0';
    signal VALID    : std_ulogic                                  := '0';
    signal CYC      : integer                                     := 0;
    signal VSEW     : std_ulogic_vector(2 downto 0)               := (others => '0');
    signal OP2      : std_ulogic_vector(VLEN-1 downto 0)          := (others => '0');
    signal OP1      : std_ulogic_vector(VLEN-1 downto 0)          := (others => '0');
    signal OP0      : std_ulogic_vector(VLEN-1 downto 0)          := (others => '0');
    signal VMASK    : std_ulogic_vector(VALU_CHUNK_W-1 downto 0)  := (others => '0');
    signal ALU_OP   : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := (others => '0');
    signal ALU_OUT  : std_ulogic_vector(VLEN-1 downto 0)          := (others => '0');
    signal ALU_DONE : std_ulogic                                  := '0';

    type test_info_t is record
        TEST_COUNT : integer;
        TEST_PASS  : integer;
        TEST_FAIL  : integer;
    end record;
    signal ITER_INFO  : test_info_t := (TEST_COUNT => 0, TEST_PASS => 0, TEST_FAIL => 0);
    signal TOTAL_INFO : test_info_t := (TEST_COUNT => 0, TEST_PASS => 0, TEST_FAIL => 0);

    type expand_t is array (natural range <>) of std_ulogic_vector;
    signal op2_type8    : expand_t((VLEN/8)-1 downto 0)(7 downto 0)   := (others => (others => '0'));
    signal op1_type8    : expand_t((VLEN/8)-1 downto 0)(7 downto 0)   := (others => (others => '0'));
    signal out_type8    : expand_t((VLEN/8)-1 downto 0)(7 downto 0)   := (others => (others => '0'));
    signal check_type8  : expand_t((VLEN/8)-1 downto 0)(7 downto 0)   := (others => (others => '0'));
    signal op2_type16   : expand_t((VLEN/16)-1 downto 0)(15 downto 0) := (others => (others => '0')); 
    signal op1_type16   : expand_t((VLEN/16)-1 downto 0)(15 downto 0) := (others => (others => '0'));
    signal out_type16   : expand_t((VLEN/16)-1 downto 0)(15 downto 0) := (others => (others => '0'));
    signal check_type16 : expand_t((VLEN/16)-1 downto 0)(15 downto 0) := (others => (others => '0'));
    signal op2_type32   : expand_t((VLEN/32)-1 downto 0)(31 downto 0) := (others => (others => '0'));
    signal op1_type32   : expand_t((VLEN/32)-1 downto 0)(31 downto 0) := (others => (others => '0'));
    signal out_type32   : expand_t((VLEN/32)-1 downto 0)(31 downto 0) := (others => (others => '0'));
    signal check_type32 : expand_t((VLEN/32)-1 downto 0)(31 downto 0) := (others => (others => '0'));
    signal ZERO_type4   : expand_t((VLEN/4)-1 downto 0)(3 downto 0)   := (others => (others => '0'));
    signal ZERO_type64  : expand_t((VLEN/64)-1 downto 0)(63 downto 0) := (others => (others => '0'));

    procedure test_op(constant op_i    : in  std_ulogic_vector;
                      signal   cycle   : out integer;
                      signal   op_o    : out std_ulogic_vector;
                      signal   vsew_o  : out std_ulogic_vector;
                      signal   valid_o : out std_ulogic;
                      signal   done_o  : in  std_ulogic;
                      signal   tinfo   : out test_info_t) is
    begin        
        op_o <= op_i;

        -- SEW = 8 bits --
        vsew_o <= "000";
        cycle <= 0;
        for cyc in 0 to 3 loop
            tinfo.TEST_COUNT <= tinfo.TEST_COUNT + 1;
            
            valid_o <= '0';
            wait for 20 ns;
            valid_o <= '1';

            while (done_o = '0') loop
                wait for 20 ns;
            end loop;

            if check_type8 /= out_type8 then
                tinfo.TEST_FAIL <= tinfo.TEST_FAIL + 1;
                report "SEW = 8 || CYC = " & to_string(cyc) & " || INSTRUCTION " & to_hstring(op_i) & " || MISMATCH: " severity error;
                for ii in check_type8'range loop
                    if check_type8(ii) /= out_type8(ii) then
                        report "INDEX " & integer'image(ii) & " | EXPECTED " & to_hstring(check_type8(ii)) & " | ACTUAL " & to_hstring(out_type8(ii));
                    end if;
                end loop;
            else
                tinfo.TEST_PASS <= tinfo.TEST_PASS + 1;
            end if;
            wait for 20 ns;

            cycle <= cycle + 1;
        end loop;
        wait for 80 ns;

        -- SEW = 16 bits --
        vsew_o <= "001";
        cycle <= 0;
        for cyc in 0 to 3 loop
            tinfo.TEST_COUNT <= tinfo.TEST_COUNT + 1;

            valid_o <= '0';
            wait for 20 ns;
            valid_o <= '1';

            while (done_o = '0') loop
                wait for 20 ns;
            end loop;

            if check_type16 /= out_type16 then
                tinfo.TEST_FAIL <= tinfo.TEST_FAIL + 1;
                report "SEW = 16 || CYC = " & to_string(cyc) & " || INSTRUCTION " & to_hstring(op_i) & " || MISMATCH: " severity error;
                for ii in check_type16'range loop
                    if check_type16(ii) /= out_type16(ii) then
                        report "INDEX " & integer'image(ii) & " | EXPECTED " & to_hstring(check_type16(ii)) & " | ACTUAL " & to_hstring(out_type16(ii));
                    end if;
                end loop;
            else
                tinfo.TEST_PASS <= tinfo.TEST_PASS + 1;
            end if;
            wait for 20 ns;

            cycle <= cycle + 1;
        end loop;
        wait for 80 ns;

        -- SEW = 32 bits --
        vsew_o <= "010";
        cycle <= 0;
        for cyc in 0 to 3 loop
            tinfo.TEST_COUNT <= tinfo.TEST_COUNT + 1;

            valid_o <= '0';
            wait for 20 ns;
            valid_o <= '1';

            while (done_o = '0') loop
                wait for 20 ns;
            end loop;

            if check_type32 /= out_type32 then
                tinfo.TEST_FAIL <= tinfo.TEST_FAIL + 1;
                report "SEW = 32 || CYC = " & to_string(cyc) & " || INSTRUCTION " & to_hstring(op_i) & " || MISMATCH: " severity error;
                for ii in check_type32'range loop
                    if check_type32(ii) /= out_type32(ii) then
                        report "INDEX " & integer'image(ii) & " | EXPECTED " & to_hstring(check_type32(ii)) & " | ACTUAL " & to_hstring(out_type32(ii));
                    end if;
                end loop;
            else
                tinfo.TEST_PASS <= tinfo.TEST_PASS + 1;
            end if;
            wait for 20 ns;

            cycle <= cycle + 1;
        end loop;
        wait for 80 ns;

        valid_o <= '0';
    end procedure test_op;

    procedure check_output(constant op_i     : in  std_ulogic_vector;
                           constant cycle    : in  integer;
                           signal   check    : out expand_t;
                           signal   opA      : in  expand_t;
                           signal   opB      : in  expand_t;
                           signal   mask     : in  std_ulogic_vector;
                           signal   opA_2sew : in  expand_t;
                           signal   opA_half : in  expand_t) is
        constant ELEM       : integer := opA'length;
        constant SEW        : integer := opA(opA'low)'length;
        constant SEW_2      : integer := opA_2sew(opA_2sew'low)'length;
        constant HALF_SEW   : integer := opA_half(opA_half'low)'length;
        variable cycle_i    : integer;
        variable shift_bits : integer;
        variable temp_2sew  : std_ulogic_vector((2*SEW)-1 downto 0);
    begin
        assert (opA'length = opB'length) and (check'length = opB'length) report "ERROR - check_output opA/opB/check signals do not have the same size"     severity error;
        assert (SEW_2 = 2*SEW)                                           report "ERROR - check_output opA_2sew does NOT have EEW = 2*(opA'SEW)"            severity error;
        assert (HALF_SEW = SEW/2)                                        report "ERROR - check_output opA_half does NOT have EEW = (opA'SEW)/2"            severity error;

        case alu_op is
            when valu_waddu | valu_wsubu | valu_wadd | valu_wsub | valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew | valu_zext_vf2 | valu_sext_vf2 => cycle_i := (cycle mod 2);
            when valu_zext_vf4 | valu_sext_vf4 => cycle_i := (cycle mod 4);
            when others => cycle_i := cycle;
        end case;

        shift_bits := integer(ceil(log2(real(SEW)))) - 1;
        for ii in 0 to ELEM-1 loop
            case ALU_OP is
                when valu_waddu      => temp_2sew := std_ulogic_vector(resize(unsigned(opA(cycle_i*(ELEM/2)+(ii/2))), SEW_2) + resize(unsigned(opB(cycle_i*(ELEM/2)+(ii/2))), SEW_2));
                when valu_wsubu      => temp_2sew := std_ulogic_vector(resize(unsigned(opA(cycle_i*(ELEM/2)+(ii/2))), SEW_2) - resize(unsigned(opB(cycle_i*(ELEM/2)+(ii/2))), SEW_2));
                when valu_wadd       => temp_2sew := std_ulogic_vector(resize(signed(opA(cycle_i*(ELEM/2)+(ii/2))), SEW_2) + resize(signed(opB(cycle_i*(ELEM/2)+(ii/2))), SEW_2));
                when valu_wsub       => temp_2sew := std_ulogic_vector(resize(signed(opA(cycle_i*(ELEM/2)+(ii/2))), SEW_2) - resize(signed(opB(cycle_i*(ELEM/2)+(ii/2))), SEW_2));
                when valu_waddu_2sew => temp_2sew := std_ulogic_vector(unsigned(opA_2sew(ii/2)) + resize(unsigned(opB(cycle_i*(ELEM/2)+(ii/2))), SEW_2));
                when valu_wsubu_2sew => temp_2sew := std_ulogic_vector(unsigned(opA_2sew(ii/2)) - resize(unsigned(opB(cycle_i*(ELEM/2)+(ii/2))), SEW_2));
                when valu_wadd_2sew  => temp_2sew := std_ulogic_vector(signed(opA_2sew(ii/2)) + resize(signed(opB(cycle_i*(ELEM/2)+(ii/2))), SEW_2));
                when valu_wsub_2sew  => temp_2sew := std_ulogic_vector(signed(opA_2sew(ii/2)) - resize(signed(opB(cycle_i*(ELEM/2)+(ii/2))), SEW_2));
                when others => temp_2sew := (others => '0');
            end case;

            check(ii) <= (check(ii)'range => '0');
            case ALU_OP is
                when valu_waddu | valu_wsubu | valu_wadd | valu_wsub | valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew =>
                    check(ii) <= (check(ii)'range => '0') when (SEW = 32) else temp_2sew(temp_2sew'high downto SEW) when ((ii mod 2) = 1) else temp_2sew(SEW-1 downto 0);
                when valu_add        => check(ii) <= std_ulogic_vector(unsigned(opA(ii)) + unsigned(opB(ii)));
                when valu_sub        => check(ii) <= std_ulogic_vector(unsigned(opA(ii)) - unsigned(opB(ii)));
                when valu_rsub       => check(ii) <= std_ulogic_vector(unsigned(opB(ii)) - unsigned(opA(ii)));
                when valu_zext_vf2   => check(ii) <= (check(ii)'range => '0') when (SEW = 8) else std_ulogic_vector(resize(unsigned(opA_half(cycle_i*ELEM+ii)), SEW));
                when valu_sext_vf2   => check(ii) <= (check(ii)'range => '0') when (SEW = 8) else std_ulogic_vector(resize(signed(opA_half(cycle_i*ELEM+ii)), SEW));
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
                when valu_sltu       => check(ii/SEW)(ii mod SEW) <= '1' when (unsigned(opA(ii)) < unsigned(opB(ii)))  else '0';
                when valu_slt        => check(ii/SEW)(ii mod SEW) <= '1' when (signed(opA(ii)) < signed(opB(ii)))      else '0';
                when valu_sleu       => check(ii/SEW)(ii mod SEW) <= '1' when (unsigned(opA(ii)) <= unsigned(opB(ii))) else '0';
                when valu_sle        => check(ii/SEW)(ii mod SEW) <= '1' when (signed(opA(ii)) <= signed(opB(ii)))     else '0';
                when valu_sgtu       => check(ii/SEW)(ii mod SEW) <= '1' when (unsigned(opA(ii)) > unsigned(opB(ii)))  else '0';
                when valu_sgt        => check(ii/SEW)(ii mod SEW) <= '1' when (signed(opA(ii)) > signed(opB(ii)))      else '0';
                when valu_sgeu       => check(ii/SEW)(ii mod SEW) <= '1' when (unsigned(opA(ii)) >= unsigned(opB(ii))) else '0';
                when valu_sge        => check(ii/SEW)(ii mod SEW) <= '1' when (signed(opA(ii)) >= signed(opB(ii)))     else '0';
                when valu_adc        => check(ii) <= (check(ii)'range => '0');
                when valu_madc       => check(ii) <= (check(ii)'range => '0');
                when valu_sbc        => check(ii) <= (check(ii)'range => '0');
                when valu_msbc       => check(ii) <= (check(ii)'range => '0');
                when valu_minu       => check(ii) <= opB(ii) when (unsigned(opA(ii)) > unsigned(opB(ii))) else opA(ii);
                when valu_min        => check(ii) <= opB(ii) when (signed(opA(ii)) > signed(opB(ii)))     else opA(ii);
                when valu_maxu       => check(ii) <= opB(ii) when (unsigned(opA(ii)) < unsigned(opB(ii))) else opA(ii);
                when valu_max        => check(ii) <= opB(ii) when (signed(opA(ii)) < signed(opB(ii)))     else opA(ii);
                when valu_merge      => check(ii) <= opB(ii) when mask(ii) = '1' else opA(ii);
                when valu_nsrl       => check(ii) <= (check(ii)'range => '0');
                when valu_nsra       => check(ii) <= (check(ii)'range => '0');
                when others          => check(ii) <= (check(ii)'range => '0');
            end case;
        end loop; 
    end procedure check_output;
begin
    CLK <= not CLK after 10 ns;

    process(all) begin
        for ii in 0 to ((VLEN/8)-1) loop
            op2_type8(ii) <= OP2(8*ii+7 downto 8*ii);
            op1_type8(ii) <= OP1(8*ii+7 downto 8*ii);
            out_type8(ii) <= ALU_OUT(8*ii+7 downto 8*ii);
        end loop;

        for ii in 0 to ((VLEN/16)-1) loop
            op2_type16(ii) <= OP2(16*ii+15 downto 16*ii);
            op1_type16(ii) <= OP1(16*ii+15 downto 16*ii);
            out_type16(ii) <= ALU_OUT(16*ii+15 downto 16*ii);
        end loop;

        for ii in 0 to ((VLEN/32)-1) loop
            op2_type32(ii) <= OP2(32*ii+31 downto 32*ii);
            op1_type32(ii) <= OP1(32*ii+31 downto 32*ii);
            out_type32(ii) <= ALU_OUT(32*ii+31 downto 32*ii);
        end loop;

        check_output(ALU_OP, CYC, check_type8,  op2_type8,  op1_type8,  VMASK, op2_type16,  ZERO_type4);
        check_output(ALU_OP, CYC, check_type16, op2_type16, op1_type16, VMASK, op2_type32,  op2_type8);
        check_output(ALU_OP, CYC, check_type32, op2_type32, op1_type32, VMASK, ZERO_type64, op2_type16);
    end process;
    
    valu: entity work.neorv32_valu port map(
        clk      => CLK,
        rst      => RST,
        valid    => VALID,
        op2      => OP2,
        op1      => OP1,
        op0      => OP0,
        alu_op   => ALU_OP,
        vmask    => VMASK,
        vsew     => VSEW,
        alu_out  => ALU_OUT,
        alu_done => ALU_DONE
    );

    stimuli: process
        variable RV    : RandomPType;
        constant ITERS : natural := 10;
    begin
        RV.InitSeed(RV'instance_name, TRUE);
        RST <= '1';
        wait for 20 ns;
        RST <= '0';
        -- WAIT FOR A BIT TO MAKE EVALUATIONS A BIT AFTER THE POSEDGE --
        wait for 5 ns;

        for iter in 0 to ITERS-1 loop
            -- Resets the Test Results record for this loop --
            ITER_INFO <= (TEST_COUNT => 0, TEST_PASS => 0, TEST_FAIL => 0);
            wait for 0 ns;

            -- Randomizes values for operands and mask --
            for ii in 0 to (OP2'length/16)-1 loop
                OP2(16*ii+15 downto 16*ii)   <= RV.RandSlv(0, 65535, 16);
                OP1(16*ii+15 downto 16*ii)   <= RV.RandSlv(0, 65535, 16);
            end loop;
            
            for ii in 0 to (VMASK'length/16)-1 loop
                VMASK(16*ii+15 downto 16*ii) <= RV.RandSlv(0, 65535, 16);
            end loop;    
                
            -- Run the instructions tests --
            test_op(valu_add,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sub,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_rsub,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_waddu,      CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_wsubu,      CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_wadd,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_wsub,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_waddu_2sew, CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_wsubu_2sew, CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_wadd_2sew,  CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_wsub_2sew,  CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_zext_vf2,   CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sext_vf2,   CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            -- test_op(valu_zext_vf4,   CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            -- test_op(valu_sext_vf4,   CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_and,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_or,         CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_xor,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sll,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_srl,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sra,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_seq,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sne,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sltu,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_slt,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sleu,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sle,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sgtu,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sgt,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sgeu,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_sge,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            -- test_op(valu_adc,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            -- test_op(valu_madc,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            -- test_op(valu_sbc,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            -- test_op(valu_msbc,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_minu,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_min,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_maxu,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_max,        CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            test_op(valu_merge,      CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            -- test_op(valu_nsrl,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);
            -- test_op(valu_nsra,       CYC, ALU_OP, VSEW, VALID, ALU_DONE, ITER_INFO);

            report "TEST INFO   => ITER: " & to_string(iter) & " OP2: " & to_hstring(OP2) & " OP1: " & to_hstring(OP1) & " VMASK: " & to_hstring(VMASK);
            report "TEST REPORT => PASSES: " & to_string(ITER_INFO.TEST_PASS) & " FAILS: " & to_string(ITER_INFO.TEST_FAIL) & " (TEST COUNT: " & to_string(ITER_INFO.TEST_COUNT) & ")";

            TOTAL_INFO <= (
                TEST_COUNT => TOTAL_INFO.TEST_COUNT + ITER_INFO.TEST_COUNT,
                TEST_PASS  => TOTAL_INFO.TEST_PASS  + ITER_INFO.TEST_PASS,
                TEST_FAIL  => TOTAL_INFO.TEST_FAIL  + ITER_INFO.TEST_FAIL
            );
            wait for 0 ns;
        end loop;

        report "SUMMARY => TOTAL PASSES: " & to_string(TOTAL_INFO.TEST_PASS) & " TOTAL FAILS: " & to_string(TOTAL_INFO.TEST_FAIL) & " (TOTAL COUNT: " & to_string(TOTAL_INFO.TEST_COUNT) & ")";

        finish;
    end process;
end architecture tb;