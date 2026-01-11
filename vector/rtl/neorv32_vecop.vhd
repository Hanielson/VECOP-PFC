library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_vecop is
    port(
        -- Clock and Reset --
        clk     : in std_ulogic;
        rst     : in std_ulogic;

        -- HACK: these ports should be removed after testing --
        vinst       : in std_ulogic_vector(XLEN-1 downto 0);
        vinst_valid : in std_ulogic
    );
end neorv32_vecop;

architecture neorv32_vecop_rtl of neorv32_vecop is

    ------------------------------
    --- Component Declarations ---
    ------------------------------
    component neorv32_vcu is
        port(
            clk         : in std_ulogic;
            rst         : in std_ulogic;
            vinst       : in std_ulogic_vector(XLEN-1 downto 0);
            vinst_valid : in std_ulogic;
            vq_full     : in std_ulogic;
            scal2       : in std_ulogic_vector(XLEN-1 downto 0);
            scal1       : in std_ulogic_vector(XLEN-1 downto 0);
            vmask       : in std_ulogic_vector(VLEN-1 downto 0);
            vstart      : in std_ulogic_vector(XLEN-1 downto 0);
            vl          : in std_ulogic_vector(XLEN-1 downto 0);
            vill        : in std_ulogic;
            vma         : in std_ulogic;
            vta         : in std_ulogic;
            vsew        : in std_ulogic_vector(2 downto 0);
            vlmul       : in std_ulogic_vector(2 downto 0);
            sld_done    : in std_ulogic;
            lsu_done    : in std_ulogic;
            memtrp_id   : in std_ulogic_vector(1 downto 0);
            memtrp_addr : in std_ulogic_vector(XLEN-1 downto 0);
            vctrl       : out vctrl_bus_t;
            cp_result   : out std_ulogic_vector(XLEN-1 downto 0);
            cp_valid    : out std_ulogic
        );
    end component neorv32_vcu;

    component neorv32_vrf is
        port(
            clk     : in std_ulogic;
            vs2     : in std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
            vs1     : in std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
            vd      : in std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
            wr_ben  : in std_ulogic_vector((VLEN/8)-1 downto 0);
            wr_data : in std_ulogic_vector(VLEN-1 downto 0);
            vs2_out : out std_ulogic_vector(VLEN-1 downto 0);
            vs1_out : out std_ulogic_vector(VLEN-1 downto 0);
            vd_out  : out std_ulogic_vector(VLEN-1 downto 0);
            vmask   : out std_ulogic_vector(VLEN-1 downto 0)
        );
    end component neorv32_vrf;

    component neorv32_valu is
        port(
            clk     : in std_ulogic;
            rst     : in std_ulogic;
            valid   : in std_ulogic;
            op2     : in std_ulogic_vector(VLEN-1 downto 0);
            op1     : in std_ulogic_vector(VLEN-1 downto 0);
            op0     : in std_ulogic_vector(VLEN-1 downto 0);
            alu_op  : in std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
            vmask   : in std_ulogic_vector(XLEN-1 downto 0);
            vsew    : in std_ulogic_vector(2 downto 0);
            alu_out : out std_ulogic_vector(VLEN-1 downto 0)
        );
    end component neorv32_valu;

    component neorv32_vsld is
        port(
            clk       : in std_ulogic;
            rst       : in std_ulogic;
            sld_vs2   : in std_ulogic_vector(VLEN-1 downto 0);
            sld_vs1   : in std_ulogic_vector(VLEN-1 downto 0);
            vsew      : in std_ulogic_vector(2 downto 0);
            sld_en    : in std_ulogic;
            sld_up    : in std_ulogic;
            sld_last  : in std_ulogic;
            sld_elem  : in std_ulogic_vector((VLEN/8)-1 downto 0);
            sld_out   : out std_ulogic_vector(VLEN-1 downto 0);
            sld_be    : out std_ulogic_vector((VLEN/8)-1 downto 0);
            sld_done  : out std_ulogic
        );
    end component neorv32_vsld;

    ---------------------------
    --- Signal Declarations ---
    ---------------------------
    signal vcsr  : vcsr_t;
    signal vctrl : vctrl_bus_t;
    signal vmask : std_ulogic_vector(VLEN-1 downto 0);

    -- VECOP Output Signals --
    signal cp_result : std_ulogic_vector(XLEN-1 downto 0);
    signal cp_valid  : std_ulogic;

    -- VCU Signals --
    -- signal vinst           : std_ulogic_vector(XLEN-1 downto 0);
    -- signal vinst_valid     : std_ulogic;
    signal vq_full         : std_ulogic;
    signal vq_scal2        : std_ulogic_vector(XLEN-1 downto 0);
    signal vq_scal1        : std_ulogic_vector(XLEN-1 downto 0);
    signal sld_done        : std_ulogic;
    signal sld_be          : std_ulogic_vector((VLEN/8)-1 downto 0);
    signal lsu_done        : std_ulogic;
    signal lsu_memtrp_id   : std_ulogic_vector(1 downto 0);
    signal lsu_memtrp_addr : std_ulogic_vector(XLEN-1 downto 0);

    -- vtype CSR Fields (some of them...) --
    signal vill  : std_ulogic;
    signal vma   : std_ulogic;
    signal vta   : std_ulogic;
    signal vsew  : std_ulogic_vector(2 downto 0);
    signal vlmul : std_ulogic_vector(2 downto 0);

    -- VRF Signals --
    signal wr_data : std_ulogic_vector(VLEN-1 downto 0);

    -- OP-SEL Signals --
    signal vs2_out : std_ulogic_vector(VLEN-1 downto 0);
    signal vs1_out : std_ulogic_vector(VLEN-1 downto 0);
    signal vd_out  : std_ulogic_vector(VLEN-1 downto 0);
    
    -- ALU Signals --
    signal op2     : std_ulogic_vector(VLEN-1 downto 0);
    signal op1     : std_ulogic_vector(VLEN-1 downto 0);
    signal op0     : std_ulogic_vector(VLEN-1 downto 0);
    signal alu_out : std_ulogic_vector(VLEN-1 downto 0);

    -- SLD Signals --
    signal sld_out : std_ulogic_vector(VLEN-1 downto 0);

    -- LSU Signals --
    signal lsu_out : std_ulogic_vector(VLEN-1 downto 0);

