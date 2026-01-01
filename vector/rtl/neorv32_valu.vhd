library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_valu is
    port(
        -- Clock and Reset --
        clk     : in std_ulogic;
        rst     : in std_ulogic;

        -- ALU Operation ID and Valid --
        alu_op  : in std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
        valid   : in std_ulogic;

        -- Vector Operands --
        op2     : in std_ulogic_vector(VLEN-1 downto 0);
        op1     : in std_ulogic_vector(VLEN-1 downto 0);
        op0     : in std_ulogic_vector(VLEN-1 downto 0);
        -- Vector Mask --
        vmask   : in std_ulogic_vector(VLEN-1 downto 0);
        -- Vector Selected Element Width --
        vsew    : in std_ulogic_vector(2 downto 0);

        -- ALU Result --
        alu_out : out std_ulogic_vector(VLEN-1 downto 0)
    );
end neorv32_valu;

architecture neorv32_valu_rtl of neorv32_valu is

    -- ALU Cycle Indication --
    signal valu_cyc : std_ulogic_vector(2 downto 0);
    
    -- Internal Vector Operands --
    signal op2_i     : std_ulogic_vector(VLEN-1 downto 0);
    signal op1_i     : std_ulogic_vector(VLEN-1 downto 0);
    signal op0_i     : std_ulogic_vector(VLEN-1 downto 0);
    signal vmask_i   : std_ulogic_vector(VLEN-1 downto 0);
    signal vsew_i    : std_ulogic_vector(2 downto 0);

    -- SUM/SUB Operation Signals --
    signal vcarry    : std_ulogic_vector((VLEN/8) downto 0);
    signal vcarry_in : std_ulogic_vector((VLEN/8) downto 0);
    signal add_temp  : std_ulogic_vector((VLEN-1)+(VLEN/8) downto 0);
    signal add_final : std_ulogic_vector(VLEN-1 downto 0);

    -- INT-EXT Operation Signals --
    signal ext16 : std_ulogic_vector(VLEN-1 downto 0);
    signal ext32 : std_ulogic_vector(VLEN-1 downto 0);

    -- BITWISE Operation Signals --
    signal logic_final : std_ulogic_vector(VLEN-1 downto 0);

    -- SHIFT Signals --
    signal shift_out  : std_ulogic_vector(VLEN-1 downto 0);
    signal narrow_out : std_ulogic_vector((VLEN/2)-1 downto 0);

    -- COMPARISON Signals --
    signal comp_out : std_ulogic_vector(VLEN-1 downto 0);

    -- MERGE Signals --
    signal merge_out : std_ulogic_vector(VLEN-1 downto 0);

    ---------------------------
    --- AUXILIARY FUNCTIONS ---
    ---------------------------
    
    -- SHIFT OPERATIONS FUNCTION --
    function shift_map(sew  : integer; 
                       op   : std_ulogic_vector; 
                       op_a : std_ulogic_vector; 
                       op_b : std_ulogic_vector) return std_ulogic_vector is
        variable result     : std_ulogic_vector(VLEN-1 downto 0);
        variable shift_bits : integer;
    begin
        -- Defines how many bits from the element will be used to define the shift amount --
        shift_bits := integer(ceil(log2(real(sew)))) - 1;

        -- Byte/Byte2/Byte4 indexation, based on SEW (8, 16, 32 bits) --
        for ii in 0 to ((VLEN / sew) - 1) loop
            case op is
                when valu_sll             => result(sew*ii+(sew-1) downto sew*ii) := std_ulogic_vector(shift_left(unsigned(op_a(sew*ii+(sew-1) downto sew*ii)),  to_integer(unsigned(op_b(sew*ii+shift_bits downto sew*ii)))));
                when valu_srl | valu_nsrl => result(sew*ii+(sew-1) downto sew*ii) := std_ulogic_vector(shift_right(unsigned(op_a(sew*ii+(sew-1) downto sew*ii)), to_integer(unsigned(op_b(sew*ii+shift_bits downto sew*ii)))));
                when valu_sra | valu_nsra => result(sew*ii+(sew-1) downto sew*ii) := std_ulogic_vector(shift_right(signed(op_a(sew*ii+(sew-1) downto sew*ii)),   to_integer(unsigned(op_b(sew*ii+shift_bits downto sew*ii)))));
                when others               => result(sew*ii+(sew-1) downto sew*ii) := (others => '0');
            end case;
        end loop;
        return result;
    end function shift_map;

    -- NARROW MAPPING FUNCTION --
    function narrow_map(sew     : integer;
                        operand : std_ulogic_vector) return std_ulogic_vector is
        variable result   : std_ulogic_vector((VLEN/2)-1 downto 0);
        variable half_sew : integer;
    begin
        half_sew := sew/2;
        for ii in 0 to ((VLEN / sew) - 1) loop
            result(half_sew*ii+(half_sew-1) downto half_sew*ii) := operand(sew*ii+(half_sew-1) downto sew*ii);
        end loop;
        return result;
    end function narrow_map;

    -- COMPARISON OPERATION FUNCTION --
    function compare_map(idx  : integer;
                         sew  : integer;
                         op   : std_ulogic_vector;
                         op_a : std_ulogic_vector;
                         op_b : std_ulogic_vector) return std_ulogic is
        variable comp   : std_ulogic := '0';
        variable result : std_ulogic := '0';
        variable a      : std_ulogic_vector(sew-1 downto 0) := (others => '0');
        variable b      : std_ulogic_vector(sew-1 downto 0) := (others => '0');
    begin
        if (idx < (VLEN / sew)) then
            a := op_a(sew*idx+(sew-1) downto sew*idx);
            b := op_b(sew*idx+(sew-1) downto sew*idx);
            case op is
                when valu_seq                           => comp := '1' when (a = b)                      else '0';
                when valu_sne                           => comp := '1' when (not (a = b))                else '0';
                when valu_sltu | valu_minu | valu_maxu  => comp := '1' when (unsigned(a) < unsigned(b))  else '0';
                when valu_slt  | valu_min  | valu_max   => comp := '1' when (signed(a) < signed(b))      else '0';
                when valu_sleu                          => comp := '1' when (unsigned(a) <= unsigned(b)) else '0';
                when valu_sle                           => comp := '1' when (signed(a) <= signed(b))     else '0';
                when valu_sgtu                          => comp := '1' when (unsigned(a) > unsigned(b))  else '0';
                when valu_sgt                           => comp := '1' when (signed(a) > signed(b))      else '0';
                when valu_sgeu                          => comp := '1' when (unsigned(a) >= unsigned(b)) else '0';
                when valu_sge                           => comp := '1' when (signed(a) >= signed(b))     else '0';
                when others                             => comp := '0';
            end case;
            result := comp;
        else 
            result := '0';
        end if;
        return result;
    end function compare_map;

