library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_vlsu is
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

        -- VRF Response Interface --
        vrf_vs2_rdata : in std_ulogic_vector(VLEN-1 downto 0);
        vrf_vs1_rdata : in std_ulogic_vector(VLEN-1 downto 0);
        vrf_vd_rdata  : in std_ulogic_vector(VLEN-1 downto 0);

        -- Memory Response Interface --
        mem_ack   : in std_ulogic;
        mem_rdata : in std_ulogic_vector(VLSU_MEM_W-1 downto 0);

        -- Sequencer Control Bus --
        vlsu_seq : out vlsu_seq_if_t;

        -- V-Dispatcher Output Signals --
        seqend : out std_ulogic;
        result : out std_ulogic_vector(XLEN-1 downto 0)
    );
end neorv32_vlsu;

architecture neorv32_vlsu_rtl of neorv32_vlsu is
    -- V-LSU State Machine --
    type lsu_state_t is (IDLE, DECODE, INVALID, WAIT_READ_VRF, READ_VRF, UPDATE_ADDR, READ_MEM, LOAD_VRF, STORE_MEM, SEQ_DONE);
    signal state : lsu_state_t;

    -- V-CSR Signals --
    signal vstart : std_ulogic_vector(XLEN-1 downto 0);
    signal vl     : std_ulogic_vector(XLEN-1 downto 0);
    signal vill   : std_ulogic;
    signal vma    : std_ulogic;
    signal vta    : std_ulogic;
    signal vsew   : std_ulogic_vector(2 downto 0);
    signal vlmul  : std_ulogic_vector(2 downto 0);

    -- Instruction DECODE Fields --
    signal nf          : std_ulogic_vector(2 downto 0);
    signal mew         : std_ulogic;
    signal mop         : std_ulogic_vector(1 downto 0);
    signal vm          : std_ulogic;
    signal lumop_off   : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal encod_width : std_ulogic_vector(2 downto 0);
    signal base_vreg   : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

    -- Element/EMUL Configurations --
    signal data_eew    : std_ulogic_vector(2 downto 0);
    signal emul        : std_ulogic_vector(2 downto 0);

    -- Element/EMUL Internal Counters/Values --
    signal elem_counter : std_ulogic_vector(ELEM_ID_WIDTH-1 downto 0);
    signal num_elems    : std_ulogic_vector(ELEM_ID_WIDTH-1 downto 0);
    signal mul_counter  : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal emul_i       : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

    -- VRF Write/Read Pointer --
    signal vrf_data_ptr : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

    -- Load/Store Memory Address --
    signal mem_addr : std_ulogic_vector(XLEN-1 downto 0);

    -- VRF Data Remap to 32-bit chunks --
    type chunk_array_t is array ((VLEN/VLSU_MEM_W)-1 downto 0) of std_ulogic_vector(VLSU_MEM_W-1 downto 0);
    signal vrf_data_chunks : chunk_array_t;

    -- VRF/MEM Registered Read Data --
    signal vrf_rdata_i : std_ulogic_vector(VLEN-1 downto 0);
    signal mem_rdata_i : std_ulogic_vector(VLSU_MEM_W-1 downto 0);

    -- MEMORY Write Data/Byte Enable Signals --
    signal mem_wdata : std_ulogic_vector(VLSU_MEM_W-1 downto 0);
    signal mem_be    : std_ulogic_vector((VLSU_MEM_W/8)-1 downto 0);
    
    -- VRF Write Data/Byte Enable Signals --
    signal vrf_wdata : std_ulogic_vector(VLEN-1 downto 0);
    signal vrf_ben   : std_ulogic_vector((VLEN/8)-1 downto 0);
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
    --- Instruction Fields Extraction ---
    -------------------------------------
    process(all) begin
        nf          <= vinst(31 downto 29);
        mew         <= vinst(28);
        mop         <= vinst(27 downto 26);
        vm          <= vinst(25);
        lumop_off   <= vinst(24 downto 20);
        encod_width <= vinst(14 downto 12);
        base_vreg   <= vinst(11 downto 7);
    end process;

    ----------------------
    --- EMUL Decoding ---
    ----------------------
    process(all) begin
        case emul is
            when "001"  => emul_i <= "00001";
            when "010"  => emul_i <= "00011";
            when "011"  => emul_i <= "00111";
            when others => emul_i <= "00000";
        end case;
    end process;

    ---------------------------------
    --- Element Number Definition ---
    ---------------------------------
    process(all) begin
        -- How many elements are there in the vector register? --
        case data_eew is
            -- EEW = 8-bits --
            when "000"  => num_elems <= std_ulogic_vector(to_unsigned(((VLEN/8)-1),  num_elems'length));
            -- EEW = 16-bits --
            when "101"  => num_elems <= std_ulogic_vector(to_unsigned(((VLEN/16)-1), num_elems'length));
            -- EEW = 32-bits --
            when "110"  => num_elems <= std_ulogic_vector(to_unsigned(((VLEN/32)-1), num_elems'length));
            -- Unsupported EEW --
            when others => num_elems <= (others => '0');
        end case;
    end process;

    -----------------------------------------------
    --- V-LSU State Machine => Sequential Logic ---
    -----------------------------------------------
    process(clk, rst)
        variable mop_invalid     : std_ulogic;
        variable sew_ratio       : std_ulogic_vector(2 downto 0);
        variable sew_invalid     : std_ulogic;
        variable emul_invalid    : std_ulogic;
        variable emul_nxt        : std_ulogic_vector(emul'range);
        variable vreg_invalid    : std_ulogic;
        variable addr_misaligned : std_ulogic;
        variable vlmul_off       : integer;
        variable unit_stride     : natural;
        variable addr_src        : std_ulogic_vector(mem_addr'length downto 0);
        variable nxt_addr        : std_ulogic_vector(mem_addr'length downto 0);
        variable addr_offset     : std_ulogic_vector(mem_addr'length-1 downto 0);
    begin
        if (rst = '1') then
            state        <= IDLE;
            vrf_data_ptr <= (others => '0');
            mem_addr     <= (others => '0');
            data_eew     <= (others => '0');
            emul         <= (others => '0');
            vrf_rdata_i  <= (others => '0');
            elem_counter <= (others => '0');
            mul_counter  <= (others => '0');
            mem_rdata_i  <= (others => '0');
        elsif rising_edge(clk) then
            case state is
                -- IDLE => waiting for start indication from dispatcher --
                when IDLE =>
                    elem_counter <= (others => '0');
                    mul_counter  <= (others => '0');
                    if (start = '1') then
                        state <= DECODE;
                    end if;

                -- DECODE => decodes instruction and extracts fields --
                when DECODE =>
                    -- Extracts the VRF DATA pointer (for either Load/Store) --
                    vrf_data_ptr <= base_vreg;
                    -- Store Initial Memory Address --
                    mem_addr <= scal1;

                    -- Memory Addressing Mode --
                    case mop is
                        -- Strided Addressing --
                        when "00" | "10" =>
                            mop_invalid := '0';
                            data_eew    <= encod_width;
                            -- Calculates the (EEW/SEW) ratio (using a Lookup Table) and checks if ratio is invalid --
                            case vsew is
                                -- VSEW = 8-bits --
                                when "000" =>
                                    case encod_width is
                                        -- WIDTH = 8-bits --
                                        when "000" => sew_ratio := "000"; sew_invalid := '0';
                                        -- WIDTH = 16-bits --
                                        when "101" => sew_ratio := "001"; sew_invalid := '0';
                                        -- WIDTH = 32-bits --
                                        when "110" => sew_ratio := "010"; sew_invalid := '0';
                                        -- Unsupported WIDTHs --
                                        when others => sew_ratio := "100"; sew_invalid := '1';
                                    end case;
                                
                                -- VSEW = 16-bits --
                                when "001" =>
                                    case encod_width is
                                        -- WIDTH = 8-bits --
                                        when "000" => sew_ratio := "101"; sew_invalid := '0';
                                        -- WIDTH = 16-bits --
                                        when "101" => sew_ratio := "000"; sew_invalid := '0';
                                        -- WIDTH = 32-bits --
                                        when "110" => sew_ratio := "001"; sew_invalid := '0';
                                        -- Unsupported WIDTHs --
                                        when others => sew_ratio := "100"; sew_invalid := '1';
                                    end case;

                                -- VSEW = 32-bits --
                                when "010" =>
                                    case encod_width is
                                        -- WIDTH = 8-bits --
                                        when "000" => sew_ratio := "110"; sew_invalid := '0';
                                        -- WIDTH = 16-bits --
                                        when "101" => sew_ratio := "101"; sew_invalid := '0';
                                        -- WIDTH = 32-bits --
                                        when "110" => sew_ratio := "000"; sew_invalid := '0';
                                        -- Unsupported WIDTHs --
                                        when others => sew_ratio := "100"; sew_invalid := '1';
                                    end case;
                            
                                -- Invalid VSEW --
                                when others => sew_ratio := "100"; sew_invalid := '1';
                            end case;

                            -- Lookup Table to calculate the Effective Multiplier (EMUL) and check if it is valid --
                            case sew_ratio is
                                -- (EEW/SEW) = 1 --
                                when "000" => vlmul_off := 0; emul_invalid := '0';

                                -- (EEW/SEW) = 2 --
                                when "001" =>
                                    case vlmul is
                                        -- Invalid VLMULs --
                                        when "011" | "100" => vlmul_off := 0; emul_invalid := '1';
                                        -- Valid VLMULs --
                                        when others => vlmul_off := 1; emul_invalid := '0';
                                    end case;

                                -- (EEW/SEW) = 4 --
                                when "010" =>
                                    case vlmul is
                                        -- Invalid VLMULs --
                                        when "010" | "011" | "100" => vlmul_off := 0; emul_invalid := '1';
                                        -- Valid VLMULs --
                                        when others => vlmul_off := 2; emul_invalid := '0';
                                    end case;

                                -- (EEW/SEW) = 1/2 --
                                when "101" =>
                                    case vlmul is
                                        -- Invalid VLMULs --
                                        when "100" | "101" => vlmul_off := 0; emul_invalid := '1';
                                        -- Valid VLMULs --
                                        when others => vlmul_off := -1; emul_invalid := '0';
                                    end case;

                                -- (EEW/SEW) = 1/4 --
                                when "110" =>
                                    case vlmul is
                                        -- Invalid VLMULs --
                                        when "100" | "101" | "110" => vlmul_off := 0; emul_invalid := '1';
                                        -- Valid VLMULs --
                                        when others => vlmul_off := -2; emul_invalid := '0';
                                    end case;

                                -- Invalid (EEW/SEW) Ratio --
                                when others => vlmul_off := 0; emul_invalid := '1';
                            end case;

                            emul_nxt := std_ulogic_vector(resize(signed(vlmul), emul_nxt'length) + to_signed(vlmul_off, emul_nxt'length));
                            emul <= emul_nxt;
                        
                        -- Indexed Addressing (not supported for now...) --
                        when "01" | "11" => 
                            mop_invalid  := '1';
                            sew_invalid  := '0';
                            emul_invalid := '0';
                            data_eew     <= (others => '0');
                            emul         <= (others => '0');

                        -- Unsupported Addressing Modes --
                        when others =>
                            mop_invalid  := '1';
                            sew_invalid  := '0';
                            emul_invalid := '0';
                            data_eew     <= (others => '0');
                            emul         <= (others => '0');
                    end case;

                    -- Check if register specifier is legal for calculated EMUL --
                    case emul_nxt is
                        -- EMUL = 1 --
                        when "000" => vreg_invalid := '0';
                        -- EMUL = 2 --
                        when "001" => vreg_invalid := '0' when (base_vreg(0) = '0') else '1';
                        -- EMUL = 4 --
                        when "010" => vreg_invalid := '0' when (base_vreg(1 downto 0) = "00") else '1';
                        -- EMUL = 8 --
                        when "011" => vreg_invalid := '0' when (base_vreg(2 downto 0) = "000") else '1';
                        -- Unsupported EMUL --
                        when others => vreg_invalid := '0';
                    end case;

                    if (mop_invalid = '1') or (sew_invalid = '1') or (emul_invalid = '1') or (vreg_invalid = '1') then
                        state <= INVALID;
                    else
                        -- DECODE OPCODE --
                        case vinst(6 downto 0) is
                            when vop_load  => state <= UPDATE_ADDR;
                            when vop_store => state <= WAIT_READ_VRF;
                            when others    => state <= INVALID;
                        end case;
                    end if;

                -- WAIT_READ_VRF => waits one cycle due to synchronous read (FPGA BRAMs) --
                when WAIT_READ_VRF => state <= READ_VRF;

                -- READ_VRF => registers the VRF RDATA --
                when READ_VRF =>
                    state       <= UPDATE_ADDR;
                    vrf_rdata_i <= vrf_vs2_rdata;

                -- UPDATE_ADDR => updates the memory access address according to access mode --
                when UPDATE_ADDR =>
                    -- Base Address and Offset Calculation --
                    case mop is
                        -- Unit-Stride --
                        when "00" => 
                            case data_eew is
                                -- EEW = 8-bits --
                                when "000"  => unit_stride := 1;
                                -- EEW = 16-bits --
                                when "101"  => unit_stride := 2;
                                -- EEW = 32-bits --
                                when "110"  => unit_stride := 4;
                                -- Unsupported EEW --
                                when others => unit_stride := 0;
                            end case;
                            -- Address Offset Calculation --> if this is the first in the segment, offset is zero. Else, offset is unit stride --
                            if (elem_counter = std_ulogic_vector(to_unsigned(0, elem_counter'length))) and (mul_counter = std_ulogic_vector(to_unsigned(0, mul_counter'length))) then
                                addr_offset := (others => '0');
                            else
                                addr_offset := std_ulogic_vector(to_unsigned(unit_stride, addr_offset'length));
                            end if;
                            addr_src := std_ulogic_vector(resize(unsigned(mem_addr), addr_src'length));

                        -- Constant-Stride --
                        when "10" =>
                            -- Address Offset Calculation --> if this is the first in the segment, offset is zero. Else, offset is unit stride --
                            if (elem_counter = std_ulogic_vector(to_unsigned(0, elem_counter'length))) and (mul_counter = std_ulogic_vector(to_unsigned(0, mul_counter'length))) then
                                addr_offset := (others => '0');
                            else
                                addr_offset := std_ulogic_vector(resize(unsigned(scal2), addr_offset'length));
                            end if;
                            addr_src := std_ulogic_vector(resize(unsigned(mem_addr), addr_src'length));

                        -- Unordered/Ordered Indexed (not supported for now...) --
                        when "01" | "11" =>
                            addr_offset := (others => '0');
                            addr_src    := (others => '0');

                        -- Invalid Access Modes --
                        when others => null;
                    end case;

                    -- Address Update --
                    nxt_addr := std_ulogic_vector(signed(addr_src) + resize(signed(addr_offset), nxt_addr'length));

                    -- Checks if next address if aligned or not, based on DATA_EEW --
                    case data_eew is
                        -- EEW = 8 bits --
                        when "000" => addr_misaligned := '0';
                        -- EEW = 16 bits --
                        when "101" => addr_misaligned := '0' when (nxt_addr(0) = '0') else '1';
                        -- EEW = 32 bits --
                        when "110" => addr_misaligned := '0' when (nxt_addr(1 downto 0) = "00") else '1';
                        -- INVALID EEW VALUE --
                        when others => addr_misaligned := '0';
                    end case;

                    -- Updates mem_addr register with next memory address to be accessed --
                    mem_addr <= std_ulogic_vector(nxt_addr(nxt_addr'left-1 downto 0));

                    -- Next State Logic for DECODE --
                    if (addr_misaligned = '1') then
                        state <= INVALID;
                    else
                        case vinst(6 downto 0) is
                            when vop_load  => state <= READ_MEM;
                            when vop_store => state <= STORE_MEM;
                            when others    => state <= INVALID;
                        end case;
                    end if;

                -- READ_MEM => sends read request to memory and waits for completion, registering the READ DATA and updating counters/pointers when done --
                when READ_MEM =>
                    -- Memory Request ACK --
                    if (mem_ack = '1') then
                        state       <= LOAD_VRF;
                        mem_rdata_i <= mem_rdata;
                    end if;

                -- LOAD_VRF => writes the memory READ DATA to the VRF --
                when LOAD_VRF =>
                    -- If all vector elements have been stored --
                    if (elem_counter = num_elems) then
                        -- If all V-regs in the V-group have been processed --
                        if (mul_counter = emul_i) then
                            state <= SEQ_DONE;
                        else
                            state        <= UPDATE_ADDR;
                            elem_counter <= (others => '0');
                            mul_counter  <= std_ulogic_vector(unsigned(mul_counter) + 1);
                            vrf_data_ptr <= std_ulogic_vector(unsigned(vrf_data_ptr) + 1);
                        end if;
                    else
                        state        <= UPDATE_ADDR;
                        elem_counter <= std_ulogic_vector(unsigned(elem_counter) + 1);
                    end if;

                -- STORE_MEM => sends write request to memory and waits for completion, updating counters/pointers when done --
                when STORE_MEM =>
                    -- Memory Request ACK --
                    if (mem_ack = '1') then
                        -- If all vector elements have been stored --
                        if (elem_counter = num_elems) then
                            -- If all V-regs in the V-group have been processed --
                            if (mul_counter = emul_i) then
                                state <= SEQ_DONE;
                            else
                                state        <= READ_VRF;
                                elem_counter <= (others => '0');
                                mul_counter  <= std_ulogic_vector(unsigned(mul_counter) + 1);
                                vrf_data_ptr <= std_ulogic_vector(unsigned(vrf_data_ptr) + 1);
                            end if;
                        else
                            state        <= UPDATE_ADDR;
                            elem_counter <= std_ulogic_vector(unsigned(elem_counter) + 1);
                        end if;
                    end if;

                -- SEQ_DONE => indicates completion of instruction sequencing, giving control back to dispatcher --
                when SEQ_DONE => state <= IDLE;

                -- INVALID => indicates the decoded instruction is invalid and will generate a trap --
                when INVALID =>
                    -- TODO: trap instruction --
                    state <= IDLE;

                -- Invalid States --
                when others => null;
            end case;
        end if;
    end process;

    --------------------------------------------------------------
    --- STORE Datapath => remap VLEN VRF data to 32 bit chunks ---
    --------------------------------------------------------------
    VRF_CHUNK_GEN: for ii in vrf_data_chunks'range generate
        vrf_data_chunks(ii) <= vrf_rdata_i((ii*VLSU_MEM_W)+(VLSU_MEM_W-1) downto ii*VLSU_MEM_W);
    end generate VRF_CHUNK_GEN;

    -------------------------------------------------------------------------------------
    -- LOAD/STORE Datapath => calculate the WDATA and BYTE ENABLE corresponding values --
    -------------------------------------------------------------------------------------
    process(all) 
        variable vrf_chunk_sel : std_ulogic_vector(VLSU_CHUNK_CNT_W-1 downto 0);
        variable vrf_elem_sel  : std_ulogic_vector(1 downto 0);
        variable wdata_chunk   : std_ulogic_vector(VLSU_MEM_W-1 downto 0);
        variable elem_sel      : std_ulogic_vector(1 downto 0);
        variable align_sel     : std_ulogic_vector(1 downto 0);
        variable wdata_8b      : std_ulogic_vector(7 downto 0);
        variable wdata_16b     : std_ulogic_vector(15 downto 0);
        variable wdata_32b     : std_ulogic_vector(31 downto 0);
        variable wdata         : std_ulogic_vector(VLSU_MEM_W-1 downto 0);
        variable byte_en       : std_ulogic_vector((VLSU_MEM_W/8)-1 downto 0);
    begin
        -- Defines the Chunk Select and Element Select signals --
        case data_eew is
            -- EEW = 8 bits --
            when "000" =>
                vrf_chunk_sel := elem_counter(elem_counter'left downto 2);
                vrf_elem_sel  := elem_counter(1 downto 0);
            -- EEW = 16 bits --
            when "101" =>
                vrf_chunk_sel := elem_counter(elem_counter'left-1 downto 1);
                vrf_elem_sel  := "0" & elem_counter(0);
            -- EEW = 32 bits --
            when "110" =>
                vrf_chunk_sel := elem_counter(elem_counter'left-2 downto 0);
                vrf_elem_sel  := "00";
            -- INVALID EEW VALUE --
            when others =>
                vrf_chunk_sel := (others => '0');
                vrf_elem_sel  := (others => '0');
        end case;

        -- Calculate the 32-bit chunk to have the elements extracted from, and also define the MUX select signals, based on instruction --
        -- NOTE: the LOAD process is basically the reverse one of STORE, hence why we multiplex the selection signals to reuse logic    --
        case vinst(6 downto 0) is
            when vop_load  =>
                wdata_chunk := mem_rdata;
                elem_sel    := mem_addr(1 downto 0);
                align_sel   := vrf_elem_sel;
            when vop_store =>
                wdata_chunk := vrf_data_chunks(to_integer(unsigned(vrf_chunk_sel)));
                elem_sel    := vrf_elem_sel;
                align_sel   := mem_addr(1 downto 0);
            when others    =>
                wdata_chunk := (others => '0');
                elem_sel    := (others => '0');
                align_sel   := (others => '0');
        end case;

        -- Extract the element to be sent to memory and , according to memory address, align the data to the 32-bit memory data bus and generate byte enable --
        wdata_8b  := (others => '0');
        wdata_16b := (others => '0');
        wdata_32b := (others => '0');
        wdata     := (others => '0');
        byte_en   := (others => '0');
        case data_eew is
            -- EEW = 8 bits --
            when "000" =>
                -- Multiplexer to select the 8-bit element to be sent to memory, according to element counter --
                case elem_sel is
                    when "00"   => wdata_8b := wdata_chunk(7  downto 0);
                    when "01"   => wdata_8b := wdata_chunk(15 downto 8);
                    when "10"   => wdata_8b := wdata_chunk(23 downto 16);
                    when "11"   => wdata_8b := wdata_chunk(31 downto 24);
                    when others => null;
                end case;
                -- Multiplexer to align the data to the memory bus according to the calculated memory address --
                case align_sel is
                    when "00"   => wdata(7  downto 0)  := wdata_8b; byte_en(0) := '1';
                    when "01"   => wdata(15 downto 8)  := wdata_8b; byte_en(1) := '1';
                    when "10"   => wdata(23 downto 16) := wdata_8b; byte_en(2) := '1';
                    when "11"   => wdata(31 downto 24) := wdata_8b; byte_en(3) := '1';
                    when others => null;
                end case;

            -- EEW = 16 bits --
            when "101" =>
                -- Multiplexer to select the 16-bit element to be sent to memory, according to element counter --
                case elem_sel is
                    when "00"   => wdata_16b := wdata_chunk(15 downto 0);
                    when "01"   => wdata_16b := wdata_chunk(31 downto 16);
                    when others => null;
                end case;
                -- Multiplexer to align the data to the memory bus according to the calculated memory address --
                case align_sel is
                    when "00"   => wdata(15 downto 0)  := wdata_16b; byte_en(1 downto 0) := "11";
                    when "10"   => wdata(31 downto 16) := wdata_16b; byte_en(3 downto 2) := "11";
                    when others => null;
                end case;

            -- EEW = 32 bits --
            when "110" =>
                -- Multiplexer to select the 32-bit element to be sent to memory, according to element counter --
                case elem_sel is
                    when "00"   => wdata_32b := wdata_chunk(31 downto 0);
                    when others => null;
                end case;
                -- Multiplexer to align the data to the memory bus according to the calculated memory address --
                case align_sel is
                    when "00"   => wdata(31 downto 0) := wdata_32b; byte_en(3 downto 0) := "1111";
                    when others => null;
                end case;

            -- INVALID SEW VALUE --
            when others => null;
        end case;

        -- Multiplex the calculated WRITE DATA and BYTE ENABLE to either VRF or MEMORY, based on instruction --
        mem_wdata <= (others => '0');
        mem_be    <= (others => '0');
        vrf_wdata <= (others => '0');
        vrf_ben   <= (others => '0');
        case vinst(6 downto 0) is
            -- LOAD --
            when vop_load =>
                case vrf_chunk_sel is
                    -- Bits [31:0] --
                    when "00" => vrf_wdata(31 downto 0) <= wdata  ; vrf_ben(3 downto 0) <= byte_en;
                    -- Bits [63:32] --
                    when "01" => vrf_wdata(63 downto 32) <= wdata ; vrf_ben(7 downto 4) <= byte_en;
                    -- Bits [95:64] --
                    when "10" => vrf_wdata(95 downto 64) <= wdata ; vrf_ben(11 downto 8) <= byte_en;
                    -- Bits [127:96] --
                    when "11" => vrf_wdata(127 downto 96) <= wdata; vrf_ben(15 downto 12) <= byte_en;
                    -- INVALID --
                    when others => null;
                end case;

            -- STORE --
            when vop_store =>
                mem_wdata <= wdata;
                mem_be    <= byte_en;

            -- INVALID INSTRUCTION TYPES --
            when others => null;
        end case;
    end process;

    --------------------------------------------------
    --- V-LSU State Machine => Combinational Logic ---
    --------------------------------------------------
    process(all)
        -- VRF Control Variables --
        variable seq_vrf_vs2   : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable seq_vrf_vs1   : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable seq_vrf_vd    : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
        variable seq_vrf_wdata : std_ulogic_vector(VLEN-1 downto 0);
        variable seq_vrf_ben   : std_ulogic_vector((VLEN/8)-1 downto 0);

        -- Memory Control Variables --
        variable seq_mem_strb  : std_ulogic;
        variable seq_mem_rw    : std_ulogic;
        variable seq_mem_addr  : std_ulogic_vector(XLEN-1 downto 0);
        variable seq_mem_wdata : std_ulogic_vector(VLSU_MEM_W-1 downto 0);
        variable seq_mem_ben   : std_ulogic_vector((VLSU_MEM_W/8)-1 downto 0);
    begin
        -- V-LSU SEQ VRF Control --
        seq_vrf_vs2   := (others => '0');
        seq_vrf_vs1   := (others => '0');
        seq_vrf_vd    := (others => '0');
        seq_vrf_wdata := (others => '0');
        seq_vrf_ben   := (others => '0');
        
        -- V-LSU SEQ MEMORY Control --
        seq_mem_strb  := '0';
        seq_mem_rw    := '0';
        seq_mem_addr  := (others => '0');
        seq_mem_wdata := (others => '0');
        seq_mem_ben   := (others => '0');
        
        -- V-LSU Dispatcher Interface --
        seqend <= '0';
        result <= (others => '0');

        case state is
            when IDLE => null;

            when DECODE => null;

            when WAIT_READ_VRF | READ_VRF => seq_vrf_vs2 := vrf_data_ptr; 

            when UPDATE_ADDR => null;

            when READ_MEM =>
                seq_mem_strb := '1';
                seq_mem_rw   := '0';
                seq_mem_addr := mem_addr;

            when LOAD_VRF =>
                seq_vrf_vd    := vrf_data_ptr;
                seq_vrf_wdata := vrf_wdata;
                seq_vrf_ben   := vrf_ben;

            when STORE_MEM =>
                seq_mem_strb  := '1';
                seq_mem_rw    := '1';
                seq_mem_addr  := mem_addr;
                seq_mem_wdata := mem_wdata;
                seq_mem_ben   := mem_be;

            when SEQ_DONE => seqend <= '1';

            when INVALID => null;

            when others => null;
        end case;

        vlsu_seq <= (
            vrf_vs2 => seq_vrf_vs2, vrf_vs1 => seq_vrf_vs1, vrf_vd => seq_vrf_vd, vrf_wdata => seq_vrf_wdata, vrf_ben => seq_vrf_ben,
            mem_strb => seq_mem_strb, mem_rw => seq_mem_rw, mem_addr => seq_mem_addr, mem_wdata => seq_mem_wdata, mem_ben => seq_mem_ben 
        );
    end process;

end architecture neorv32_vlsu_rtl;