library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_vcu is
    port(
        -- Clock and Reset --
        clk         : in std_ulogic;
        rst         : in std_ulogic;

        -- VI-Queue Signals --
        vinst       : in std_ulogic_vector(XLEN-1 downto 0);
        vinst_valid : in std_ulogic;
        vq_full     : in std_ulogic;
        scal2       : in std_ulogic_vector(XLEN-1 downto 0);
        scal1       : in std_ulogic_vector(XLEN-1 downto 0);

        -- Vector Mask --
        vmask       : in std_ulogic_vector(VLEN-1 downto 0);

        -- V-CSR Signals --
        vstart      : in std_ulogic_vector(XLEN-1 downto 0);
        vl          : in std_ulogic_vector(XLEN-1 downto 0);
        vill        : in std_ulogic;
        vma         : in std_ulogic;
        vta         : in std_ulogic;
        vsew        : in std_ulogic_vector(2 downto 0);
        vlmul       : in std_ulogic_vector(2 downto 0);

        -- V-SLD Signals --
        sld_done    : in std_ulogic;
        sld_be      : in std_ulogic_vector((VLEN/8)-1 downto 0);

        -- V-LSU Signals --
        lsu_done    : in std_ulogic;
        memtrp_id   : in std_ulogic_vector(1 downto 0);
        memtrp_addr : in std_ulogic_vector(XLEN-1 downto 0);

        -- Control Signals Bus --
        vctrl       : out vctrl_bus_t;

        -- Outputs to Scalar Core --
        cp_result   : out std_ulogic_vector(XLEN-1 downto 0);
        cp_valid    : out std_ulogic
    );
end neorv32_vcu;

architecture neorv32_vcu_rtl of neorv32_vcu is

    type ctrl_state_t is (IDLE, DECODE, VCONFIG, ALU_START, ALU_EXEC, SLIDE_START, SLIDE_EXEC, INVALID);
    signal state : ctrl_state_t;

    signal vinst_i : std_ulogic_vector(XLEN-1 downto 0);
    signal vlmul_i : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

    signal reg_offset  : unsigned(VREF_ADDR_WIDTH-1 downto 0);
    signal elem_offset : unsigned(4 downto 0);

    signal dest    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal dest_ff : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal src1    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal src2    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

    signal funct3 : std_ulogic_vector(2 downto 0);
    signal vs1    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vs2    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vm     : std_ulogic;
    signal funct6 : std_ulogic_vector(5 downto 0);

    signal valu_op : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);

    signal cyc_count : std_ulogic_vector(2 downto 0);
    signal mul_count : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

