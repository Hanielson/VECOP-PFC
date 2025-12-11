library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.neorv32_vpackage.all;

entity neorv32_valu is
    generic(
        VLEN : natural := 256;
        XLEN : natural := 32
    );
    port(
        -- Clock and Reset --
        clk     : in std_ulogic;
        rst     : in std_ulogic;

        -- Vector Operands --
        op2     : in std_ulogic_vector(VLEN-1 downto 0);
        op1     : in std_ulogic_vector(VLEN-1 downto 0);
        op0     : in std_ulogic_vector(VLEN-1 downto 0);
        -- ALU Operation ID --
        alu_id  : in std_ulogic_vector(7 downto 0);
        -- Vector Multiplier --
        vlmul   : in std_ulogic_vector(2 downto 0);
        -- Vector Mask --
        vmask   : in std_ulogic_vector(XLEN-1 downto 0);
        -- Vector Selected Element Width --
        vsew    : in std_ulogic_vector(2 downto 0);
        -- Narrow/Widen Operation Indication --
        narrow  : in std_ulogic;
        widen   : in std_ulogic;

        -- ALU Result --
        alu_out : out std_ulogic_vector(VLEN-1 downto 0)
    );
end neorv32_valu;

architecture neorv32_valu_rtl of neorv32_valu is

    -- ALU State Machine Signals --
    signal alu_cyc : std_ulogic_vector(2 downto 0);
    
    -- Internal Vector Operands --
    signal op2_i     : std_ulogic_vector(VLEN-1 downto 0);
    signal op1_i     : std_ulogic_vector(VLEN-1 downto 0);
    signal op0_i     : std_ulogic_vector(VLEN-1 downto 0);
    signal alu_out_i : std_ulogic_vector((8*VLEN)-1 downto 0);
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
    signal shift_out : std_ulogic_vector(VLEN-1 downto 0);

