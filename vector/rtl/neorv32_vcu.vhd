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
        sld_valid   : in std_ulogic;

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

    type ctrl_state_t is (IDLE, DECODE, CSR_WR, ALU_DISPATCH, ALU_EXEC, INVALID);
    signal state : ctrl_state_t;

    signal vinst_i : std_ulogic_vector(XLEN-1 downto 0);
    signal vlmul_i : std_ulogic_vector(2 downto 0);

    signal dest   : std_ulogic_vector(4 downto 0);
    signal src1   : std_ulogic_vector(4 downto 0);
    signal src2   : std_ulogic_vector(4 downto 0);

    signal funct3 : std_ulogic_vector(5 downto 0);
    signal vm     : std_ulogic;
    signal funct6 : std_ulogic_vector(2 downto 0);

    signal valu_op : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);

    signal cyc_count : std_ulogic_vector(2 downto 0);
    signal mul_count : std_ulogic_vector(2 downto 0);

begin

    ----------------------
    --- VLMUL Decoding ---
    ----------------------
    process(all) begin
        case vlmul is
            when "001"  => vlmul_i <= "001";
            when "010"  => vlmul_i <= "011";
            when "011"  => vlmul_i <= "111";
            when others => vlmul_i <= "000";
        end case;
    end process;

    ---------------------------------------------------------------
    --- Function Fields / Vector Mask from Instruction Encoding ---
    ---------------------------------------------------------------
    process(all) begin
        funct3 <= vinst_i(14 downto 12);
        vm     <= vinst_i(25);
        funct6 <= vinst_i(31 downto 26);
    end process;

    --------------------------------------------------------------------
    --- Next-State Generation / Instruction Load / Internal Counters ---
    --------------------------------------------------------------------
    process(clk, rst)
        variable opcode  : std_ulogic_vector(6 downto 0);
        variable max_cyc : std_ulogic_vector(2 downto 0);
    begin
        if (rst = '1') then
            cyc_count <= (others => '0');
            mul_count <= (others => '0');
            vinst_i   <= (others => '0');
            state     <= IDLE;
        elsif rising_edge(clk) then
            case state is
                -- Waiting for Valid Instruction --
                when IDLE =>
                    cyc_count <= (others => '0');
                    mul_count <= (others => '0');
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
                    -- Instruction Operands/Destination --
                    dest   <= vinst_i(11 downto 7);
                    src1   <= vinst_i(19 downto 15);
                    src2   <= vinst_i(24 downto 20);
                    
                    -- Operation State --
                    opcode := vinst_i(6 downto 0);
                    if    (opcode = vop_load)   then state <= (others => '0');
                    elsif (opcode = vop_store)  then state <= (others => '0');
                    elsif (opcode = vop_arith)  then state <= ALU_DISPATCH;
                    elsif (opcode = vop_config) then state <= CSR_WR;
                    else                             state <= INVALID;
                    end if;
                
                -- CSR Write State --
                when CSR_WR =>
                    state <= IDLE;

                -- ALU Dispatch State--
                when ALU_DISPATCH =>
                    if (valu_op = valu_invalid) then state <= INVALID;
                    else                             state <= ALU_EXEC;
                    end if;

                -- ALU Execution State --
                when ALU_EXEC =>
                    case valu_op is
                        when valu_waddu      | valu_wsubu      | valu_wadd      | valu_wsub      | 
                             valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew | 
                             valu_zext_vf2   | valu_sext_vf2 => max_cyc := "001"
                        when valu_zext_vf4 | valu_sext_vf4   => max_cyc := "011"
                        when others                          => max_cyc := "000"
                    end case;

                    if (cyc_count = max_cyc) then
                        cyc_count <= (others => '0');
                        if (mul_count = vlmul_i) then 
                            state <= IDLE;
                        else
                            src2      <= std_ulogic_vector(unsigned(src2) + 1);
                            dest      <= std_ulogic_vector(unsigned(dest) + 1);
                            mul_count <= std_ulogic_vector(unsigned(mul_count) + 1);
                            state     <= ALU_EXEC;
                        end if;
                    else
                        if (valu_op = valu_waddu_2sew) or (valu_op = valu_wsubu_2sew) or (valu_op = valu_wadd_2sew) or (valu_op = valu_wsub_2sew) then
                            src2 <= std_ulogic_vector(unsigned(src2) + 1);
                        end if;
                        dest      <= std_ulogic_vector(unsigned(dest) + 1);
                        cyc_count <= std_ulogic_vector(unsigned(cyc_count) + 1);
                        state     <= ALU_EXEC;
                    end if;
                    
                -- INVALID STATE --
                when others =>
                    state <= INVALID;
            end case;
        end if;
    end process;

    ------------------------------
    --- Output Generation Logic --
    ------------------------------
    process(all)
        variable vs2     : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable vs1     : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable vd      : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable byte_en : std_ulogic_vector((VLEN/8)-1 downto 0);
        variable wr_sel  : std_ulogic_vector(1 downto 0);
        variable imm     : std_ulogic_vector(4 downto 0);
        variable sel_op2 : std_ulogic;
        variable sel_op1 : std_ulogic;
        variable sel_imm : std_ulogic;
        variable scalar  : std_ulogic_vector(XLEN-1 downto 0);
    begin
        case state is
            -- Waiting for Valid Instruction --
            when IDLE =>
                vctrl <= (
                    viq_nxt => '1',
                    others  => '0'
                );
                cp_result <= (others => '0');
                cp_valid  <= '0';
            
            -- CSR Write State --
            -- when CSR_WR =>

            -- ALU Dispatch State --
            when ALU_DISPATCH =>
                vctrl <= (
                    valu_op      => valu_op,
                    valu_valid   => '1',
                    others       => '0'
                );
                cp_result <= (others => '0');
                cp_valid  <= '0';

            -- ALU Execution State --
            when ALU_EXEC =>
                -- Operation Independent Signals --
                vs2     := src2;
                vs1     := src1;
                vd      := dest;
                imm     := src1;
                sel_op2 := '0';
                scalar  := scal1;
                wr_sel  := "00";
                
                -- Operation/Cycle Dependent Signals --
                -- TODO: ADD BYTE ENABLE GENERATION LOGIC --
                byte_en := x"FFFFFFFF";
                case funct3 is
                    -- Immediate --
                    when "011" =>
                        sel_op1 := '1';
                        sel_imm := '0';
                    
                    -- Scalar --
                    when "100" | "101" | "110" =>
                        sel_op1 := '1';
                        sel_imm := '1';

                    -- Vector Operand --
                    when others =>
                        sel_op1 := '0';
                        sel_imm := '0';
                end case;

                vctrl <= (
                    vrf_vs2      => vs2,
                    vrf_vs1      => vs1,
                    vrf_vd       => vd,
                    vrf_ben      => byte_en,
                    vrf_wr_sel   => wr_sel,
                    osel_imm     => imm,
                    osel_sel_op2 => sel_op2,
                    osel_sel_op1 => sel_op1,
                    osel_sel_imm => sel_imm,
                    osel_scalar  => scalar,
                    valu_op      => valu_op,
                    valu_valid   => '1',
                    others       => '0'
                );

            -- INVALID STATE --
            when others =>
                vctrl     <= (others => '0');
                cp_result <= (others => '0');
                cp_valid  <= '0';
        end case;
    end;

    --------------------------------
    --- ALU Operation Definition ---
    --------------------------------
    process(all) begin
        case funct3 is
            -- OPIVV, OPIVX or OPIVI --
            when "000" | "100" | "011" =>
                if     (funct6 = "000000")                        then valu_op <= valu_add;
                elsif ((funct6 = "000010") and (funct3 /= "011")) then valu_op <= valu_sub;
                elsif ((funct6 = "000011") and (funct3 /= "000")) then valu_op <= valu_rsub;
                elsif ((funct6 = "000100") and (funct3 /= "011")) then valu_op <= valu_minu;
                elsif ((funct6 = "000101") and (funct3 /= "011")) then valu_op <= valu_min;
                elsif ((funct6 = "000110") and (funct3 /= "011")) then valu_op <= valu_maxu;
                elsif ((funct6 = "000111") and (funct3 /= "011")) then valu_op <= valu_max;
                elsif  (funct6 = "001001")                        then valu_op <= valu_and;
                elsif  (funct6 = "001010")                        then valu_op <= valu_or;
                elsif  (funct6 = "001011")                        then valu_op <= valu_xor;
                elsif  (funct6 = "010000")                        then valu_op <= valu_adc;
                elsif  (funct6 = "010001")                        then valu_op <= valu_madc;
                elsif ((funct6 = "010010") and (funct3 /= "011")) then valu_op <= valu_sbc;
                elsif ((funct6 = "010011") and (funct3 /= "011")) then valu_op <= valu_msbc;
                elsif  (funct6 = "010111")                        then valu_op <= valu_merge;
                elsif  (funct6 = "011000")                        then valu_op <= valu_seq;
                elsif  (funct6 = "011001")                        then valu_op <= valu_sne;
                elsif ((funct6 = "011010") and (funct3 /= "011")) then valu_op <= valu_sltu;
                elsif ((funct6 = "011011") and (funct3 /= "011")) then valu_op <= valu_slt;
                elsif  (funct6 = "011100")                        then valu_op <= valu_sleu;
                elsif  (funct6 = "011101")                        then valu_op <= valu_sle;
                elsif ((funct6 = "011110") and (funct3 /= "000")) then valu_op <= valu_sgtu;
                elsif ((funct6 = "011111") and (funct3 /= "000")) then valu_op <= valu_sgt;
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
                    if (src1 = "00100") then valu_op <= valu_zext_vf4;
                    elsif (src1 = "00101") then valu_op <= valu_sext_vf4;
                    elsif (src1 = "00110") then valu_op <= valu_zext_vf2;
                    elsif (src1 = "00111") then valu_op <= valu_sext_vf2;
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
    end;

end neorv32_vcu_rtl;