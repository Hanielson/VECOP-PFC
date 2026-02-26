library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_vecop is
    port(
        -- Clock and Reset --
        clk            : in std_ulogic;
        rst            : in std_ulogic;

        -- Scalar Core Interface --
        vinst_in       : in std_ulogic_vector(XLEN-1 downto 0);
        scal2_in       : in std_ulogic_vector(XLEN-1 downto 0);
        scal1_in       : in std_ulogic_vector(XLEN-1 downto 0);
        vinst_valid_in : in std_ulogic;
        viq_full       : out std_ulogic;
        viq_empty      : out std_ulogic

        -- HACK: REMOVE THESE PORTS AFTER TESTING --
        -- xor_alu_out : out std_ulogic;
        -- xor_sld_out : out std_ulogic;
        -- xor_vs2_out : out std_ulogic;
        -- xor_vs1_out : out std_ulogic;
        -- xor_vd_out  : out std_ulogic
    );
end neorv32_vecop;

architecture neorv32_vecop_rtl of neorv32_vecop is
    ------------------------------
    --- Component Declarations ---
    ------------------------------
    component neorv32_vdispatcher is
        port(
            clk            : in std_ulogic;
            rst            : in std_ulogic;
            vinst_in       : in std_ulogic_vector(XLEN-1 downto 0);
            scal2_in       : in std_ulogic_vector(XLEN-1 downto 0);
            scal1_in       : in std_ulogic_vector(XLEN-1 downto 0);
            vinst_valid_in : in std_ulogic;
            vcsr           : in vcsr_t;
            vback_resp     : in vback_resp_if;
            vback_ctrl     : out vback_ctrl_if;
            viq_full       : out std_ulogic;
            viq_empty      : out std_ulogic;
            cp_result      : out std_ulogic_vector(XLEN-1 downto 0);
            cp_valid       : out std_ulogic
        );
    end component neorv32_vdispatcher;

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

    component neorv32_valu_seq is
        port(
            clk      : in std_ulogic;
            rst      : in std_ulogic;
            vinst    : in std_ulogic_vector(XLEN-1 downto 0);
            scal2    : in std_ulogic_vector(XLEN-1 downto 0);
            scal1    : in std_ulogic_vector(XLEN-1 downto 0);
            start    : in std_ulogic;
            vmask    : in std_ulogic_vector(VLEN-1 downto 0);
            vcsr     : in vcsr_t;
            alu_done : in std_ulogic;
            valu_seq : out valu_seq_if_t;
            seqend   : out std_ulogic;
            result   : out std_ulogic_vector(XLEN-1 downto 0)
        );
    end component neorv32_valu_seq;

    component neorv32_valu is
        port(
            clk      : in std_ulogic;
            rst      : in std_ulogic;
            alu_op   : in std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
            valid    : in std_ulogic;
            op2      : in std_ulogic_vector(VLEN-1 downto 0);
            op1      : in std_ulogic_vector(VLEN-1 downto 0);
            op0      : in std_ulogic_vector(VLEN-1 downto 0);
            vmask    : in std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
            vsew     : in std_ulogic_vector(2 downto 0);
            alu_out  : out std_ulogic_vector(VLEN-1 downto 0);
            alu_done : out std_ulogic
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

    component neorv32_vlsu is
        port(
            clk           : in std_ulogic;
            rst           : in std_ulogic;
            vinst         : in std_ulogic_vector(XLEN-1 downto 0);
            scal2         : in std_ulogic_vector(XLEN-1 downto 0);
            scal1         : in std_ulogic_vector(XLEN-1 downto 0);
            start         : in std_ulogic;
            vmask         : in std_ulogic_vector(VLEN-1 downto 0);
            vcsr          : in vcsr_t;
            vrf_vs2_rdata : in std_ulogic_vector(VLEN-1 downto 0);
            vrf_vs1_rdata : in std_ulogic_vector(VLEN-1 downto 0);
            vrf_vd_rdata  : in std_ulogic_vector(VLEN-1 downto 0);
            mem_ack       : in std_ulogic;
            mem_rdata     : in std_ulogic_vector(VLSU_MEM_W-1 downto 0);
            vlsu_seq      : out vlsu_seq_if_t;
            seqend        : out std_ulogic;
            result        : out std_ulogic_vector(XLEN-1 downto 0)
        );
    end component neorv32_vlsu;

    component neorv32_vmockmem is
        port(
            clk   : in std_ulogic;
            rst   : in std_ulogic;
            strb  : in std_ulogic;
            rw    : in std_ulogic;
            addr  : in std_ulogic_vector(XLEN-1 downto 0);
            wdata : in std_ulogic_vector(VLSU_MEM_W-1 downto 0);
            ben   : in std_ulogic_vector((VLSU_MEM_W/8)-1 downto 0);
            ack   : out std_ulogic;
            rdata : out std_ulogic_vector(VLSU_MEM_W-1 downto 0)
        );
    end component neorv32_vmockmem;

    ---------------------------
    --- Signal Declarations ---
    ---------------------------
    signal vcsr  : vcsr_t;
    signal vmask : std_ulogic_vector(VLEN-1 downto 0);

    -- VECOP Output Signals --
    signal cp_result : std_ulogic_vector(XLEN-1 downto 0);
    signal cp_valid  : std_ulogic;

    -- V-Dispatcher Signals --
    signal vback_resp : vback_resp_if;
    signal vback_ctrl : vback_ctrl_if;

    -- Sequencers Signals --
    signal valu_seq : valu_seq_if_t;
    signal vlsu_seq : vlsu_seq_if_t;

    -- V-CSR Signals --
    signal vstart : std_ulogic_vector(XLEN-1 downto 0);
    signal vl     : std_ulogic_vector(XLEN-1 downto 0);
    signal vill   : std_ulogic;
    signal vma    : std_ulogic;
    signal vta    : std_ulogic;
    signal vsew   : std_ulogic_vector(2 downto 0);
    signal vlmul  : std_ulogic_vector(2 downto 0);

    -- VRF Signals --
    signal vrf_vs2     : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vrf_vs1     : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vrf_vd      : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vrf_ben     : std_ulogic_vector((VLEN/8)-1 downto 0);
    signal vrf_wr_data : std_ulogic_vector(VLEN-1 downto 0);
    signal vs2_data     : std_ulogic_vector(VLEN-1 downto 0);
    signal vs1_data     : std_ulogic_vector(VLEN-1 downto 0);
    signal vd_data      : std_ulogic_vector(VLEN-1 downto 0);
    
    -- ALU Signals --
    signal op2      : std_ulogic_vector(VLEN-1 downto 0);
    signal op1      : std_ulogic_vector(VLEN-1 downto 0);
    signal op0      : std_ulogic_vector(VLEN-1 downto 0);
    signal alu_out  : std_ulogic_vector(VLEN-1 downto 0);
    signal alu_done : std_ulogic;

    -- SLD Signals --
    signal sld_out  : std_ulogic_vector(VLEN-1 downto 0);
    signal sld_be   : std_ulogic_vector((VLEN/8)-1 downto 0);
    signal sld_done : std_ulogic;

    -- Mock Memory Signals --
    signal mockmem_ack   : std_ulogic;
    signal mockmem_rdata : std_ulogic_vector(VLSU_MEM_W-1 downto 0);

    ------------------------------------------------------------------------
    
    -- HACK: TEST IF VIVADO IS TRIMMING STUFF UP --
    -- attribute DONT_TOUCH : string;
    -- attribute DONT_TOUCH of neorv32_vecop_rtl : architecture is "TRUE";
begin
    -- HACK: THESE SIGNALS SHOULD BE REMOVED AFTER TESTING --
    -- xor_alu_out <= xor alu_out;
    -- xor_sld_out <= xor sld_out;
    -- xor_vs2_out <= xor vs2_data;
    -- xor_vs1_out <= xor vs1_data;
    -- xor_vd_out  <= xor vd_data;

    ----------------------------------
    --- Sub-Modules Instantiations ---
    ----------------------------------
    vdisp: entity work.neorv32_vdispatcher port map (
        clk            => clk,
        rst            => rst,
        vinst_in       => vinst_in,
        vinst_valid_in => vinst_valid_in,
        scal2_in       => (others => '0'),
        scal1_in       => (others => '0'),
        vcsr           => vcsr,
        vback_resp     => vback_resp,
        vback_ctrl     => vback_ctrl,
        viq_full       => viq_full,
        viq_empty      => viq_empty,
        cp_result      => cp_result,
        cp_valid       => cp_valid
    );

    vrf: entity work.neorv32_vrf port map (
        clk     => clk,
        vs2     => vrf_vs2,
        vs1     => vrf_vs1,
        vd      => vrf_vd,
        wr_ben  => vrf_ben,
        wr_data => vrf_wr_data,
        vs2_out => vs2_data,
        vs1_out => vs1_data,
        vd_out  => vd_data,
        vmask   => vmask
    );

    valu_seq_top: entity work.neorv32_valu_seq port map(
        clk      => clk,
        rst      => rst,
        vinst    => vback_ctrl.vinst,
        scal2    => vback_ctrl.scal2,
        scal1    => vback_ctrl.scal1,
        start    => vback_ctrl.valu_start,
        vmask    => vmask,
        vcsr     => vcsr,
        alu_done => alu_done,
        valu_seq => valu_seq,
        seqend   => vback_resp.valu_seqend,
        result   => vback_resp.valu_result
    );

    valu: entity work.neorv32_valu port map (
        clk      => clk,
        rst      => rst,
        alu_op   => valu_seq.valu_op,
        valid    => valu_seq.valu_valid,
        op2      => op2,
        op1      => op1,
        op0      => op0,
        vmask    => vmask(VALU_CHUNK_W-1 downto 0),
        vsew     => vsew,
        alu_out  => alu_out,
        alu_done => alu_done
    );

    vsld: entity work.neorv32_vsld port map (
        clk       => clk,
        rst       => rst,
        sld_vs2   => vs2_data,
        sld_vs1   => vs1_data,
        vsew      => vsew,
        sld_en    => '0', -- vctrl.sld_en,
        sld_up    => '0', -- vctrl.sld_up,
        sld_last  => '0', -- vctrl.sld_last,
        sld_elem  => (others =>'0'), -- vctrl.sld_elem,
        sld_out   => sld_out,
        sld_be    => sld_be,
        sld_done  => sld_done
    );

    vlsu: entity work.neorv32_vlsu port map (
        clk           => clk,
        rst           => rst,
        vinst         => vback_ctrl.vinst,
        scal2         => vback_ctrl.scal2,
        scal1         => vback_ctrl.scal1,
        start         => vback_ctrl.vlsu_start,
        vmask         => vmask,
        vcsr          => vcsr,
        vrf_vs2_rdata => vs2_data,
        vrf_vs1_rdata => vs1_data,
        vrf_vd_rdata  => vd_data,
        mem_ack       => mockmem_ack,
        mem_rdata     => mockmem_rdata,
        vlsu_seq      => vlsu_seq,
        seqend        => vback_resp.vlsu_seqend,
        result        => vback_resp.vlsu_result
    );

    vmockmem: entity work.neorv32_vmockmem port map (
        clk   => clk,
        rst   => rst,
        strb  => vlsu_seq.mem_strb,
        rw    => vlsu_seq.mem_rw,
        addr  => vlsu_seq.mem_addr,
        wdata => vlsu_seq.mem_wdata,
        ben   => vlsu_seq.mem_ben,
        ack   => mockmem_ack,
        rdata => mockmem_rdata
    );

    ------------------------------------
    --- V-CSR Signals Extraction ---
    ------------------------------------
    vstart <= vcsr.vstart;
    vl     <= vcsr.vl;
    vill   <= vcsr.vtype(XLEN-1);
    vma    <= vcsr.vtype(7);
    vta    <= vcsr.vtype(6);
    vsew   <= vcsr.vtype(5 downto 3);
    vlmul  <= vcsr.vtype(2 downto 0);

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
                if (vback_ctrl.csr_wen(2) = '1') then
                    vcsr.vtype <= vback_ctrl.csr_vtype_n;
                end if;
                if (vback_ctrl.csr_wen(1) = '1') then
                    vcsr.vl <= vback_ctrl.csr_vl_n;
                end if;
                if (vback_ctrl.csr_wen(0) = '1') then
                    vcsr.vstart <= vback_ctrl.csr_vstart_n;
                end if;
                vcsr.vlenb <= vcsr.vlenb;
            end if;
        end if;
    end process VCSR_LOGIC;

    --------------------------
    --- VRF Interface MUXes ---
    --------------------------
    VRF_MUX : process(all) begin
        case vback_ctrl.vrf_sel is
            -- V-ALU Write-Back --
            when "00" =>
                vrf_vs2     <= valu_seq.vrf_vs2;
                vrf_vs1     <= valu_seq.vrf_vs1;
                vrf_vd      <= valu_seq.vrf_vd;
                vrf_ben     <= valu_seq.vrf_ben;
                vrf_wr_data <= alu_out;
            -- V-SLD Write-Back --
            when "01" =>
                vrf_vs2     <= (others => '0');
                vrf_vs1     <= (others => '0');
                vrf_vd      <= (others => '0');
                vrf_ben     <= (others => '0');
                vrf_wr_data <= sld_out;
            -- V-LSU Write-Back --
            when "10" =>
                vrf_vs2     <= vlsu_seq.vrf_vs2;
                vrf_vs1     <= vlsu_seq.vrf_vs1;
                vrf_vd      <= vlsu_seq.vrf_vd;
                vrf_ben     <= vlsu_seq.vrf_ben;
                vrf_wr_data <= vlsu_seq.vrf_wdata;
            -- VS2 Write-Back (for move instruction) --
            when "11" =>
                vrf_vs2     <= (others => '0');
                vrf_vs1     <= (others => '0');
                vrf_vd      <= (others => '0');
                vrf_ben     <= (others => '0'); 
                vrf_wr_data <= vs2_data;
            when others => 
                vrf_vs2     <= (others => '0');
                vrf_vs1     <= (others => '0');
                vrf_vd      <= (others => '0');
                vrf_ben     <= (others => '0');
                vrf_wr_data <= (others => '0');
        end case;
    end process VRF_MUX;

    --------------------
    --- OP-SEL Logic ---
    --------------------
    OP_SEL : process(all) 
        variable imm_scl : std_ulogic_vector(VLEN-1 downto 0);
    begin
        op2 <= vs2_data when (vback_ctrl.osel_sel_op2 = '0') else vd_data;
        op0 <= vs2_data when (vback_ctrl.osel_sel_op2 = '1') else vd_data;
        for ii in 0 to ((VLEN / 8) - 1) loop
            -- Select SCALAR --
            if (vback_ctrl.osel_sel_imm = '1') then
                case vsew is
                    when "000"  => imm_scl(8*ii+7 downto 8*ii) := vback_ctrl.osel_scalar(7 downto 0);
                    when "001"  => imm_scl(8*ii+7 downto 8*ii) := vback_ctrl.osel_scalar(8*(ii mod 2)+7 downto 8*(ii mod 2));
                    when "010"  => imm_scl(8*ii+7 downto 8*ii) := vback_ctrl.osel_scalar(8*(ii mod 4)+7 downto 8*(ii mod 4));
                    when others => imm_scl(8*ii+7 downto 8*ii) := (others => '0');
                end case;
            -- Select IMMEDIATE --
            else
                case vsew is
                    when "000"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(vback_ctrl.osel_imm), 8));
                    when "001"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(vback_ctrl.osel_imm), 8)) when ((ii mod 2) = 0) else (others => '0');
                    when "010"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(vback_ctrl.osel_imm), 8)) when ((ii mod 4) = 0) else (others => '0');
                    when others => imm_scl(8*ii+7 downto 8*ii) := (others => '0');
                end case;
            end if;
        end loop;
        op1 <= vs1_data when (vback_ctrl.osel_sel_op1 = '0') else imm_scl;
    end process OP_SEL;
end architecture neorv32_vecop_rtl;