begin

    -----------------------
    -- ALU State Machine --
    -----------------------
    process(clk, rst) begin
        if rst then
            alu_cyc <= "000";
        elsif rising_edge(clk) then
            alu_cyc <= std_ulogic_vector(unsigned(alu_cyc) + 1);
        end if;
    end process;

    --------------------------------------
    -- ALU Internal Operands Definition --
    --------------------------------------
    process(all) begin
        case alu_id is
            -- ADD/SUB --
            when valu_add | valu_sub =>
                vsew_i  <= vsew;
                op2_i   <= op2;
                op1_i   <= op1;
                op0_i   <= op0;
                alu_out <= add_final;
            -- REVERSE SUB --
            when valu_rsub =>
                vsew_i  <= vsew;
                op2_i   <= op1;
                op1_i   <= op2;
                op0_i   <= op0;
                alu_out <= add_final;
            -- BITWISE LOGICAL --
            when valu_and | valu_or | valu_xor =>
                vsew_i  <= vsew;
                op2_i   <= op2;
                op1_i   <= op1;
                op0_i   <= op0;
                alu_out <= logic_final;
            -- UNSUPPORTED INSTRUCTION --
            when others =>
                vsew_i  <= (others => '0');
                op2_i   <= (others => '0');
                op1_i   <= (others => '0');
                op0_i   <= (others => '0');
                alu_out <= (others => '0');
        end case;
    end process;

    --- TODO: IMPLEMENT SEQUENTIAL LOGIC TO LOAD THE MASK, EXTRACT THE N-BITS TO BE USED AND SHIFT THE REGISTER WHEN IT'S DONE ---
    --- This logic should be used by instructions like Sum w/ Carry_In, Merge Instructions---
    vcarry_in(vcarry_in'left) <= '0';
    CARRY_IN_GENERATE : for ii in 0 to ((VLEN / 8) - 1) generate
        case sew is
            when "000"  => vcarry_in(ii) <= vmask_i(ii);
            when "001"  => vcarry_in(ii) <= vmask_i(ii/2) when ((ii mod 2) = 0) else '0';
            when "010"  => vcarry_in(ii) <= vmask_i(ii/4) when ((ii mod 4) = 0) else '0';
            when "011"  => vcarry_in(ii) <= vmask_i(ii/8) when ((ii mod 8) = 0) else '0';
            when others => vcarry_in(ii) <= vmask_i(ii/8) when ((ii mod 8) = 0) else '0';
        end case; 
    end generate CARRY_IN_GENERATE;

    ------------------------------------------------
    -- SUM logic for vadd/vsub/vrsub instructions --
    ------------------------------------------------
    vcarry(0) <= '0';
    SUM_GENERATE : for ii in 0 to ((VLEN / 8) - 1) generate
        -- Process to generate carry bits for SUM operation --
        process(all) begin
            -- If it's a multiple of 64 bits (done in case of expansion) --
            if ((ii mod 8) = 7) then
                vcarry(ii+1) <= '0';
            -- If not met previous conditions and is multiple of 32 bits --
            elsif ((ii mod 4) = 3) then
                vcarry(ii+1) <= '0' when ((vsew = "010") or (vsew = "001") or (vsew = "000")) else add_temp(9*ii+8);
            -- If not met previous conditions and is multiple of 16 bits --
            elsif ((ii mod 2) = 1) then
                vcarry(ii+1) <= '0' when ((vsew = "001") or (vsew = "000")) else add_temp(9*ii+8);
            -- If not met previous conditions, then for each byte --
            else
                vcarry(ii+1) <= '0' when (vsew = "000") else add_temp(9*ii+8);
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
            op_b  := ext_b when (alu_op = valu_waddu_2sew) or (alu_op = valu_wasubu_2sew) or (alu_op = valu_wadd_2sew) or (alu_op = valu_wsub_2sew) else op1_i;

            add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op_a(8*ii+7 downto 8*ii)), 9) + resize(unsigned(op_b(8*ii+7 downto 8*ii)), 9) + vcarry(ii)) when (alu_id = valu_add) else
                                            std_ulogic_vector(resize(unsigned(op_a(8*ii+7 downto 8*ii)), 9) - resize(unsigned(op_b(8*ii+7 downto 8*ii)), 9) + vcarry(ii));
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
            operand := op1_i     when (alu_op = valu_waddu_2sew) or (alu_op = valu_wasubu_2sew) or (alu_op = valu_wadd_2sew) or (alu_op = valu_wsub_2sew) else
                       add_final when (alu_op = valu_waddu) or (alu_op = valu_wasubu) or (alu_op = valu_wadd) or (alu_op = valu_wsub) else
                       op2_i;
            offset_8b_1 := 8*ii;
            offset_8b_2 := 8*ii+(VLEN/16);

            -- INT-EXT: SEW/2 to SEW --
            if (alu_op = valu_zext_vf2) or (alu_op = valu_waddu_2sew) or (alu_op = valu_wasubu_2sew) then
                if (alu_cyc = "000") then
                    ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_1+7 downto offset_8b_1)), 16));
                elsif (alu_cyc = "001") then
                    ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_2+7 downto offset_8b_2)), 16));
                else
                    ext16(16*ii+15 downto 16*ii) <= (others => '0');
                end if;
            elsif (alu_op = valu_sext_vf2) or (alu_op = valu_wadd_2sew) or (alu_op = valu_wsub_2sew) then
                if (alu_cyc = "000") then
                    ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_1+7 downto offset_8b_1)), 16));
                elsif (alu_cyc = "001") then
                    ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_2+7 downto offset_8b_2)), 16));
                else
                    ext16(16*ii+15 downto 16*ii) <= (others => '0');
                end if;
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
            operand := op1_i     when (alu_op = valu_waddu_2sew) or (alu_op = valu_wasubu_2sew) or (alu_op = valu_wadd_2sew) or (alu_op = valu_wsub_2sew) else
                       add_final when (alu_op = valu_waddu) or (alu_op = valu_wasubu) or (alu_op = valu_wadd) or (alu_op = valu_wsub) else
                       op2_i;
            offset_16b_1 := 16*ii;
            offset_16b_2 := 16*(ii+(VLEN/32));
            offset_8b_1  := 8*ii;
            offset_8b_2  := 8*(ii+(VLEN/32));
            offset_8b_3  := 8*(ii+(2*(VLEN/32)));
            offset_8b_4  := 8*(ii+(3*(VLEN/32)));

            -- INT-EXT: SEW/2 to SEW --
            if (alu_op = valu_zext_vf2) or (alu_op = valu_waddu_2sew) or (alu_op = valu_wasubu_2sew) then
                if (alu_cyc = "000") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_16b_1+15 downto offset_16b_1)), 32));
                elsif (alu_cyc = "001") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_16b_2+15 downto offset_16b_2)), 32));
                else
                    ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end if;
            elsif (alu_op = valu_sext_vf2) or (alu_op = valu_wadd_2sew) or (alu_op = valu_wsub_2sew) then
                if (alu_cyc = "000") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_16b_1+15 downto offset_16b_1)), 32));
                elsif (alu_cyc = "001") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_16b_2+15 downto offset_16b_2)), 32));
                else
                    ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end if;

            -- INT-EXT: SEW/4 to SEW --
            elsif (alu_op = valu_zext_vf4) then
                if (alu_cyc = "000") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_1+7 downto offset_8b_1)), 32));
                elsif (alu_cyc = "001") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_2+7 downto offset_8b_2)), 32));
                elsif (alu_cyc = "010") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_3+7 downto offset_8b_3)), 32));
                elsif (alu_cyc = "011") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(operand(offset_8b_4+7 downto offset_8b_4)), 32));
                else
                    ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end if;
            elsif (alu_op = valu_sext_vf4) then
                if (alu_cyc = "000") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_1+7 downto offset_8b_1)), 32));
                elsif (alu_cyc = "001") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_2+7 downto offset_8b_2)), 32));
                elsif (alu_cyc = "010") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_3+7 downto offset_8b_3)), 32));
                elsif (alu_cyc = "011") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(operand(offset_8b_4+7 downto offset_8b_4)), 32));
                else
                    ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end if;
            -- INT-EXT: UNSUPPORTED OPERATION --
            else
                ext32(32*ii+31 downto 32*ii) <= (others => '0');
            end if;
        end process;
    end generate INT_EXT_32b;

    --------------------------------------------------
    -- BITWISE logic for vand/vor/vxor instructions --
    --------------------------------------------------
    logic_final <= (op2_i and op1_i) when (alu_id = valu_and) else
                   (op2_i or op1_i)  when (alu_id = valu_or)  else
                   (op2_i xor op1_i) when (alu_id = valu_xor) else
                   (others => '0');    

    -------------------------------------
    -- DATAPATH for SHIFT instructions --
    -------------------------------------
    function shift_map(sew : integer, alu_id : std_ulogic_vector, op_a : std_ulogic_vector, op_b : std_ulogic_vector) return std_ulogic_vector(VLEN-1 downto 0) is
        variable result : std_ulogic_vector(VLEN-1 downto 0);
    begin
        -- Byte/Byte2/Byte4 indexation, based on SEW (8, 16, 32 bits) --
        for ii in 0 to ((VLEN / sew) - 1) loop
            case alu_id is
                when valu_sll => result(sew*ii+(sew-1) downto sew*ii) <= op_a(sew*ii+(sew-1) downto sew*ii) sll unsigned(op_b(sew*ii+(sew-1) downto sew*ii));
                when valu_srl => result(sew*ii+(sew-1) downto sew*ii) <= op_a(sew*ii+(sew-1) downto sew*ii) srl unsigned(op_b(sew*ii+(sew-1) downto sew*ii));
                when valu_sra => result(sew*ii+(sew-1) downto sew*ii) <= op_a(sew*ii+(sew-1) downto sew*ii) sra unsigned(op_b(sew*ii+(sew-1) downto sew*ii));
                when others   => result(sew*ii+(sew-1) downto sew*ii) <= (others => '0');
            end case;
        end loop;

        return result;
    end function shift_map;

    process(all) begin
        case vsew_i is
            when "000"  => shift_out <= shift_map(8,  alu_id, op2_i, op1_i);
            when "001"  => shift_out <= shift_map(16, alu_id, op2_i, op1_i);
            when "010"  => shift_out <= shift_map(32, alu_id, op2_i, op1_i);
            when others => shift_out <= (others => '0');
        end case;
    end process;

    --------------------------------------------------------------
    -- DATAPATH for SEW = [8, 16, 32] bits COMPARE instructions --
    --------------------------------------------------------------
    function compare_map(idx : integer, sew : integer, alu_id : std_ulogic_vector, op_a : std_ulogic_vector, op_b : std_ulogic_vector) return std_ulogic is
        variable comp   : std_ulogic := '0';
        variable result : std_ulogic := '0';
        variable a      : std_ulogic_vector(sew-1 downto 0) := (others => "0");
        variable b      : std_ulogic_vector(sew-1 downto 0) := (others => "0");
    begin

        if (idx < (VLEN / sew)) then
            a := op_a(sew*idx+(sew-1) downto sew*idx);
            b := op_b(sew*idx+(sew-1) downto sew*idx);
            case alu_id is
                when valu_seq  => comp := '1' when (a = b) else '0';
                when valu_sne  => comp := '1' when (not (a = b)) else '0';
                when valu_sltu => comp := (unsigned(a) < unsigned(b));
                when valu_slt  => comp := (signed(a) < signed(b));
                when valu_sleu => comp := (unsigned(a) <= unsigned(b));
                when valu_sle  => comp := (signed(a) <= signed(b));
                when valu_sgtu => comp := (unsigned(a) > unsigned(b));
                when valu_sgt  => comp := (signed(a) > signed(b));
                when valu_sgeu => comp := (unsigned(a) >= unsigned(b));
                when valu_sge  => comp := (signed(a) >= signed(b));
                when others    => comp := '0';
            end case;
            result := comp;
        else 
            result := '0';
        end if;

        return result;
    end function compare_map;

    COMP_DATAPATH: for idx in 0 to (VLEN - 1) generate
        case vsew_i is
            when "000"  => comp_out(idx) <= compare_map(idx, 8,  alu_id, op2_i, op1_i);
            when "001"  => comp_out(idx) <= compare_map(idx, 16, alu_id, op2_i, op1_i);
            when "010"  => comp_out(idx) <= compare_map(idx, 32, alu_id, op2_i, op1_i);
            when others => comp_out(idx) <= '0';
        end case;
    end generate COMP_DATAPATH;

end neorv32_valu_rtl;