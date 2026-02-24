library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_lsu is
    port(
        clk         : in std_ulogic;
        rst         : in std_ulogic;

        -- Vector Instruction Queue --
        vinst       : in std_ulogic_vector(XLEN-1 downto 0);
        scal2       : in std_ulogic_vector(XLEN-1 downto 0);
        scal1       : in std_ulogic_vector(XLEN-1 downto 0);
        
        -- Dispatcher --
        vdisp_ctrl  : in vdisp_if_t;

        -- VRF Interface --
        vrf_to_vlsu : in vrf_out_if_t;
        vlsu_to_vrf : out vrf_in_if_t;
        
        -- Vector CSR --
        vcsr        : in vcsr_t;

        -- Memory Interface --
        mem_ack     : in std_ulogic;
        mem_rdata   : in std_ulogic_vector(XLEN-1 downto 0);
    );
end neorv32_lsu;

architecture neorv32_lsu_rtl of neorv32_lsu is
    -- V-LSU State Machine --
    type lsu_state_t is (IDLE, DECODE, UPDATE_ADDR, READ_VRF, STORE_EXEC, READ_MEM, LOAD_VRF, ELEM_UPDATE, SEG_UPDATE, MUL_UPDATE, FINISH_LSU);
    signal state : lsu_state_t;

    signal vrf_wptr : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal vrf_rptr : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

    -- V-CSR Signals --
    signal vill  : std_ulogic_vector(XLEN-1 downto 0);
    signal vma   : std_ulogic;
    signal vta   : std_ulogic;
    signal vsew  : std_ulogic_vector(2 downto 0);
    signal vlmul : std_ulogic_vector(2 downto 0);

    -- Registered Input Signals --
    signal vinst_i : std_ulogic_vector(XLEN-1 downto 0);
    signal scal2_i : std_ulogic_vector(XLEN-1 downto 0);
    signal scal1_i : std_ulogic_vector(XLEN-1 downto 0);
    signal vmask_i : std_ulogic_vector(VLEN-1 downto 0);
    signal vcsr_i  : vcsr_t;

    -- Instruction Decode Fields --
    signal nf          : std_ulogic_vector(2 downto 0);
    signal mew         : std_ulogic;
    signal mop         : std_ulogic_vector(1 downto 0);
    signal vm          : std_ulogic;
    signal lumop_off   : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);
    signal base_addr   : std_ulogic_vector(XLEN-1 downto 0);
    signal encod_width : std_ulogic_vector(2 downto 0);
    signal base_vreg   : std_ulogic_vector(VREF_ADDR_WIDTH-1 downto 0);

    -- Element Configurations --
    signal data_eew    : std_ulogic_vector(2 downto 0);
    signal index_eew   : std_ulogic_vector(2 downto 0);
    signal emul        : std_ulogic_vector(2 downto 0);

    -- Vector Indexes Remap to highest SEW (32-bit) --
    type index_map_t is array ((VLEN/MAX_VSEW)-1 downto 0) of std_ulogic_vector(MAX_VSEW-1 downto 0);
    signal index_map  : index_map_t;
    signal index_bpos : std_ulogic_vector(3 downto 0);

    -- Load/Store Memory Address --
    signal mem_addr : std_ulogic_vector(XLEN-1 downto 0);
