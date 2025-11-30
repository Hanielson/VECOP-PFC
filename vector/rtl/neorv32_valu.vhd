library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.neorv32_vpackage.all;

entity neorv32_valu is
    generic(
        VLEN : natural := 256;
        XLEN : natural := 32
    );
    port(
        -- Vector Operands --
        op2     : in std_ulogic_vector(VLEN-1 downto 0);
        op1     : in std_ulogic_vector(VLEN-1 downto 0);
        op0     : in std_ulogic_vector(VLEN-1 downto 0);
        -- ALU Operation ID --
        alu_id  : in std_ulogic_vector(7 downto 0);
        -- Vector Multiplier --
        vlmul   : in std_ulogic_vector(2 downto 0);
        -- Vector Mask --
        vmask   : in std_ulogic_vector(XLEN-1 downto 0);
        -- Vector Selected Element Width --
        vsew    : in std_ulogic_vector(2 downto 0);
        -- Narrow/Widen Operation Indication --
        narrow  : in std_ulogic;
        widen   : in std_ulogic;

        -- ALU Result --
        alu_out : out std_ulogic_vector(VLEN-1 downto 0)
    );
end neorv32_valu;

architecture neorv32_valu_rtl of neorv32_valu is
    
    -- Internal Vector Operands --
    signal op2_i     : std_ulogic_vector(VLEN-1 downto 0);
    signal op1_i     : std_ulogic_vector(VLEN-1 downto 0);
    signal op0_i     : std_ulogic_vector(VLEN-1 downto 0);
    signal alu_out_i : std_ulogic_vector((8*VLEN)-1 downto 0);
    signal vsew_i    : std_ulogic_vector(2 downto 0);

    -- SUM/SUB Operation Signals --
    signal vcarry    : std_ulogic_vector((VLEN/8)-1 downto 0);
    signal add_temp  : std_ulogic_vector((VLEN-1)+(VLEN/8) downto 0);
    signal add_final : std_ulogic_vector(VLEN-1 downto 0);

    -- INT-EXT Operation Signals --
    signal ext16     : std_ulogic_vector(VLEN-1 downto 0);
    signal ext32     : std_ulogic_vector(VLEN-1 downto 0);

    -- BITWISE Operation Signals --
    signal logic_final : std_ulogic_vector(VLEN-1 downto 0);

    -- SINGLE-WIDTH Signals --
    signal sew8_out  : std_ulogic_vector(VLEN-1 downto 0);
    signal sew16_out : std_ulogic_vector(VLEN-1 downto 0);
    signal sew32_out : std_ulogic_vector(VLEN-1 downto 0);

