library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_vmask is
    port(
        -- Clock and Reset --
        clk : in std_ulogic;
        rst : in std_ulogic;

        -- ALU Operation ID, Valid and Clear --
        alu_op : in std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
        valid  : in std_ulogic;
        clear  : in std_ulogic;

        -- Enable Operand Masking --
        masking_en : in std_ulogic;

        -- LMUL Counter --
        mul_counter : in std_ulogic_vector(2 downto 0);

        -- Vector Operands --
        vmaskA : in std_ulogic_vector(VLEN-1 downto 0);
        vmaskB : in std_ulogic_vector(VLEN-1 downto 0);

        -- Vector Mask --
        vmask_in : in std_ulogic_vector(VLEN-1 downto 0);

        -- Vector Selected Element Width --
        vsew : in std_ulogic_vector(2 downto 0);

        -- ALU Result --
        mask_out  : out std_ulogic_vector(VLEN-1 downto 0);
        mask_done : out std_ulogic
    );
end neorv32_vmask;

architecture neorv32_vmask_rtl of neorv32_vmask is
    -- VALU-SEQ Internal State Machine --
    type mask_state_t is (IDLE, EXEC, DONE, CLEANUP);
    signal state : mask_state_t;

    -- Mask Output Multiplexed Value --
    signal mask_out_i : std_ulogic_vector(VLEN-1 downto 0);

    -- Registered Mask Inputs --
    signal vmaskA_i : std_ulogic_vector(VLEN-1 downto 0);
    signal vmaskB_i : std_ulogic_vector(VLEN-1 downto 0);

    -- Bitwise Operations Results --
    signal mand  : std_ulogic_vector(VLEN-1 downto 0);
    signal mnand : std_ulogic_vector(VLEN-1 downto 0);
    signal mandn : std_ulogic_vector(VLEN-1 downto 0);
    signal mxor  : std_ulogic_vector(VLEN-1 downto 0);
    signal mor   : std_ulogic_vector(VLEN-1 downto 0);
    signal mnor  : std_ulogic_vector(VLEN-1 downto 0);
    signal morn  : std_ulogic_vector(VLEN-1 downto 0);
    signal mxnor : std_ulogic_vector(VLEN-1 downto 0);

    -- Prefix Trees Stages Definition --
    constant PREFIX_BITWIDTH : natural := natural(ceil(log2(real(VLEN))));
    constant PREFIX_STAGES   : natural := natural(ceil(log2(real(MAX_ELEM))));

    -- Prefix Sum Tree Input MUX --
    constant PSUM_IMUX_SEL_W : natural := natural(ceil(log2(real(MIN_VSEW))));
    signal psum_imux_sel   : std_ulogic_vector(PSUM_IMUX_SEL_W-1 downto 0);
    type psum_imux_t is array (MIN_VSEW-1 downto 0) of std_ulogic_vector(MAX_ELEM-1 downto 0);
    signal psum_imux  : psum_imux_t;
    signal psum_input : std_ulogic_vector(MAX_ELEM-1 downto 0);

    -- Prefix Sum Tree Accumulator --
    signal psum_accum : unsigned(PREFIX_BITWIDTH downto 0);
    
    -- Prefix Sum Tree --
    type psum_stage_t is array (MAX_ELEM-1 downto 0) of unsigned(PREFIX_BITWIDTH downto 0);
    type psum_tree_t is array (0 to PREFIX_STAGES) of psum_stage_t;
    signal psum_tree : psum_tree_t;
    signal psum_out  : std_ulogic_vector(VLEN-1 downto 0);

    -- Prefix OR Tree --
    type prefix_or_tree_t is array (0 to PREFIX_STAGES) of std_ulogic_vector(VLEN-1 downto 0);
    signal prefix_or_tree : prefix_or_tree_t;

    -- Find First Set Vector --
    signal ffset : std_ulogic_vector(VLEN-1 downto 0);

    -- Set Before/Include/Only First Masks --
    signal before_first  : std_ulogic_vector(VLEN-1 downto 0);
    signal include_first : std_ulogic_vector(VLEN-1 downto 0);
    signal only_first    : std_ulogic_vector(VLEN-1 downto 0);