begin

    ------------------------------------
    --- vtype CSR Signals Extraction ---
    ------------------------------------
    vill  <= vcsr.vtype(XLEN-1);
    vma   <= vcsr.vtype(7);
    vta   <= vcsr.vtype(6);
    vsew  <= vcsr.vtype(5 downto 3);
    vlmul <= vcsr.vtype(2 downto 0);

    -------------------------------------
    --- Instruction Fields Extraction ---
    -------------------------------------
    process(all) begin
        nf          <= vinst_i(31 downto 29);
        mew         <= vinst_i(28);
        mop         <= vinst_i(27 downto 26);
        vm          <= vinst_i(25);
        lumop_off   <= vinst_i(24 downto 20);
        encod_width <= vinst_i(14 downto 12);
        base_vreg   <= vinst_i(11 downto 7);
    end process;

    ------------------------------
    --- Index Remap to 32-bits ---
    ------------------------------
    IDX_REMAP_GEN: for ii in 0 to (VLEN/MAX_VSEW)-1 generate
        index_map(ii) <= vrf_to_vlsu.vs2_out((ii*MAX_VSEW)+(MAX_VSEW-1) downto (ii*MAX_VSEW));
    end generate IDX_REMAP_GEN;

    -----------------------------------------------
    --- V-LSU State Machine => Sequential Logic ---
    -----------------------------------------------
    process(clk, rst) 
        variable unit_stride   : natural;
        variable addr_src      : std_ulogic_vector(mem_addr'length downto 0);
        variable nxt_addr      : std_ulogic_vector(mem_addr'length downto 0);
        variable addr_offset   : std_ulogic_vector(mem_addr'length-1 downto 0);
        variable index_wpos    : std_ulogic_vector(index_bpos'length-3 downto 0);
        variable index_boffset : unsigned(index_bpos'range);
    begin
        if (rst = '1') then
            state     <= IDLE;
            vinst_i   <= (others => '0');
            scal2_i   <= (others => '0');
            scal1_i   <= (others => '0');
            vmask_i   <= (others => '0');
            vcsr_i    <= (others => (others => '0'));
            base_addr <= (others => '0');
            mem_addr  <= (others => '0');
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    if (vlsu_start = '1') then
                        state     <= DECODE;
                        vinst_i   <= vinst;
                        scal2_i   <= scal2;
                        scal1_i   <= scal1;
                        vmask_i   <= vmask;
                        vcsr_i    <= vcsr;
                        base_addr <= scal1;
                    end if;

                when DECODE =>
                    -- OPCODE Decode --
                    case vinst_i(6 downto 0) is
                        -- Load Instruction --
                        when vop_load => 
                            state    <= UPDATE_ADDR;
                            vrf_wptr <= base_vreg;
                        -- Store Instruction --
                        when vop_store => 
                            state    <= READ_VRF;
                            vrf_rptr <= base_vreg;
                        -- INVALID LSU Operation --
                        when others => 
                            state <= INVALID;
                    end case;

                    -- Store Initial Memory Address --
                    mem_addr <= base_addr;

                    -- Memory Addressing Mode --
                    case mop is
                        -- Strided Addressing --
                        when "00" | "10" =>
                            data_eew  <= encod_width;
                            index_eew <= (others => '0');
                            -- TODO: EMUL DEFINITION --
                            emul      <= vlmul;
                        -- Indexed Addressing --
                        when "01" | "11" =>
                            data_eew  <= vsew;
                            index_eew <= encod_width;
                            emul      <= vlmul;
                        when others => null;
                    end case;

                when READ_VRF =>
                    state <= UPDATE_ADDR;

                when UPDATE_ADDR =>
                    -- TODO: IF CURRENT ELEMENT IS INACTIVE, SKIP --
                    case vinst_i(6 downto 0) is
                        when vop_load  => state <= READ_MEM;
                        when vop_store => state <= STORE_EXEC;
                        when others    => state <= INVALID;
                    end case;
            
                    -- Base Address and Offset Calculation --
                    case mop is
                        -- Unit-Stride --
                        when "00" => 
                            case data_eew is
                                when "000"  => unit_stride := 1;
                                when "001"  => unit_stride := 2;
                                when "010"  => unit_stride := 4;
                                when others => unit_stride := 0;
                            end case;
                            -- Address Offset Calculation --> if this is the first in the segment, offset is zero. Else, offset is unit stride --
                            if (elem_counter = std_ulogic_vector(to_unsigned(0, elem_counter'length))) and (mul_counter = std_ulogic_vector(to_unsigned(0, mul_counter'length))) then
                                addr_offset := (others => '0');
                            else
                                addr_offset := std_ulogic_vector(to_unsigned(unit_stride, addr_offset'length));
                            end if;
                            addr_src := resize(unsigned(mem_addr), addr_src'length);

                        -- Constant-Stride --
                        when "10" =>
                            -- Address Offset Calculation --> if this is the first in the segment, offset is zero. Else, offset is unit stride --
                            if (elem_counter = std_ulogic_vector(to_unsigned(0, elem_counter'length))) and (mul_counter = std_ulogic_vector(to_unsigned(0, mul_counter'length))) then
                                addr_offset := (others => '0');
                            else
                                addr_offset := std_ulogic_vector(resize(unsigned(scal2_i), addr_offset'length));
                            end if;
                            addr_src := resize(unsigned(mem_addr), addr_src'length);

                        -- Unordered/Ordered Indexed --
                        when "01" | "11" =>
                            index_wpos   := to_integer(unsigned(index_bpos(index_bpos'length-1 downto 2)));
                            index_8bits  := to_integer(unsigned(index_bpos(1 downto 0)));
                            index_16bits := to_integer(unsigned(index_bpos(1 downto 1)));
                            case index_eew is
                                -- SEW = 8 bits --
                                when "000" => 
                                    -- Byte Index Extraction Logic --
                                    case index_8bits is
                                        when 0 => addr_offset := std_ulogic_vector(resize(unsigned(index_map(index_wpos)(7 downto 0)),   addr_offset'length));
                                        when 1 => addr_offset := std_ulogic_vector(resize(unsigned(index_map(index_wpos)(15 downto 8)),  addr_offset'length));
                                        when 2 => addr_offset := std_ulogic_vector(resize(unsigned(index_map(index_wpos)(23 downto 16)), addr_offset'length));
                                        when 3 => addr_offset := std_ulogic_vector(resize(unsigned(index_map(index_wpos)(31 downto 24)), addr_offset'length));
                                        when others => null;
                                    end case;
                                
                                -- SEW = 16 bits --
                                when "001" =>
                                    -- 16 bits Index Extraction Logic --
                                    case index_16bits is
                                        when 0 => addr_offset := std_ulogic_vector(resize(unsigned(index_map(index_wpos)(15 downto 0)),  addr_offset'length));
                                        when 1 => addr_offset := std_ulogic_vector(resize(unsigned(index_map(index_wpos)(31 downto 16)), addr_offset'length));
                                        when others => null;
                                    end case;
                                
                                -- SEW = 32 bits --
                                when "010"  => addr_offset := std_ulogic_vector(resize(unsigned(index_map(index_wpos)(31 downto 0)), addr_offset'length));
                                
                                -- SEW INVALID --
                                when others => addr_offset := (others => '0');
                            end case;
                            addr_src := resize(unsigned(base_addr), addr_src'length);
                        when others => null;
                    end case;

                    -- Address Update --
                    nxt_addr := signed(addr_src) + resize(signed(addr_offset), nxt_addr'length);
                    mem_addr <= std_ulogic_vector(nxt_addr(nxt_addr'length-1 downto 0));

                when STORE_EXEC =>
                    -- Memory Request ACK --
                    if (mem_ack = '1') then
                        -- If all vector elements have been stored --
                        if (elem_counter = num_elems) then
                            -- If all V-regs in the V-group have been processed --
                            if (mul_counter = lmul_i) then
                                state        <= FINISH_LSU;
                                elem_counter <= (others => '0');
                                mul_counter  <= (others => '0');
                                index_bpos   <= (others => '0');
                            else
                                state        <= READ_VRF;
                                elem_counter <= (others => '0');
                                mul_counter  <= std_ulogic_vector(unsigned(mul_counter) + 1);
                                index_bpos   <= (others => '0');
                                vrf_rptr     <= std_ulogic_vector(unsigned(vrf_rptr) + 1);
                            end if;
                        else
                            state        <= UPDATE_ADDR;
                            elem_counter <= std_ulogic_vector(unsigned(elem_counter) + 1);
                            -- If operation mode is indexed, increment Index Byte Offset... Gating added for Dynamic Power Consumption --
                            if (mop = "01") or (mop = "11") then
                                case index_eew is
                                    when "000"  => index_boffset := 1;
                                    when "001"  => index_boffset := 2;
                                    when "010"  => index_boffset := 4;
                                    when others => index_boffset := 0;
                                end case;
                                index_bpos <= std_ulogic_vector(unsigned(index_bpos) + index_boffset);
                            end if;
                        end if;
                    end if;

                when FINISH_LSU =>
                    state <= IDLE;

                when others => null;
            end case;
        end if;
    end process;

    --------------------------------------------------
    --- V-LSU State Machine => Combinational Logic ---
    --------------------------------------------------
    process(all) begin
        case state is
            when READ_VRF =>
                vlsu_to_vrf.vs2      <= lumop_off;
                vlsu_to_vrf.vs1      <= (others => '0');
                vlsu_to_vrf.vd       <= vrf_rptr;
                vlsu_to_vrf.byte_en  <= (others => '0');
                vlsu_to_vrf.result   <= (others => '0');
        end case;
    end process;

end architecture neorv32_lsu_rtl;