begin

    ----------------------------------
    --- Sub-Modules Instantiations ---
    ----------------------------------
    vcu: entity work.neorv32_vcu port map (
        clk         => clk,
        rst         => rst,
        vinst       => vinst,
        vinst_valid => vinst_valid,
        vq_full     => vq_full,
        scal2       => vq_scal2,
        scal1       => vq_scal1,
        vmask       => vmask,
        vstart      => vcsr.vstart,
        vl          => vcsr.vl,
        vill        => vill,
        vma         => vma,
        vta         => vta,
        vsew        => vsew,
        vlmul       => vlmul,
        sld_done    => sld_done,
        sld_be      => sld_be,
        lsu_done    => lsu_done,
        memtrp_id   => lsu_memtrp_id,
        memtrp_addr => lsu_memtrp_addr,
        vctrl       => vctrl,
        cp_result   => cp_result,
        cp_valid    => cp_valid
    );

    vrf: entity work.neorv32_vrf port map (
        clk     => clk,
        vs2     => vctrl.vrf_vs2,
        vs1     => vctrl.vrf_vs1,
        vd      => vctrl.vrf_vd,
        wr_ben  => vctrl.vrf_ben,
        wr_data => wr_data,
        vs2_out => vs2_out,
        vs1_out => vs1_out,
        vd_out  => vd_out,
        vmask   => vmask
    );

    valu: entity work.neorv32_valu port map (
        clk     => clk,
        rst     => rst,
        alu_op  => vctrl.valu_op,
        valid   => vctrl.valu_valid,
        op2     => op2,
        op1     => op1,
        op0     => op0,
        vmask   => vmask,
        vsew    => vsew,
        alu_out => alu_out
    );

    vsld: entity work.neorv32_vsld port map (
        clk       => clk,
        rst       => rst,
        sld_vs2   => vs2_out,
        sld_vs1   => vs1_out,
        vsew      => vsew,
        sld_en    => vctrl.sld_en,
        sld_up    => vctrl.sld_up,
        sld_last  => vctrl.sld_last,
        sld_elem  => vctrl.sld_elem,
        sld_out   => sld_out,
        sld_be    => sld_be,
        sld_done  => sld_done
    );

    ------------------------------------
    --- vtype CSR Signals Extraction ---
    ------------------------------------
    vill  <= vcsr.vtype(XLEN-1);
    vma   <= vcsr.vtype(7);
    vta   <= vcsr.vtype(6);
    vsew  <= vcsr.vtype(5 downto 3);
    vlmul <= vcsr.vtype(2 downto 0);

    -------------------
    --- V-CSR Logic ---
    -------------------
    VCSR_LOGIC : process(clk, rst) begin
        if (rst = '1') then
            vcsr <= (
                vtype  => (XLEN-1 => '1', others => '0'), 
                vl     => (others => '0'), 
                vlenb  => std_ulogic_vector(to_unsigned(VLEN/8, vcsr.vlenb'length)), 
                vstart => (others => '0')
            );
        else
            if rising_edge(clk) then
                if (vctrl.csr_wen(2) = '1') then
                    vcsr.vtype <= vctrl.csr_vtype_n;
                end if;
                if (vctrl.csr_wen(1) = '1') then
                    vcsr.vl <= vctrl.csr_vl_n;
                end if;
                if (vctrl.csr_wen(0) = '1') then
                    vcsr.vstart <= vctrl.csr_vstart_n;
                end if;
            end if;
        end if;
    end process VCSR_LOGIC;

    --------------------------
    --- VRF Write Data MUX ---
    --------------------------
    WR_MUX : process(all) begin
        case vctrl.vrf_wr_sel is
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
        op2 <= vs2_out when (vctrl.osel_sel_op2 = '0') else vd_out;
        op0 <= vs2_out when (vctrl.osel_sel_op2 = '1') else vd_out;
        for ii in 0 to ((VLEN / 8) - 1) loop
            -- Select SCALAR --
            if (vctrl.osel_sel_imm = '1') then
                case vsew is
                    when "000"  => imm_scl(8*ii+7 downto 8*ii) := vctrl.osel_scalar(7 downto 0);
                    when "001"  => imm_scl(8*ii+7 downto 8*ii) := vctrl.osel_scalar(8*(ii mod 2)+7 downto 8*(ii mod 2));
                    when "010"  => imm_scl(8*ii+7 downto 8*ii) := vctrl.osel_scalar(8*(ii mod 4)+7 downto 8*(ii mod 2));
                    when others => imm_scl(8*ii+7 downto 8*ii) := (others => '0');
                end case;
            -- Select IMMEDIATE --
            else
                case vsew is
                    when "000"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(vctrl.osel_imm), 8));
                    when "001"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(vctrl.osel_imm), 8)) when ((ii mod 2) = 0) else (others => '0');
                    when "010"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(vctrl.osel_imm), 8)) when ((ii mod 4) = 0) else (others => '0');
                    when others => imm_scl(8*ii+7 downto 8*ii) := (others => '0');
                end case;
            end if;
        end loop;
        op1 <= vs1_out when (vctrl.osel_sel_op1 = '0') else imm_scl;
    end process OP_SEL;

end neorv32_vecop_rtl;
