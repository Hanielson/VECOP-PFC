library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use ieee.std_logic_textio.all;

use std.textio.all;

use work.neorv32_vpackage.all;

entity neorv32_vmockmem is
    port(
        -- Clock --
        clk : in std_ulogic;
        rst : in std_ulogic;

        -- Memory Write/Read Input Ports --
        strb  : in std_ulogic;
        rw    : in std_ulogic;
        addr  : in std_ulogic_vector(XLEN-1 downto 0);
        wdata : in std_ulogic_vector(VLSU_MEM_W-1 downto 0);
        ben   : in std_ulogic_vector((VLSU_MEM_W/8)-1 downto 0);

        -- Memory Write/Read Output Ports --
        ack   : out std_ulogic;
        rdata : out std_ulogic_vector(VLSU_MEM_W-1 downto 0)
    );
end neorv32_vmockmem;

-------------------------------------------------------------------------------------------------------------------
-- NOTE: this architecture follows the coding guidelines for Quartus Prime RAM w/ Byte Enable Inference          --
-- LINK: https://www.intel.com/content/www/us/en/docs/programmable/683082/21-3/ram-with-byte-enable-signals.html --
-------------------------------------------------------------------------------------------------------------------
architecture neorv32_vmockmem_rtl of neorv32_vmockmem is
    -- Memory Parameters --
    constant MEM_SIZE : natural := 512;
    constant ADDR_W   : natural := natural(ceil(log2(real(MEM_SIZE))));
    
    -- Memory Array Type Definition --
    type mockmem_t is array (MEM_SIZE-1 downto 0) of std_ulogic_vector(VLSU_MEM_W-1 downto 0);

    impure function init_ram(file_name: string) return mockmem_t is
        file     init_file   : text;
        variable line_buffer : line;
        variable temp_bv     : std_ulogic_vector(VLSU_MEM_W-1 downto 0);
        variable ram_content : mockmem_t := (others => (others => '0'));
    begin
        file_open(init_file, file_name, read_mode);
        for ii in 0 to MEM_SIZE-1 loop
            if not endfile(init_file) then
                readline(init_file, line_buffer);
                hread(line_buffer, ram_content(ii));
            end if;
        end loop;
        file_close(init_file);
        return ram_content;
    end function;

    -- Memory Array Declaration --
    signal mockmem : mockmem_t := init_ram("D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/mem_contents.txt");

    -- Internal Word Address --
    signal addr_i : std_ulogic_vector(ADDR_W-1 downto 0);
begin

    ----------------------------
    -- Synchronous Write/Read --
    ----------------------------
    process(clk) begin
        if rising_edge(clk) then
            if (strb = '1') then
                if (rw = '1') then
                    -- WRITE --
                    for byte in 0 to ((VLSU_MEM_W/8)-1) loop
                        if (ben(byte) = '1') then
                            mockmem(to_integer(unsigned(addr_i)))(8*byte+7 downto 8*byte) <= wdata(8*byte+7 downto 8*byte);
                        end if;
                    end loop;
                else
                    -- READ --
                    rdata <= mockmem(to_integer(unsigned(addr_i)));
                end if;
            end if;
        end if;
    end process;

    -- Use only the address bits that are in the memory's range --
    addr_i <= addr(ADDR_W+1 downto 2);

    --- ACK Signal Generation (1 cycle delayed strobe signal) --
    process(clk, rst) begin
        if (rst = '1') then
            ack <= '0';
        elsif rising_edge(clk) then
            ack <= strb;
        end if;
    end process;

end architecture neorv32_vmockmem_rtl;