begin

    --------------------------------------
    -- ALU Internal Operands Definition --
    --------------------------------------
    process(all) begin
        -- ADD/SUB --
        if (alu_id = valu_add) or (alu_id = valu_sub) then
            vsew_i  <= vsew;
            op2_i   <= op2;
            op1_i   <= op1;
            op0_i   <= op0;
            alu_out <= add_final;
        -- REVERSE SUB --
        elsif (alu_id = valu_rsub) then
            vsew_i  <= vsew;
            op2_i   <= op1;
            op1_i   <= op2;
            op0_i   <= op0;
            alu_out <= add_final;
        -- REVERSE SUB --
        elsif (alu_id = valu_rsub) then
            vsew_i  <= vsew;
            op2_i   <= op1;
            op1_i   <= op2;
            op0_i   <= op0;
            alu_out <= add_final;
        -- BITWISE LOGICAL --
        elsif (alu_id = valu_and) or (alu_id = valu_or) or (alu_id = valu_xor) then
            vsew_i  <= vsew;
            op2_i   <= op2;
            op1_i   <= op1;
            op0_i   <= op0;
            alu_out <= logic_final;
        -- UNSUPPORTED INSTRUCTION --
        else
            vsew_i  <= (others => '0');
            op2_i   <= (others => '0');
            op1_i   <= (others => '0');
            op0_i   <= (others => '0');
            alu_out <= (others => '0');
        end if;
    end process;

    ------------------------------------------------
    -- SUM logic for vadd/vsub/vrsub instructions --
    ------------------------------------------------
    SUM_GENERATE : for ii in 0 to ((VLEN / 8) - 1) generate
        -- Process to generate carry bits for SUM operation --
        process(all) begin
            -- If it's a multiple of 64 bits (done in case of expansion) --
            if ((ii mod 8) = 7) then
                vcarry(ii) <= '0';
            -- If not met previous conditions and is multiple of 32 bits --
            elsif ((ii mod 4) = 3) then
                vcarry(ii) <= '0' when ((vsew = "010") or (vsew = "001") or (vsew = "000")) else add_temp(9*ii+8);
            -- If not met previous conditions and is multiple of 16 bits --
            elsif ((ii mod 2) = 1) then
                vcarry(ii) <= '0' when ((vsew = "001") or (vsew = "000")) else add_temp(9*ii+8);
            -- If not met previous conditions, then for each byte --
            else
                vcarry(ii) <= '0' when (vsew = "000") else add_temp(9*ii+8);
            end if;
        end process;

        -- Intermediary ADD result to extract carry bit --
        GEN_ADD_TEMP: if (ii = 0) generate
            add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op2_i(8*ii+7 downto 8*ii)), 9) + resize(unsigned(op1_i(8*ii+7 downto 8*ii)), 9)) when (alu_id = valu_add)  else
                                            std_ulogic_vector(resize(unsigned(op2_i(8*ii+7 downto 8*ii)), 9) - resize(unsigned(op1_i(8*ii+7 downto 8*ii)), 9));
        else generate
            add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op2_i(8*ii+7 downto 8*ii)), 9) + resize(unsigned(op1_i(8*ii+7 downto 8*ii)), 9) + vcarry(ii-1)) when (alu_id = valu_add) else
                                            std_ulogic_vector(resize(unsigned(op2_i(8*ii+7 downto 8*ii)), 9) - resize(unsigned(op1_i(8*ii+7 downto 8*ii)), 9) + vcarry(ii-1));
        end generate GEN_ADD_TEMP;

        -- Final ADD result --
        add_final(8*ii+7 downto 8*ii) <= add_temp(9*ii+7 downto 9*ii);
    end generate SUM_GENERATE;

    -------------------------------------
    -- INT-EXT logic for SEW = 16 bits --
    -------------------------------------
    INT_EXT_16b : for ii in 0 to ((VLEN / 16) - 1) generate
        process(all) 
            variable offset_8b_1 : natural;
            variable offset_8b_2 : natural;
        begin
            offset_8b_1 := 8*ii;
            offset_8b_2 := 8*ii+(VLEN/16);

            if (alu_op = valu_zext_vf2) then
                if (alu_cyc = "000") then
                    ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(unsigned(op2(offset_8b_1+7 downto offset_8b_1)), 16));
                elsif (alu_cyc = "001") then
                    ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(unsigned(op2(offset_8b_2+7 downto offset_8b_2)), 16));
                else
                    ext16(16*ii+15 downto 16*ii) <= (others => '0');
                end if;
            elsif (alu_op = valu_sext_vf2) then
                if (alu_cyc = "000") then
                    ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(signed(op2(offset_8b_1+7 downto offset_8b_1)), 16));
                elsif (alu_cyc = "001") then
                    ext16(16*ii+15 downto 16*ii) <= std_ulogic_vector(resize(signed(op2(offset_8b_2+7 downto offset_8b_2)), 16));
                else
                    ext16(16*ii+15 downto 16*ii) <= (others => '0');
                end if;
            else
                ext16(16*ii+15 downto 16*ii) <= (others => '0');
            end if;
        end process;
    end generate INT_EXT_16b;

    -------------------------------------
    -- INT-EXT logic for SEW = 32 bits --
    -------------------------------------
    INT_EXT_32b : for ii in 0 to ((VLEN / 32) - 1) generate
        process(all) 
            variable offset_16b_1 : natural;
            variable offset_16b_2 : natural;

            variable offset_8b_1 : natural;
            variable offset_8b_2 : natural;
            variable offset_8b_3 : natural;
            variable offset_8b_4 : natural;
        begin
            offset_16b_1 := 16*ii;
            offset_16b_2 := 16*(ii+(VLEN/32));

            offset_8b_1 := 8*ii;
            offset_8b_2 := 8*(ii+(VLEN/32));
            offset_8b_3 := 8*(ii+(2*(VLEN/32)));
            offset_8b_4 := 8*(ii+(3*(VLEN/32)));

            -- INT-EXT: SEW/2 to SEW --
            if (alu_op = valu_zext_vf2) then
                if (alu_cyc = "000") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(op2(offset_16b_1+15 downto offset_16b_1)), 32));
                elsif (alu_cyc = "001") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(op2(offset_16b_2+15 downto offset_16b_2)), 32));
                else
                    ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end if;
            elsif (alu_op = valu_sext_vf2) then
                if (alu_cyc = "000") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(op2(offset_16b_1+15 downto offset_16b_1)), 32));
                elsif (alu_cyc = "001") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(op2(offset_16b_2+15 downto offset_16b_2)), 32));
                else
                    ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end if;

            -- INT-EXT: SEW/4 to SEW --
            elsif (alu_op = valu_zext_vf4) then
                if (alu_cyc = "000") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(op2(offset_8b_1+7 downto offset_8b_1)), 32));
                elsif (alu_cyc = "001") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(op2(offset_8b_2+7 downto offset_8b_2)), 32));
                elsif (alu_cyc = "010") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(op2(offset_8b_3+7 downto offset_8b_3)), 32));
                elsif (alu_cyc = "011") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(unsigned(op2(offset_8b_4+7 downto offset_8b_4)), 32));
                else
                    ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end if;
            elsif (alu_op = valu_sext_vf4) then
                if (alu_cyc = "000") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(op2(offset_8b_1+7 downto offset_8b_1)), 32));
                elsif (alu_cyc = "001") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(op2(offset_8b_2+7 downto offset_8b_2)), 32));
                elsif (alu_cyc = "010") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(op2(offset_8b_3+7 downto offset_8b_3)), 32));
                elsif (alu_cyc = "011") then
                    ext32(32*ii+31 downto 32*ii) <= std_ulogic_vector(resize(signed(op2(offset_8b_4+7 downto offset_8b_4)), 32));
                else
                    ext32(32*ii+31 downto 32*ii) <= (others => '0');
                end if;
            -- INT-EXT: UNSUPPORTED OPERATION --
            else
                ext32(32*ii+31 downto 32*ii) <= (others => '0');
            end if;
        end process;
    end generate INT_EXT_32b;

    --------------------------------------------------
    -- BITWISE logic for vand/vor/vxor instructions --
    --------------------------------------------------
    LOGIC_PROCESS : process(all) 
    begin
        if (alu_id = valu_and) then
            logic_final <= op2_i and op1_i;
        elsif (alu_id = valu_or) then
            logic_final <= op2_i or op1_i;
        elsif (alu_id = valu_xor) then
            logic_final <= op2_i xor op1_i;
        else
            logic_final <= (others => '0');
        end if;        
    end generate LOGIC_PROCESS;

    ----------------------------------------------------------
    -- DATAPATH for SEW = 8 bits SINGLE-WIDTH instructions --
    ----------------------------------------------------------
    SINGLE_SHIFT_SEW8: for byte in 0 to ((VLEN / 8) - 1) generate
        if (alu_id = valu_sll) then
            sew8_out(8*byte+7 downto 8*byte) <= op2_i(8*byte+7 downto 8*byte) sll unsigned(op1_i);
        elsif (alu_id = valu_srl ) then
            sew8_out(8*byte+7 downto 8*byte) <= op2_i(8*byte+7 downto 8*byte) srl unsigned(op1_i);
        elsif (alu_id = valu_sra) then
            sew8_out(8*byte+7 downto 8*byte) <= op2_i(8*byte+7 downto 8*byte) sra unsigned(op1_i);
        else
            sew8_out(8*byte+7 downto 8*byte) <= (others => '0');
        end if;
    end generate SINGLE_SHIFT_SEW8;

    ----------------------------------------------------------
    -- DATAPATH for SEW = 16 bits SINGLE-WIDTH instructions --
    ----------------------------------------------------------
    SINGLE_SHIFT_SEW16: for byte2 in 0 to ((VLEN / 16) - 1) generate
        if (alu_id = valu_sll) then
            sew16_out(16*byte2+15 downto 16*byte2) <= op2_i(16*byte2+15 downto 16*byte2) sll unsigned(op1_i);
        elsif (alu_id = valu_srl ) then
            sew16_out(16*byte2+15 downto 16*byte2) <= op2_i(16*byte2+15 downto 16*byte2) srl unsigned(op1_i);
        elsif (alu_id = valu_sra) then
            sew16_out(16*byte2+15 downto 16*byte2) <= op2_i(16*byte2+15 downto 16*byte2) sra unsigned(op1_i);
        else
            sew16_out(16*byte2+15 downto 16*byte2) <= (others => '0');
        end if;
    end generate SINGLE_SHIFT_SEW16;

    ----------------------------------------------------------
    -- DATAPATH for SEW = 32 bits SINGLE-WIDTH instructions --
    ----------------------------------------------------------
    SINGLE_SHIFT_SEW32: for byte4 in 0 to ((VLEN / 32) - 1) generate
        if (alu_id = valu_sll) then
            sew32_out(32*byte4+31 downto 32*byte4) <= op2_i(32*byte4+31 downto 32*byte4) sll unsigned(op1_i);
        elsif (alu_id = valu_srl ) then
            sew32_out(32*byte4+31 downto 32*byte4) <= op2_i(32*byte4+31 downto 32*byte4) srl unsigned(op1_i);
        elsif (alu_id = valu_sra) then
            sew32_out(32*byte4+31 downto 32*byte4) <= op2_i(32*byte4+31 downto 32*byte4) sra unsigned(op1_i);
        else
            sew32_out(32*byte4+31 downto 32*byte4) <= (others => '0');
        end if;
    end generate SINGLE_SHIFT_SEW32;

end neorv32_valu_rtl;