begin

    ----------------------------
    --- V-MASK State Machine ---
    ----------------------------
    process(clk, rst) begin
        if (rst = '1') then
            state      <= IDLE;
            mask_out   <= (others => '0');
            psum_accum <= (others => '0');
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    if (clear = '1') then
                        state <= CLEANUP;
                    elsif (valid = '1') then
                        state <= EXEC;
                    end if;

                when EXEC =>
                    state      <= DONE;
                    mask_out   <= mask_out_i;
                    -- Prefix Sum Accumulator is only updated after all current results have been extracted... This can go over multiple cycles, depending on VSEW --
                    case vsew is
                        -- VSEW = 8 bits --
                        when "000" => psum_accum <= psum_tree(PREFIX_STAGES)(MAX_ELEM-1);
                        -- VSEW = 16 bits --
                        when "001" => psum_accum <= psum_tree(PREFIX_STAGES)(MAX_ELEM-1) when (mul_counter(0) = '1') else psum_accum;
                        -- VSEW = 32 bits --
                        when "010" => psum_accum <= psum_tree(PREFIX_STAGES)(MAX_ELEM-1) when (mul_counter(1 downto 0) = "11") else psum_accum;
                        -- INVALID VSEW --
                        when others => psum_accum <= (others => '0');
                    end case;

                when DONE =>
                    if (valid = '0') then
                        state <= IDLE;
                    end if;

                when CLEANUP =>
                    mask_out   <= (others => '0');
                    psum_accum <= (others => '0');
                    if (clear = '0') then
                        state <= IDLE;
                    end if;
                    
                when others => state <= IDLE;
            end case;
        end if;
    end process;

    mask_done <= '1' when (state = DONE) else '0';

    ---------------------------------------
    --- V-MASK Operand Input Definition ---
    ---------------------------------------
    process(all) begin
        if (masking_en = '1') then
            case alu_op is
                when valu_id => vmaskA_i <= (others => '1');
                when others              => vmaskA_i <= (vmaskA and vmask_in);
            end case;
            vmaskB_i <= (vmaskB and vmask_in);
        else
            case alu_op is
                when valu_id => vmaskA_i <= (others => '1');
                when others              => vmaskA_i <= vmaskA;
            end case;
            vmaskB_i <= vmaskB;
        end if;
    end process;

    -----------------------------------
    --- V-MASK Output Selection MUX ---
    -----------------------------------
    process(all) begin
        case alu_op is
            when valu_mandn => mask_out_i <= mandn;
            when valu_mand  => mask_out_i <= mand;
            when valu_mor   => mask_out_i <= mor;
            when valu_mxor  => mask_out_i <= mxor;
            when valu_morn  => mask_out_i <= morn;
            when valu_mnand => mask_out_i <= mnand;
            when valu_mnor  => mask_out_i <= mnor;
            when valu_mxnor => mask_out_i <= mxnor;
            when valu_cpop  => mask_out_i <= (others => '0');
            when valu_first => mask_out_i <= (others => '0');
            when valu_msbf  => mask_out_i <= before_first;
            when valu_msof  => mask_out_i <= only_first;
            when valu_msif  => mask_out_i <= include_first;
            when valu_iota  => mask_out_i <= psum_out;
            when valu_id    => mask_out_i <= psum_out;
            when others     => mask_out_i <= (others => '0');
        end case;
    end process;

    --------------------------
    --- Bitwise Operations ---
    --------------------------
    mand  <= vmaskA_i and vmaskB_i;
    mnand <= not (vmaskA_i and vmaskB_i);
    mandn <= vmaskA_i and (not vmaskB_i);
    mxor  <= vmaskA_i xor vmaskB_i;
    mor   <= vmaskA_i or vmaskB_i;
    mnor  <= not (vmaskA_i or vmaskB_i);
    morn  <= vmaskA_i or (not vmaskB_i);
    mxnor <= not (vmaskA_i xor vmaskB_i);

    ---------------------------------
    --- Prefix Sum Tree Input MUX ---
    ---------------------------------
    PREFIX_SUM_IMUX : for ii in 0 to MIN_VSEW-1 generate
        psum_imux(ii) <= vmaskA_i((ii*(VLEN/MIN_VSEW))+((VLEN/MIN_VSEW)-1) downto (ii*(VLEN/MIN_VSEW)));
    end generate PREFIX_SUM_IMUX;

    process(all) begin
        -- Define INPUT MUX selection signal for prefix SUM Tree --
        case vsew is
            -- VSEW = 8 bits --
            when "000" => psum_imux_sel <= mul_counter(PSUM_IMUX_SEL_W-1 downto 0);
            -- VSEW = 16 bits --
            when "001" => psum_imux_sel <= mul_counter(PSUM_IMUX_SEL_W-1 downto 1) & "0";
            -- VSEW = 32 bits --
            when "010" => psum_imux_sel <= mul_counter(PSUM_IMUX_SEL_W-1 downto 2) & "00";
            -- INVALID VSEW --
            when others => psum_imux_sel <= (others => '0');
        end case;
        psum_input <= psum_imux(to_integer(unsigned(psum_imux_sel)));
    end process;

    -----------------------
    --- Prefix Sum Tree ---
    -----------------------
    PREFIX_SUM_STAGE : for ii in 0 to PREFIX_STAGES generate
        PREFIX_SUM_ELEM : for jj in 0 to psum_tree(ii)'length-1 generate
            -- Stage 0 is simply the mask bits expanded --
            PREFIX_SUM_MASK: if (ii = 0) generate
                -- ELEMENT 0 on STAGE 0 is added to ACCUM register --
                PREFIX_SUM_ACCUM: if (jj = 0) generate
                    psum_tree(ii)(jj) <= resize(unsigned(psum_input(jj downto jj)), psum_tree(ii)(jj)'length) + psum_accum;
                -- Other ELEMENTS on STAGE 0 remain untouched --
                else generate
                    psum_tree(ii)(jj) <= resize(unsigned(psum_input(jj downto jj)), psum_tree(ii)(jj)'length);
                end generate PREFIX_SUM_ACCUM;
            -- Stages != 0 do the actual prefix sum --
            else generate
                -- Elements with index < (2^(ii-1)) already have the results done --
                PREFIX_SUM_RUN: if (jj < (2**(ii-1))) generate
                    psum_tree(ii)(jj) <= psum_tree(ii-1)(jj);
                -- Other elements need to sum their previous stage value with the value from element (jj - (2^(ii-1))) of the previous stage --
                else generate
                    psum_tree(ii)(jj) <= psum_tree(ii-1)(jj) + psum_tree(ii-1)(jj - (2**(ii-1)));
                end generate PREFIX_SUM_RUN;
            end generate PREFIX_SUM_MASK;
        end generate PREFIX_SUM_ELEM;
    end generate PREFIX_SUM_STAGE;

    ----------------------------------
    --- Prefix Sum Tree OUTPUT MUX ---
    ----------------------------------
    process(all)
        type psum_omux_16b_t is array ((MAX_ELEM/2)-1 downto 0) of unsigned(PREFIX_BITWIDTH downto 0);
        variable psum_omux_16b : psum_omux_16b_t := (others => (others => '0'));
        
        type psum_omux_32b_t is array ((MAX_ELEM/4)-1 downto 0) of unsigned(PREFIX_BITWIDTH downto 0);
        variable psum_omux_32b : psum_omux_32b_t := (others => (others => '0'));

        variable psum_out_8b  : std_ulogic_vector(VLEN-1 downto 0) := (others => '0');
        variable psum_out_16b : std_ulogic_vector(VLEN-1 downto 0) := (others => '0');
        variable psum_out_32b : std_ulogic_vector(VLEN-1 downto 0) := (others => '0');
    begin
        for ii in 0 to MAX_ELEM-1 loop
            psum_out_8b(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(psum_tree(PREFIX_STAGES)(ii)), 8));
        end loop;

        for ii in 0 to (MAX_ELEM/2)-1 loop
            psum_omux_16b(ii)                   := psum_tree(PREFIX_STAGES)(((MAX_ELEM/2) * to_integer(unsigned(mul_counter(0 downto 0)))) + ii);
            psum_out_16b(16*ii+15 downto 16*ii) := std_ulogic_vector(resize(psum_omux_16b(ii), 16));
        end loop;

        for ii in 0 to (MAX_ELEM/4)-1 loop
            psum_omux_32b(ii)                   := psum_tree(PREFIX_STAGES)(((MAX_ELEM/4) * to_integer(unsigned(mul_counter(1 downto 0)))) + ii);
            psum_out_32b(32*ii+31 downto 32*ii) := std_ulogic_vector(resize(psum_omux_32b(ii), 32));
        end loop;

        case vsew is
            -- VSEW = 8 bits --
            when "000" => psum_out <= psum_out_8b;
            -- VSEW = 16 bits --
            when "001" => psum_out <= psum_out_16b;
            -- VSEW = 32 bits --
            when "010" => psum_out <= psum_out_32b;
            -- INVALID VSEW --
            when others => psum_out <= (others => '0');
        end case;
    end process;

    ----------------------
    --- Prefix OR Tree ---
    ----------------------
    prefix_or_tree(0) <= vmaskA_i;
    PREFIX_OR_STAGE : for ii in 1 to PREFIX_STAGES generate
        PREFIX_OR_ELEM : for jj in 0 to prefix_or_tree(ii)'length-1 generate
            -- Elements with index < (2^(ii-1)) already have the results done --
            PREFIX_OR_RUN: if (jj < (2**(ii-1))) generate
                prefix_or_tree(ii)(jj) <= prefix_or_tree(ii-1)(jj);
            -- Other elements need to OR their previous stage value with the value from element (jj - (2^(ii-1))) of the previous stage --
            else generate
                prefix_or_tree(ii)(jj) <= prefix_or_tree(ii-1)(jj) or prefix_or_tree(ii-1)(jj - (2**(ii-1)));
            end generate PREFIX_OR_RUN;
        end generate PREFIX_OR_ELEM;
    end generate PREFIX_OR_STAGE;

    ------------------------------------
    --- First Non-Zero Bit Isolation ---
    ------------------------------------
    ffset(0) <= prefix_or_tree(PREFIX_STAGES)(0);
    ISOLATE_GEN : for ii in 1 to ffset'length-1 generate
        ffset(ii) <= prefix_or_tree(PREFIX_STAGES)(ii) and (not prefix_or_tree(PREFIX_STAGES)(ii-1));
    end generate ISOLATE_GEN;

    ---------------------------
    --- Results Assignments ---
    ---------------------------
    process(all) begin
        before_first  <= not prefix_or_tree(PREFIX_STAGES);
        include_first <= before_first or ffset;
        only_first    <= ffset;
    end process;

end neorv32_vmask_rtl;