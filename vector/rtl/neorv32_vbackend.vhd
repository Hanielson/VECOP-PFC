library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_backend is
    port(
        -- Clock and Reset --
        clk : in std_ulogic;
        rst : in std_ulogic;

        -- VI-Queue Ports --
        viq_inst  : in std_ulogic_vector(XLEN-1 downto 0);
        viq_scal2 : in std_ulogic_vector(XLEN-1 downto 0);
        viq_scal1 : in std_ulogic_vector(XLEN-1 downto 0);
        viq_valid : in std_ulogic;
        viq_nxt   : out std_ulogic;
        
        -- V-CSR --
        vcsr         : in vcsr_t;
        
        -- Back-End Control/Response Ports --
        vback_resp : in vback_resp_if;
        vback_ctrl : out vback_ctrl_if
    );
end neorv32_backend;

architecture neorv32_backend_rtl of neorv32_backend is
    -- V-DISPATCH Internal State Machine --
    type back_state_t is (WAIT_INST, IS_CONFIG, VCONFIG, DISPATCH, POP_VIQ);
    signal state : back_state_t;

    -- V-CSR Signals --
    signal vstart : std_ulogic_vector(XLEN-1 downto 0);
    signal vl     : std_ulogic_vector(XLEN-1 downto 0);
    signal vill   : std_ulogic;
    signal vma    : std_ulogic;
    signal vta    : std_ulogic;
    signal vsew   : std_ulogic_vector(2 downto 0);
    signal vlmul  : std_ulogic_vector(2 downto 0);

    -- Instruction Word and Fields --
    signal dest    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal funct3  : std_ulogic_vector(2 downto 0);
    signal vs1     : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vs2     : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vm      : std_ulogic;
    signal funct6  : std_ulogic_vector(5 downto 0);
