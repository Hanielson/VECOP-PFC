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

        -- V-ALU Signals --
        alu_done : in std_ulogic;
        
        -- Sequencer Control Bus --
        valu_seq : out valu_seq_if_t;

        -- V-Dispatcher Output Signals --
        seqend : out std_ulogic;
        result : out std_ulogic_vector(XLEN-1 downto 0)
    );
end neorv32_valu_seq;

architecture neorv32_valu_seq_rtl of neorv32_valu_seq is
    -- VALU-SEQ Internal State Machine --
    type ctrl_state_t is (IDLE, DECODE, INVALID, WAIT_READ, DISPATCH_ALU, WRITE_BACK, UPDATE_CYC, UPDATE_MUL, SEQ_DONE);
    signal state : ctrl_state_t;

    -- Internal Cycle/Mul Counters --
    signal cycle_count : std_ulogic_vector(2 downto 0);
    signal mul_count   : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

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
    signal vlmul_i : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

    -- V-ALU Operation Type --
    signal valu_op_i : std_ulogic_vector(VALU_OP_WIDTH-1 downto 0);
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
            when "001"  => vlmul_i <= "00001";
            when "010"  => vlmul_i <= "00011";
            when "011"  => vlmul_i <= "00111";
            when others => vlmul_i <= "00000";
        end case;
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
            state       <= IDLE;
            cycle_count <= (others => '0');
            mul_count   <= (others => '0');
            dest        <= (others => '0');
            src1        <= (others => '0');
            src2        <= (others => '0');
        elsif rising_edge(clk) then
            case state is
                -- IDLE Control State --
                when IDLE =>
                    -- Resets the Cycle/Mul counters --
                    cycle_count <= (others => '0');
                    mul_count   <= (others => '0');
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
                when WAIT_READ => state <= DISPATCH_ALU;

                -- DISPATCH ALU Operation Control State --
                when DISPATCH_ALU =>
                    if (alu_done = '1') then
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
                    if (cycle_count /= max_cycle) then
                        state <= UPDATE_CYC;
                    -- If another loop of execution is needed due to LMUL --
                    elsif (mul_count /= vlmul_i) then
                        state <= UPDATE_MUL;
                    -- If all is done, then signal back to dispatcher unit... --
                    else
                        state <= SEQ_DONE;
                    end if;

                -- UPDATE CYCLE COUNTER Control State --
                when UPDATE_CYC =>
                    state <= WAIT_READ;
                    -- Update Instruction Cycle counter --
                    cycle_count <= std_ulogic_vector(unsigned(cycle_count) + 1);
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
                    cycle_count <= (others => '0');
                    mul_count   <= std_ulogic_vector(unsigned(mul_count) + 1);
                    -- Update Operands/Destination Pointers
                    dest <= std_ulogic_vector(unsigned(dest) + 1);
                    src1 <= std_ulogic_vector(unsigned(src1) + 1);
                    src2 <= std_ulogic_vector(unsigned(src2) + 1);

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
        variable valu_valid   : std_ulogic;
    begin
        
        -- Auxiliary Variables --
        ben_i  := (others => '0');
        mask_i := (others => '0');

        -- VRF Control --
        vrf_vs2 := src2; 
        vrf_vs1 := src1; 
        vrf_vd  := dest; 

        -- V-ALU Control --
        valu_op    := valu_op_i;
        valu_valid := '0';

        -- V-Dispatcher Response --
        seqend <= '0';
        result <= (others => '0');

        case state is
            -- IDLE Control State => Waiting for Valid Instruction --
            when IDLE => null;

            -- WAIT VRF READ Control State => Waiting for VRF read values --
            when WAIT_READ => null;

            -- DISPATCH Operation Control State --
            when DISPATCH_ALU =>
                -- V-ALU Control Signals --
                valu_valid := '1';

            -- WRITE BACK to VRF Control State --
            when WRITE_BACK =>
                -- Byte Enable Calculation Logic --
                case valu_op_i is
                    -- Narrowing Operations --
                    when valu_nsrl | valu_nsra =>
                        if (cycle_count(0) = '1') then
                            ben_i := (ben_i'length-1 downto (ben_i'length/2) => '1', others => '0');
                        else
                            ben_i := ((ben_i'length/2)-1 downto 0 => '1', others => '0');
                        end if;

                    -- Other Operation Types --
                    when others => ben_i := (others => '1');
                end case;

                -- Auxiliary Variables for Byte Enable definition --
                mask_i  := (others => '1');

            -- SEQ_DONE Control State --
            when SEQ_DONE => seqend <= '1';
            
            when others => null;
        end case;

        valu_seq <= (
            vrf_vs2 => vrf_vs2, vrf_vs1 => vrf_vs1, vrf_vd => vrf_vd, vrf_ben => (ben_i and mask_i),
            valu_op => valu_op, valu_valid => valu_valid
        );
    end process;

    --------------------------------
    --- ALU Operation Definition ---
    --------------------------------
    process(all) begin
        case funct3 is
            -- OPIVV, OPIVX or OPIVI --
            when "000" | "100" | "011" =>
                if    (funct6 = "000000")                       then valu_op_i <= valu_add;
                elsif (funct6 = "000010") and (funct3 /= "011") then valu_op_i <= valu_sub;
                elsif (funct6 = "000011") and (funct3 /= "000") then valu_op_i <= valu_rsub;
                elsif (funct6 = "000100") and (funct3 /= "011") then valu_op_i <= valu_minu;
                elsif (funct6 = "000101") and (funct3 /= "011") then valu_op_i <= valu_min;
                elsif (funct6 = "000110") and (funct3 /= "011") then valu_op_i <= valu_maxu;
                elsif (funct6 = "000111") and (funct3 /= "011") then valu_op_i <= valu_max;
                elsif (funct6 = "001001")                       then valu_op_i <= valu_and;
                elsif (funct6 = "001010")                       then valu_op_i <= valu_or;
                elsif (funct6 = "001011")                       then valu_op_i <= valu_xor;
                elsif (funct6 = "010000")                       then valu_op_i <= valu_adc;
                elsif (funct6 = "010001")                       then valu_op_i <= valu_madc;
                elsif (funct6 = "010010") and (funct3 /= "011") then valu_op_i <= valu_sbc;
                elsif (funct6 = "010011") and (funct3 /= "011") then valu_op_i <= valu_msbc;
                elsif (funct6 = "010111")                       then valu_op_i <= valu_merge;
                elsif (funct6 = "011000")                       then valu_op_i <= valu_se;
                elsif (funct6 = "011001")                       then valu_op_i <= valu_sne;
                elsif (funct6 = "011010") and (funct3 /= "011") then valu_op_i <= valu_sltu;
                elsif (funct6 = "011011") and (funct3 /= "011") then valu_op_i <= valu_slt;
                elsif (funct6 = "011100")                       then valu_op_i <= valu_sleu;
                elsif (funct6 = "011101")                       then valu_op_i <= valu_sle;
                elsif (funct6 = "011110") and (funct3 /= "000") then valu_op_i <= valu_sgtu;
                elsif (funct6 = "011111") and (funct3 /= "000") then valu_op_i <= valu_sgt;
                elsif (funct6 = "100101")                       then valu_op_i <= valu_sll;
                elsif (funct6 = "101000")                       then valu_op_i <= valu_srl;
                elsif (funct6 = "101001")                       then valu_op_i <= valu_sra;
                elsif (funct6 = "101100")                       then valu_op_i <= valu_nsrl;
                elsif (funct6 = "101101")                       then valu_op_i <= valu_nsra;
                -- INVALID FUNCT6 --
                else
                    valu_op_i <= valu_invalid;
                end if;

            -- OPMVV or OPMVX --
            when "010" | "110" =>
                if (funct6 = "010010") then
                    if    (vs1 = "00100") then valu_op_i <= valu_zext_vf4;
                    elsif (vs1 = "00101") then valu_op_i <= valu_sext_vf4;
                    elsif (vs1 = "00110") then valu_op_i <= valu_zext_vf2;
                    elsif (vs1 = "00111") then valu_op_i <= valu_sext_vf2;
                    -- INVALID SOURCE_1 --
                    else
                        valu_op_i <= valu_invalid;
                    end if;
                elsif (funct6 = "110000") then valu_op_i <= valu_waddu;
                elsif (funct6 = "110001") then valu_op_i <= valu_wadd;
                elsif (funct6 = "110010") then valu_op_i <= valu_wsubu;
                elsif (funct6 = "110011") then valu_op_i <= valu_wsub;
                elsif (funct6 = "110100") then valu_op_i <= valu_waddu_2sew;
                elsif (funct6 = "110101") then valu_op_i <= valu_wadd_2sew;
                elsif (funct6 = "110110") then valu_op_i <= valu_wsubu_2sew;
                elsif (funct6 = "110111") then valu_op_i <= valu_wsub_2sew;
                -- INVALID FUNCT6 --
                else
                    valu_op_i <= valu_invalid;
                end if;

            -- OPFVV or OPFVF --
            when "001" | "101" => valu_op_i <= valu_invalid;

            -- INVALID FUNCT3 --
            when others => valu_op_i <= valu_invalid;
        end case;
    end process;

end architecture neorv32_valu_seq_rtl;