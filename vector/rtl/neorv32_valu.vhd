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
    signal op2_i : std_ulogic_vector(VLEN-1 downto 0);
    signal op1_i : std_ulogic_vector(VLEN-1 downto 0);
    signal op0_i : std_ulogic_vector(VLEN-1 downto 0);

    -- SUM/SUB Operation Signals --
    signal vcarry    : std_ulogic_vector((VLEN/8)-1 downto 0);
    signal add_temp  : std_ulogic_vector((VLEN-1)+(VLEN/8) downto 0);
    signal add_final : std_ulogic_vector(VLEN-1 downto 0);

    -- INT-EXT Operation Signals --
    type extended_array is array (7 downto 0) of std_ulogic_vector(VLEN-1 downto 0);
    signal extended : extended_array;

begin

    --------------------------------------
    -- ALU Internal Operands Definition --
    --------------------------------------
    process(all) begin
        -- ADD/SUB --
        if (alu_id = valu_add) or (alu_id = valu_sub) then
            op2_i   <= op2;
            op1_i   <= op1;
            op0_i   <= op0;
            alu_out <= add_final;
        -- REVERSE SUB --
        elsif (alu_id = valu_rsub) then
            op2_i   <= op1;
            op1_i   <= op2;
            op0_i   <= op0;
            alu_out <= add_final;
        -- UNSUPPORTED INSTRUCTION --
        else
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
            add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op2_i(8*ii+7 downto 8*ii)), 9) + resize(unsigned(op1_i(8*ii+7 downto 8*ii)), 9)) when (alu_id = valu_add) else
                                            std_ulogic_vector(resize(unsigned(op2_i(8*ii+7 downto 8*ii)), 9) - resize(unsigned(op1_i(8*ii+7 downto 8*ii)), 9));
        else generate
            add_temp(9*ii+8 downto 9*ii) <= std_ulogic_vector(resize(unsigned(op2_i(8*ii+7 downto 8*ii)), 9) + resize(unsigned(op1_i(8*ii+7 downto 8*ii)), 9) + vcarry(ii-1)) when (alu_id = valu_add) else
                                            std_ulogic_vector(resize(unsigned(op2_i(8*ii+7 downto 8*ii)), 9) - resize(unsigned(op1_i(8*ii+7 downto 8*ii)), 9) + vcarry(ii-1));
        end generate GEN_ADD_TEMP;

        -- Final ADD result --
        add_final(8*ii+7 downto 8*ii) <= add_temp(9*ii+7 downto 9*ii);
    end generate SUM_GENERATE;

    -------------------
    -- INT-EXT logic --
    -------------------
    INT_EXT_GENERATE : for ii in 0 to ((VLEN / 8) - 1) generate
        process(all) begin
            -- INT-EXT: SEW/2 to SEW
            if ((alu_id = valu_zext_vf2) or (alu_id = valu_sext_vf2)) then
                -- VSEW = 16 bits --
                if (vsew = "001") then
                    extended(ii mod VLEN)(8*ii+7 downto 8*ii) <= op2(8*(ii/2)+7 downto 8*(ii/2)) when ((ii mod 2) = 0)         else 
                                                                 (others => '0')                 when (alu_id = valu_zext_vf2) else
                                                                 (others => '1')                 when (alu_id = valu_sext_vf2) else;
                -- VSEW = 32 bits --
                elsif (vsew = "010") then
                    extended(ii mod VLEN)(8*ii+7 downto 8*ii) <= op2(8*(ii/2)+7     downto 8*(ii/2))     when ((ii   mod 4) = 0)       else
                                                                 op2(8*((ii+1)/2)+7 downto 8*((ii+1)/2)) when ((ii-1 mod 4) = 0)       else
                                                                 (others => '0')                         when (alu_id = valu_zext_vf2) else
                                                                 (others => '1')                         when (alu_id = valu_sext_vf2) else;
                -- VSEW = 64 bits --
                elsif (vsew = "011") then
                    extended(ii mod VLEN)(8*ii+7 downto 8*ii) <= op2(8*(ii/2)+7     downto 8*(ii/2))     when ((ii   mod 8) = 0)       else
                                                                 op2(8*((ii+1)/2)+7 downto 8*((ii+1)/2)) when ((ii-1 mod 8) = 0)       else
                                                                 op2(8*((ii+2)/2)+7 downto 8*((ii+2)/2)) when ((ii-2 mod 8) = 0)       else
                                                                 op2(8*((ii+3)/2)+7 downto 8*((ii+3)/2)) when ((ii-3 mod 8) = 0)       else
                                                                 (others => '0')                         when (alu_id = valu_zext_vf2) else
                                                                 (others => '1')                         when (alu_id = valu_sext_vf2) else;
                -- UNSUPPORTED VSEW --
                else
                    extended(ii mod VLEN)(8*ii+7 downto 8*ii) <= (others <= '0');
                end if;
            end if;

            -- INT-EXT: SEW/4 to SEW
            if ((alu_id = valu_zext_vf4) or (alu_id = valu_sext_vf4)) then
                -- VSEW = 32 bits --
                if (vsew = "010") then
                    extended(ii mod VLEN)(8*ii+7 downto 8*ii) <= op2(8*(ii/4)+7 downto 8*(ii/4)) when ((ii mod 4) = 0)         else 
                                                                 (others => '0')                 when (alu_id = valu_zext_vf4) else
                                                                 (others => '1')                 when (alu_id = valu_sext_vf4) else;
                -- VSEW = 64 bits --
                elsif (vsew = "011") then
                    extended(ii mod VLEN)(8*ii+7 downto 8*ii) <= op2(8*(ii/4)+7     downto 8*(ii/4))     when ((ii   mod 8) = 0)       else
                                                                 op2(8*((ii+3)/4)+7 downto 8*((ii+3)/4)) when ((ii-1 mod 8) = 0)       else
                                                                 (others => '0')                         when (alu_id = valu_zext_vf4) else
                                                                 (others => '1')                         when (alu_id = valu_sext_vf4) else;
                -- UNSUPPORTED VSEW --
                else
                    extended(ii mod VLEN)(8*ii+7 downto 8*ii) <= (others <= '0');
                end if;
            end if;

            -- INT-EXT: SEW/8 to SEW
            if ((alu_id = valu_zext_vf8) or (alu_id = valu_sext_vf8)) then
                -- VSEW = 64 bits --
                if (vsew = "011") then
                    extended(ii mod VLEN)(8*ii+7 downto 8*ii) <= op2(8*(ii/8)+7 downto 8*(ii/8)) when ((ii mod 16) = 0) else
                                                                 (others => '0')                 when (alu_id = valu_zext_vf8) else
                                                                 (others => '1')                 when (alu_id = valu_sext_vf8) else;
                -- UNSUPPORTED VSEW --
                else
                    extended(ii mod VLEN)(8*ii+7 downto 8*ii) <= (others => '0');
                end if;
            end if;
        end process;
    end generate INT_EXT_GENERATE;

end neorv32_valu_rtl;
