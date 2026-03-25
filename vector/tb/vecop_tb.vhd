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
            scal2_in       : in std_ulogic_vector(XLEN-1 downto 0);
            scal1_in       : in std_ulogic_vector(XLEN-1 downto 0);
            vinst_valid_in : in std_ulogic;
            viq_full       : out std_ulogic;
            viq_empty      : out std_ulogic
        );
    end component neorv32_vecop;

    signal CLK         : std_ulogic                         := '0';
    signal RST         : std_ulogic                         := '0';
    signal VINST       : std_ulogic_vector(XLEN-1 downto 0) := (others => '0');
    signal SCAL2       : std_ulogic_vector(XLEN-1 downto 0) := (others => '0');
    signal SCAL1       : std_ulogic_vector(XLEN-1 downto 0) := (others => '0');
    signal VINST_VALID : std_ulogic                         := '0';
    signal VQ_FULL     : std_ulogic;
    signal VQ_EMPTY    : std_ulogic;

    type lsu_access_mode_t is (UNIT_STRIDE, CONSTANT_STRIDE);

    signal RUN_ALU_TEST : boolean := TRUE;
    signal RUN_LSU_TEST : boolean := FALSE;

    procedure send_instruction(signal full : in std_ulogic; signal valid : out std_ulogic) is
    begin
        valid <= '1';
        wait for 20 ns;
        -- Wait for a free slot in the FIFO --
        while (full = '1') loop
            wait for 20 ns;
        end loop;
        valid <= '0';
        wait for 40 ns;
    end procedure send_instruction;

    procedure send_instruction_and_wait(signal empty : in std_ulogic; signal valid : out std_ulogic) is
    begin
        -- Send Instruction to FIFO and wait for it to complete (FIFO empty again) --
        while (empty = '0') loop
            wait for 20 ns;
        end loop;
        -- Send out the instruction to the V-IQ FIFO --
        valid <= '1';
        wait for 20 ns;
        valid <= '0';
        wait for 20 ns;
        -- Wait until the instruction is completed by checking FIFO status --
        while (empty = '0') loop
            wait for 20 ns;
        end loop;
    end procedure send_instruction_and_wait;

    procedure check_result_alu(
        constant LMUL      : in integer;
        constant DEST_SEW  : in integer;
        constant DEST_LMUL : in integer;
        constant INDEX     : in integer;
        constant SEW       : in integer;
        constant alu_op    : in std_ulogic_vector;
        constant vs2       : in expand_t;
        constant vs1       : in expand_t;
        constant vd        : in std_ulogic_vector;
        constant mask      : in std_ulogic_vector
    ) is
        constant DEST_ELEM  : integer := (VLEN/DEST_SEW);
        variable cycle_i    : integer;
        variable shift_bits : integer;
        variable temp_2sew  : std_ulogic_vector(DEST_SEW-1 downto 0);

        variable check      : expand_t((VLEN/DEST_SEW)-1 downto 0)(DEST_SEW-1 downto 0) := (others => (others => '0'));
        variable full_check : std_ulogic_vector(VLEN-1 downto 0)                        := (others => '0');
    begin

        cycle_i    := INDEX mod (DEST_LMUL/LMUL);
        shift_bits := (integer(ceil(log2(real(DEST_SEW)))) - 1);

        -- Loop that constructs the check array based on instruction and operand values --
        for ii in 0 to DEST_ELEM-1 loop
            case alu_op is
                when valu_waddu      => temp_2sew := std_ulogic_vector(resize(unsigned(vs2((cycle_i * DEST_ELEM) + ii)), DEST_SEW) + resize(unsigned(vs1((cycle_i * DEST_ELEM) + ii)), DEST_SEW));
                when valu_wsubu      => temp_2sew := std_ulogic_vector(resize(unsigned(vs2((cycle_i * DEST_ELEM) + ii)), DEST_SEW) - resize(unsigned(vs1((cycle_i * DEST_ELEM) + ii)), DEST_SEW));
                when valu_wadd       => temp_2sew := std_ulogic_vector(resize(signed(vs2((cycle_i * DEST_ELEM) + ii)), DEST_SEW) + resize(signed(vs1((cycle_i * DEST_ELEM) + ii)), DEST_SEW));
                when valu_wsub       => temp_2sew := std_ulogic_vector(resize(signed(vs2((cycle_i * DEST_ELEM) + ii)), DEST_SEW) - resize(signed(vs1((cycle_i * DEST_ELEM) + ii)), DEST_SEW));
                when valu_waddu_2sew => temp_2sew := std_ulogic_vector(unsigned(vs2(ii)) + resize(unsigned(vs1((cycle_i * DEST_ELEM) + ii)), DEST_SEW));
                when valu_wsubu_2sew => temp_2sew := std_ulogic_vector(unsigned(vs2(ii)) - resize(unsigned(vs1((cycle_i * DEST_ELEM) + ii)), DEST_SEW));
                when valu_wadd_2sew  => temp_2sew := std_ulogic_vector(signed(vs2(ii)) + resize(signed(vs1((cycle_i * DEST_ELEM) + ii)), DEST_SEW));
                when valu_wsub_2sew  => temp_2sew := std_ulogic_vector(signed(vs2(ii)) - resize(signed(vs1((cycle_i * DEST_ELEM) + ii)), DEST_SEW));
                when others          => temp_2sew := (others => '0');
            end case;

            check(ii) := (check(ii)'range => '0');
            case alu_op is
                when valu_waddu      | valu_wsubu      | valu_wadd      | valu_wsub |
                     valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew => check(ii) := (check(ii)'range => '0') when (SEW = 32) else temp_2sew;
                when valu_add        => check(ii) := std_ulogic_vector(unsigned(vs2(ii)) + unsigned(vs1(ii)));
                when valu_sub        => check(ii) := std_ulogic_vector(unsigned(vs2(ii)) - unsigned(vs1(ii)));
                when valu_rsub       => check(ii) := std_ulogic_vector(unsigned(vs1(ii)) - unsigned(vs2(ii)));
                when valu_zext_vf2   => check(ii) := (check(ii)'range => '0') when (SEW = 8) else std_ulogic_vector(resize(unsigned(vs2(cycle_i*DEST_ELEM+ii)), SEW));
                when valu_sext_vf2   => check(ii) := (check(ii)'range => '0') when (SEW = 8) else std_ulogic_vector(resize(signed(vs2(cycle_i*DEST_ELEM+ii)), SEW));
                when valu_zext_vf4   => check(ii) := (check(ii)'range => '0') when (SEW = 8) or (SEW = 16) else std_ulogic_vector(resize(unsigned(vs2(cycle_i*DEST_ELEM+ii)), SEW));
                when valu_sext_vf4   => check(ii) := (check(ii)'range => '0') when (SEW = 8) or (SEW = 16) else std_ulogic_vector(resize(signed(vs2(cycle_i*DEST_ELEM+ii)), SEW));
                when valu_and        => check(ii) := (vs2(ii) and vs1(ii));
                when valu_or         => check(ii) := (vs2(ii) or  vs1(ii));
                when valu_xor        => check(ii) := (vs2(ii) xor vs1(ii));
                when valu_sll        => check(ii) := std_ulogic_vector(shift_left(unsigned(vs2(ii)), to_integer(unsigned(vs1(ii)(shift_bits downto 0)))));
                when valu_srl        => check(ii) := std_ulogic_vector(shift_right(unsigned(vs2(ii)), to_integer(unsigned(vs1(ii)(shift_bits downto 0)))));
                when valu_sra        => check(ii) := std_ulogic_vector(shift_right(signed(vs2(ii)), to_integer(unsigned(vs1(ii)(shift_bits downto 0)))));
                when valu_se         => check(ii/SEW)(ii mod SEW) := '1' when (vs2(ii)  = vs1(ii)) else '0';
                when valu_sne        => check(ii/SEW)(ii mod SEW) := '1' when (vs2(ii) /= vs1(ii)) else '0';
                when valu_sltu       => check(ii/SEW)(ii mod SEW) := '1' when (unsigned(vs2(ii)) < unsigned(vs1(ii)))  else '0';
                when valu_slt        => check(ii/SEW)(ii mod SEW) := '1' when (signed(vs2(ii)) < signed(vs1(ii)))      else '0';
                when valu_sleu       => check(ii/SEW)(ii mod SEW) := '1' when (unsigned(vs2(ii)) <= unsigned(vs1(ii))) else '0';
                when valu_sle        => check(ii/SEW)(ii mod SEW) := '1' when (signed(vs2(ii)) <= signed(vs1(ii)))     else '0';
                when valu_sgtu       => check(ii/SEW)(ii mod SEW) := '1' when (unsigned(vs2(ii)) > unsigned(vs1(ii)))  else '0';
                when valu_sgt        => check(ii/SEW)(ii mod SEW) := '1' when (signed(vs2(ii)) > signed(vs1(ii)))      else '0';
                when valu_adc        => check(ii) := (check(ii)'range => '0');
                when valu_madc       => check(ii) := (check(ii)'range => '0');
                when valu_sbc        => check(ii) := (check(ii)'range => '0');
                when valu_msbc       => check(ii) := (check(ii)'range => '0');
                when valu_minu       => check(ii) := vs1(ii) when (unsigned(vs2(ii)) > unsigned(vs1(ii))) else vs2(ii);
                when valu_min        => check(ii) := vs1(ii) when (signed(vs2(ii)) > signed(vs1(ii)))     else vs2(ii);
                when valu_maxu       => check(ii) := vs1(ii) when (unsigned(vs2(ii)) < unsigned(vs1(ii))) else vs2(ii);
                when valu_max        => check(ii) := vs1(ii) when (signed(vs2(ii)) < signed(vs1(ii)))     else vs2(ii);
                when valu_merge      => check(ii) := vs1(ii) when mask(ii) = '1' else vs2(ii);
                when valu_nsrl       => check(ii) := (check(ii)'range => '0');
                when valu_nsra       => check(ii) := (check(ii)'range => '0');
                when others          => check(ii) := (check(ii)'range => '0');
            end case;
        end loop;

        -- First loop needs to complete before assigning the check variable to full_check --
        for ii in 0 to DEST_ELEM-1 loop
            full_check(ii*DEST_SEW+DEST_SEW-1 downto ii*DEST_SEW) := check(ii);
        end loop;

        -- Check calculated expected value against what is read from the VRF --
        if (full_check = vd) then
            report "V-ALU Operation Check -- LMUL loop index " & integer'image(INDEX) & " -- ACTUAL: " & to_hstring(vd) & " EXPECTED: " & to_hstring(full_check) & "...PASSED";
        else
            report "V-ALU Operation Check -- LMUL loop index " & integer'image(INDEX) & " -- ACTUAL: " & to_hstring(vd) & " EXPECTED: " & to_hstring(full_check) & "...FAILED";
        end if;
    end procedure check_result_alu;

    procedure run_alu(
        constant LMUL        : in  integer;
        constant VSEW        : in  integer;
        constant alu_op      : in  std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
        constant vs2         : in  integer;
        constant vs1         : in  integer;
        constant vd          : in  integer;
        constant funct6      : in  std_ulogic_vector(5 downto 0);
        constant funct3      : in  std_ulogic_vector(2 downto 0);
        constant scalar      : in  integer;
        signal   vregfile    : in  vregfile_t;
        signal   viq_full    : in  std_ulogic;
        signal   viq_empty   : in  std_ulogic;
        signal   instr_valid : out std_ulogic
    ) is
        -- LMUL must be either [1, 2, 4, 8], so we have the vector with MAX_SIZE = 8 --
        type lmul_array_t is array (natural range <>) of std_ulogic_vector(VLEN-1 downto 0);
        variable vs2_data : lmul_array_t(0 to 7);
        variable vs1_data : lmul_array_t(0 to 7);
        variable vd_data  : lmul_array_t(0 to 7);

        variable DEST_LMUL : integer := 0;

        variable is_multiwidth : boolean := FALSE;
        variable is_widening   : boolean := FALSE;
        variable is_extend_vf2 : boolean := FALSE;
        variable is_extend_vf4 : boolean := FALSE;
        variable vs2_index     : integer := 0;
        variable vs1_index     : integer := 0;

        variable mask : std_ulogic_vector((VLEN/VSEW)-1 downto 0) := (others => '1');

        variable vs2_type8  : expand_t((VLEN/8)-1 downto 0)(7 downto 0)   := (others => (others => '0'));
        variable vs1_type8  : expand_t((VLEN/8)-1 downto 0)(7 downto 0)   := (others => (others => '0'));
        variable vs2_type16 : expand_t((VLEN/16)-1 downto 0)(15 downto 0) := (others => (others => '0')); 
        variable vs1_type16 : expand_t((VLEN/16)-1 downto 0)(15 downto 0) := (others => (others => '0'));
        variable vs2_type32 : expand_t((VLEN/32)-1 downto 0)(31 downto 0) := (others => (others => '0'));
        variable vs1_type32 : expand_t((VLEN/32)-1 downto 0)(31 downto 0) := (others => (others => '0'));
    begin
        -- Read operands vs2/vs1 values before dispatching the instruction (in case of destination overlap) --
        -- TODO: there can be no overflow in register address for LMUL > 1, so when generating the instruction this needs to be respected --
        for ii in 0 to 7 loop
            vs2_data(ii) := vregfile((vs2 + ii) mod 32);
            vs1_data(ii) := vregfile((vs1 + ii) mod 32);

            for jj in 0 to (vs1_data(ii)'length/VSEW)-1 loop
                case funct3 is
                    when "011"                 => vs1_data(ii)(((jj*VSEW)+VSEW)-1 downto jj*VSEW) := std_ulogic_vector(to_unsigned(vs1, VSEW));
                    when "100" | "101" | "110" => vs1_data(ii)(((jj*VSEW)+VSEW)-1 downto jj*VSEW) := std_ulogic_vector(to_unsigned(scalar, VSEW));
                    when others                => vs1_data(ii)(((jj*VSEW)+VSEW)-1 downto jj*VSEW) := vregfile((vs1 + ii) mod 32)(((jj*VSEW)+VSEW)-1 downto jj*VSEW);
                end case;
            end loop;
        end loop;

        -- Send Instruction to FIFO and wait for it to complete (FIFO empty again) --
        -- TODO: add support for FIFO backpressure --
        send_instruction_and_wait(viq_empty, instr_valid);

        -- Classify the instructions according to Destination Effective LMUL (EMUL), if it is Widening and/or Multi-Width --
        case alu_op is
            -- Widening Operations, but with same width operands --
            when valu_waddu | valu_wsubu | valu_wadd | valu_wsub =>
                DEST_LMUL     := (2 * LMUL);
                is_multiwidth := FALSE;
                is_widening   := TRUE;
                is_extend_vf2 := FALSE;
                is_extend_vf4 := FALSE;
            -- Widening Operations (2 * SEW), with different width operands --
            when valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew =>
                DEST_LMUL     := (2 * LMUL);
                is_multiwidth := TRUE;
                is_widening   := TRUE;
                is_extend_vf2 := FALSE;
                is_extend_vf4 := FALSE;
            -- Sign Extension Operations (SEW / 2) --
            when valu_zext_vf2 | valu_sext_vf2 =>
                DEST_LMUL     := (2 * LMUL);
                is_multiwidth := FALSE;
                is_widening   := FALSE;
                is_extend_vf2 := TRUE;
                is_extend_vf4 := FALSE;
            -- Sign Extension Operations (SEW / 4) --
            when valu_zext_vf4 | valu_sext_vf4 =>
                DEST_LMUL     := (4 * LMUL);
                is_multiwidth := FALSE;
                is_widening   := FALSE;
                is_extend_vf2 := FALSE;
                is_extend_vf4 := TRUE;
            -- Other Operations --
            when others =>
                DEST_LMUL     := LMUL;
                is_multiwidth := FALSE;
                is_widening   := FALSE;
        end case;

        -- Extract the destination value and calculate/check the operation results --
        for ii in 0 to DEST_LMUL-1 loop
            vd_data(ii) := vregfile(vd + ii);
        end loop;

        for ii in 0 to DEST_LMUL-1 loop
            -- Calculate the corresponding indexes for the vs2/vs1 values in the list of extracted values --
            vs2_index := ii when is_multiwidth else ii/(DEST_LMUL/LMUL);
            vs1_index := ii/(DEST_LMUL/LMUL);

            -- VSEW = 8 bits --
            for jj in 0 to ((VLEN/8)-1) loop
                vs2_type8(jj) := vs2_data(vs2_index)(8*jj+7 downto 8*jj);
                vs1_type8(jj) := vs1_data(vs1_index)(8*jj+7 downto 8*jj);
            end loop;
            -- VSEW = 16 bits --
            for jj in 0 to ((VLEN/16)-1) loop
                vs2_type16(jj) := vs2_data(vs2_index)(16*jj+15 downto 16*jj);
                vs1_type16(jj) := vs1_data(vs1_index)(16*jj+15 downto 16*jj);
            end loop;
            -- VSEW = 32 bits --
            for jj in 0 to ((VLEN/32)-1) loop
                vs2_type32(jj) := vs2_data(vs2_index)(32*jj+31 downto 32*jj);
                vs1_type32(jj) := vs1_data(vs1_index)(32*jj+31 downto 32*jj);
            end loop;

            -- Check the result of the instruction, according to VSEW configuration and type of instruction --
            if (VSEW = 8) then
                if (is_multiwidth) then
                    check_result_alu(LMUL, (VSEW * (DEST_LMUL/LMUL)), DEST_LMUL, ii, VSEW, alu_op, vs2_type16, vs1_type8, vd_data(ii), mask);
                elsif (is_extend_vf2) then
                    report "Sign Extension VF2 operations with VSEW = 8 are not supported" severity error;
                elsif (is_extend_vf4) then
                    report "Sign Extension VF4 operations with VSEW = 8 are not supported" severity error;
                else
                    check_result_alu(LMUL, (VSEW * (DEST_LMUL/LMUL)), DEST_LMUL, ii, VSEW, alu_op, vs2_type8, vs1_type8, vd_data(ii), mask);
                end if;
            elsif (VSEW = 16) then
                if (is_multiwidth) then
                    check_result_alu(LMUL, (VSEW * (DEST_LMUL/LMUL)), DEST_LMUL, ii, VSEW, alu_op, vs2_type32, vs1_type16, vd_data(ii), mask);
                elsif (is_extend_vf2) then
                    check_result_alu(LMUL, VSEW, DEST_LMUL, ii, VSEW, alu_op, vs2_type8, vs1_type16, vd_data(ii), mask);
                elsif (is_extend_vf4) then
                    report "Sign Extension VF4 operations with VSEW = 16 are not supported" severity error;
                else
                    check_result_alu(LMUL, (VSEW * (DEST_LMUL/LMUL)), DEST_LMUL, ii, VSEW, alu_op, vs2_type16, vs1_type16, vd_data(ii), mask);
                end if;
            elsif (VSEW = 32) then
                if (is_multiwidth) or (is_widening) then
                    report "Widening operations with VSEW = 32 are not supported" severity error;
                elsif (is_extend_vf2) then
                    check_result_alu(LMUL, VSEW, DEST_LMUL, ii, VSEW, alu_op, vs2_type16, vs1_type32, vd_data(ii), mask);
                elsif (is_extend_vf4) then
                    check_result_alu(LMUL, VSEW, DEST_LMUL, ii, VSEW, alu_op, vs2_type8, vs1_type32, vd_data(ii), mask);
                else
                    check_result_alu(LMUL, (VSEW * (DEST_LMUL/LMUL)), DEST_LMUL, ii, VSEW, alu_op, vs2_type32, vs1_type32, vd_data(ii), mask);
                end if;
            else
                report "Unsupported VSEW value: " & integer'image(VSEW) severity error;
            end if;
        end loop;
    end procedure run_alu;

    procedure test_alu(
        constant LMUL        : in integer;
        constant VSEW        : in integer;
        signal   vregfile    : in vregfile_t;
        signal   viq_full    : in std_ulogic;
        signal   viq_empty   : in std_ulogic;
        signal   instruction : out std_ulogic_vector(XLEN-1 downto 0);
        signal   instr_valid : out std_ulogic
    ) is
        variable RV : RandomPType;

        -- List of V-ALU Operations --
        type valu_op_t is array (natural range <>) of std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
        variable valu_op_pool : valu_op_t(0 to 33) := (
            valu_add, valu_sub, valu_rsub,
            valu_waddu, valu_wsubu, valu_wadd, valu_wsub,
            valu_waddu_2sew, valu_wsubu_2sew, valu_wadd_2sew, valu_wsub_2sew,
            valu_zext_vf2, valu_sext_vf2, valu_zext_vf4, valu_sext_vf4,
            valu_and, valu_or, valu_xor, valu_sll, valu_srl, valu_sra,
            valu_se, valu_sne, valu_sltu, valu_slt, valu_sleu, valu_sle, valu_sgtu, valu_sgt,
            -- valu_adc, valu_madc, valu_sbc, valu_msbc,
            valu_minu, valu_min, valu_maxu, valu_max,
            valu_merge
            -- valu_nsrl, valu_nsra,
            -- valu_vgather
        );
        variable opname : string(1 to 11);

        variable testop : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);

        variable funct6 : std_ulogic_vector(5 downto 0);
        variable funct3 : std_ulogic_vector(2 downto 0);
        variable vm     : std_ulogic;

        variable scalar : integer;

        variable vs2 : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable vs1 : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable vd  : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

        variable vs2_value : std_ulogic_vector(VLEN-1 downto 0);
        variable vs1_value : std_ulogic_vector(VLEN-1 downto 0);
        variable vd_value  : std_ulogic_vector(VLEN-1 downto 0);
    begin
        -- Initialize seed for random number generator --
        RV.InitSeed(RV'instance_name);

        -- TODO: add support for masked operations --
        vm := '0';

        -- TODO: add support for scalar operand --
        scalar := 0;

        for ii in valu_op_pool'range loop
            -- TODO: some restriction needs to be set for widening operations and some others --
            --       that don't support overlap between source and destination registers      --
            vs2 := std_ulogic_vector(to_unsigned(RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1), VREF_ADDR_WIDTH));
            vs1 := std_ulogic_vector(to_unsigned(RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1), VREF_ADDR_WIDTH));
            vd  := std_ulogic_vector(to_unsigned(RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1), VREF_ADDR_WIDTH));

            -- Get current operation to be tested from the pool --
            testop := valu_op_pool(ii);

            -- TODO: increase supported combination of funct6 and funct3 to test more operation types --
            -- Operation FUNCT6 / FUNCT3 Lookup Table --
            case testop is
                when valu_add        => funct6 := "000000"; funct3 := "000"; opname := "VADD       "; vs1 := vs1;
                when valu_sub        => funct6 := "000010"; funct3 := "000"; opname := "VSUB       "; vs1 := vs1;
                when valu_rsub       => funct6 := "000011"; funct3 := "011"; opname := "VRSUB      "; vs1 := vs1;
                when valu_waddu      => funct6 := "110000"; funct3 := "010"; opname := "VWADDU     "; vs1 := vs1;
                when valu_wsubu      => funct6 := "110010"; funct3 := "010"; opname := "VWSUBU     "; vs1 := vs1;
                when valu_wadd       => funct6 := "110001"; funct3 := "010"; opname := "VWADD      "; vs1 := vs1;
                when valu_wsub       => funct6 := "110011"; funct3 := "010"; opname := "VWSUB      "; vs1 := vs1;
                when valu_waddu_2sew => funct6 := "110100"; funct3 := "010"; opname := "VWADDU_2SEW"; vs1 := vs1;
                when valu_wsubu_2sew => funct6 := "110110"; funct3 := "010"; opname := "VWSUBU_2SEW"; vs1 := vs1;
                when valu_wadd_2sew  => funct6 := "110101"; funct3 := "010"; opname := "VWADD_2SEW "; vs1 := vs1;
                when valu_wsub_2sew  => funct6 := "110111"; funct3 := "010"; opname := "VWSUB_2SEW "; vs1 := vs1;
                when valu_zext_vf2   => funct6 := "010010"; funct3 := "010"; opname := "VZEXT_VF2  "; vs1 := "00110";
                when valu_sext_vf2   => funct6 := "010010"; funct3 := "010"; opname := "VSEXT_VF2  "; vs1 := "00111";
                when valu_zext_vf4   => funct6 := "010010"; funct3 := "010"; opname := "VZEXT_VF4  "; vs1 := "00100";
                when valu_sext_vf4   => funct6 := "010010"; funct3 := "010"; opname := "VSEXT_VF4  "; vs1 := "00101";
                when valu_and        => funct6 := "001001"; funct3 := "000"; opname := "VAND       "; vs1 := vs1;
                when valu_or         => funct6 := "001010"; funct3 := "000"; opname := "VOR        "; vs1 := vs1;
                when valu_xor        => funct6 := "001011"; funct3 := "000"; opname := "VXOR       "; vs1 := vs1;
                when valu_sll        => funct6 := "100101"; funct3 := "000"; opname := "VSLL       "; vs1 := vs1;
                when valu_srl        => funct6 := "101000"; funct3 := "000"; opname := "VSRL       "; vs1 := vs1;
                when valu_sra        => funct6 := "101001"; funct3 := "000"; opname := "VSRA       "; vs1 := vs1;
                when valu_se         => funct6 := "011000"; funct3 := "000"; opname := "VSE        "; vs1 := vs1;
                when valu_sne        => funct6 := "011001"; funct3 := "000"; opname := "VSNE       "; vs1 := vs1;
                when valu_sltu       => funct6 := "011010"; funct3 := "000"; opname := "VSLTU      "; vs1 := vs1;
                when valu_slt        => funct6 := "011011"; funct3 := "000"; opname := "VSLT       "; vs1 := vs1;
                when valu_sleu       => funct6 := "011100"; funct3 := "000"; opname := "VSLEU      "; vs1 := vs1;
                when valu_sle        => funct6 := "011101"; funct3 := "000"; opname := "VSLE       "; vs1 := vs1;
                when valu_sgtu       => funct6 := "011110"; funct3 := "011"; opname := "VSGTU      "; vs1 := vs1;
                when valu_sgt        => funct6 := "011111"; funct3 := "011"; opname := "VSGT       "; vs1 := vs1;
                when valu_minu       => funct6 := "000100"; funct3 := "000"; opname := "VMINU      "; vs1 := vs1;
                when valu_min        => funct6 := "000101"; funct3 := "000"; opname := "VMIN       "; vs1 := vs1;
                when valu_maxu       => funct6 := "000110"; funct3 := "000"; opname := "VMAXU      "; vs1 := vs1;
                when valu_max        => funct6 := "000111"; funct3 := "000"; opname := "VMAX       "; vs1 := vs1;
                when valu_merge      => funct6 := "010111"; funct3 := "000"; opname := "VMERGE     "; vs1 := vs1;
                when others          => report "Selected V-ALU Operation " & to_string(testop) & " is not supported" severity error;
            end case;

            -- Construct the instruction word --
            instruction <= funct6 & vm & vs2 & vs1 & funct3 & vd & vop_arith_cfg;

            report "TESTING V-ALU OPERATION: " & opname;
            run_alu(LMUL, VSEW, testop, to_integer(unsigned(vs2)), to_integer(unsigned(vs1)), to_integer(unsigned(vd)), funct6, funct3, scalar, vregfile, viq_full, viq_empty, instr_valid);
            
            wait for 80 ns;
        end loop;
    end procedure test_alu;

    procedure test_lsu(
        constant LMUL        : in  integer;
        constant VSEW        : in  integer;
        constant access_mode : in  lsu_access_mode_t;
        constant lsu_width   : in  integer;
        constant load        : in  boolean;
        constant store       : in  boolean;
        signal   vregfile    : in  vregfile_t;
        signal   viq_full    : in  std_ulogic;
        signal   viq_empty   : in  std_ulogic;
        signal   instruction : out std_ulogic_vector(XLEN-1 downto 0);
        signal   scal2       : out std_ulogic_vector(XLEN-1 downto 0);
        signal   scal1       : out std_ulogic_vector(XLEN-1 downto 0);
        signal   instr_valid : out std_ulogic
    ) is
        -- Random Number Generator --
        variable RV : RandomPType;

        -- Instruction Fields --
        variable nf          : std_ulogic_vector(2 downto 0);
        variable mew         : std_ulogic;
        variable mop         : std_ulogic_vector(1 downto 0);
        variable vm          : std_ulogic;
        variable sumop       : std_ulogic_vector(4 downto 0);
        variable rs1         : std_ulogic_vector(4 downto 0);
        variable encod_width : std_ulogic_vector(2 downto 0);
        variable base_vreg   : std_ulogic_vector(4 downto 0);
        variable opcode      : std_ulogic_vector(6 downto 0);
    begin

        -- Initialize seed for random number generator --
        RV.InitSeed(RV'instance_name);

        ------------------------------------
        -- Instruction Fields Definitions --
        ------------------------------------
        -- TODO: add support for more values for all fields --
        nf  := (others => '0');
        mew := '0';
        -- Define Memory Access Mode --
        case access_mode is
            when UNIT_STRIDE     => mop := "00";
            when CONSTANT_STRIDE => mop := "10";
            when others          => mop := (others => '0');
        end case;
        vm    := '0';
        sumop := (others => '0');
        rs1   := (others => '0');
        -- Define Instruction Encoded Width --
        case lsu_width is
            when 8      => encod_width := "000"; 
            when 16     => encod_width := "101"; 
            when 32     => encod_width := "110"; 
            when others => encod_width := (others => '0'); 
        end case;
        -- Define Vector Register from/to which we will store/load the data --
        base_vreg := std_ulogic_vector(to_unsigned(RV.RandInt(0, (2**VREF_ADDR_WIDTH)-1), VREF_ADDR_WIDTH));
        -- Define OPCODE based on type of access (LOAD/STORE) --
        if (load) then
            opcode := vop_load;
        elsif (store) then
            opcode := vop_store;
        else
            report "TEST LSU -- operation type (LOAD/STORE) was not specified" severity error;
        end if;
            
        -- Construct the instruction word --
        instruction <= nf & mew & mop & vm & sumop & rs1 & encod_width & base_vreg & opcode;

        -- Calculate Stride and Memory Start Address --
        case lsu_width is
            when 8 =>
                scal2 <= std_ulogic_vector(to_unsigned(1, scal2'length));
                scal1 <= std_ulogic_vector(to_unsigned(0, scal1'length));

            when 16 =>
                scal2 <= std_ulogic_vector(to_unsigned(2, scal2'length));
                scal1 <= std_ulogic_vector(to_unsigned(0, scal1'length));

            when 32 =>
                scal2 <= std_ulogic_vector(to_unsigned(4, scal2'length));
                scal1 <= std_ulogic_vector(to_unsigned(0, scal1'length));

            when others =>
                scal2 <= std_ulogic_vector(to_unsigned(0, scal2'length));
                scal1 <= std_ulogic_vector(to_unsigned(0, scal1'length));
        end case;

        -- Send Instruction to FIFO and wait for it to complete (FIFO empty again) --
        -- TODO: add support for FIFO backpressure --
        send_instruction_and_wait(viq_empty, instr_valid);
    end procedure test_lsu;
begin

    CLK <= not CLK after 10 ns;

    vecop: entity work.neorv32_vecop port map (
        clk            => CLK,
        rst            => RST,
        vinst_in       => VINST,
        scal2_in       => SCAL2,
        scal1_in       => SCAL1,
        vinst_valid_in => VINST_VALID,
        viq_full       => VQ_FULL,
        viq_empty      => VQ_EMPTY
    );

    stimuli: process
        alias vregfile : vregfile_t is << signal .vecop_tb.vecop.vrf.vregfile_0 : vregfile_t >>;
        alias mockmem  : mockmem_t is << signal .vecop_tb.vecop.vmockmem.mockmem : mockmem_t >>;
    begin

        RST <= '0';
        wait for 40 ns;
        RST <= '1';
        wait for 40 ns;
        RST <= '0';
        wait for 40 ns;

        -- VSETVLI --> VLMUL = 1 | VSEW = 8 | VTA=VMA=0 | VL=MAXVL 
        --------     |    VTYPEI     |  RS1    |  F3   |  RD     |  OPCODE  |
        VINST <= "0" & "00000000000" & "00000" & "111" & "11111" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        if (RUN_ALU_TEST) then
            test_alu(1, 8, vregfile, VQ_FULL, VQ_EMPTY, VINST, VINST_VALID);
        end if;

        if (RUN_LSU_TEST) then
            test_lsu(1, 8, UNIT_STRIDE, 8, TRUE, FALSE, vregfile, VQ_FULL, VQ_EMPTY, VINST, SCAL1, SCAL2, VINST_VALID);
        end if;

        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------

        -- VSETVLI --> VLMUL = 1 | VSEW = 16 | VTA=VMA=0 | VL=MAXVL 
        --------     |    VTYPEI     |  RS1    |  F3   |  RD     |  OPCODE  |
        VINST <= "0" & "00000001000" & "00000" & "111" & "11111" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        if (RUN_ALU_TEST) then
            test_alu(1, 16, vregfile, VQ_FULL, VQ_EMPTY, VINST, VINST_VALID);
        end if;

        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------

        -- VSETVLI --> VLMUL = 1 | VSEW = 32 | VTA=VMA=0 | VL=MAXVL 
        --------     |    VTYPEI     |  RS1    |  F3   |  RD     |  OPCODE  |
        VINST <= "0" & "00000010000" & "00000" & "111" & "11111" & "1010111";
        send_instruction(VQ_FULL, VINST_VALID);

        if (RUN_ALU_TEST) then
            test_alu(1, 32, vregfile, VQ_FULL, VQ_EMPTY, VINST, VINST_VALID);
        end if;

        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------
        --------------------------------------------------------------------------------------------

        while (VQ_EMPTY = '0') loop
            wait for 20 ns;
        end loop;
        wait for 160 ns;

        finish;
    end process;

end architecture tb;