begin

    -----------------------
    -- ALU State Machine --
    -----------------------
    process(clk, rst) begin
        if (rst = '1') then
            valu_cyc   <= "000";
        elsif rising_edge(clk) then
            case alu_op is
                when valu_waddu | valu_wsubu | valu_wadd | valu_wsub | valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew | valu_zext_vf2 | valu_sext_vf2 =>
                    valu_cyc <= "000" when (valu_cyc = "001") or (valid = '0') else std_ulogic_vector(unsigned(valu_cyc) + 1);
                when valu_zext_vf4 | valu_sext_vf4 =>
                    valu_cyc <= "000" when (valu_cyc = "011") or (valid = '0') else std_ulogic_vector(unsigned(valu_cyc) + 1);
                when others =>
                    valu_cyc <= "000" when (valu_cyc = "111") or (valid = '0') else std_ulogic_vector(unsigned(valu_cyc) + 1);
            end case;
        end if;
    end process;

    --------------------------------------
    -- ALU Internal Operands Definition --
    --------------------------------------
    process(all) 
        constant ZEROES : std_ulogic_vector((VLEN/2)-1 downto 0) := (others => '0');
    begin
        case alu_op is
            -- ADD/SUB + SINGLE-WIDTH WIDENING ADD/SUB + ADD/SUB W/ CARRY/BORROW IN --
            when valu_add | valu_sub | valu_adc | valu_madc | valu_sbc | valu_msbc =>
                vsew_i  <= vsew;
                op2_i   <= op2;
                op1_i   <= op1;
                op0_i   <= op0;
                alu_out <= add_final;
            -- SINGLE-WIDTH WIDENING OPERATIONS --
            when valu_waddu | valu_wsubu | valu_wadd | valu_wsub =>
                vsew_i  <= vsew;
                op2_i   <= op2;
                op1_i   <= op1;
                op0_i   <= op0;
                alu_out <= ext16 when (vsew = "000") else
                           ext32 when (vsew = "001") else
                           (others => '0');
            -- DOUBLE-WIDTH WIDENING OPERATIONS --
            when valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew =>
                vsew_i  <= "001" when (vsew = "000") else
                           "010" when (vsew = "001") else
                           (others => '0');
                op2_i   <= op2;
                op1_i   <= op1;
                op0_i   <= op0;
                alu_out <= add_final when (vsew = "000") or (vsew = "001") else
                           (others => '0');
            -- REVERSE SUB --
            when valu_rsub =>
                vsew_i  <= vsew;
                op2_i   <= op1;
                op1_i   <= op2;
                op0_i   <= op0;
                alu_out <= add_final;
            -- INTEGER EXTEND OPERATIONS --
            when valu_zext_vf2 | valu_sext_vf2 | valu_zext_vf4 | valu_sext_vf4 =>
                vsew_i  <= vsew;
                op2_i   <= op2;
                op1_i   <= op1;
                op0_i   <= op0;
                alu_out <= ext16 when (vsew = "001") else
                           ext32 when (vsew = "010") else
                           (others => '0');
            -- BITWISE LOGICAL --
            when valu_and | valu_or | valu_xor =>
                vsew_i  <= vsew;
                op2_i   <= op2;
                op1_i   <= op1;
                op0_i   <= op0;
                alu_out <= logic_final;
            -- SHIFT OPERATIONS --
            when valu_sll | valu_srl | valu_sra =>
                vsew_i  <= vsew;
                op2_i   <= op2;
                op1_i   <= op1;
                op0_i   <= op0;
                alu_out <= shift_out;
            -- NARROWING SHIFT OPERATIONS --
            when valu_nsrl | valu_nsra =>
                vsew_i  <= "001" when (vsew = "000") else
                           "010" when (vsew = "001") else
                           (others => '0');
                op2_i   <= op2;
                op1_i   <= op1;
                op0_i   <= op0;
                alu_out <= narrow_out & ZEROES when (valu_cyc(0) = '1') else ZEROES & narrow_out;
            -- COMPARISON OPERATIONS --
            when valu_seq | valu_sne  | valu_sltu | valu_slt | valu_sleu | valu_sle | valu_sgtu | valu_sgt | valu_sgeu | valu_sge =>
                vsew_i  <= vsew;
                op2_i   <= op2;
                op1_i   <= op1;
                op0_i   <= op0;
                alu_out <= comp_out;
            -- MIN/MAX AND MERGE OPERATIONS --
            when valu_minu | valu_min | valu_maxu | valu_max | valu_merge =>
                vsew_i  <= vsew;
                op2_i   <= op2;
                op1_i   <= op1;
                op0_i   <= op0;
                alu_out <= merge_out;
            -- UNSUPPORTED INSTRUCTION --
            when others =>
                vsew_i  <= (others => '0');
                op2_i   <= (others => '0');
                op1_i   <= (others => '0');
                op0_i   <= (others => '0');
                alu_out <= (others => '0');
        end case;
    end process;

    ----------------------------------------------------
    -- CARRY IN logic for carry_in/merge instructions --
    ----------------------------------------------------
    process(clk, rst) begin
        if (rst = '1') then
            vmask_i <= (others => '0');
        elsif rising_edge(clk) then
            vmask_i <= vmask_i srl (VLEN/8)  when ((vsew_i = "000") and (valid = '1')) else
                       vmask_i srl (VLEN/16) when ((vsew_i = "001") and (valid = '1')) else
                       vmask_i srl (VLEN/32) when ((vsew_i = "010") and (valid = '1')) else
                       vmask;
        end if;
    end process;
    --- This logic should be used by instructions like Sum w/ Carry_In, Merge Instructions---
    CARRY_IN_GENERATE : for ii in 0 to ((VLEN / 8) - 1) generate
        process(all) begin
            if ((alu_op = valu_adc) or (alu_op = valu_madc) or (alu_op = valu_sbc) or (alu_op = valu_msbc)) then
                case vsew_i is
                    when "000"  => vcarry_in(ii) <= vmask_i(ii);
                    when "001"  => vcarry_in(ii) <= vmask_i(ii/2) when ((ii mod 2) = 0) else '0';
                    when "010"  => vcarry_in(ii) <= vmask_i(ii/4) when ((ii mod 4) = 0) else '0';
                    when others => vcarry_in(ii) <= '0';
                end case;
            else
                vcarry_in(ii) <= '0';
            end if;
        end process;
    end generate CARRY_IN_GENERATE;

    ------------------------------------------------
    -- SUM logic for vadd/vsub/vrsub instructions --
    ------------------------------------------------
    vcarry(0) <= vcarry_in(0);
    SUM_GENERATE : for ii in 0 to ((VLEN / 8) - 1) generate
        -- Process to generate carry bits for SUM operation --
        process(all) begin
            -- If it's a multiple of 64 bits (done in case of expansion) --
            if ((ii mod 8) = 7) then
                vcarry(ii+1) <= vcarry_in(ii+1);
            -- If not met previous conditions and is multiple of 32 bits --
            elsif ((ii mod 4) = 3) then
                vcarry(ii+1) <= vcarry_in(ii+1) when ((vsew_i = "010") or (vsew_i = "001") or (vsew_i = "000")) else add_temp(9*ii+8);
            -- If not met previous conditions and is multiple of 16 bits --
            elsif ((ii mod 2) = 1) then
                vcarry(ii+1) <= vcarry_in(ii+1) when ((vsew_i = "001") or (vsew_i = "000")) else add_temp(9*ii+8);
            -- If not met previous conditions, then for each 8 bits --
            else
                vcarry(ii+1) <= vcarry_in(ii+1) when (vsew_i = "000") else add_temp(9*ii+8);
            end if;
        end process;

        -- Intermediary ADD result to extract carry bit --
        process(all) 
            variable op_a, op_b, ext_b : std_ulogic_vector(VLEN-1 downto 0);
        begin
            op_a  := op2_i;
            ext_b := ext16 when (vsew_i = "001") else
                     ext32 when (vsew_i = "010") else
                     (others => '0');
            op_b  := ext_b when (alu_op = valu_waddu_2sew) or (alu_op = valu_wsubu_2sew) or (alu_op = valu_wadd_2sew) or (alu_op = valu_wsub_2sew) else 
                     op1_i;
            
            case alu_op is
                when valu_add | valu_waddu_2sew | valu_wadd_2sew | valu_waddu | valu_wadd | valu_adc | valu_madc =>
                    add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op_a(8*ii+7 downto 8*ii)), 9) + resize(unsigned(op_b(8*ii+7 downto 8*ii)), 9) + vcarry(ii));
                when valu_sub | valu_wsubu_2sew | valu_wsub_2sew | valu_wsubu | valu_wsub | valu_sbc | valu_msbc | valu_rsub =>
                    add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op_a(8*ii+7 downto 8*ii)), 9) - resize(unsigned(op_b(8*ii+7 downto 8*ii)), 9) - vcarry(ii));
                when others =>
                    add_temp(9*ii+8 downto 9*ii) <= (others => '0');
            end case;
        end process;

        -- Final ADD result --
        add_final(8*ii+7 downto 8*ii) <= add_temp(9*ii+7 downto 9*ii);
    end generate SUM_GENERATE;

    -------------------------------------
    -- INT-EXT logic for SEW = 16 bits --
    -------------------------------------
    INT_EXT_16b : for ii in 0 to ((VLEN / 16) - 1) generate
        process(all)
            variable operand : std_ulogic_vector(VLEN-1 downto 0);
            variable offset_8b_1, offset_8b_2 : natural;
        begin
            operand := op1_i     when (alu_op = valu_waddu_2sew) or (alu_op = valu_wsubu_2sew) or (alu_op = valu_wadd_2sew) or (alu_op = valu_wsub_2sew) or (alu_op = valu_nsrl) or (alu_op = valu_nsra) else
                       add_final when (alu_op = valu_waddu) or (alu_op = valu_wsubu) or (alu_op = valu_wadd) or (alu_op = valu_wsub) else
                       op2_i;
            offset_8b_1 := 8*ii;
            offset_8b_2 := 8*(ii+(VLEN/16));

            -- INT-EXT: SEW/2 to SEW --
            if (alu_op = valu_zext_vf2) or (alu_op = valu_waddu_2sew) or (alu_op = valu_wsubu_2sew) or (alu_op = valu_nsrl) or (alu_op = valu_nsra) or (alu_op = valu_waddu) or (alu_op = valu_wsubu) then
                case valu_cyc is
                    when "000"  => ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_1+7 downto offset_8b_1)), 16));
                    when "001"  => ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_2+7 downto offset_8b_2)), 16));
                    when others => ext16(16*ii+15 downto 16*ii) <= (others => '0');
                end case;
            elsif (alu_op = valu_sext_vf2) or (alu_op = valu_wadd_2sew) or (alu_op = valu_wsub_2sew) or (alu_op = valu_wadd) or (alu_op = valu_wsub) then
                case valu_cyc is
                    when "000"  => ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_1+7 downto offset_8b_1)), 16));
                    when "001"  => ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_2+7 downto offset_8b_2)), 16));
                    when others => ext16(16*ii+15 downto 16*ii) <= (others => '0');
                end case;
            -- INT-EXT: UNSUPPORTED OPERATION --
            else
                ext16(16*ii+15 downto 16*ii) <= (others => '0');
            end if;
        end process;
    end generate INT_EXT_16b;

    -------------------------------------
    -- INT-EXT logic for SEW = 32 bits --
    -------------------------------------
    INT_EXT_32b : for ii in 0 to ((VLEN / 32) - 1) generate
        process(all)
            variable operand : std_ulogic_vector(VLEN-1 downto 0);
            variable offset_16b_1, offset_16b_2 : natural;
            variable offset_8b_1, offset_8b_2, offset_8b_3, offset_8b_4 : natural;
        begin
            operand := op1_i     when (alu_op = valu_waddu_2sew) or (alu_op = valu_wsubu_2sew) or (alu_op = valu_wadd_2sew) or (alu_op = valu_wsub_2sew) or (alu_op = valu_nsrl) or (alu_op = valu_nsra) else
                       add_final when (alu_op = valu_waddu) or (alu_op = valu_wsubu) or (alu_op = valu_wadd) or (alu_op = valu_wsub) else
                       op2_i;
            offset_16b_1 := 16*ii;
            offset_16b_2 := 16*(ii+(VLEN/32));
            offset_8b_1  := 8*ii;
            offset_8b_2  := 8*(ii+(VLEN/32));
            offset_8b_3  := 8*(ii+(2*(VLEN/32)));
            offset_8b_4  := 8*(ii+(3*(VLEN/32)));

            -- INT-EXT: SEW/2 to SEW --
            if (alu_op = valu_zext_vf2) or (alu_op = valu_waddu_2sew) or (alu_op = valu_wsubu_2sew) or (alu_op = valu_nsrl) or (alu_op = valu_nsra) or (alu_op = valu_waddu) or (alu_op = valu_wsubu) then
                case valu_cyc is
                    when "000"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_16b_1+15 downto offset_16b_1)), 32));
                    when "001"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_16b_2+15 downto offset_16b_2)), 32));
                    when others => ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end case;
            elsif (alu_op = valu_sext_vf2) or (alu_op = valu_wadd_2sew) or (alu_op = valu_wsub_2sew) or (alu_op = valu_wadd) or (alu_op = valu_wsub) then
                case valu_cyc is
                    when "000"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_16b_1+15 downto offset_16b_1)), 32));
                    when "001"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_16b_2+15 downto offset_16b_2)), 32));
                    when others => ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end case;
            -- INT-EXT: SEW/4 to SEW --
            elsif (alu_op = valu_zext_vf4) then
                case valu_cyc is
                    when "000"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_1+7 downto offset_8b_1)), 32));
                    when "001"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_2+7 downto offset_8b_2)), 32));
                    when "010"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_3+7 downto offset_8b_3)), 32));
                    when "011"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_4+7 downto offset_8b_4)), 32));
                    when others => ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end case;
            elsif (alu_op = valu_sext_vf4) then
                case valu_cyc is
                    when "000"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_1+7 downto offset_8b_1)), 32));
                    when "001"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_2+7 downto offset_8b_2)), 32));
                    when "010"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_3+7 downto offset_8b_3)), 32));
                    when "011"  => ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_4+7 downto offset_8b_4)), 32));
                    when others => ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end case;
            -- INT-EXT: UNSUPPORTED OPERATION --
            else
                ext32(32*ii+31 downto 32*ii) <= (others => '0');
            end if;
        end process;
    end generate INT_EXT_32b;

    --------------------------------------------------
    -- BITWISE logic for vand/vor/vxor instructions --
    --------------------------------------------------
    logic_final <= (op2_i and op1_i) when (alu_op = valu_and) else
                   (op2_i or op1_i)  when (alu_op = valu_or)  else
                   (op2_i xor op1_i) when (alu_op = valu_xor) else
                   (others => '0');    

    -------------------------------------
    -- DATAPATH for SHIFT instructions --
    -------------------------------------
    process(all) 
        variable shift_op : std_ulogic_vector(VLEN-1 downto 0);
    begin
        case alu_op is
            when valu_nsrl | valu_nsra => shift_op := ext16 when (vsew_i = "001") else ext32 when (vsew_i = "010") else (others => '0');
            when others                => shift_op := op1_i;
        end case;

        case vsew_i is
            when "000" => 
                shift_out  <= shift_map(8,  alu_op, op2_i, shift_op);
                narrow_out <= (others => '0');
            when "001" => 
                shift_out  <= shift_map(16, alu_op, op2_i, shift_op);
                narrow_out <= narrow_map(16, shift_out);
            when "010" => 
                shift_out  <= shift_map(32, alu_op, op2_i, shift_op);
                narrow_out <= narrow_map(32, shift_out);
            when others => 
                shift_out  <= (others => '0');
                narrow_out <= (others => '0');
        end case;
    end process;

    --------------------------------------------------------------
    -- DATAPATH for SEW = [8, 16, 32] bits COMPARE instructions --
    --------------------------------------------------------------
    COMP_DATAPATH: for idx in 0 to (VLEN - 1) generate
        process(all) begin
            case vsew_i is
                when "000"  => comp_out(idx) <= compare_map(idx, 8,  alu_op, op2_i, op1_i);
                when "001"  => comp_out(idx) <= compare_map(idx, 16, alu_op, op2_i, op1_i);
                when "010"  => comp_out(idx) <= compare_map(idx, 32, alu_op, op2_i, op1_i);
                when others => comp_out(idx) <= '0';
            end case;
        end process;
    end generate COMP_DATAPATH;

    -------------------------------
    -- DATAPATH for Vector Merge --
    -------------------------------
    MERGE_DATAPATH: for ii in 0 to ((VLEN / 8) - 1) generate
        process(all)
            variable op_a, op_b   : std_ulogic_vector(VLEN-1 downto 0);
            variable merge_mask   : std_ulogic_vector(VLEN-1 downto 0);
            variable pre_sel, sel : std_ulogic;
        begin
            op_a := op2_i;
            op_b := op1_i;
            merge_mask := vmask_i when (alu_op = valu_merge) else comp_out;
            pre_sel := merge_mask(ii)   when vsew_i = "000" else
                       merge_mask(ii/2) when vsew_i = "001" else
                       merge_mask(ii/4) when vsew_i = "010" else
                       '0';
            sel := (not pre_sel) when (alu_op = valu_minu) or (alu_op = valu_min) else pre_sel;
            merge_out(8*ii+7 downto 8*ii) <= op_b(8*ii+7 downto 8*ii) when (sel = '1') else op_a(8*ii+7 downto 8*ii);
        end process;
    end generate MERGE_DATAPATH;

end neorv32_valu_rtl;