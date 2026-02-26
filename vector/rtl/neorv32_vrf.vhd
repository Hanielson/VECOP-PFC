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
    impure function init_ram(file_name: string) return vregfile_t is
        file     init_file   : text;
        variable line_buffer : line;
        variable temp_bv     : std_ulogic_vector(VLEN-1 downto 0);
        variable ram_content : vregfile_t := (others => (others => '0'));
    begin
        file_open(init_file, file_name, read_mode);
        for ii in 0 to (2**VREF_ADDR_WIDTH)-1 loop
            if not endfile(init_file) then
                readline(init_file, line_buffer);
                hread(line_buffer, ram_content(ii));
            end if;
        end loop;
        file_close(init_file);
        return ram_content;
    end function;

    -- Vector Register File --
    -- NOTE: 4 copies of the VRF are needed to enable implementation via BRAMs, as each BRAM supports, at most, --
    --       1R+1W at the same clock cycle (Dual Ported RAM)                                                    --
    signal vregfile_0 : vregfile_t := init_ram("D:/UFMG/TCC/projeto/NeoRV32/vector/scripts/vrf_contents_zero.txt");
    signal vregfile_1 : vregfile_t := vregfile_0;
    signal vregfile_2 : vregfile_t := vregfile_0;
    signal vregfile_3 : vregfile_t := vregfile_0;

    attribute ramstyle : string;
    attribute ramstyle of vregfile_0 : signal is "block";
    attribute ramstyle of vregfile_1 : signal is "block";
    attribute ramstyle of vregfile_2 : signal is "block";
    attribute ramstyle of vregfile_3 : signal is "block";
begin
    ----------------------------
    -- Synchronous Write/Read --
    ----------------------------
    process(clk) begin
        if rising_edge(clk) then
            -- WRITE --
            for byte in 0 to ((VLEN/8)-1) loop
                if (wr_ben(byte) = '1') then
                    vregfile_0(to_integer(unsigned(vd)))(8*byte+7 downto 8*byte) <= wr_data(8*byte+7 downto 8*byte);
                    vregfile_1(to_integer(unsigned(vd)))(8*byte+7 downto 8*byte) <= wr_data(8*byte+7 downto 8*byte);
                    vregfile_2(to_integer(unsigned(vd)))(8*byte+7 downto 8*byte) <= wr_data(8*byte+7 downto 8*byte);
                    vregfile_3(to_integer(unsigned(vd)))(8*byte+7 downto 8*byte) <= wr_data(8*byte+7 downto 8*byte);
                end if;
            end loop;
            -- READ --
            vs2_out <= vregfile_0(to_integer(unsigned(vs2)));
            vs1_out <= vregfile_0(to_integer(unsigned(vs1)));
            vd_out  <= vregfile_0(to_integer(unsigned(vd)));
            vmask   <= vregfile_0(0);
        end if;
    end process;
end architecture neorv32_vrf_rtl;