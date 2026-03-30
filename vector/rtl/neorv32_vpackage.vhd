library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package neorv32_vpackage is

    -------------------------------
    --- Architectural Constants ---
    -------------------------------
    constant RVV_VERSION      : string  := "v1.0";
    constant VLEN             : natural := 128;
    constant XLEN             : natural := 32;
    constant VREF_ADDR_WIDTH  : natural := 5;
    constant VALU_OP_WIDTH    : natural := 8;
    constant MIN_VSEW         : natural := 8;
    constant MAX_VSEW         : natural := 32;
    constant MAX_ELEM         : natural := (VLEN / MIN_VSEW);
    constant ELEM_ID_WIDTH    : natural := natural(ceil(log2(real(MAX_ELEM))));
    constant VALU_CHUNK_W     : natural := 32;
    constant MAX_CHUNK        : natural := (VLEN / VALU_CHUNK_W);
    constant CHUNK_CNT_W      : natural := natural(ceil(log2(real(MAX_CHUNK))));
    constant VLSU_MEM_W       : natural := 32;
    constant VLSU_MAX_CHUNK   : natural := (VLEN / VLSU_MEM_W);
    constant VLSU_CHUNK_CNT_W : natural := natural(ceil(log2(real(VLSU_MAX_CHUNK))));

    ---------------------------------------
    --- Vector Control/Status Registers ---
    ---------------------------------------
    type vcsr_t is record
        vtype  : std_ulogic_vector(XLEN-1 downto 0);
        vl     : std_ulogic_vector(XLEN-1 downto 0);
        vlenb  : std_ulogic_vector(XLEN-1 downto 0);
        vstart : std_ulogic_vector(XLEN-1 downto 0);
    end record;

    --------------------------
    --- Vector Control Bus ---
    --------------------------
    type vctrl_bus_t is record
        -- V-QUEUE Control Signals --
        viq_nxt : std_ulogic;

        -- CSR Control Signals --
        csr_wen      : std_ulogic_vector(2 downto 0);
        csr_vtype_n  : std_ulogic_vector(XLEN-1 downto 0);
        csr_vl_n     : std_ulogic_vector(XLEN-1 downto 0);
        csr_vstart_n : std_ulogic_vector(XLEN-1 downto 0);

        -- V-SLD Control Signals --
        sld_en    : std_ulogic;
        sld_up    : std_ulogic;
        sld_last  : std_ulogic;
        sld_elem  : std_ulogic_vector(ELEM_ID_WIDTH-1 downto 0);

        -- VRF Control Signals --
        vrf_vs2    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        vrf_vs1    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        vrf_vd     : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        vrf_ben    : std_ulogic_vector((VLEN/8)-1 downto 0);
        vrf_wr_sel : std_ulogic_vector(1 downto 0);

        -- O-SEL Control Signals --
        osel_imm     : std_ulogic_vector(4 downto 0);
        osel_sel_op2 : std_ulogic;
        osel_sel_op1 : std_ulogic;
        osel_sel_imm : std_ulogic;
        osel_scalar  : std_ulogic_vector(XLEN-1 downto 0);

        -- V-ALU Control Signals --
        valu_op    : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
        valu_valid : std_ulogic;

        -- V-SLU Control Signals --
        vlsu_wen   : std_ulogic;
        vlsu_addr  : std_ulogic_vector(XLEN-1 downto 0);
        vlsu_strd  : std_ulogic_vector(XLEN-1 downto 0);
        vlsu_mode  : std_ulogic;
        vlsu_ordrd : std_ulogic;
        vlsu_vme   : std_ulogic;
        vlsu_width : std_ulogic_vector(2 downto 0);
        vlsu_start : std_ulogic;
    end record;

    --------------------------------------------
    -- Vector Instruction Queue Interface Bus --
    --------------------------------------------
    type viq_if_t is record
        inst  : std_ulogic_vector(XLEN-1 downto 0);
        scal2 : std_ulogic_vector(XLEN-1 downto 0);
        scal1 : std_ulogic_vector(XLEN-1 downto 0);
        valid : std_ulogic;
    end record;

    -----------------------------------------------
    --- Back-End Control/Response Interface Bus ---
    -----------------------------------------------
    type vback_ctrl_if is record
        -- V-CSR Control Signals --
        csr_wen      : std_ulogic_vector(2 downto 0);
        csr_vtype_n  : std_ulogic_vector(XLEN-1 downto 0);
        csr_vl_n     : std_ulogic_vector(XLEN-1 downto 0);
        csr_vstart_n : std_ulogic_vector(XLEN-1 downto 0);

        -- VRF Signals --
        vrf_sel : std_ulogic_vector(1 downto 0);

        -- O-SEL Control Signals --
        osel_imm     : std_ulogic_vector(4 downto 0);
        osel_sel_op2 : std_ulogic;
        osel_sel_op1 : std_ulogic;
        osel_sel_imm : std_ulogic;
        osel_scalar  : std_ulogic_vector(XLEN-1 downto 0);

        -- Dispatcher-Sequencers Control Signals --
        vinst      : std_ulogic_vector(XLEN-1 downto 0);
        scal2      : std_ulogic_vector(XLEN-1 downto 0);
        scal1      : std_ulogic_vector(XLEN-1 downto 0);
        valu_start : std_ulogic;
        vsld_start : std_ulogic;
        vlsu_start : std_ulogic;
    end record;

    type vback_resp_if is record
        -- V-ALU Response Signals --
        valu_seqend : std_ulogic;
        valu_result : std_ulogic_vector(XLEN-1 downto 0);
        
        -- V-SLD Response Signals --
        vsld_seqend : std_ulogic;
        vsld_result : std_ulogic_vector(XLEN-1 downto 0);
        
        -- V-LSU Response Signals --
        vlsu_seqend    : std_ulogic;
        vlsu_result    : std_ulogic_vector(XLEN-1 downto 0);
        vlsu_trap_id   : std_ulogic_vector(3 downto 0);
        vlsu_trap_addr : std_ulogic_vector(XLEN-1 downto 0);
    end record;

    -----------------------------
    --- V-ALU Operation Types ---
    -----------------------------
    type valu_opclass_t is (VALU_INTOP, VALU_MOP, VALU_INVALOP);

    --------------------------------
    -- SEQUENCERS Interface Buses --
    --------------------------------
    type valu_seq_if_t is record
        vrf_vs2      : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        vrf_vs1      : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        vrf_vd       : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        vrf_ben      : std_ulogic_vector((VLEN/8)-1 downto 0);
        valu_op      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
        valu_opclass : valu_opclass_t;
        vint_valid   : std_ulogic;
        vint_clear   : std_ulogic;
        vint_mask    : std_ulogic_vector((VLEN/8)-1 downto 0);
        vmask_valid  : std_ulogic;
        vmask_clear  : std_ulogic;
        masking_en   : std_ulogic;
        cyc_count    : std_ulogic_vector(2 downto 0);
        mul_count    : std_ulogic_vector(2 downto 0);
    end record;

    type vlsu_seq_if_t is record
        vrf_vs2   : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        vrf_vs1   : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        vrf_vd    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        vrf_wdata : std_ulogic_vector(VLEN-1 downto 0);
        vrf_ben   : std_ulogic_vector((VLEN/8)-1 downto 0);
        mem_strb  : std_ulogic;
        mem_rw    : std_ulogic;
        mem_addr  : std_ulogic_vector(XLEN-1 downto 0);
        mem_wdata : std_ulogic_vector(VLSU_MEM_W-1 downto 0);
        mem_ben   : std_ulogic_vector((VLSU_MEM_W/8)-1 downto 0);
    end record;

    ----------------------
    --- Vector Opcodes ---
    ----------------------
    constant vop_load      : std_ulogic_vector(6 downto 0) := "0000111";
    constant vop_store     : std_ulogic_vector(6 downto 0) := "0100111";
    constant vop_arith_cfg : std_ulogic_vector(6 downto 0) := "1010111";

    -----------------------------------------
    --- VRF Register File Type Definition ---
    -----------------------------------------
    type vregfile_t is array ((2**VREF_ADDR_WIDTH)-1 downto 0) of std_ulogic_vector(VLEN-1 downto 0);

    --------------------------------------------------
    --- Mock Memory Parameters and Type Definition ---
    --------------------------------------------------
    constant MEM_SIZE : natural := 512;
    constant ADDR_W   : natural := natural(ceil(log2(real(MEM_SIZE))));
    type mockmem_t is array (MEM_SIZE-1 downto 0) of std_ulogic_vector(VLSU_MEM_W-1 downto 0);

    --------------------------------------------------------
    --- VSEW Interpreted/Expanded Vector Type Definition ---
    --------------------------------------------------------
    type expand_t is array (natural range <>) of std_ulogic_vector;

    ----------------------------
    --- V-ALU Operations IDs ---
    ----------------------------
    constant valu_invalid    : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"00";
    constant valu_add        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"01";
    constant valu_sub        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"02";
    constant valu_rsub       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"03";
    constant valu_waddu      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"04";
    constant valu_wsubu      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"05";
    constant valu_wadd       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"06";
    constant valu_wsub       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"07";
    constant valu_waddu_2sew : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"08";
    constant valu_wsubu_2sew : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"09";
    constant valu_wadd_2sew  : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"0A";
    constant valu_wsub_2sew  : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"0B";
    constant valu_zext_vf2   : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"0C";
    constant valu_sext_vf2   : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"0D";
    constant valu_zext_vf4   : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"0E";
    constant valu_sext_vf4   : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"0F";
    constant valu_zext_vf8   : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"10";
    constant valu_sext_vf8   : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"11";
    constant valu_and        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"12";
    constant valu_or         : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"13";
    constant valu_xor        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"14";
    constant valu_sll        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"15";
    constant valu_srl        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"16";
    constant valu_sra        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"17";
    constant valu_se         : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"18";
    constant valu_sne        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"19";
    constant valu_sltu       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"1A";
    constant valu_slt        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"1B";
    constant valu_sleu       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"1C";
    constant valu_sle        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"1D";
    constant valu_sgtu       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"1E";
    constant valu_sgt        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"1F";
    constant valu_adc        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"20";
    constant valu_madc       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"21";
    constant valu_sbc        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"22";
    constant valu_msbc       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"23";
    constant valu_minu       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"24";
    constant valu_min        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"25";
    constant valu_maxu       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"26";
    constant valu_max        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"27";
    constant valu_merge      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"28";
    constant valu_nsrl       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"29";
    constant valu_nsra       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"2A";
    constant valu_vgather    : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"2B";
    constant valu_sldup      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"2C";
    constant valu_slddn      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"2D";
    constant valu_sld1up     : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"3E";
    constant valu_sld1dn     : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"3F";
    constant valu_mandn      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"40";
    constant valu_mand       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"41";
    constant valu_mor        : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"42";
    constant valu_mxor       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"43";
    constant valu_morn       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"44";
    constant valu_mnand      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"45";
    constant valu_mnor       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"46";
    constant valu_mxnor      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"47";
    constant valu_mvxs       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"48";
    constant valu_cpop       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"49";
    constant valu_first      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"4A";
    constant valu_msbf       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"4B";
    constant valu_msof       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"4C";
    constant valu_msif       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"4D";
    constant valu_iota       : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"4E";
    constant valu_id         : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0) := x"4F";
    
end neorv32_vpackage;