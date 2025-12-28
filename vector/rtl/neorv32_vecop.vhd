library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_vecop is
    generic(
        VLEN            : natural := 256;
        XLEN            : natural := 32;
        VREF_ADDR_WIDTH : natural := 5
    );
    port(
        -- Clock and Reset --
        clk     : in std_ulogic;
        rst     : in std_ulogic
    );
end neorv32_vecop;

architecture neorv32_vecop_rtl of neorv32_vecop is

    ------------------------------
    --- Component Declarations ---
    ------------------------------
    component neorv32_vrf is
        generic(
            VLEN       : natural;
            XLEN       : natural;
            ADDR_WIDTH : natural
        );
        port(
            clk     : in std_ulogic;
            vs2     : in std_ulogic_vector(ADDR_WIDTH-1 downto 0);
            vs1     : in std_ulogic_vector(ADDR_WIDTH-1 downto 0);
            vd      : in std_ulogic_vector(ADDR_WIDTH-1 downto 0);
            wr_ben  : in std_ulogic_vector((VLEN/8)-1 downto 0);
            wr_data : in std_ulogic_vector(VLEN-1 downto 0);
            vs2_out : out std_ulogic_vector(VLEN-1 downto 0);
            vs1_out : out std_ulogic_vector(VLEN-1 downto 0);
            vd_out  : out std_ulogic_vector(VLEN-1 downto 0);
            vmask   : out std_ulogic_vector(VLEN-1 downto 0)
        );
    end component neorv32_vrf;

    component neorv32_valu is
        generic(
            VLEN : natural;
            XLEN : natural
        );
        port(
            clk     : in std_ulogic;
            rst     : in std_ulogic;
            valid   : in std_ulogic;
            op2     : in std_ulogic_vector(VLEN-1 downto 0);
            op1     : in std_ulogic_vector(VLEN-1 downto 0);
            op0     : in std_ulogic_vector(VLEN-1 downto 0);
            alu_op  : in std_ulogic_vector(VALU_OP_SIZE-1 downto 0);
            vmask   : in std_ulogic_vector(XLEN-1 downto 0);
            vsew    : in std_ulogic_vector(2 downto 0);
            alu_out : out std_ulogic_vector(VLEN-1 downto 0)
        );
    end component neorv32_valu;

    ---------------------------
    --- Signal Declarations ---
    ---------------------------
    signal vsew    : std_ulogic_vector(2 downto 0);
    signal vmask   : std_ulogic_vector(VLEN-1 downto 0);
    signal valid   : std_ulogic;

    -- VRF Signals --
    signal vs2     : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vs1     : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vd      : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal wr_ben  : std_ulogic_vector((VLEN/8)-1 downto 0);
    signal wr_data : std_ulogic_vector(VLEN-1 downto 0);
    signal wr_sel  : std_ulogic_vector(1 downto 0);

    -- OP-SEL Signals --
    signal vs2_out : std_ulogic_vector(VLEN-1 downto 0);
    signal vs1_out : std_ulogic_vector(VLEN-1 downto 0);
    signal vd_out  : std_ulogic_vector(VLEN-1 downto 0);
    signal imm     : std_ulogic_vector(4 downto 0);
    signal sel_op2 : std_ulogic;
    signal sel_op1 : std_ulogic;
    signal sel_imm : std_ulogic;
    signal scalar  : std_ulogic_vector(XLEN-1 downto 0);
    
    -- ALU Signals --
    signal op2     : std_ulogic_vector(VLEN-1 downto 0);
    signal op1     : std_ulogic_vector(VLEN-1 downto 0);
    signal op0     : std_ulogic_vector(VLEN-1 downto 0);
    signal alu_op  : std_ulogic_vector(VALU_OP_SIZE-1 downto 0);
    signal alu_out : std_ulogic_vector(VLEN-1 downto 0);

    -- SLD Signals --
    signal sld_out : std_ulogic_vector(VLEN-1 downto 0);

    -- LSU Signals --
    signal lsu_out : std_ulogic_vector(VLEN-1 downto 0);

begin

    ----------------------------------
    --- Sub-Modules Instantiations ---
    ----------------------------------
    vrf: entity work.neorv32_vrf
    generic map(
        VLEN       => VLEN,
        XLEN       => XLEN,
        ADDR_WIDTH => VREF_ADDR_WIDTH
    )
    port map (
        clk     => clk,
        vs2     => vs2,
        vs1     => vs1,
        vd      => vd,
        wr_ben  => wr_ben,
        wr_data => wr_data,
        vs2_out => vs2_out,
        vs1_out => vs1_out,
        vd_out  => vd_out,
        vmask   => vmask
    );

    valu: entity work.neorv32_valu
    generic map(
        VLEN => VLEN,
        XLEN => XLEN
    )
    port map (
        clk     => clk,
        rst     => rst,
        valid   => valid,
        op2     => op2,
        op1     => op1,
        op0     => op0,
        alu_op  => alu_op,
        vmask   => vmask,
        vsew    => vsew,
        alu_out => alu_out
    );

    --------------------------
    --- VRF Write Data MUX ---
    --------------------------
    WR_MUX : process(all) begin
        case wr_sel is
            when "00"   => wr_data <= alu_out;
            when "01"   => wr_data <= sld_out;
            when "10"   => wr_data <= lsu_out;
            when "11"   => wr_data <= vs2_out;
            when others => wr_data <= (others => '0');
        end case;
    end process WR_MUX;

    --------------------
    --- OP-SEL Logic ---
    --------------------
    OP_SEL : process(all) 
        variable imm_scl : std_ulogic_vector(VLEN-1 downto 0);
    begin
        op2 <= vs2_out when (sel_op2 = '0') else vd_out;
        op0 <= vs2_out when (sel_op2 = '1') else vd_out;
        for ii in 0 to ((VLEN / 8) - 1) loop
            -- Select SCALAR --
            if (sel_imm = '1') then
                case vsew is
                    when "000"  => imm_scl(8*ii+7 downto 8*ii) := scalar(7 downto 0);
                    when "001"  => imm_scl(8*ii+7 downto 8*ii) := scalar(8*(ii mod 2)+7 downto 8*(ii mod 2));
                    when "010"  => imm_scl(8*ii+7 downto 8*ii) := scalar(8*(ii mod 4)+7 downto 8*(ii mod 2));
                    when others => imm_scl(8*ii+7 downto 8*ii) := (others => '0');
                end case;
            -- Select IMMEDIATE --
            else
                case vsew is
                    when "000"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(imm), 8));
                    when "001"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(imm), 8)) when ((ii mod 2) = 0) else (others => '0');
                    when "010"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(imm), 8)) when ((ii mod 4) = 0) else (others => '0');
                    when others => imm_scl(8*ii+7 downto 8*ii) := (others => '0');
                end case;
            end if;
        end loop;
        op1 <= vs1_out when (sel_op1 = '0') else imm_scl;
    end process OP_SEL;

end neorv32_vecop_rtl;
