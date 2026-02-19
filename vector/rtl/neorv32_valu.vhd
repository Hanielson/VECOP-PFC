library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_valu is
    port(
        -- Clock and Reset --
        clk      : in std_ulogic;
        rst      : in std_ulogic;
        -- ALU Operation ID and Valid --
        alu_op   : in std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
        valid    : in std_ulogic;
        -- Vector Operands --
        op2      : in std_ulogic_vector(VLEN-1 downto 0);
        op1      : in std_ulogic_vector(VLEN-1 downto 0);
        op0      : in std_ulogic_vector(VLEN-1 downto 0);
        -- Vector Mask --
        vmask    : in std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
        -- Vector Selected Element Width --
        vsew     : in std_ulogic_vector(2 downto 0);
        -- ALU Result --
        alu_out  : out std_ulogic_vector(VLEN-1 downto 0);
        alu_done : out std_ulogic
    );
end neorv32_valu;

architecture neorv32_valu_rtl of neorv32_valu is
    -- V-ALU Internal State Machine --
    type alu_state_t is (IDLE, EXEC_CHUNK, DONE);
    signal state         : alu_state_t;
    signal chunk_counter : std_ulogic_vector(CHUNK_CNT_W-1 downto 0);
    signal cycle_counter : std_ulogic_vector(2 downto 0);

    -- Chunk Type Definition --
    type chunk_array_t is array ((VLEN/VALU_CHUNK_W)-1 downto 0) of std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    signal op2_chunks : chunk_array_t;
    signal op0_chunks : chunk_array_t;
    signal op1_chunks : chunk_array_t;
    signal out_chunks : chunk_array_t;

    -- Mask Chunk Type Definition --
    type m8_chunk_t is array((VLEN/VALU_CHUNK_W)-1 downto 0) of std_ulogic_vector((VALU_CHUNK_W/8)-1 downto 0);
    signal m8_chunks : m8_chunk_t;
    type m16_chunk_t is array((VLEN/VALU_CHUNK_W)-1 downto 0) of std_ulogic_vector((VALU_CHUNK_W/16)-1 downto 0);
    signal m16_chunks : m16_chunk_t;
    type m32_chunk_t is array((VLEN/VALU_CHUNK_W)-1 downto 0) of std_ulogic_vector((VALU_CHUNK_W/32)-1 downto 0);
    signal m32_chunks : m32_chunk_t;
    
    -- Internal Vector Operands --
    signal op2_i     : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    signal op1_i     : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    signal op0_i     : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    signal alu_out_i : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    signal vmask_i   : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    signal vsew_i    : std_ulogic_vector(2 downto 0);
    
    -- SUM/SUB Operation Signals --
    signal vcarry     : std_ulogic_vector((VALU_CHUNK_W/8) downto 0);
    signal vcarry_in  : std_ulogic_vector((VALU_CHUNK_W/8) downto 0);
    signal vcarry_out : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    signal add_temp   : std_ulogic_vector((VALU_CHUNK_W-1)+(VALU_CHUNK_W/8) downto 0);
    signal add_final  : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    
    -- INT-EXT Operation Signals --f
    type extend_array_t is array (2 downto 0) of std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    signal extended : extend_array_t;
    
    -- BITWISE Operation Signals --
    signal logic_final : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    
    -- SHIFT Signals --
    signal shift_out  : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    signal narrow_out : std_ulogic_vector((VALU_CHUNK_W/2)-1 downto 0);
    
    -- COMPARISON Signals --
    signal comp_out : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    
    -- MERGE Signals --
    signal merge_out : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);

    ---------------------------
    --- AUXILIARY FUNCTIONS ---
    ---------------------------
    function shift_map(sew  : integer; 
                       op   : std_ulogic_vector; 
                       op_a : std_ulogic_vector; 
                       op_b : std_ulogic_vector) return std_ulogic_vector is
        variable result     : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
        variable shift_bits : integer;
    begin
        -- Defines how many bits from the element will be used to define the shift amount --
        shift_bits := integer(ceil(log2(real(sew)))) - 1;
        -- Byte/Byte2/Byte4 indexation, based on SEW (8, 16, 32 bits) --
        for ii in 0 to ((VALU_CHUNK_W/sew)-1) loop
            case op is
                when valu_sll             => result(sew*ii+(sew-1) downto sew*ii) := std_ulogic_vector(shift_left(unsigned(op_a(sew*ii+(sew-1) downto sew*ii)),  to_integer(unsigned(op_b(sew*ii+shift_bits downto sew*ii)))));
                when valu_srl | valu_nsrl => result(sew*ii+(sew-1) downto sew*ii) := std_ulogic_vector(shift_right(unsigned(op_a(sew*ii+(sew-1) downto sew*ii)), to_integer(unsigned(op_b(sew*ii+shift_bits downto sew*ii)))));
                when valu_sra | valu_nsra => result(sew*ii+(sew-1) downto sew*ii) := std_ulogic_vector(shift_right(signed(op_a(sew*ii+(sew-1) downto sew*ii)),   to_integer(unsigned(op_b(sew*ii+shift_bits downto sew*ii)))));
                when others               => result(sew*ii+(sew-1) downto sew*ii) := (others => '0');
            end case;
        end loop;
        return result;
    end function shift_map;

    function narrow_map(sew     : integer;
                        operand : std_ulogic_vector) return std_ulogic_vector is
        variable result   : std_ulogic_vector((VALU_CHUNK_W/2)-1 downto 0);
        variable half_sew : integer;
    begin
        half_sew := sew/2;
        for ii in 0 to ((VALU_CHUNK_W/sew)-1) loop
            result(half_sew*ii+(half_sew-1) downto half_sew*ii) := operand(sew*ii+(half_sew-1) downto sew*ii);
        end loop;
        return result;
    end function narrow_map;

    function compare_map(idx     : integer;
                         sew     : integer;
                         alu_op  : std_ulogic_vector;
                         op_a    : std_ulogic_vector;
                         op_b    : std_ulogic_vector;
                         sub_out : std_ulogic_vector;
                         carry   : std_ulogic_vector) return std_ulogic is
        variable comp                     : std_ulogic := '0';
        variable result                   : std_ulogic := '0';
        variable elem                     : std_ulogic_vector(sew-1 downto 0) := (others => '0');
        variable borrow, ovflw, zero, neg : std_ulogic;
        variable ELEM_MSB, ELEM_LSB : natural;
        variable OP_MSB : natural;
    begin
        ELEM_MSB := sew*idx+(sew-1);
        ELEM_LSB := sew*idx;
        
        if (idx < (VALU_CHUNK_W / sew)) then
            elem   := sub_out(ELEM_MSB downto ELEM_LSB);
            borrow := carry(idx);
            ovflw  := (op_a(ELEM_MSB) xor op_b(ELEM_MSB)) and (elem(elem'left) xor op_a(ELEM_MSB));
            zero   := not (or elem);
            neg    := elem(elem'left);
            case alu_op is
                when valu_se                            => result := '1' when (zero = '1')                                    else '0';
                when valu_sne                           => result := '0' when (zero = '1')                                    else '1';
                when valu_sltu | valu_minu | valu_maxu  => result := '1' when (borrow = '1')                                  else '0';
                when valu_sgeu                          => result := '0' when (borrow = '1')                                  else '1';
                when valu_slt  | valu_min  | valu_max   => result := '1' when (neg = '1') xor (ovflw = '1')                   else '0';
                when valu_sge                           => result := '0' when (neg = '1') xor (ovflw = '1')                   else '1';
                when valu_sgt                           => result := '0' when ((neg = '1') xor (ovflw = '1')) or (zero = '1') else '1';
                when valu_sle                           => result := '1' when ((neg = '1') xor (ovflw = '1')) or (zero = '1') else '0';
                when valu_sgtu                          => result := '1' when (borrow = '0') and (zero = '0')                 else '0';
                when valu_sleu                          => result := '0' when (borrow = '0') and (zero = '0')                 else '1';
                when others                             => result := '0';
            end case;
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
            state         <= IDLE;
            chunk_counter <= (others => '0');
            cycle_counter <= (others => '0');
        elsif rising_edge(clk) then
            case state is
                -- IDLE state --
                when IDLE => 
                    state <= EXEC_CHUNK when (valid = '1') else IDLE;
                    chunk_counter <= (others => '0');
                -- Execute Chunk (32-bits) state --
                when EXEC_CHUNK =>
                    if (chunk_counter = std_ulogic_vector(to_unsigned(MAX_CHUNK - 1, CHUNK_CNT_W))) then
                        state <= DONE;
                        case alu_op is
                            when valu_waddu | valu_wsubu | valu_wadd | valu_wsub | valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew | valu_zext_vf2 | valu_sext_vf2 =>
                                cycle_counter <= "000" when (cycle_counter = "001") else std_ulogic_vector(unsigned(cycle_counter) + 1);
                            when valu_zext_vf4 | valu_sext_vf4 =>
                                cycle_counter <= "000" when (cycle_counter = "011") else std_ulogic_vector(unsigned(cycle_counter) + 1);
                            when others =>
                                cycle_counter <= "000";
                        end case;
                    else
                        chunk_counter <= std_ulogic_vector(unsigned(chunk_counter) + to_unsigned(1, chunk_counter'length));
                    end if;
                -- DONE state --
                when DONE =>
                    state <= IDLE when (valid = '0') else DONE;
                -- Invalid States --
                when others => state <= IDLE;
            end case;
        end if;
    end process;

    alu_done <= '1' when (state = DONE) else '0';

    ------------------------------
    -- Chunk Mapping/Extraction --
    ------------------------------
    IN_CHUNK_MAPPING: for ii in 0 to (VLEN/VALU_CHUNK_W)-1 generate
        op2_chunks(ii) <= op2((ii*VALU_CHUNK_W)+(VALU_CHUNK_W-1) downto (ii*VALU_CHUNK_W));
        op1_chunks(ii) <= op1((ii*VALU_CHUNK_W)+(VALU_CHUNK_W-1) downto (ii*VALU_CHUNK_W));
        op0_chunks(ii) <= op0((ii*VALU_CHUNK_W)+(VALU_CHUNK_W-1) downto (ii*VALU_CHUNK_W));
    end generate IN_CHUNK_MAPPING;

    OUT_CHUNK_EXTRACTING: for ii in 0 to alu_out'length-1 generate
        OUT_CHUNK_EXTRACTING_INTERNAL: if (ii < (m32_chunks'length * m32_chunks(0)'length)) generate
            process(all) begin
                case alu_op is
                    when valu_se | valu_sne | valu_sltu | valu_slt | valu_sleu | valu_sle | valu_sgtu | valu_sgt | valu_sgeu | valu_sge =>
                        case vsew_i is
                            when "000"  => alu_out(ii) <= m8_chunks(ii/m8_chunks(0)'length)(ii mod m8_chunks(0)'length);
                            when "001"  => alu_out(ii) <= m16_chunks(ii/m16_chunks(0)'length)(ii mod m16_chunks(0)'length);
                            when "010"  => alu_out(ii) <= m32_chunks(ii/m32_chunks(0)'length)(ii mod m32_chunks(0)'length);
                            when others => alu_out(ii) <= '0';
                        end case;

                    when others =>
                        alu_out(ii) <= out_chunks(ii/VALU_CHUNK_W)(ii mod VALU_CHUNK_W);
                end case;
            end process;
            
        elsif (ii < (m16_chunks'length * m16_chunks(0)'length)) generate
            process(all) begin
                case alu_op is
                    when valu_se | valu_sne | valu_sltu | valu_slt | valu_sleu | valu_sle | valu_sgtu | valu_sgt | valu_sgeu | valu_sge =>
                        case vsew_i is
                            when "000"  => alu_out(ii) <= m8_chunks(ii/m8_chunks(0)'length)(ii mod m8_chunks(0)'length);
                            when "001"  => alu_out(ii) <= m16_chunks(ii/m16_chunks(0)'length)(ii mod m16_chunks(0)'length);
                            when others => alu_out(ii) <= '0';
                        end case;

                    when others =>
                        alu_out(ii) <= out_chunks(ii/VALU_CHUNK_W)(ii mod VALU_CHUNK_W);
                end case;
            end process;

        elsif (ii < (m8_chunks'length  * m8_chunks(0)'length)) generate
            process(all) begin
                case alu_op is
                    when valu_se | valu_sne | valu_sltu | valu_slt | valu_sleu | valu_sle | valu_sgtu | valu_sgt | valu_sgeu | valu_sge =>
                        case vsew_i is
                            when "000"  => alu_out(ii) <= m8_chunks(ii/m8_chunks(0)'length)(ii mod m8_chunks(0)'length);
                            when others => alu_out(ii) <= '0';
                        end case;

                    when others =>
                        alu_out(ii) <= out_chunks(ii/VALU_CHUNK_W)(ii mod VALU_CHUNK_W);
                end case;
            end process;

        else generate
            process(all) begin
                case alu_op is
                    when valu_se | valu_sne | valu_sltu | valu_slt | valu_sleu | valu_sle | valu_sgtu | valu_sgt | valu_sgeu | valu_sge =>
                        alu_out(ii) <= '0';

                    when others =>
                        alu_out(ii) <= out_chunks(ii/VALU_CHUNK_W)(ii mod VALU_CHUNK_W);
                end case;
            end process;        
        end generate OUT_CHUNK_EXTRACTING_INTERNAL;
    end generate OUT_CHUNK_EXTRACTING;

    -- Input Operands Chunk --
    process(all) begin
        case alu_op is
            -- Widening Operations with Same-Width Operands --
            when valu_waddu | valu_wsubu | valu_wadd | valu_wsub | valu_zext_vf2 | valu_sext_vf2=>
                op0_i <= (others => '0');
                case chunk_counter is
                    when "00" | "01" => 
                        op2_i <= op2_chunks(2) when (cycle_counter = "001") else op2_chunks(0);
                        op1_i <= op1_chunks(2) when (cycle_counter = "001") else op1_chunks(0);
                    when "10" | "11" => 
                        op2_i <= op2_chunks(3) when (cycle_counter = "001") else op2_chunks(1);
                        op1_i <= op1_chunks(3) when (cycle_counter = "001") else op1_chunks(1);
                    when others =>
                        op2_i <= (others => '0');
                        op1_i <= (others => '0');
                end case;

            -- Widening/Narrowing Operations with Multi-Width Operands (2*SEW and SEW) --
            when valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew | valu_nsrl | valu_nsra =>
                op0_i <= (others => '0');
                case chunk_counter is
                    when "00" => 
                        op2_i <= op2_chunks(0);
                        op1_i <= op1_chunks(2) when (cycle_counter = "001") else op1_chunks(0);
                    when "01" =>
                        op2_i <= op2_chunks(1);
                        op1_i <= op1_chunks(2) when (cycle_counter = "001") else op1_chunks(0);
                    when "10" => 
                        op2_i <= op2_chunks(2);
                        op1_i <= op1_chunks(3) when (cycle_counter = "001") else op1_chunks(1);
                    when "11" =>
                        op2_i <= op2_chunks(3);
                        op1_i <= op1_chunks(3) when (cycle_counter = "001") else op1_chunks(1);
                    when others =>
                        op2_i <= (others => '0');
                        op1_i <= (others => '0');
                end case;
            
            -- Widening Operations with SEW/4 operands --
            when valu_zext_vf4 | valu_sext_vf4 =>
                op1_i <= (others => '0');
                op0_i <= (others => '0');
                -- No need to check for chunk_counter, as for each full cycle_counter we'll stay with the same pointer --
                case cycle_counter is
                    when "000"  => op2_i <= op2_chunks(0);
                    when "001"  => op2_i <= op2_chunks(1);
                    when "010"  => op2_i <= op2_chunks(2);
                    when "011"  => op2_i <= op2_chunks(3);
                    when others => op2_i <= (others => '0');
                end case;

            -- Other types of operations --
            when others =>
                case chunk_counter is
                    when "00"   => op2_i <= op2_chunks(0)  ; op1_i <= op1_chunks(0)  ; op0_i <= op0_chunks(0);
                    when "01"   => op2_i <= op2_chunks(1)  ; op1_i <= op1_chunks(1)  ; op0_i <= op0_chunks(1);
                    when "10"   => op2_i <= op2_chunks(2)  ; op1_i <= op1_chunks(2)  ; op0_i <= op0_chunks(2);
                    when "11"   => op2_i <= op2_chunks(3)  ; op1_i <= op1_chunks(3)  ; op0_i <= op0_chunks(3);
                    when others => op2_i <= (others => '0'); op1_i <= (others => '0'); op0_i <= (others => '0');
                end case;
        end case;
    end process;

    -----------------------------------
    -- Output Chunk Generation Logic --
    -----------------------------------
    process(clk, rst) begin
        if (rst = '1') then
            out_chunks <= (others => (others => '0'));
            m8_chunks  <= (others => (others => '0'));
            m16_chunks <= (others => (others => '0'));
            m32_chunks <= (others => (others => '0'));
        elsif rising_edge(clk) then
            case state is
                when IDLE => 
                    out_chunks <= (others => (others => '0'));
                    m8_chunks  <= (others => (others => '0'));
                    m16_chunks <= (others => (others => '0'));
                    m32_chunks <= (others => (others => '0'));
                
                when EXEC_CHUNK => 
                    out_chunks(to_integer(unsigned(chunk_counter))) <= alu_out_i;
                    m8_chunks(to_integer(unsigned(chunk_counter)))  <= alu_out_i((VALU_CHUNK_W/8)-1 downto 0);
                    m16_chunks(to_integer(unsigned(chunk_counter))) <= alu_out_i((VALU_CHUNK_W/16)-1 downto 0);
                    m32_chunks(to_integer(unsigned(chunk_counter))) <= alu_out_i((VALU_CHUNK_W/32)-1 downto 0);
                
                when others => 
                    out_chunks <= out_chunks;
                    m8_chunks  <= m8_chunks;
                    m16_chunks <= m16_chunks;
                    m32_chunks <= m32_chunks;
            end case;
        end if;
    end process;

    --------------------------------------
    -- ALU Internal Operands Definition --
    --------------------------------------
    process(all) 
        constant ZEROES : std_ulogic_vector((VALU_CHUNK_W/2)-1 downto 0) := (others => '0');
    begin
        case alu_op is
            -- ADD/SUB + SINGLE-WIDTH WIDENING ADD/SUB + ADD/SUB W/ CARRY/BORROW IN --
            when valu_add | valu_sub | valu_adc | valu_madc | valu_sbc | valu_msbc =>
                vsew_i    <= vsew;
                alu_out_i <= add_final;
            -- SINGLE-WIDTH WIDENING OPERATIONS --
            when valu_waddu | valu_wsubu | valu_wadd | valu_wsub =>
                vsew_i    <= "001" when (vsew = "000") else
                             "010" when (vsew = "001") else
                             "111";
                alu_out_i <= add_final when (vsew = "000") or (vsew = "001") else (others => '0');
            -- DOUBLE-WIDTH WIDENING OPERATIONS --
            when valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew =>
                vsew_i    <= "001" when (vsew = "000") else
                             "010" when (vsew = "001") else
                             "111";
                alu_out_i <= add_final when (vsew = "000") or (vsew = "001") else (others => '0');
            -- REVERSE SUB --
            when valu_rsub =>
                vsew_i    <= vsew;
                alu_out_i <= add_final;
            -- INTEGER EXTEND OPERATIONS --
            when valu_zext_vf2 | valu_sext_vf2 | valu_zext_vf4 | valu_sext_vf4 =>
                vsew_i    <= vsew;
                alu_out_i <= extended(2);
            -- BITWISE LOGICAL --
            when valu_and | valu_or | valu_xor =>
                vsew_i    <= vsew;
                alu_out_i <= logic_final;
            -- SHIFT OPERATIONS --
            when valu_sll | valu_srl | valu_sra =>
                vsew_i    <= vsew;
                alu_out_i <= shift_out;
            -- NARROWING SHIFT OPERATIONS --
            when valu_nsrl | valu_nsra =>
                vsew_i    <= "001" when (vsew = "000") else
                             "010" when (vsew = "001") else
                             "111";
                alu_out_i <= narrow_out & ZEROES when ((vsew = "000") or (vsew = "001")) and (cycle_counter(0) = '1') else 
                             ZEROES & narrow_out when ((vsew = "000") or (vsew = "001")) and (cycle_counter(0) = '0') else
                             (others => '0');
            -- COMPARISON OPERATIONS --
            when valu_se | valu_sne | valu_sltu | valu_slt | valu_sleu | valu_sle | valu_sgtu | valu_sgt | valu_sgeu | valu_sge =>
                vsew_i    <= vsew;
                alu_out_i <= comp_out;
            -- MIN/MAX AND MERGE OPERATIONS --
            when valu_minu | valu_min | valu_maxu | valu_max | valu_merge =>
                vsew_i    <= vsew;
                alu_out_i <= merge_out;
            -- UNSUPPORTED INSTRUCTION --
            when others =>
                vsew_i    <= (others => '0');
                alu_out_i <= (others => '0');
        end case;
    end process;

    ----------------------------------------------------
    -- CARRY IN logic for carry_in/merge instructions --
    ----------------------------------------------------
    process(clk, rst) begin
        if (rst = '1') then
            vmask_i <= (others => '0');
        elsif rising_edge(clk) then
            case state is
                when IDLE => 
                    vmask_i <= vmask when (cycle_counter = "000") else vmask_i;
                when EXEC_CHUNK =>
                    vmask_i <= vmask_i srl 4 when (vsew_i = "000") else
                               vmask_i srl 2 when (vsew_i = "001") else
                               vmask_i srl 1 when (vsew_i = "010") else
                               vmask_i;
                when DONE => 
                    vmask_i <= vmask_i;
            end case;
        end if;
    end process;

    --- This logic should be used by instructions like Sum w/ Carry_In, Merge Instructions---
    vcarry_in(vcarry_in'left) <= '0';
    CARRY_IN_GENERATE : for ii in 0 to (VALU_CHUNK_W/8)-1 generate
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

    ---------------------------------
    -- CARRY bits generation logic --
    ---------------------------------
    CARRY_OUT_GENERATE: for ii in 0 to (VALU_CHUNK_W-1) generate
        CARRY_OUT_GENERATE_INTERNAL: if (ii < (VALU_CHUNK_W/32)) generate
            process(all) begin
                case vsew_i is
                    when "000"  => vcarry_out(ii) <= add_temp(9*ii+8);
                    when "001"  => vcarry_out(ii) <= add_temp(18*ii+17);
                    when "010"  => vcarry_out(ii) <= add_temp(36*ii+35);
                    when others => vcarry_out(ii) <= '0';
                end case;
            end process;

        elsif (ii < (VALU_CHUNK_W/16)) generate
            process(all) begin
                case vsew_i is
                    when "000"  => vcarry_out(ii) <= add_temp(9*ii+8);
                    when "001"  => vcarry_out(ii) <= add_temp(18*ii+17);
                    when others => vcarry_out(ii) <= '0';
                end case;
            end process;

        elsif (ii < (VALU_CHUNK_W/8)) generate
            process(all) begin
                case vsew_i is
                    when "000"  => vcarry_out(ii) <= add_temp(9*ii+8);
                    when others => vcarry_out(ii) <= '0';
                end case;
            end process;

        else generate
            vcarry_out(ii) <= '0';
        end generate CARRY_OUT_GENERATE_INTERNAL;
    end generate CARRY_OUT_GENERATE;

    ------------------------------------------------
    -- SUM logic for vadd/vsub/vrsub instructions --
    ------------------------------------------------
    vcarry(0) <= vcarry_in(0);
    SUM_GENERATE : for ii in 0 to (VALU_CHUNK_W/8)-1 generate
        -- Process to generate carry bits for SUM operation --
        process(all) begin
            -- If it's a multiple of 32 bits --
            if ((ii mod 4) = 3) then
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
            variable op_a, op_b : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
        begin
            case alu_op is
                when valu_waddu_2sew | valu_waddu =>
                    op_a := extended(2) when (alu_op = valu_waddu) else op2_i;
                    op_b := extended(1) when (alu_op = valu_waddu) or (alu_op = valu_waddu_2sew) else op1_i;
                    add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op_a(8*ii+7 downto 8*ii)), 9) + resize(unsigned(op_b(8*ii+7 downto 8*ii)), 9) + vcarry(ii));

                when valu_add | valu_wadd_2sew | valu_wadd | valu_adc | valu_madc =>
                    op_a := extended(2) when (alu_op = valu_wadd) else op2_i;
                    op_b := extended(1) when (alu_op = valu_wadd) or (alu_op = valu_wadd_2sew) else op1_i;
                    add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op_a(8*ii+7 downto 8*ii)), 9) + resize(unsigned(op_b(8*ii+7 downto 8*ii)), 9) + vcarry(ii));

                when valu_wsubu_2sew | valu_wsubu | valu_sltu | valu_sleu | valu_sgtu | valu_sgeu | valu_minu | valu_maxu  =>
                    op_a := extended(2) when (alu_op = valu_wsubu) else op2_i;
                    op_b := extended(1) when (alu_op = valu_wsubu) or (alu_op = valu_wsubu_2sew) else op1_i;
                    add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op_a(8*ii+7 downto 8*ii)), 9) - resize(unsigned(op_b(8*ii+7 downto 8*ii)), 9) - vcarry(ii));

                when valu_sub | valu_wsub_2sew | valu_wsub | valu_sbc  | valu_msbc | valu_se  | 
                     valu_sne | valu_slt       | valu_sle  | valu_sgt  | valu_sge  | valu_min | valu_max =>
                    op_a := extended(2) when (alu_op = valu_wsub) else op2_i;
                    op_b := extended(1) when (alu_op = valu_wsub) or (alu_op = valu_wsub_2sew) else op1_i;
                    add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op_a(8*ii+7 downto 8*ii)), 9) - resize(unsigned(op_b(8*ii+7 downto 8*ii)), 9) - vcarry(ii));

                when valu_rsub =>
                    add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op1_i(8*ii+7 downto 8*ii)), 9) - resize(unsigned(op2_i(8*ii+7 downto 8*ii)), 9) - vcarry(ii));

                when others =>
                    add_temp(9*ii+8 downto 9*ii) <= (others => '0');
            end case;
        end process;
        -- Final ADD result --
        add_final(8*ii+7 downto 8*ii) <= add_temp(9*ii+7 downto 9*ii);
    end generate SUM_GENERATE;

    ------------------------------------------------
    --- ELEMENT EXTENSION (one for each operand) ---
    ------------------------------------------------
    EXTEND_GENERATE: for ii in 0 to 2 generate
        process(all)
            variable operand : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
        begin
            -- Define Source of Extension --
            case ii is
                when      0 => operand := op0_i;
                when      1 => operand := op1_i;
                when      2 => operand := op2_i;
                when others => null;
            end case;

            -- Extend Elements on Chunk --
            case vsew_i is
                -- SEW = 16 bits --
                when "001" =>
                    case alu_op is
                        when valu_zext_vf2 | valu_waddu_2sew | valu_wsubu_2sew | valu_nsrl | valu_nsra | valu_waddu | valu_wsubu =>
                            case chunk_counter(0) is
                                when '0' =>
                                    extended(ii)(15 downto 0)  <= std_ulogic_vector(resize(unsigned(operand(7 downto 0)), 16));
                                    extended(ii)(31 downto 16) <= std_ulogic_vector(resize(unsigned(operand(15 downto 8)), 16));
                                when '1' =>
                                    extended(ii)(15 downto 0)  <= std_ulogic_vector(resize(unsigned(operand(23 downto 16)), 16));
                                    extended(ii)(31 downto 16) <= std_ulogic_vector(resize(unsigned(operand(31 downto 24)), 16));
                                when others =>
                                    extended(ii)(15 downto 0)  <= (others => '0');
                                    extended(ii)(31 downto 16) <= (others => '0');
                            end case;

                        when valu_sext_vf2 | valu_wadd_2sew | valu_wsub_2sew | valu_wadd | valu_wsub =>
                            case chunk_counter(0) is
                                when '0' =>
                                    extended(ii)(15 downto 0)  <= std_ulogic_vector(resize(signed(operand(7 downto 0)), 16));
                                    extended(ii)(31 downto 16) <= std_ulogic_vector(resize(signed(operand(15 downto 8)), 16));
                                when '1' =>
                                    extended(ii)(15 downto 0)  <= std_ulogic_vector(resize(signed(operand(23 downto 16)), 16));
                                    extended(ii)(31 downto 16) <= std_ulogic_vector(resize(signed(operand(31 downto 24)), 16));
                                when others =>
                                    extended(ii)(15 downto 0)  <= (others => '0');
                                    extended(ii)(31 downto 16) <= (others => '0');
                            end case;

                        when valu_zext_vf4 =>
                            case chunk_counter is
                                when "00"   => extended(ii) <= std_ulogic_vector(resize(unsigned(operand(7 downto 0)), 32));
                                when "01"   => extended(ii) <= std_ulogic_vector(resize(unsigned(operand(15 downto 8)), 32));
                                when "10"   => extended(ii) <= std_ulogic_vector(resize(unsigned(operand(23 downto 16)), 32));
                                when "11"   => extended(ii) <= std_ulogic_vector(resize(unsigned(operand(31 downto 24)), 32));
                                when others => extended(ii) <= (others => '0');
                            end case;

                        when valu_sext_vf4 =>
                            case chunk_counter is
                                when "00"   => extended(ii) <= std_ulogic_vector(resize(signed(operand(7 downto 0)), 32));
                                when "01"   => extended(ii) <= std_ulogic_vector(resize(signed(operand(15 downto 8)), 32));
                                when "10"   => extended(ii) <= std_ulogic_vector(resize(signed(operand(23 downto 16)), 32));
                                when "11"   => extended(ii) <= std_ulogic_vector(resize(signed(operand(31 downto 24)), 32));
                                when others => extended(ii) <= (others => '0');
                            end case;

                        when others => extended(ii) <= (others => '0');
                    end case;

                -- SEW = 32 bits --
                when "010" =>
                    case alu_op is
                        when valu_zext_vf2 | valu_waddu_2sew | valu_wsubu_2sew | valu_nsrl | valu_nsra | valu_waddu | valu_wsubu =>
                            case chunk_counter(0) is
                                when '0' =>
                                    extended(ii) <= std_ulogic_vector(resize(unsigned(operand(15 downto 0)), 32));
                                when '1' =>
                                    extended(ii) <= std_ulogic_vector(resize(unsigned(operand(31 downto 16)), 32));
                                when others =>
                                    extended(ii) <= (others => '0');
                            end case;

                        when valu_sext_vf2 | valu_wadd_2sew | valu_wsub_2sew | valu_wadd | valu_wsub =>
                            case chunk_counter(0) is
                                when '0' =>
                                    extended(ii) <= std_ulogic_vector(resize(signed(operand(15 downto 0)), 32));
                                when '1' =>
                                    extended(ii) <= std_ulogic_vector(resize(signed(operand(31 downto 16)), 32));
                                when others =>
                                    extended(ii) <= (others => '0');
                            end case;

                        when others => extended(ii) <= (others => '0');
                    end case;

                -- SEW = INVALID --
                when others => extended(ii) <= (others => '0');
            end case;
        end process;
    end generate EXTEND_GENERATE;

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
        variable shift_op : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
    begin
        case alu_op is
            when valu_nsrl | valu_nsra => shift_op := extended(1);
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
    COMP_DATAPATH: for idx in 0 to VALU_CHUNK_W-1 generate
        process(all) begin
            case vsew_i is
                when "000"  => comp_out(idx) <= compare_map(idx, 8,  alu_op, op2_i, op1_i, add_final, vcarry_out);
                when "001"  => comp_out(idx) <= compare_map(idx, 16, alu_op, op2_i, op1_i, add_final, vcarry_out);
                when "010"  => comp_out(idx) <= compare_map(idx, 32, alu_op, op2_i, op1_i, add_final, vcarry_out);
                when others => comp_out(idx) <= '0';
            end case;
        end process;
    end generate COMP_DATAPATH;

    -------------------------------
    -- DATAPATH for Vector Merge --
    -------------------------------
    MERGE_DATAPATH: for ii in 0 to (VALU_CHUNK_W/8)-1 generate
        process(all)
            variable merge_mask   : std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
            variable pre_sel, sel : std_ulogic;
        begin
            merge_mask := vmask_i when (alu_op = valu_merge) else comp_out;
            pre_sel := merge_mask(ii)   when vsew_i = "000" else
                       merge_mask(ii/2) when vsew_i = "001" else
                       merge_mask(ii/4) when vsew_i = "010" else
                       '0';
            sel := (not pre_sel) when (alu_op = valu_minu) or (alu_op = valu_min) else pre_sel;
            merge_out(8*ii+7 downto 8*ii) <= op1_i(8*ii+7 downto 8*ii) when (sel = '1') else op2_i(8*ii+7 downto 8*ii);
        end process;
    end generate MERGE_DATAPATH;
end architecture neorv32_valu_rtl;