begin

    --------------------------------------------------------
    -- Instruction / Scalar Forwarding to Execution Units --
    --------------------------------------------------------
    vback_ctrl.vinst <= viq_inst;
    vback_ctrl.scal2 <= viq_scal2;
    vback_ctrl.scal1 <= viq_scal1;

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

    --------------------------------------------------------
    --- Function Fields Extraction from Instruction Word ---
    --------------------------------------------------------
    process(all) begin
        dest   <= viq_inst(11 downto 7);
        funct3 <= viq_inst(14 downto 12);
        vs1    <= viq_inst(19 downto 15);
        vs2    <= viq_inst(24 downto 20);
        vm     <= viq_inst(25);
        funct6 <= viq_inst(31 downto 26);
    end process;
    
    -------------------------------------------
    --- State Machine Next-State Generation ---
    -------------------------------------------
    process(clk, rst) begin
        if (rst = '1') then
            state   <= WAIT_INST;
        elsif rising_edge(clk) then
            case state is
                -- Waiting for Valid Instruction --
                when WAIT_INST =>
                    if (viq_valid = '1') then
                        state <= IS_CONFIG;
                    end if;

                -- Identifies if instruction is for configuration or execution --
                when IS_CONFIG =>
                    if (viq_inst(6 downto 0) = vop_arith_cfg) and (funct3 = "111") then
                        state <= VCONFIG;
                    else
                        state <= DISPATCH;
                    end if;

                -- Handle configuration instructions... Back-End stays in VCONFIG state for only one cycle --
                when VCONFIG => state <= POP_VIQ;

                -- Dispatch instruction to appropriate unit and waits for a response --
                when DISPATCH =>
                    case viq_inst(6 downto 0) is
                        -- V-ALU Response Handling --
                        when vop_arith_cfg => 
                            if (vback_resp.valu_seqend = '1') then
                                state <= POP_VIQ;
                            end if;
                        -- V-LSU Response Handling --
                        when vop_load | vop_store => 
                            if (vback_resp.vlsu_seqend = '1') then
                                state <= POP_VIQ;
                            end if;
                        when others => null;
                    end case;

                -- Pops the V-IQ to get the next instruction --
                when POP_VIQ => state <= WAIT_INST;

                when others => null;
            end case;
        end if;
    end process;

    ----------------------------------------
    --- State Machine Combinational Logic --
    ----------------------------------------
    process(all) 
        -- Auxiliary Variables --
        variable vtype_i    : std_ulogic_vector(XLEN-1 downto 0);
        variable vtype_n    : std_ulogic_vector(XLEN-1 downto 0);
        variable avl        : std_ulogic_vector(XLEN-1 downto 0);
        variable vl_n       : std_ulogic_vector(XLEN-1 downto 0);
        variable vlmax      : unsigned(XLEN-1 downto 0);
    begin
        -- Default Values for Control Signals --
        viq_nxt                 <= '0';
        vback_ctrl.csr_wen      <= (others => '0');
        vback_ctrl.csr_vtype_n  <= (others => '0');
        vback_ctrl.csr_vl_n     <= (others => '0');
        vback_ctrl.csr_vstart_n <= (others => '0');
        vback_ctrl.vrf_sel      <= (others => '0');
        vback_ctrl.osel_imm     <= (others => '0');
        vback_ctrl.osel_sel_op2 <= '0';
        vback_ctrl.osel_sel_op1 <= '0';
        vback_ctrl.osel_sel_imm <= '0';
        vback_ctrl.osel_scalar  <= (others => '0');
        vback_ctrl.valu_start   <= '0';
        vback_ctrl.vsld_start   <= '0';
        vback_ctrl.vlsu_start   <= '0';

        -- State-Specific Control Signal Generation --
        case state is
            when WAIT_INST => viq_nxt <= not viq_valid;

            when IS_CONFIG => null;

            when VCONFIG =>
                -- Proposed VTYPE and AVL Values Extraction --
                case viq_inst(31 downto 30) is
                    -- VTYPE = SCALAR_2 ; AVL = SCALAR_1 --
                    when "10" =>
                        vtype_i := viq_scal2;
                        if    (vs1 /= "00000") then avl := viq_scal1;
                        elsif (dest = "00000") then avl := (others => '1');
                        else                        avl := vl;     
                        end if;

                    -- VTYPE = IMMEDIATE ; AVL = IMMEDIATE --
                    when "11" =>
                        vtype_i := std_ulogic_vector(resize(unsigned(viq_inst(29 downto 20)), vtype_i'length));
                        avl     := std_ulogic_vector(resize(unsigned(viq_inst(19 downto 15)), avl'length));

                    -- VTYPE = IMMEDIATE ; AVL = SCALAR_1 --
                    when others =>
                        vtype_i := std_ulogic_vector(resize(unsigned(viq_inst(30 downto 20)), vtype_i'length));
                        if    (vs1 /= "00000") then avl := viq_scal1;
                        elsif (dest = "00000") then avl := (others => '1');
                        else                        avl := vl;     
                        end if;
                end case;

                -- Check for any invalid field in proposed vtype value --
                if  (vtype_i(2 downto 0) = "100") or (vtype_i(5) = '1') or (vtype_i(5 downto 3) = "011") or
                    (vtype_i(XLEN-2 downto 8) /= std_ulogic_vector(to_unsigned(0, XLEN-9))) or (vtype_i(XLEN-1) = '1') then
                    vtype_n := (XLEN-1 => '1', others => '0');
                    vl_n    := (others => '0');
                -- If it's all good... --
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

                -- Control Signals --
                vback_ctrl.csr_wen     <= "110";
                vback_ctrl.csr_vtype_n <= vtype_n;
                vback_ctrl.csr_vl_n    <= vl_n;

            when DISPATCH =>
                -- Decode the instruction and determine the target unit --
                case viq_inst(6 downto 0) is
                    -- V-ALU Instructions --
                    when vop_arith_cfg => 
                        vback_ctrl.vrf_sel      <= "00";
                        vback_ctrl.osel_imm     <= vs1;
                        vback_ctrl.osel_sel_op2 <= '0';
                        case funct3 is
                            when "011"                 => vback_ctrl.osel_sel_op1 <= '1'; vback_ctrl.osel_sel_imm <= '0'; -- Immediate      --
                            when "100" | "101" | "110" => vback_ctrl.osel_sel_op1 <= '1'; vback_ctrl.osel_sel_imm <= '1'; -- Scalar         --
                            when others                => vback_ctrl.osel_sel_op1 <= '0'; vback_ctrl.osel_sel_imm <= '0'; -- Vector Operand --
                        end case;
                        vback_ctrl.osel_scalar <= viq_scal1;
                        vback_ctrl.valu_start  <= '1';
                    
                    -- Load/Store Instructions --
                    when vop_load | vop_store => 
                        vback_ctrl.vrf_sel    <= "10";
                        vback_ctrl.vlsu_start <= '1';
                    
                    -- Unsupported Instruction --
                    when others => null;
                end case;

            when POP_VIQ => viq_nxt <= '1';

            when others => null;
        end case;
    end process;

end neorv32_backend_rtl;