begin

    ----------------------
    --- VLMUL Decoding ---
    ----------------------
    process(all) begin
        case vlmul is
            when "001"  => vlmul_i <= "00010";
            when "010"  => vlmul_i <= "00100";
            when "011"  => vlmul_i <= "01000";
            when others => vlmul_i <= "00001";
        end case;
    end process;

    ---------------------------------------------------------------
    --- Function Fields / Vector Mask from Instruction Encoding ---
    ---------------------------------------------------------------
    process(all) begin
        funct3 <= vinst_i(14 downto 12);
        vs1    <= vinst_i(19 downto 15);
        vs2    <= vinst_i(24 downto 20);
        vm     <= vinst_i(25);
        funct6 <= vinst_i(31 downto 26);
    end process;

    --------------------------------------------------------------------
    --- Next-State Generation / Instruction Load / Internal Counters ---
    --------------------------------------------------------------------
    process(clk, rst)
        variable opcode      : std_ulogic_vector(6 downto 0);
        variable max_cyc     : std_ulogic_vector(2 downto 0);
        variable offset      : std_ulogic_vector(XLEN-1 downto 0);
        variable src2_offset : unsigned(VREF_ADDR_WIDTH-1 downto 0);
        variable dest_offset : unsigned(VREF_ADDR_WIDTH-1 downto 0);
    begin
        if (rst = '1') then
            cyc_count <= (others => '0');
            dest      <= (others => '0');
            src1      <= (others => '0');
            src2      <= (others => '0');
            mul_count <= (others => '0');
            dest_ff   <= (others => '0');
            vinst_i   <= (others => '0');
            state     <= IDLE;
        elsif rising_edge(clk) then
            case state is
                -- Waiting for Valid Instruction --
                when IDLE =>
                    cyc_count <= (others => '0');
                    dest      <= (others => '0');
                    src1      <= (others => '0');
                    src2      <= (others => '0');
                    mul_count <= (others => '0');
                    dest_ff   <= (others => '0');
                    -- If received a valid instruction indication... --
                    if (vinst_valid = '1') then
                        vinst_i <= vinst;
                        state   <= DECODE;
                    -- Else, keep waiting... --
                    else
                        state <= IDLE;
                    end if;

                -- Instruction Decode Stage --
                when DECODE =>
                    --------------------------------------
                    -- Instruction Operands/Destination --
                    --------------------------------------
                    -- NOTE: we store src2/src1 in registers to operate on them during multi-cycle operations, --
                    --       however the original values are preserved in vs2/vs1 signals for ALU op decoding  --

                    if    (funct3 = "100") then offset := scal1;
                    elsif (funct3 = "011") then offset := std_ulogic_vector(resize(unsigned(vinst_i(19 downto 15)), XLEN));
                    else                        offset := (others => '0');
                    end if;
                    case vsew is
                        when "000" =>
                            reg_offset  <= resize(unsigned(offset(XLEN-1 downto 5)), VREF_ADDR_WIDTH);
                            elem_offset <= resize(unsigned(offset(4 downto 0)), 5);
                        when "001" =>
                            reg_offset  <= resize(unsigned(offset(XLEN-1 downto 4)), VREF_ADDR_WIDTH);
                            elem_offset <= resize(unsigned(offset(3 downto 0)), 5);
                        when "010" =>
                            reg_offset  <= resize(unsigned(offset(XLEN-1 downto 3)), VREF_ADDR_WIDTH);
                            elem_offset <= resize(unsigned(offset(2 downto 0)), 5);
                        when others =>
                            reg_offset  <= (others => '0');
                            elem_offset <= (others => '0');
                    end case;
                    
                    case valu_op is
                        when valu_sldup =>
                            dest_offset := reg_offset;
                            src2_offset := (others => '0');
                            
                        when valu_slddn =>
                            dest_offset := (others => '0');
                            src2_offset := reg_offset;
                        
                        when others =>
                            dest_offset := (others => '0');
                            src2_offset := (others => '0');
                    end case;

                    dest <= std_ulogic_vector(resize(unsigned(vinst_i(11 downto 7)), VREF_ADDR_WIDTH) + dest_offset);
                    src1 <= vinst_i(19 downto 15);
                    src2 <= std_ulogic_vector(resize(unsigned(vinst_i(24 downto 20)), VREF_ADDR_WIDTH) + src2_offset);
                    
                    -- Operation State --
                    opcode := vinst_i(6 downto 0);
                    case opcode is
                        -- Load Instruction --
                        when vop_load =>
                            state <= IDLE;

                        -- Store Instruction --
                        when vop_store =>
                            state <= IDLE;

                        -- Airthmetic or Configuration Instruction --
                        when vop_arith_cfg =>
                            if (funct3 = "111") then
                                state <= VCONFIG;
                            elsif (valu_op = valu_invalid) then
                                state <= INVALID;
                            elsif (valu_op = valu_sldup) or (valu_op = valu_slddn) or (valu_op = valu_sld1up) or (valu_op = valu_sld1dn) then
                                -- TODO: update this check for synthesis --
                                if ((unsigned(reg_offset) + 1) > unsigned(vlmul_i)) then
                                    state <= IDLE;
                                else
                                    state <= SLIDE_START;
                                end if;
                            else
                                state <= ALU_START;
                            end if;

                        -- Unsupported Opcode --
                        when others =>
                            state <= INVALID;
                    end case;
                
                -- CSR Write State --
                when VCONFIG =>
                    state <= IDLE;
                    
                -- ALU Startup/Execution State --
                when ALU_START | ALU_EXEC =>
                    case valu_op is
                        when valu_waddu      | valu_wsubu      |
                             valu_wadd       | valu_wsub       |
                             valu_waddu_2sew | valu_wsubu_2sew |
                             valu_wadd_2sew  | valu_wsub_2sew  |
                             valu_zext_vf2   | valu_sext_vf2   |
                             valu_nsrl       | valu_nsra   => max_cyc := "001";
                        when valu_zext_vf4 | valu_sext_vf4 => max_cyc := "011";
                        when others                        => max_cyc := "000";
                    end case;

                    if (cyc_count = max_cyc) then
                        cyc_count <= (others => '0');
                        dest      <= std_ulogic_vector(unsigned(dest) + 1);
                        src1      <= std_ulogic_vector(unsigned(src1) + 1);
                        src2      <= std_ulogic_vector(unsigned(src2) + 1);
                        mul_count <= std_ulogic_vector(unsigned(mul_count) + 1);
                    else
                        cyc_count <= std_ulogic_vector(unsigned(cyc_count) + 1);
                        
                        if (valu_op /= valu_nsrl) and (valu_op /= valu_nsra) then
                            dest <= std_ulogic_vector(unsigned(dest) + 1);
                        end if;

                        if (valu_op = valu_waddu_2sew) or (valu_op = valu_wsubu_2sew) or 
                           (valu_op = valu_wadd_2sew)  or (valu_op = valu_wsub_2sew)  or
                           (valu_op = valu_nsrl)       or (valu_op = valu_nsra)       then
                            src2 <= std_ulogic_vector(unsigned(src2) + 1);
                        end if;
                    end if;

                    if (cyc_count = "000") and (mul_count = vlmul_i) then
                        state <= IDLE;
                    else
                        state <= ALU_EXEC;
                    end if;

                    -- Delays Destination in 1 cycle because of Read delay --
                    dest_ff <= dest;

                -- SLIDE Startup/Execution State --
                when SLIDE_START | SLIDE_EXEC =>
                    -- SRC2 already needs to be updated on SLIDE_START due to READ_DELAY --
                    -- DEST should only be updated when SLD operation is done            --
                    if (state = SLIDE_START) or (sld_done = '1') then
                        if (sld_done = '1') then
                            dest      <= std_ulogic_vector(unsigned(dest) + 1);
                        end if;
                        src2      <= std_ulogic_vector(unsigned(src2) + 1);
                        mul_count <= std_ulogic_vector(unsigned(mul_count) + 1);
                    end if;

                    if (mul_count = vlmul_i) and (sld_done = '1') then
                        state <= IDLE;
                    else
                        state <= SLIDE_EXEC;
                    end if;
                    
                -- Invalid Instruction State --
                -- TODO: for now we just return to IDLE, but vill needs to be set... --
                when INVALID =>
                    state <= IDLE;

                when others =>
                    state <= INVALID;
            end case;
        end if;
    end process;

    ------------------------------
    --- Output Generation Logic --
    ------------------------------
    process(all)
        variable vs2_i      : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable vs1_i      : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable vd         : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable valu_valid : std_ulogic;
        variable ben_i      : std_ulogic_vector((VLEN/8)-1 downto 0);
        variable byte_en    : std_ulogic_vector((VLEN/8)-1 downto 0);
        variable mask_i     : std_ulogic_vector((VLEN/8)-1 downto 0);
        variable wr_sel     : std_ulogic_vector(1 downto 0);
        variable imm        : std_ulogic_vector(4 downto 0);
        variable sel_op2    : std_ulogic;
        variable sel_op1    : std_ulogic;
        variable sel_imm    : std_ulogic;
        variable scalar     : std_ulogic_vector(XLEN-1 downto 0);

        variable vsld_en   : std_ulogic;
        variable vsld_last : std_ulogic;
        variable vsld_up   : std_ulogic;
        variable vsld_elem : std_ulogic_vector(4 downto 0);

        variable vtype_i : std_ulogic_vector(XLEN-1 downto 0);
        variable vtype_n : std_ulogic_vector(XLEN-1 downto 0);
        variable avl     : std_ulogic_vector(XLEN-1 downto 0);
        variable vl_n    : std_ulogic_vector(XLEN-1 downto 0);
        variable vlmax   : unsigned(XLEN-1 downto 0);
    begin
        case state is
            -- Waiting for Valid Instruction --
            when IDLE =>
                vctrl <= (
                    -- VI-Queue Control --
                    viq_nxt => '1',
                    -- CSR Control --
                    csr_wen => (others => '0'), csr_vtype_n  => (others => '0'), csr_vl_n => (others => '0'), csr_vstart_n => (others => '0'),
                    -- V-SLD Control --
                    sld_en => '0', sld_elem => (others => '0'), sld_up => '0', sld_last => '0',
                    -- VRF Control --
                    vrf_vs2 => (others => '0'), vrf_vs1 => (others => '0'), vrf_vd => (others => '0'), vrf_ben => (others => '0'), vrf_wr_sel => (others => '0'),
                    -- O-SEL Control --
                    osel_imm => (others => '0'), osel_sel_op2 => '0', osel_sel_op1 => '0', osel_sel_imm => '0', osel_scalar => (others => '0'),
                    -- V-ALU Control --
                    valu_op => (others => '0'), valu_valid => '0',
                    -- V-LSU Control --
                    vlsu_wen => '0', vlsu_addr => (others => '0'), vlsu_strd => (others => '0'), vlsu_mode => '0', vlsu_ordrd => '0', vlsu_vme => '0', vlsu_width => (others => '0'), vlsu_start => '0'
                );
                cp_result <= (others => '0');
                cp_valid  <= '0';

            -- V-CONFIG State --
            when VCONFIG =>
                case vinst_i(31 downto 30) is
                    when "10" =>
                        vtype_i := scal2;
                        if    (vs1 /= "00000") then avl := scal1;
                        elsif (dest = "00000") then avl := (others => '1');
                        else                        avl := vl;     
                        end if;

                    when "11" =>
                        vtype_i := std_ulogic_vector(resize(unsigned(vinst_i(29 downto 20)), vtype_i'length));
                        avl     := std_ulogic_vector(resize(unsigned(vinst_i(19 downto 15)), avl'length));

                    when others =>
                        vtype_i := std_ulogic_vector(resize(unsigned(vinst_i(30 downto 20)), vtype_i'length));
                        if    (vs1 /= "00000") then avl := scal1;
                        elsif (dest = "00000") then avl := (others => '1');
                        else                        avl := vl;     
                        end if;
                end case;

                -- Check for any invalid field in proposed vtype value --
                if (vtype_i(XLEN-1) = '1') or (vtype_i(XLEN-2 downto 8) /= std_ulogic_vector(to_unsigned(0, XLEN-9))) or (vtype_i(5 downto 3) = "011") or (vtype_i(5) = '1') or (vtype_i(2 downto 0) = "100") then
                    vtype_n := (XLEN-1 => '1', others => '0');
                    vl_n    := (others => '0');
                else
                    vtype_n := vtype_i;

                    -- Calculates VLMAX for the proposed VSEW configuration --
                    if    (vtype_i(5 downto 3) = "000") then vlmax := shift_right(to_unsigned(VLEN, vlmax'length), 3);
                    elsif (vtype_i(5 downto 3) = "001") then vlmax := shift_right(to_unsigned(VLEN, vlmax'length), 4);
                    elsif (vtype_i(5 downto 3) = "010") then vlmax := shift_right(to_unsigned(VLEN, vlmax'length), 5);
                    else                                     vlmax := to_unsigned(0, vlmax'length);
                    end if;

                    -- Defines new vl value based on AVL and VLMAX, stripmining if necessary --
                    if (unsigned(avl) > vlmax) then vl_n := std_ulogic_vector(resize(vlmax, vl_n'length));
                    else                            vl_n := avl;
                    end if;
                end if;

                vctrl <= (
                    -- VI-Queue Control --
                    viq_nxt => '0',
                    -- CSR Control --
                    csr_wen => "110", csr_vtype_n => vtype_n, csr_vl_n => vl_n, csr_vstart_n => (others => '0'),
                    -- V-SLD Control --
                    sld_en => '0', sld_elem => (others => '0'), sld_up => '0', sld_last => '0',
                    -- VRF Control --
                    vrf_vs2 => (others => '0'), vrf_vs1 => (others => '0'), vrf_vd => (others => '0'), vrf_ben => (others => '0'), vrf_wr_sel => (others => '0'),
                    -- O-SEL Control --
                    osel_imm => (others => '0'), osel_sel_op2 => '0', osel_sel_op1 => '0', osel_sel_imm => '0', osel_scalar => (others => '0'),
                    -- V-ALU Control --
                    valu_op => (others => '0'), valu_valid => '0',
                    -- V-LSU Control --
                    vlsu_wen => '0', vlsu_addr => (others => '0'), vlsu_strd => (others => '0'), vlsu_mode => '0', vlsu_ordrd => '0', vlsu_vme => '0', vlsu_width => (others => '0'), vlsu_start => '0'
                );
                cp_result <= vl_n;
                cp_valid  <= '1';

            -- ALU Execution State --
            when ALU_START | ALU_EXEC =>
                -- Operation Independent Signals --
                vs2_i   := src2;
                vs1_i   := src1;
                vd      := dest_ff;
                imm     := vs1;
                sel_op2 := '0';
                scalar  := scal1;
                wr_sel  := "00";
                
                -- Operation/Cycle Dependent Signals --
                if (state = ALU_START) then
                    valu_valid := '0';
                    ben_i      := (others => '0');
                else
                    valu_valid := '1';
                    case valu_op is
                        -- Narrowing Operations --
                        when valu_nsrl | valu_nsra =>
                            if (cyc_count(0) = '1') then
                                ben_i := (ben_i'length-1 downto (ben_i'length/2) => '1', others => '0');
                            else
                                ben_i := ((ben_i'length/2)-1 downto 0 => '1', others => '0');
                            end if;

                        -- Other Operation Types --
                        when others =>
                            ben_i      := (others => '1');
                    end case;
                end if;
                -- TODO: implement masking using below variable
                mask_i  := (others => '1');
                byte_en := ben_i and mask_i;

                case funct3 is
                    -- Immediate --
                    when "011"                 => sel_op1 := '1'; sel_imm := '0';
                    -- Scalar --
                    when "100" | "101" | "110" => sel_op1 := '1'; sel_imm := '1';
                    -- Vector Operand --
                    when others                => sel_op1 := '0'; sel_imm := '0';
                end case;

                vctrl <= (
                    -- VI-Queue Control --
                    viq_nxt => '0',
                    -- CSR Control --
                    csr_wen => (others => '0'), csr_vtype_n  => (others => '0'), csr_vl_n => (others => '0'), csr_vstart_n => (others => '0'),
                    -- V-SLD Control --
                    sld_en => '0', sld_elem => (others => '0'), sld_up => '0', sld_last => '0',
                    -- VRF Control --
                    vrf_vs2 => vs2_i, vrf_vs1 => vs1_i, vrf_vd => vd, vrf_ben => byte_en, vrf_wr_sel => wr_sel,
                    -- O-SEL Control --
                    osel_imm => imm, osel_sel_op2 => sel_op2, osel_sel_op1 => sel_op1, osel_sel_imm => sel_imm, osel_scalar => scalar,
                    -- V-ALU Control --
                    valu_op => valu_op, valu_valid => valu_valid,
                    -- V-LSU Control --
                    vlsu_wen => '0', vlsu_addr => (others => '0'), vlsu_strd => (others => '0'), vlsu_mode => '0', vlsu_ordrd => '0', vlsu_vme => '0', vlsu_width => (others => '0'), vlsu_start => '0'
                );
                cp_result <= (others => '0');
                cp_valid  <= '0';

            -- SLIDE START --    
            when SLIDE_START | SLIDE_EXEC =>
                wr_sel := "01";
                vs2_i  := src2;
                vs1_i  := std_ulogic_vector(unsigned(src2) + 1);

                if (state = SLIDE_START) or ((sld_done = '1') and (mul_count = vlmul_i)) then
                    vsld_en := '0';
                else
                    vsld_en := '1';
                end if;

                if (mul_count = vlmul_i) then
                    vsld_last := '1';
                else
                    vsld_last := '0';
                end if;

                case valu_op is
                    when valu_sldup =>
                        vsld_up   := '1';
                        vsld_elem := std_ulogic_vector(elem_offset);
                    when valu_slddn =>
                        vsld_up   := '0';
                        vsld_elem := std_ulogic_vector(elem_offset);
                    when valu_sld1up =>
                        vsld_up   := '1';
                        vsld_elem := (0 => '1', others => '0');
                    when valu_sld1dn =>
                        vsld_up   := '0';
                        vsld_elem := (0 => '1', others => '0');
                    when others =>
                end case;

                if ((mul_count = "00001") and ((valu_op = valu_sldup) or (valu_op = valu_sld1up))) or
                   ((mul_count = vlmul_i) and ((valu_op = valu_slddn) or (valu_op = valu_sld1dn))) then 
                    ben_i := sld_be;
                else
                    ben_i := (others => '1');
                end if;
                -- TODO: implement masking using below variable
                mask_i  := (others => '1');
                byte_en := ben_i and mask_i;

                vctrl <= (
                    -- VI-Queue Control --
                    viq_nxt => '0',
                    -- CSR Control --
                    csr_wen => (others => '0'), csr_vtype_n  => (others => '0'), csr_vl_n => (others => '0'), csr_vstart_n => (others => '0'),
                    -- V-SLD Control --
                    sld_en => vsld_en, sld_elem => vsld_elem, sld_up => vsld_up, sld_last => vsld_last,
                    -- VRF Control --
                    vrf_vs2 => vs2_i, vrf_vs1 => vs1_i, vrf_vd => dest, vrf_ben => byte_en, vrf_wr_sel => wr_sel,
                    -- O-SEL Control --
                    osel_imm => (others => '0'), osel_sel_op2 => '0', osel_sel_op1 => '0', osel_sel_imm => '0', osel_scalar => (others => '0'),
                    -- V-ALU Control --
                    valu_op => (others => '0'), valu_valid => '0',
                    -- V-LSU Control --
                    vlsu_wen => '0', vlsu_addr => (others => '0'), vlsu_strd => (others => '0'), vlsu_mode => '0', vlsu_ordrd => '0', vlsu_vme => '0', vlsu_width => (others => '0'), vlsu_start => '0'
                );
                cp_result <= (others => '0');
                cp_valid  <= '0';

            -- INVALID STATE --
            when others =>
                vctrl <= (
                    -- VI-Queue Control --
                    viq_nxt => '0',
                    -- CSR Control --
                    csr_wen => (others => '0'), csr_vtype_n  => (others => '0'), csr_vl_n => (others => '0'), csr_vstart_n => (others => '0'),
                    -- V-SLD Control --
                    sld_en => '0', sld_elem => (others => '0'), sld_up => '0', sld_last => '0',
                    -- VRF Control --
                    vrf_vs2 => (others => '0'), vrf_vs1 => (others => '0'), vrf_vd => (others => '0'), vrf_ben => (others => '0'), vrf_wr_sel => (others => '0'),
                    -- O-SEL Control --
                    osel_imm => (others => '0'), osel_sel_op2 => '0', osel_sel_op1 => '0', osel_sel_imm => '0', osel_scalar => (others => '0'),
                    -- V-ALU Control --
                    valu_op => (others => '0'), valu_valid => '0',
                    -- V-LSU Control --
                    vlsu_wen => '0', vlsu_addr => (others => '0'), vlsu_strd => (others => '0'), vlsu_mode => '0', vlsu_ordrd => '0', vlsu_vme => '0', vlsu_width => (others => '0'), vlsu_start => '0'
                );
                cp_result <= (others => '0');
                cp_valid  <= '0';
        end case;
    end process;

    --------------------------------
    --- ALU Operation Definition ---
    --------------------------------
    process(all) begin
        case funct3 is
            -- OPIVV, OPIVX or OPIVI --
            when "000" | "100" | "011" =>
                if     (funct6 = "000000")                        then valu_op <= valu_add;
                elsif  (funct6 = "000010") and (funct3 /= "011")  then valu_op <= valu_sub;
                elsif  (funct6 = "000011") and (funct3 /= "000")  then valu_op <= valu_rsub;
                elsif  (funct6 = "000100") and (funct3 /= "011")  then valu_op <= valu_minu;
                elsif  (funct6 = "000101") and (funct3 /= "011")  then valu_op <= valu_min;
                elsif  (funct6 = "000110") and (funct3 /= "011")  then valu_op <= valu_maxu;
                elsif  (funct6 = "000111") and (funct3 /= "011")  then valu_op <= valu_max;
                elsif  (funct6 = "001001")                        then valu_op <= valu_and;
                elsif  (funct6 = "001010")                        then valu_op <= valu_or;
                elsif  (funct6 = "001011")                        then valu_op <= valu_xor;
                elsif  (funct6 = "001110") and (funct3 /= "000")  then valu_op <= valu_sldup;
                elsif  (funct6 = "001111") and (funct3 /= "000")  then valu_op <= valu_slddn;
                elsif  (funct6 = "010000")                        then valu_op <= valu_adc;
                elsif  (funct6 = "010001")                        then valu_op <= valu_madc;
                elsif  (funct6 = "010010") and (funct3 /= "011")  then valu_op <= valu_sbc;
                elsif  (funct6 = "010011") and (funct3 /= "011")  then valu_op <= valu_msbc;
                elsif  (funct6 = "010111")                        then valu_op <= valu_merge;
                elsif  (funct6 = "011000")                        then valu_op <= valu_seq;
                elsif  (funct6 = "011001")                        then valu_op <= valu_sne;
                elsif  (funct6 = "011010") and (funct3 /= "011")  then valu_op <= valu_sltu;
                elsif  (funct6 = "011011") and (funct3 /= "011")  then valu_op <= valu_slt;
                elsif  (funct6 = "011100")                        then valu_op <= valu_sleu;
                elsif  (funct6 = "011101")                        then valu_op <= valu_sle;
                elsif  (funct6 = "011110") and (funct3 /= "000")  then valu_op <= valu_sgtu;
                elsif  (funct6 = "011111") and (funct3 /= "000")  then valu_op <= valu_sgt;
                elsif  (funct6 = "100101")                        then valu_op <= valu_sll;
                elsif  (funct6 = "101000")                        then valu_op <= valu_srl;
                elsif  (funct6 = "101001")                        then valu_op <= valu_sra;
                elsif  (funct6 = "101100")                        then valu_op <= valu_nsrl;
                elsif  (funct6 = "101101")                        then valu_op <= valu_nsra;
                -- INVALID FUNCT6 --
                else
                    valu_op <= valu_invalid;
                end if;

            -- OPMVV or OPMVX --
            when "010" | "110" =>
                if (funct6 = "010010") then
                    if (vs1 = "00100") then valu_op <= valu_zext_vf4;
                    elsif (vs1 = "00101") then valu_op <= valu_sext_vf4;
                    elsif (vs1 = "00110") then valu_op <= valu_zext_vf2;
                    elsif (vs1 = "00111") then valu_op <= valu_sext_vf2;
                    -- INVALID SOURCE_1 --
                    else
                        valu_op <= valu_invalid;
                    end if;
                elsif  (funct6 = "110000") then valu_op <= valu_waddu;
                elsif  (funct6 = "110001") then valu_op <= valu_wadd;
                elsif  (funct6 = "110010") then valu_op <= valu_wsubu;
                elsif  (funct6 = "110011") then valu_op <= valu_wsub;
                elsif  (funct6 = "110100") then valu_op <= valu_waddu_2sew;
                elsif  (funct6 = "110101") then valu_op <= valu_wadd_2sew;
                elsif  (funct6 = "110110") then valu_op <= valu_wsubu_2sew;
                elsif  (funct6 = "110111") then valu_op <= valu_wsub_2sew;
                -- INVALID FUNCT6 --
                else
                    valu_op <= valu_invalid;
                end if;

            -- OPFVV or OPFVF --
            when "001" | "101" => 
                valu_op <= valu_invalid;
            
            -- INVALID FUNCT3 --
            when others => 
                valu_op <= valu_invalid;
        end case;
    end process;

end neorv32_vcu_rtl;