library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_vsld is
    port(
        -- Clock and Reset --
        clk     : in std_ulogic;
        rst     : in std_ulogic;
        -- Slide Operands --
        sld_vs2 : in std_ulogic_vector(VLEN-1 downto 0);
        sld_vs1 : in std_ulogic_vector(VLEN-1 downto 0);
        -- Slide Control --
        vsew      : in std_ulogic_vector(2 downto 0);
        sld_en    : in std_ulogic;
        sld_up    : in std_ulogic;
        sld_last  : in std_ulogic;
        sld_elem  : in std_ulogic_vector(ELEM_ID_WIDTH-1 downto 0);
        -- Slide Out --
        sld_out   : out std_ulogic_vector(VLEN-1 downto 0);
        sld_be    : out std_ulogic_vector((VLEN/8)-1 downto 0);
        sld_done  : out std_ulogic
    );
end neorv32_vsld;

architecture neorv32_vsld_rtl of neorv32_vsld is
    type sld_state_t is (IDLE, PRELOAD_UP, PRELOAD_DN, LOAD, SHIFT_UP, SHIFT_DN, DONE, WAIT_READ);
    signal state : sld_state_t;
    signal elem_counter : std_ulogic_vector(ELEM_ID_WIDTH-1 downto 0);
    signal num_elem     : std_ulogic_vector(ELEM_ID_WIDTH-1 downto 0);
    signal sld_i        : std_ulogic_vector((2*VLEN)-1 downto 0);
    signal be_i         : std_ulogic_vector((VLEN/8)-1 downto 0);
    signal sld_op1_i : std_ulogic_vector(VLEN-1 downto 0);
    signal sld_op0_i : std_ulogic_vector(VLEN-1 downto 0);
    signal sld_up_i  : std_ulogic;
begin
    ------------------------------------------------
    --- SLD State Machine + Element elem_counter ---
    ------------------------------------------------
    process(clk, rst) begin
        if (rst = '1') then
            state        <= IDLE;
            elem_counter <= (others => '0');
            num_elem     <= (others => '0');
            sld_op1_i    <= (others => '0');
            sld_op0_i    <= (others => '0');
            sld_up_i     <= '0';
            sld_out      <= (others => '0');
            sld_be       <= (others => '0');
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    state    <= PRELOAD_UP when (sld_en = '1') and (sld_up = '1') else
                                PRELOAD_DN when (sld_en = '1') and (sld_up = '0') else
                                IDLE;
                    elem_counter <= (others => '0');
                    num_elem     <= sld_elem;
                    sld_op1_i    <= (others => '0');
                    sld_op0_i    <= (others => '0');
                    sld_up_i     <= sld_up;
                    sld_out      <= (others => '0');
                    sld_be       <= (others => '0');
                when PRELOAD_UP =>
                    state     <= LOAD;
                    sld_op1_i <= sld_vs2;
                    sld_op0_i <= sld_op1_i;
                    sld_up_i  <= '1';
                when PRELOAD_DN =>
                    state     <= LOAD;
                    sld_op1_i <= (others => '0') when (sld_last = '1') else sld_vs1;
                    sld_op0_i <= sld_vs2;
                    sld_up_i  <= '0';
                when LOAD =>
                    state <= SHIFT_UP when (sld_up_i = '1') else SHIFT_DN;
                when SHIFT_UP =>
                    state <= DONE when (elem_counter = num_elem) else SHIFT_UP;
                    if (elem_counter = num_elem) then 
                        sld_out <= sld_i((2*VLEN)-1 downto VLEN);
                        sld_be  <= be_i;
                    else                         
                        elem_counter <= std_ulogic_vector(unsigned(elem_counter) + 1);
                    end if;
                when SHIFT_DN =>
                    state <= DONE when (elem_counter = num_elem) else SHIFT_DN;
                    if (elem_counter = num_elem) then 
                        sld_out <= sld_i(VLEN-1 downto 0);
                        sld_be  <= be_i;
                    else                         
                        elem_counter <= std_ulogic_vector(unsigned(elem_counter) + 1);
                    end if;
                when DONE =>
                    state        <= WAIT_READ when (sld_en = '1') else IDLE;
                    elem_counter <= (others => '0');
                    sld_be       <= (others => '0');
                when WAIT_READ => 
                    state <= PRELOAD_UP when (sld_up_i = '1') else PRELOAD_DN;
                when others => 
                    state <= IDLE;
            end case;
        end if;
    end process;

    --------------
    -- SLD Done --
    --------------
    process(all) begin
        case state is
            when DONE   => sld_done <= '1';
            when others => sld_done <= '0';
        end case;
    end process;

    --------------------------
    --- SLD Shift Register ---
    --------------------------
    process(clk, rst) begin
        if (rst = '1') then
            sld_i <= (others => '0');
            be_i  <= (others => '1');
        elsif rising_edge(clk) then
            case state is
                when LOAD =>
                    sld_i <= sld_op1_i & sld_op0_i;
                when SHIFT_UP =>
                    case vsew is
                        when "000"  => sld_i <= sld_i(sld_i'left-8 downto 0)  & x"00"      ; be_i <= be_i(be_i'left-1 downto 0) & "0";
                        when "001"  => sld_i <= sld_i(sld_i'left-16 downto 0) & x"0000"    ; be_i <= be_i(be_i'left-2 downto 0) & "00";
                        when "010"  => sld_i <= sld_i(sld_i'left-32 downto 0) & x"00000000"; be_i <= be_i(be_i'left-4 downto 0) & "0000";
                        when others => sld_i <= (others => '0');
                    end case;
                when SHIFT_DN =>
                    case vsew is
                        when "000"  => sld_i <= x"00"       & sld_i(sld_i'left downto 8) ; be_i <= "0"    & be_i(be_i'left downto 1);
                        when "001"  => sld_i <= x"0000"     & sld_i(sld_i'left downto 16); be_i <= "00"   & be_i(be_i'left downto 2);
                        when "010"  => sld_i <= x"00000000" & sld_i(sld_i'left downto 32); be_i <= "0000" & be_i(be_i'left downto 4);
                        when others => sld_i <= (others => '0');
                    end case;
                when others => 
                    sld_i <= (others => '0');
            end case;
        end if;
    end process;
end architecture neorv32_vsld_rtl;