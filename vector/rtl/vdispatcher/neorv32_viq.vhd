library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_viq is
    port(
        -- Clock and Reset --
        clk : in std_ulogic;
        rst : in std_ulogic;

        -- Inputs from Scalar Core --
        vinst_in : in std_ulogic_vector(XLEN-1 downto 0);
        scal2_in : in std_ulogic_vector(XLEN-1 downto 0);
        scal1_in : in std_ulogic_vector(XLEN-1 downto 0);
        valid_in : in std_ulogic;

        -- Inputs from VECOP --
        vq_next : in std_ulogic;
        
        -- Outputs to VECOP --
        vinst_out : out std_ulogic_vector(XLEN-1 downto 0);
        scal2_out : out std_ulogic_vector(XLEN-1 downto 0);
        scal1_out : out std_ulogic_vector(XLEN-1 downto 0);
        valid_out : out std_ulogic;
        vq_full   : out std_ulogic;
        vq_empty  : out std_ulogic
    );
end neorv32_viq;

architecture neorv32_viq_rtl of neorv32_viq is
    type fifo_t is array (7 downto 0) of std_ulogic_vector(XLEN-1 downto 0);
    signal vinst_fifo : fifo_t;
    signal scal2_fifo : fifo_t;
    signal scal1_fifo : fifo_t;

    signal write_ptr : std_ulogic_vector(2 downto 0);
    signal read_ptr  : std_ulogic_vector(2 downto 0);

    signal full  : std_ulogic;
    signal empty : std_ulogic;
begin
    
    -- FIFO Full Indication --
    full    <= '1' when ((unsigned(write_ptr) + 1) = unsigned(read_ptr)) else '0';
    vq_full <= full;
    -- FIFO Empty Indication --
    empty    <= '1' when (unsigned(write_ptr) = unsigned(read_ptr)) else '0';
    vq_empty <= empty;

    process(clk, rst) begin
        if (rst = '1') then
            write_ptr  <= (others => '0');
            read_ptr   <= (others => '0');
            vinst_fifo <= (others => (others => '0'));
            scal2_fifo <= (others => (others => '0'));
            scal1_fifo <= (others => (others => '0'));
        elsif rising_edge(clk) then
            if (valid_in = '1') and (full = '0') then
                write_ptr <= std_ulogic_vector(unsigned(write_ptr) + 1);
                vinst_fifo(to_integer(unsigned(write_ptr))) <= vinst_in;
                scal2_fifo(to_integer(unsigned(write_ptr))) <= scal2_in;
                scal1_fifo(to_integer(unsigned(write_ptr))) <= scal1_in;
            end if;

            if (vq_next = '1') and (empty = '0') then
                read_ptr <= std_ulogic_vector(unsigned(read_ptr) + 1);
            end if;
        end if;
    end process;

    -- FIFOs ASYNC READ --
    vinst_out <= vinst_fifo(to_integer(unsigned(read_ptr)));
    scal2_out <= scal2_fifo(to_integer(unsigned(read_ptr)));
    scal1_out <= scal1_fifo(to_integer(unsigned(read_ptr)));
    valid_out <= '1' when (empty = '0') else '0'; 

end architecture neorv32_viq_rtl;