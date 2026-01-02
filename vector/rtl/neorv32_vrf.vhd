library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use ieee.std_logic_textio.all;

use std.textio.all;

use work.neorv32_vpackage.all;

entity neorv32_vrf is
    port(
        -- Clock --
        clk     : in std_ulogic;

        -- Address Ports --
        vs2     : in std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        vs1     : in std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        vd      : in std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

        -- Write Byte Enable --
        wr_ben  : in std_ulogic_vector((VLEN/8)-1 downto 0);
        -- Write Data Port --
        wr_data : in std_ulogic_vector(VLEN-1 downto 0);

        -- Read Data Ports --
        vs2_out : out std_ulogic_vector(VLEN-1 downto 0);
        vs1_out : out std_ulogic_vector(VLEN-1 downto 0);
        vd_out  : out std_ulogic_vector(VLEN-1 downto 0);
        -- Mask Read Port --
        vmask   : out std_ulogic_vector(VLEN-1 downto 0)
    );
end neorv32_vrf;

-------------------------------------------------------------------------------------------------------------------
-- NOTE: this architecture follows the coding guidelines for Quartus Prime RAM w/ Byte Enable Inference          --
-- LINK: https://www.intel.com/content/www/us/en/docs/programmable/683082/21-3/ram-with-byte-enable-signals.html --
-------------------------------------------------------------------------------------------------------------------
architecture neorv32_vrf_rtl of neorv32_vrf is

    -- Vector Register File --
    -- NOTE: 2 copies of the VRF are needed to enable implementation via BRAMs, as each BRAM supports, at most, --
    --       2R+2W at the same clock cycle (Dual Ported RAM)                                                    --
    type vector_t   is array ((VLEN/8)-1 downto 0) of std_ulogic_vector(7 downto 0);
    type vregfile_t is array ((2**VREF_ADDR_WIDTH)-1 downto 0) of vector_t;
    impure function init_ram(file_name: string) return vregfile_t is
        file     init_file   : text;
        variable line_buffer : line;
        variable temp_bv     : std_ulogic_vector(VLEN-1 downto 0);
        variable ram_content : vregfile_t := (others => (others => (others => '0')));
    begin
        file_open(init_file, file_name, read_mode);
        for ii in 0 to (2**VREF_ADDR_WIDTH)-1 loop
            if not endfile(init_file) then
                readline(init_file, line_buffer);
                hread(line_buffer, temp_bv);
                for jj in 0 to (VLEN/8)-1 loop
                    ram_content(ii)(jj) := temp_bv(8*jj+7 downto 8*jj);
                end loop;
            end if;
        end loop;
        file_close(init_file);
        return ram_content;
    end function;
    signal vregfile_0 : vregfile_t := init_ram("D:/UFMG/TCC/projeto/neorv32-main/rtl/vector/scripts/vrf_contents.txt");
    signal vregfile_1 : vregfile_t := init_ram("D:/UFMG/TCC/projeto/neorv32-main/rtl/vector/scripts/vrf_contents.txt");

    attribute ramstyle : string;
    attribute ramstyle of vregfile_0 : signal is "M9K";
    attribute ramstyle of vregfile_1 : signal is "M9K";

    signal vs2_i   : vector_t;
    signal vs1_i   : vector_t;
    signal vd_i    : vector_t;
    signal vmask_i : vector_t;

begin

    -------------------------------------------------
    -- Conversion of vector_t to std_ulogic_vector --
    -------------------------------------------------
    unpack: for byte in 0 to ((VLEN / 8) - 1) generate
        vs2_out(8*byte+7 downto 8*byte) <= vs2_i(byte);
        vs1_out(8*byte+7 downto 8*byte) <= vs1_i(byte);
        vd_out(8*byte+7 downto 8*byte)  <= vd_i(byte);
        vmask(8*byte+7 downto 8*byte)   <= vmask_i(byte); 
    end generate unpack;

    ----------------------------
    -- Synchronous Write/Read --
    ----------------------------
    process(clk) begin
        if rising_edge(clk) then
            for byte in 0 to ((VLEN / 8) - 1) loop
                if (wr_ben(byte) = '1') then
                    vregfile_0(to_integer(unsigned(vd)))(byte) <= wr_data(8*byte+7 downto 8*byte);
                    vregfile_1(to_integer(unsigned(vd)))(byte) <= wr_data(8*byte+7 downto 8*byte);
                end if;
            end loop;
            -- Reads from VRF_0 --
            vs2_i   <= vregfile_0(to_integer(unsigned(vs2)));
            vs1_i   <= vregfile_0(to_integer(unsigned(vs1)));
            -- Reads from VRF_1 --
            vd_i    <= vregfile_1(to_integer(unsigned(vd)));
            vmask_i <= vregfile_1(0);
        end if;
    end process;

end architecture neorv32_vrf_rtl;