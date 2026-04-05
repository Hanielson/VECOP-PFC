library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_valu is
    port(
        -- Clock and Reset --
        clk : in std_ulogic;
        rst : in std_ulogic;

        -- Back-End Input Signals --
        vinst : in std_ulogic_vector(XLEN-1 downto 0);
        scal2 : in std_ulogic_vector(XLEN-1 downto 0);
        scal1 : in std_ulogic_vector(XLEN-1 downto 0);
        start : in std_ulogic;

        -- O-SEL Control Signals --
        osel_imm     : std_ulogic_vector(4 downto 0);
        osel_sel_op2 : std_ulogic;
        osel_sel_op1 : std_ulogic;
        osel_sel_imm : std_ulogic;
        osel_scalar  : std_ulogic_vector(XLEN-1 downto 0);
    
        -- Vector Mask --
        vmask : in std_ulogic_vector(VLEN-1 downto 0);

        -- Control/Status Registers --
        vcsr : in vcsr_t;

        -- VRF Response Interface --
        vrf_vs2_rdata : in std_ulogic_vector(VLEN-1 downto 0);
        vrf_vs1_rdata : in std_ulogic_vector(VLEN-1 downto 0);
        vrf_vd_rdata  : in std_ulogic_vector(VLEN-1 downto 0);

        -- Sequencer Control Bus --
        valu_seq : out valu_seq_if_t;

        -- V-ALU Output Value --
        valu_out : out std_ulogic_vector(VLEN-1 downto 0);

        -- V-Dispatcher Output Signals --
        seqend : out std_ulogic;
        result : out std_ulogic_vector(XLEN-1 downto 0)
    );
end neorv32_valu;

architecture neorv32_valu_rtl of neorv32_valu is
    ------------------------------
    --- Component Declarations ---
    ------------------------------
    component neorv32_valu_seq is
        port(
            clk       : in std_ulogic;
            rst       : in std_ulogic;
            vinst     : in std_ulogic_vector(XLEN-1 downto 0);
            scal2     : in std_ulogic_vector(XLEN-1 downto 0);
            scal1     : in std_ulogic_vector(XLEN-1 downto 0);
            start     : in std_ulogic;
            vmask     : in std_ulogic_vector(VLEN-1 downto 0);
            vcsr      : in vcsr_t;
            int_done  : in std_ulogic;
            mask_done : in std_ulogic;
            valu_seq  : out valu_seq_if_t;
            seqend    : out std_ulogic;
            result    : out std_ulogic_vector(XLEN-1 downto 0)
        );
    end component neorv32_valu_seq;

    component neorv32_vint is
        port(
            clk         : in std_ulogic;
            rst         : in std_ulogic;
            alu_op      : in std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
            valid       : in std_ulogic;
            clear       : in std_ulogic;
            cyc_counter : in std_ulogic_vector(2 downto 0);
            op2         : in std_ulogic_vector(VLEN-1 downto 0);
            op1         : in std_ulogic_vector(VLEN-1 downto 0);
            op0         : in std_ulogic_vector(VLEN-1 downto 0);
            vmask       : in std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
            vsew        : in std_ulogic_vector(2 downto 0);
            int_out     : out std_ulogic_vector(VLEN-1 downto 0);
            int_done    : out std_ulogic
        );
    end component neorv32_vint;

    component neorv32_vmask is
        port(
            clk         : in std_ulogic;
            rst         : in std_ulogic;
            alu_op      : in std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
            valid       : in std_ulogic;
            clear       : in std_ulogic;
            masking_en  : in std_ulogic;
            vlm_mask    : in std_ulogic_vector(VLEN-1 downto 0);
            mul_counter : in std_ulogic_vector(2 downto 0);
            vmaskA      : in std_ulogic_vector(VLEN-1 downto 0);
            vmaskB      : in std_ulogic_vector(VLEN-1 downto 0);
            vmask_in    : in std_ulogic_vector(VALU_CHUNK_W-1 downto 0);
            vsew        : in std_ulogic_vector(2 downto 0);
            mask_out    : out std_ulogic_vector(VLEN-1 downto 0);
            mask_done   : out std_ulogic
        );
    end component neorv32_vmask;

    -- V-CSR Signals --
    signal vstart : std_ulogic_vector(XLEN-1 downto 0);
    signal vl     : std_ulogic_vector(XLEN-1 downto 0);
    signal vill   : std_ulogic;
    signal vma    : std_ulogic;
    signal vta    : std_ulogic;
    signal vsew   : std_ulogic_vector(2 downto 0);
    signal vlmul  : std_ulogic_vector(2 downto 0);

    -- VINT-ALU Signals --
    signal int_done : std_ulogic;
    signal int_out  : std_ulogic_vector(VLEN-1 downto 0);

    --VMASK-ALU Signals --
    signal mask_done : std_ulogic;
    signal mask_out  : std_ulogic_vector(VLEN-1 downto 0);

    -- O-SEL Signals --
    signal op2       : std_ulogic_vector(VLEN-1 downto 0);
    signal op1       : std_ulogic_vector(VLEN-1 downto 0);
    signal op0       : std_ulogic_vector(VLEN-1 downto 0);
