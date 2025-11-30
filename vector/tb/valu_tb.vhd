library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.neorv32_vpackage.all;

use std.env.finish;

entity valu_tb is
end valu_tb;

architecture tb of valu_tb is

    component neorv32_valu is
        generic(
            VLEN : natural := 256;
            XLEN : natural := 32
        );
        port(
            op2     : in std_ulogic_vector(VLEN-1 downto 0);
            op1     : in std_ulogic_vector(VLEN-1 downto 0);
            op0     : in std_ulogic_vector(VLEN-1 downto 0);
            alu_id  : in std_ulogic_vector(7 downto 0);
            vlmul   : in std_ulogic_vector(2 downto 0);
            vmask   : in std_ulogic_vector(XLEN-1 downto 0);
            vsew    : in std_ulogic_vector(2 downto 0);
            narrow  : in std_ulogic;
            widen   : in std_ulogic;
            alu_out : out std_ulogic_vector(VLEN-1 downto 0)
        );
    end component neorv32_valu;

    signal VSEW    : std_ulogic_vector(2 downto 0);
    signal OP2     : std_ulogic_vector(255 downto 0);
    signal OP1     : std_ulogic_vector(255 downto 0);
    signal OP0     : std_ulogic_vector(255 downto 0);
    signal ALU_ID  : std_ulogic_vector(7 downto 0);
    signal ALU_OUT : std_ulogic_vector(255 downto 0);

begin

    valu: entity work.neorv32_valu port map(
        op2     => OP2,
        op1     => OP1,
        op0     => OP0,
        alu_id  => ALU_ID,
        vlmul   => (others => '0'),
        vmask   => (others => '0'),
        vsew    => VSEW,
        narrow  => '0',
        widen   => '0',
        alu_out => ALU_OUT
    );

    stimuli: process
    begin
        
        OP2 <= x"01ABCDEF01ABCDEF01ABCDEF01ABCDEF01ABCDEF01ABCDEF01ABCDEF01ABCDEF";
        OP1 <= x"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
        
        -- TEST ADD OPERATION --
        ALU_ID <= valu_add;
        VSEW <= "000";
        wait for 20 ns;
        VSEW <= "001";
        wait for 20 ns;
        VSEW <= "010";
        wait for 20 ns;
        VSEW <= "011";
        wait for 20 ns;

        -- TEST SUB OPERATION --
        ALU_ID <= valu_sub;
        VSEW <= "000";
        wait for 20 ns;
        VSEW <= "001";
        wait for 20 ns;
        VSEW <= "010";
        wait for 20 ns;
        VSEW <= "011";
        wait for 20 ns;

        -- TEST R-SUB OPERATION --
        ALU_ID <= valu_rsub;
        VSEW <= "000";
        wait for 20 ns;
        VSEW <= "001";
        wait for 20 ns;
        VSEW <= "010";
        wait for 20 ns;
        VSEW <= "011";
        wait for 20 ns;

        finish;

    end process;

end tb;
