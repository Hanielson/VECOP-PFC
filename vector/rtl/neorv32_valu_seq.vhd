library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_valu_seq is
    port(
        -- Clock and Reset --
        clk : in std_ulogic;
        rst : in std_ulogic;

        -- Back-End Input Signals --
        vinst : in std_ulogic_vector(XLEN-1 downto 0);
        scal2 : in std_ulogic_vector(XLEN-1 downto 0);
        scal1 : in std_ulogic_vector(XLEN-1 downto 0);
        start : in std_ulogic;

        -- Vector Mask --
        vmask : in std_ulogic_vector(VLEN-1 downto 0);

        -- Control/Status Registers --
        vcsr : in vcsr_t;

        -- Sub-Modules Signals --
        int_done  : in std_ulogic;
        mask_done : in std_ulogic;
        
        -- Sequencer Control Bus --
        valu_seq : out valu_seq_if_t;

        -- V-Dispatcher Output Signals --
        seqend : out std_ulogic;
        result : out std_ulogic_vector(XLEN-1 downto 0)
    );
end neorv32_valu_seq;

architecture neorv32_valu_seq_rtl of neorv32_valu_seq is
    -- VALU-SEQ Internal State Machine --
    type ctrl_state_t is (IDLE, DECODE, INVALID, WAIT_READ, DISPATCH_INT, DISPATCH_MASK, WRITE_BACK, UPDATE_CYC, UPDATE_MUL, CLEAR_INT, CLEAR_MASK, SEQ_DONE);
    signal state : ctrl_state_t;

    -- Internal Cycle/Mul Counters --
    signal cyc_count : std_ulogic_vector(2 downto 0);
    signal mul_count : std_ulogic_vector(2 downto 0);

    -- V-CSR Signals --
    signal vstart : std_ulogic_vector(XLEN-1 downto 0);
    signal vl     : std_ulogic_vector(XLEN-1 downto 0);
    signal vill   : std_ulogic;
    signal vma    : std_ulogic;
    signal vta    : std_ulogic;
    signal vsew   : std_ulogic_vector(2 downto 0);
    signal vlmul  : std_ulogic_vector(2 downto 0);

    -- Instruction Word and Fields --
    signal funct3 : std_ulogic_vector(2 downto 0);
    signal vs1    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vs2    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vm     : std_ulogic;
    signal funct6 : std_ulogic_vector(5 downto 0);

    -- Operand/Destination Value Registers --
    signal dest : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal src1 : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal src2 : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

    -- LMUL Internal Decoded Value --
    signal vlmul_i : std_ulogic_vector(2 downto 0);

    -- Result EEW and EMUL Values --
    signal eew  : std_ulogic_vector(2 downto 0);
    signal emul : std_ulogic_vector(2 downto 0);

    -- VRF ByteEnable Selection MUX --
    signal ben_mux : std_ulogic_vector((VLEN/8)-1 downto 0);

    -- V-ALU Operation Type and Class --
    signal valu_op_i      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
    signal valu_opclass_i : valu_opclass_t;
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

    --------------------------------------------------------
    --- Function Fields Extraction from Instruction Word ---
    --------------------------------------------------------
    process(all) begin
        funct3 <= vinst(14 downto 12);
        vs1    <= vinst(19 downto 15);
        vs2    <= vinst(24 downto 20);
        vm     <= vinst(25);
        funct6 <= vinst(31 downto 26);
    end process;

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

    -------------------------------
    --- Result's EEW Definition ---
    -------------------------------
    process(all) 
        variable sew_off : natural := 0;
    begin
        case valu_op_i is
            -- EEW = 2*SEW => EMUL = (LMUL >> 1) --
            when valu_waddu | valu_wsubu | valu_wadd | valu_wsub | valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew =>
                sew_off := 1;
                emul <= vlmul_i(vlmul_i'left-1 downto 0) & "1";
            -- EEW = SEW => EMUL = (LMUL >> 1) --
            when valu_zext_vf2 | valu_sext_vf2  =>
                sew_off := 0;
                emul <= vlmul_i(vlmul_i'left-1 downto 0) & "1";
            -- EEW = SEW => EMUL = (LMUL >> 2) --
            when valu_zext_vf4 | valu_sext_vf4 =>
                sew_off := 0;
                emul <= vlmul_i(vlmul_i'left-2 downto 0) & "11";
            -- EEW = SEW => EMUL = LMUL --
            when others =>
                sew_off := 0;
                emul <= vlmul_i;
        end case;

        -- Calculate EEW --
        eew <= std_ulogic_vector(unsigned(vsew) + to_unsigned(sew_off, vsew'length));
    end process;

    --------------------------------------------------------------------
    --- Next-State Generation / Instruction Load / Internal Counters ---
    --------------------------------------------------------------------
    process(clk, rst)
        -- Check Related Variables --
        variable is_invalid  : boolean;
        
        -- Maximum Cycle Variable --
        variable max_cycle   : std_ulogic_vector(2 downto 0);
    begin
        if (rst = '1') then
            state     <= IDLE;
            cyc_count <= (others => '0');
            mul_count <= (others => '0');
            dest      <= (others => '0');
            src1      <= (others => '0');
            src2      <= (others => '0');
        elsif rising_edge(clk) then
            case state is
                -- IDLE Control State --
                when IDLE =>
                    -- Resets the Cycle/Mul counters --
                    cyc_count <= (others => '0');
                    mul_count <= (others => '0');
                    -- If received a start indication, go to DECODE --
                    if (start = '1') then
                        state <= DECODE;
                    end if;

                -- DECODE Instruction Control State --
                when DECODE =>
                    -- Instruction Operands/Destination --
                    -- NOTE: we store src2/src1 in registers to operate on them during multi-cycle operations, --
                    --       however the original values are preserved in vs2/vs1 signals for ALU op decoding  --
                    
                    -- DESTINATION/SRC1/SRC2 Fields Extraction + Calculated Offset --
                    dest <= std_ulogic_vector(resize(unsigned(vinst(11 downto 7)),  dest'length));
                    src1 <= std_ulogic_vector(resize(unsigned(vinst(19 downto 15)), src1'length));
                    src2 <= std_ulogic_vector(resize(unsigned(vinst(24 downto 20)), src2'length));
                    
                    -- Checks: 1) If operation is invalid --
                    is_invalid := (valu_op_i = valu_invalid);
                    
                    -- OPCODE decode and next state definition --
                    if (is_invalid) then
                        state <= INVALID;
                    else
                        state <= WAIT_READ;
                    end if;

                -- WAIT VRF READ Control State --
                -- Extra cycle needed to read from the VRF (FPGA BRAMs are Read-Synchronous)
                when WAIT_READ =>
                    case valu_opclass_i is
                        when VALU_INTOP => state <= DISPATCH_INT;
                        when VALU_MOP   => state <= DISPATCH_MASK;
                        when others     => state <= INVALID;
                    end case;

                -- DISPATCH INTEGER SubModule Control State --
                when DISPATCH_INT =>
                    if (int_done = '1') then
                        state <= WRITE_BACK;
                    end if;

                -- DISPATCH MASK SubModule Control State --
                when DISPATCH_MASK =>
                    if (mask_done = '1') then
                        state <= WRITE_BACK;
                    end if;

                -- WRITE BACK to VRF Control State --
                when WRITE_BACK =>
                    -- Calculates how many Operation Cycles (not CLK cycles...) are needed for the operation --
                    case valu_op_i is
                        when valu_waddu     | valu_wsubu     | valu_wadd     | valu_wsub     | valu_waddu_2sew | valu_wsubu_2sew | 
                             valu_wadd_2sew | valu_wsub_2sew | valu_zext_vf2 | valu_sext_vf2 | valu_nsrl       | valu_nsra => 
                            max_cycle := "001";
                        when valu_zext_vf4 | valu_sext_vf4 => 
                            max_cycle := "011";
                        when others => 
                            max_cycle := "000";
                    end case;

                    -- If instruction needs more cycles to execute --
                    if (cyc_count /= max_cycle) then
                        state <= UPDATE_CYC;
                    -- If another loop of execution is needed due to LMUL --
                    elsif (mul_count /= emul) then
                        state <= UPDATE_MUL;
                    -- If all is done, then cleanup the current status of SubModules... --
                    else
                        case valu_opclass_i is
                            when VALU_INTOP => state <= CLEAR_INT;
                            when VALU_MOP   => state <= CLEAR_MASK;
                            when others     => state <= INVALID;
                        end case;
                    end if;

                -- UPDATE CYCLE COUNTER Control State --
                when UPDATE_CYC =>
                    state <= WAIT_READ;
                    -- Update Counters --
                    cyc_count <= std_ulogic_vector(unsigned(cyc_count) + 1);
                    mul_count <= std_ulogic_vector(unsigned(mul_count) + 1);
                    -- Update Operands/Destination Pointers
                    case valu_op_i is
                        -- Multi-Width Widening Operations --
                        when valu_waddu_2sew | valu_wsubu_2sew | valu_wadd_2sew | valu_wsub_2sew =>
                            dest <= std_ulogic_vector(unsigned(dest) + 1);
                            src2 <= std_ulogic_vector(unsigned(src2) + 1);
                        
                        -- Narrowing Operation --
                        when valu_nsrl | valu_nsra =>
                            src2 <= std_ulogic_vector(unsigned(src2) + 1);
                        
                        -- Other Multi-Cycle Operations --
                        when others =>
                            dest <= std_ulogic_vector(unsigned(dest) + 1);
                        end case;

                -- UPDATE MUL COUNTER Control State --
                when UPDATE_MUL =>
                    state <= WAIT_READ;
                    -- Update Counters --
                    cyc_count <= (others => '0');
                    mul_count <= std_ulogic_vector(unsigned(mul_count) + 1);
                    -- Update Operands/Destination Pointers --
                    dest <= std_ulogic_vector(unsigned(dest) + 1);
                    if (valu_opclass_i = VALU_INTOP) then
                        src1 <= std_ulogic_vector(unsigned(src1) + 1);
                        src2 <= std_ulogic_vector(unsigned(src2) + 1);
                    end if;

                -- CLEAR INTEGER SubModule Control State --
                when CLEAR_INT => state <= SEQ_DONE;

                -- CLEAR MASK SubModule Control State --
                when CLEAR_MASK => state <= SEQ_DONE;

                -- Sequence Done Control State --
                when SEQ_DONE => state <= IDLE;

                -- INVALID Control State --
                when INVALID =>
                    -- TODO: set vill --
                    state <= IDLE;

                when others => null;
            end case;
        end if;
    end process;

    ------------------------------------
    --- Byte Enable Generation Logic ---
    ------------------------------------
    process(all)
        -- Multiplexer to select between v0 value and ALL_ONES --
        variable vmask_i : std_ulogic_vector(VLEN-1 downto 0);

        -- Multiplexer Selection Signals --
        variable ben_sel_sew8  : std_ulogic_vector(2 downto 0);
        variable ben_sel_sew16 : std_ulogic;
        variable ben_sel_sew32 : std_ulogic_vector(1 downto 0);

        -- Internal Multiplexers --
        variable ben_mux_sew8  : std_ulogic_vector((VLEN/8)-1 downto 0);
        variable ben_mux_sew16 : std_ulogic_vector((VLEN/8)-1 downto 0);
        variable ben_mux_sew32 : std_ulogic_vector((VLEN/8)-1 downto 0);
    begin

        -- If instruction is masked, use v0 value, otherwise use ALL_ONES
        vmask_i := vmask when (vm = '1') else (others => '1');

        -- SEW=8 MUX selects which (VLEN/8) word to generate the mask from --
        case eew is
            -- SEW = 8-bits--
            when "000" => ben_sel_sew8 := mul_count;
            -- SEW = 16-bits --
            when "001" => ben_sel_sew8 := mul_count(mul_count'left downto 1) & "0";
            -- SEW = 32-bits --
            when "010" => ben_sel_sew8 := mul_count(mul_count'left downto 2) & "00";
            -- INVALID SEW --
            when others => ben_sel_sew8 := (others => '0');
        end case;
        ben_mux_sew8 := vmask_i(((to_integer(unsigned(ben_sel_sew8)) + 1) * (VLEN/8))-1 downto (to_integer(unsigned(ben_sel_sew8)) * (VLEN/8)));

        -- SEW=16 MUX splits SEW=8 MUX in half --
        ben_sel_sew16 := mul_count(0);
        for ii in 0 to (ben_mux_sew8'length/2)-1 loop
            case ben_sel_sew16 is
                when '0'    => ben_mux_sew16((2*ii)+1 downto 2*ii) := std_ulogic_vector(resize(signed'(0 => ben_mux_sew8(ii))                          , 2));
                when '1'    => ben_mux_sew16((2*ii)+1 downto 2*ii) := std_ulogic_vector(resize(signed'(0 => ben_mux_sew8(ii + (ben_mux_sew8'length/2))), 2));
                when others => ben_mux_sew16((2*ii)+1 downto 2*ii) := (others => '0');
            end case;
        end loop;

        -- SEW=32 MUX splits SEW=8 MUX in a quarter --
        ben_sel_sew32 := mul_count(1 downto 0);
        for ii in 0 to (ben_mux_sew8'length/4)-1 loop
            case ben_sel_sew32 is
                when "00"   => ben_mux_sew32((4*ii)+3 downto 4*ii) := std_ulogic_vector(resize(signed'(0 => ben_mux_sew8(ii))                              , 4));
                when "01"   => ben_mux_sew32((4*ii)+3 downto 4*ii) := std_ulogic_vector(resize(signed'(0 => ben_mux_sew8(ii + (ben_mux_sew8'length/4)))    , 4));
                when "10"   => ben_mux_sew32((4*ii)+3 downto 4*ii) := std_ulogic_vector(resize(signed'(0 => ben_mux_sew8(ii + (2*(ben_mux_sew8'length/4)))), 4));
                when "11"   => ben_mux_sew32((4*ii)+3 downto 4*ii) := std_ulogic_vector(resize(signed'(0 => ben_mux_sew8(ii + (3*(ben_mux_sew8'length/4)))), 4));
                when others => ben_mux_sew32((4*ii)+3 downto 4*ii) := (others => '0');
            end case;
        end loop;

        -- Select Mask Value based on EEW --
        case eew is
            when "000"  => ben_mux <= ben_mux_sew8;
            when "001"  => ben_mux <= ben_mux_sew16;
            when "010"  => ben_mux <= ben_mux_sew32;
            when others => ben_mux <= (others => '0');
        end case;

    end process;

    ------------------------------
    --- Output Generation Logic --
    ------------------------------
    process(all)
        -- Auxiliary Variables --
        variable ben_i      : std_ulogic_vector((VLEN/8)-1 downto 0);
        variable mask_i     : std_ulogic_vector((VLEN/8)-1 downto 0);

        -- Control Output Variables --
        variable vrf_vs2      : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable vrf_vs1      : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable vrf_vd       : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable valu_op      : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
        variable valu_opclass : valu_opclass_t;
        variable vint_valid   : std_ulogic;
        variable vint_clear   : std_ulogic;
        variable vmask_valid  : std_ulogic;
        variable vmask_clear  : std_ulogic;
        variable masking_en   : std_ulogic;
    begin
        
        -- Auxiliary Variables --
        ben_i  := (others => '0');
        mask_i := (others => '0');

        -- VRF Control --
        vrf_vs2 := src2; 
        vrf_vs1 := src1; 
        vrf_vd  := dest; 

        -- V-ALU Control --
        valu_op      := valu_op_i;
        valu_opclass := valu_opclass_i;
        vint_valid   := '0';
        vint_clear   := '0';
        vmask_valid  := '0';
        vmask_clear  := '0';

        -- Operand Masking Enable --
        masking_en := vm;

        -- V-Dispatcher Response --
        seqend <= '0';
        result <= (others => '0');

        case state is
            -- IDLE Control State => Waiting for Valid Instruction --
            when IDLE => null;

            -- WAIT VRF READ Control State => Waiting for VRF read values --
            when WAIT_READ => null;

            -- DISPATCH INTEGER SubModule Control State --
            when DISPATCH_INT => vint_valid := '1';

            -- DISPATCH MASK SubModule Control State --
            when DISPATCH_MASK => vmask_valid := '1';

            -- WRITE BACK to VRF Control State --
            when WRITE_BACK =>
                -- Byte Enable Calculation Logic --
                case valu_op_i is
                    -- Narrowing Operations --
                    when valu_nsrl | valu_nsra =>
                        if (cyc_count(0) = '1') then
                            ben_i := (ben_i'length-1 downto (ben_i'length/2) => '1', others => '0');
                        else
                            ben_i := ((ben_i'length/2)-1 downto 0 => '1', others => '0');
                        end if;

                    -- Other Operation Types --
                    when others => ben_i := (others => '1');
                end case;

                -- Auxiliary Variables for Byte Enable definition --
                mask_i := ben_mux;

            -- CLEAR INTEGER SubModule Control State --
            when CLEAR_INT => vint_clear := '1';

            -- CLEAR MASK SubModule Control State --
            when CLEAR_MASK => vmask_clear := '1';

            -- SEQ_DONE Control State --
            when SEQ_DONE => seqend <= '1';
            
            when others => null;
        end case;

        valu_seq <= (
            cyc_count => cyc_count, mul_count => mul_count,
            vrf_vs2 => vrf_vs2, vrf_vs1 => vrf_vs1, vrf_vd => vrf_vd, vrf_ben => (ben_i and mask_i),
            valu_op => valu_op, valu_opclass => valu_opclass, vint_valid => vint_valid, vint_clear => vint_clear, vmask_valid => vmask_valid, vmask_clear => vmask_clear,
            masking_en => masking_en
        );
    end process;

    --------------------------------
    --- ALU Operation Definition ---
    --------------------------------
    process(all) begin
        case funct3 is
            -- OPIVV, OPIVX or OPIVI --
            when "000" | "100" | "011" =>
                if    (funct6 = "000000")                       then valu_op_i <= valu_add  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "000010") and (funct3 /= "011") then valu_op_i <= valu_sub  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "000011") and (funct3 /= "000") then valu_op_i <= valu_rsub ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "000100") and (funct3 /= "011") then valu_op_i <= valu_minu ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "000101") and (funct3 /= "011") then valu_op_i <= valu_min  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "000110") and (funct3 /= "011") then valu_op_i <= valu_maxu ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "000111") and (funct3 /= "011") then valu_op_i <= valu_max  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "001001")                       then valu_op_i <= valu_and  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "001010")                       then valu_op_i <= valu_or   ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "001011")                       then valu_op_i <= valu_xor  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "010000")                       then valu_op_i <= valu_adc  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "010001")                       then valu_op_i <= valu_madc ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "010010") and (funct3 /= "011") then valu_op_i <= valu_sbc  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "010011") and (funct3 /= "011") then valu_op_i <= valu_msbc ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "010111")                       then valu_op_i <= valu_merge; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "011000")                       then valu_op_i <= valu_se   ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "011001")                       then valu_op_i <= valu_sne  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "011010") and (funct3 /= "011") then valu_op_i <= valu_sltu ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "011011") and (funct3 /= "011") then valu_op_i <= valu_slt  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "011100")                       then valu_op_i <= valu_sleu ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "011101")                       then valu_op_i <= valu_sle  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "011110") and (funct3 /= "000") then valu_op_i <= valu_sgtu ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "011111") and (funct3 /= "000") then valu_op_i <= valu_sgt  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "100101")                       then valu_op_i <= valu_sll  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "101000")                       then valu_op_i <= valu_srl  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "101001")                       then valu_op_i <= valu_sra  ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "101100")                       then valu_op_i <= valu_nsrl ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "101101")                       then valu_op_i <= valu_nsra ; valu_opclass_i <= VALU_INTOP;
                -- INVALID FUNCT6 --
                else
                    valu_op_i <= valu_invalid; valu_opclass_i <= VALU_INVALOP;
                end if;

            -- OPMVV or OPMVX --
            when "010" | "110" =>
                -- VWXUNARY0 --
                if (funct6 = "010000") and (funct3 = "010") then
                    if    (vs1 = "00000") then valu_op_i <= valu_mvxs ; valu_opclass_i <= VALU_MOP;
                    elsif (vs1 = "10000") then valu_op_i <= valu_cpop ; valu_opclass_i <= VALU_MOP;
                    elsif (vs1 = "10001") then valu_op_i <= valu_first; valu_opclass_i <= VALU_MOP;
                    -- INVALID SOURCE_1 --
                    else
                        valu_op_i <= valu_invalid; valu_opclass_i <= VALU_INVALOP;
                    end if;
                -- VXUNARY0 --
                elsif (funct6 = "010010") and (funct3 = "010") then
                    if    (vs1 = "00100") then valu_op_i <= valu_zext_vf4; valu_opclass_i <= VALU_INTOP;
                    elsif (vs1 = "00101") then valu_op_i <= valu_sext_vf4; valu_opclass_i <= VALU_INTOP;
                    elsif (vs1 = "00110") then valu_op_i <= valu_zext_vf2; valu_opclass_i <= VALU_INTOP;
                    elsif (vs1 = "00111") then valu_op_i <= valu_sext_vf2; valu_opclass_i <= VALU_INTOP;
                    -- INVALID SOURCE_1 --
                    else
                        valu_op_i <= valu_invalid; valu_opclass_i <= VALU_INVALOP;
                    end if;
                -- VMUNARY0 --
                elsif (funct6 = "010100") and (funct3 = "010") then
                    if    (vs1 = "00001") then valu_op_i <= valu_msbf; valu_opclass_i <= VALU_MOP;
                    elsif (vs1 = "00010") then valu_op_i <= valu_msof; valu_opclass_i <= VALU_MOP;
                    elsif (vs1 = "00011") then valu_op_i <= valu_msif; valu_opclass_i <= VALU_MOP;
                    elsif (vs1 = "10000") then valu_op_i <= valu_iota; valu_opclass_i <= VALU_MOP;
                    elsif (vs1 = "10001") then valu_op_i <= valu_id  ; valu_opclass_i <= VALU_MOP;
                    -- INVALID SOURCE_1 --
                    else
                        valu_op_i <= valu_invalid; valu_opclass_i <= VALU_INVALOP;
                    end if;
                elsif (funct6 = "011000") and (funct3 = "010") then valu_op_i <= valu_mandn     ; valu_opclass_i <= VALU_MOP;
                elsif (funct6 = "011001") and (funct3 = "010") then valu_op_i <= valu_mand      ; valu_opclass_i <= VALU_MOP;
                elsif (funct6 = "011010") and (funct3 = "010") then valu_op_i <= valu_mor       ; valu_opclass_i <= VALU_MOP;
                elsif (funct6 = "011011") and (funct3 = "010") then valu_op_i <= valu_mxor      ; valu_opclass_i <= VALU_MOP;
                elsif (funct6 = "011100") and (funct3 = "010") then valu_op_i <= valu_morn      ; valu_opclass_i <= VALU_MOP;
                elsif (funct6 = "011101") and (funct3 = "010") then valu_op_i <= valu_mnand     ; valu_opclass_i <= VALU_MOP;
                elsif (funct6 = "011110") and (funct3 = "010") then valu_op_i <= valu_mnor      ; valu_opclass_i <= VALU_MOP;
                elsif (funct6 = "011111") and (funct3 = "010") then valu_op_i <= valu_mxnor     ; valu_opclass_i <= VALU_MOP;
                elsif (funct6 = "110000")                      then valu_op_i <= valu_waddu     ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "110001")                      then valu_op_i <= valu_wadd      ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "110010")                      then valu_op_i <= valu_wsubu     ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "110011")                      then valu_op_i <= valu_wsub      ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "110100")                      then valu_op_i <= valu_waddu_2sew; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "110101")                      then valu_op_i <= valu_wadd_2sew ; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "110110")                      then valu_op_i <= valu_wsubu_2sew; valu_opclass_i <= VALU_INTOP;
                elsif (funct6 = "110111")                      then valu_op_i <= valu_wsub_2sew ; valu_opclass_i <= VALU_INTOP;
                -- INVALID FUNCT6 --
                else
                    valu_op_i <= valu_invalid; valu_opclass_i <= VALU_INVALOP;
                end if;

            -- OPFVV or OPFVF --
            when "001" | "101" => valu_op_i <= valu_invalid; valu_opclass_i <= VALU_INVALOP;

            -- INVALID FUNCT3 --
            when others => valu_op_i <= valu_invalid; valu_opclass_i <= VALU_INVALOP;
        end case;
    end process;

end architecture neorv32_valu_seq_rtl;