begin

    --------------------------------
    --- V-CSR Signals Extraction ---
    --------------------------------
    vstart <= vcsr.vstart;
    vl     <= vcsr.vl;
    vill   <= vcsr.vtype(XLEN-1);
    vma    <= vcsr.vtype(7);
    vta    <= vcsr.vtype(6);
    vsew   <= vcsr.vtype(5 downto 3);
    vlmul  <= vcsr.vtype(2 downto 0);

    -------------------------------------
    --- Sequencing Unit Instantiation ---
    -------------------------------------
    valu_seq_top: entity work.neorv32_valu_seq port map(
        clk       => clk,
        rst       => rst,
        vinst     => vinst,
        scal2     => scal2,
        scal1     => scal1,
        start     => start,
        vmask     => vmask,
        vcsr      => vcsr,
        int_done  => int_done,
        mask_done => mask_done,
        valu_seq  => valu_seq,
        seqend    => seqend,
        result    => result
    );

    ---------------------------------
    --- SubModules Instantiations ---
    ---------------------------------
    vint: entity work.neorv32_vint port map(
        clk         => clk,
        rst         => rst,
        alu_op      => valu_seq.valu_op,
        valid       => valu_seq.vint_valid,
        clear       => valu_seq.vint_clear,
        cyc_counter => valu_seq.cyc_count,
        op2         => op2,
        op1         => op1,
        op0         => op0,
        vmask       => valu_seq.vint_mask,
        vsew        => vsew,
        int_out     => int_out,
        int_done    => int_done
    );

    vmask_top: entity work.neorv32_vmask port map(
        clk         => clk,
        rst         => rst,
        alu_op      => valu_seq.valu_op,
        valid       => valu_seq.vmask_valid,
        clear       => valu_seq.vmask_clear,
        masking_en  => valu_seq.masking_en,
        vlm_mask    => valu_seq.vlm_mask,
        mul_counter => valu_seq.mul_count,
        vmaskA      => vrf_vs2_rdata,
        vmaskB      => vrf_vs1_rdata,
        vmask_in    => vmask,
        vsew        => vsew,
        mask_out    => mask_out,
        mask_done   => mask_done
    );

    --------------------
    --- OP-SEL Logic ---
    --------------------
    OP_SEL : process(all) 
        variable imm_scl : std_ulogic_vector(VLEN-1 downto 0);
    begin
        op2 <= vrf_vs2_rdata when (osel_sel_op2 = '0') else vrf_vd_rdata;
        op0 <= vrf_vs2_rdata when (osel_sel_op2 = '1') else vrf_vd_rdata;
        for ii in 0 to ((VLEN / 8) - 1) loop
            -- Select SCALAR --
            if (osel_sel_imm = '1') then
                case vsew is
                    when "000"  => imm_scl(8*ii+7 downto 8*ii) := osel_scalar(7 downto 0);
                    when "001"  => imm_scl(8*ii+7 downto 8*ii) := osel_scalar(8*(ii mod 2)+7 downto 8*(ii mod 2));
                    when "010"  => imm_scl(8*ii+7 downto 8*ii) := osel_scalar(8*(ii mod 4)+7 downto 8*(ii mod 4));
                    when others => imm_scl(8*ii+7 downto 8*ii) := (others => '0');
                end case;
            -- Select IMMEDIATE --
            else
                case vsew is
                    when "000"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(osel_imm), 8));
                    when "001"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(osel_imm), 8)) when ((ii mod 2) = 0) else (others => '0');
                    when "010"  => imm_scl(8*ii+7 downto 8*ii) := std_ulogic_vector(resize(unsigned(osel_imm), 8)) when ((ii mod 4) = 0) else (others => '0');
                    when others => imm_scl(8*ii+7 downto 8*ii) := (others => '0');
                end case;
            end if;
        end loop;
        op1 <= vrf_vs1_rdata when (osel_sel_op1 = '0') else imm_scl;
    end process OP_SEL;

    -------------------------
    --- ALU_OUT MUX Logic ---
    -------------------------
    ALU_OUT : process(all) begin
        case valu_seq.valu_opclass is
            when VALU_INTOP   => valu_out <= int_out;
            when VALU_MOP     => valu_out <= mask_out;
            when VALU_INVALOP => valu_out <= (others => '0');
            when others       => valu_out <= (others => '0');
        end case;
    end process;
    
end architecture neorv32_valu_rtl;