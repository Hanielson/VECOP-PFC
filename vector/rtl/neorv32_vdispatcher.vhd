library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.neorv32_vpackage.all;

entity neorv32_vdispatcher is
    port(
        -- Clock and Reset --
        clk         : in std_ulogic;
        rst         : in std_ulogic;

        -- Inputs from Scalar Core --
        vinst_in       : in std_ulogic_vector(XLEN-1 downto 0);
        scal2_in       : in std_ulogic_vector(XLEN-1 downto 0);
        scal1_in       : in std_ulogic_vector(XLEN-1 downto 0);
        vinst_valid_in : in std_ulogic;

        -- Control/Status Registers --
        vcsr : in vcsr_t;
        
        -- Back-End Control/Response Signals --
        vback_resp : in vback_resp_if;
        vback_ctrl : out vback_ctrl_if;

        -- VI-Queue Status --
        viq_full  : out std_ulogic;
        viq_empty : out std_ulogic;

        -- Outputs to Scalar Core --
        cp_result   : out std_ulogic_vector(XLEN-1 downto 0);
        cp_valid    : out std_ulogic
    );
end neorv32_vdispatcher;

architecture neorv32_vdispatcher_rtl of neorv32_vdispatcher is
    ------------------------------
    --- Component Declarations ---
    ------------------------------
    component neorv32_frontend is
        port(
            clk             : in std_ulogic;
            rst             : in std_ulogic;
            vinst_in        : in std_ulogic_vector(XLEN-1 downto 0);
            scal2_in        : in std_ulogic_vector(XLEN-1 downto 0);
            scal1_in        : in std_ulogic_vector(XLEN-1 downto 0);
            vinst_valid_in  : in std_ulogic;
            vinst_out       : out std_ulogic_vector(XLEN-1 downto 0);
            scal2_out       : out std_ulogic_vector(XLEN-1 downto 0);
            scal1_out       : out std_ulogic_vector(XLEN-1 downto 0);
            vinst_valid_out : out std_ulogic;
            cp_result       : out std_ulogic_vector(XLEN-1 downto 0);
            cp_valid        : out std_ulogic
        );
    end component neorv32_frontend;

    component neorv32_viq is
        port(
            clk       : in std_ulogic;
            rst       : in std_ulogic;
            vinst_in  : in std_ulogic_vector(XLEN-1 downto 0);
            scal2_in  : in std_ulogic_vector(XLEN-1 downto 0);
            scal1_in  : in std_ulogic_vector(XLEN-1 downto 0);
            valid_in  : in std_ulogic;
            vq_next   : in std_ulogic;
            vinst_out : out std_ulogic_vector(XLEN-1 downto 0);
            scal2_out : out std_ulogic_vector(XLEN-1 downto 0);
            scal1_out : out std_ulogic_vector(XLEN-1 downto 0);
            valid_out : out std_ulogic;
            vq_full   : out std_ulogic;
            vq_empty  : out std_ulogic
        );
    end component neorv32_viq;

    component neorv32_backend is
        port(
            clk        : in std_ulogic;
            rst        : in std_ulogic;
            viq_inst   : in std_ulogic_vector(XLEN-1 downto 0);
            viq_scal2  : in std_ulogic_vector(XLEN-1 downto 0);
            viq_scal1  : in std_ulogic_vector(XLEN-1 downto 0);
            viq_valid  : in std_ulogic;
            viq_nxt    : out std_ulogic;
            vcsr       : in vcsr_t;
            vback_resp : in vback_resp_if;
            vback_ctrl : out vback_ctrl_if
        );
    end component neorv32_backend;

    ---------------------------
    --- Signal Declarations ---
    ---------------------------
    signal viq_inst_in       : std_ulogic_vector(XLEN-1 downto 0);
    signal viq_inst_valid_in : std_ulogic;
    signal viq_scal2_in      : std_ulogic_vector(XLEN-1 downto 0);
    signal viq_scal1_in      : std_ulogic_vector(XLEN-1 downto 0);

    signal viq_inst_out       : std_ulogic_vector(XLEN-1 downto 0);
    signal viq_inst_valid_out : std_ulogic;
    signal viq_scal2_out      : std_ulogic_vector(XLEN-1 downto 0);
    signal viq_scal1_out      : std_ulogic_vector(XLEN-1 downto 0);

    signal viq_nxt   : std_ulogic;

begin

    frontend: entity work.neorv32_frontend port map (
        clk             => clk,
        rst             => rst,
        vinst_in        => vinst_in,
        scal2_in        => scal2_in,
        scal1_in        => scal1_in,
        vinst_valid_in  => vinst_valid_in,
        vinst_out       => viq_inst_in,
        scal2_out       => viq_scal2_in,
        scal1_out       => viq_scal1_in,
        vinst_valid_out => viq_inst_valid_in,
        cp_result       => cp_result,
        cp_valid        => cp_valid
    );

    viq: entity work.neorv32_viq port map (
        clk       => clk,
        rst       => rst,
        vinst_in  => viq_inst_in,
        scal2_in  => viq_scal2_in,
        scal1_in  => viq_scal1_in,
        valid_in  => viq_inst_valid_in,
        vq_next   => viq_nxt,
        vinst_out => viq_inst_out,
        scal2_out => viq_scal2_out,
        scal1_out => viq_scal1_out,
        valid_out => viq_inst_valid_out,
        vq_full   => viq_full,
        vq_empty  => viq_empty
    );

    backend: entity work.neorv32_backend port map (
        clk        => clk,
        rst        => rst,
        viq_inst   => viq_inst_out,
        viq_scal2  => viq_scal2_out,
        viq_scal1  => viq_scal1_out,
        viq_valid  => viq_inst_valid_out,
        viq_nxt    => viq_nxt,
        vcsr       => vcsr,
        vback_ctrl => vback_ctrl,
        vback_resp => vback_resp
    );

end neorv32_vdispatcher_rtl;