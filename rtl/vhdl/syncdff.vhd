--
--  Double flip-flop synchronizer.
--
--  This entity is used to safely capture asynchronous signals.
--
--  An implementation may assign additional constraints to this entity
--  in order to reduce the probability of meta-stability issues.
--  For example, an extra tight timing constraint could be placed on
--  the data path from syncdff_ff1 to syncdff_ff2 to ensure that
--  meta-stability of ff1 is resolved before ff2 captures the signal.
--

library ieee;
use ieee.std_logic_1164.all;

entity syncdff is

    port (
        clk:        in  std_logic;          -- clock (destination domain)
        rst:        in  std_logic;          -- asynchronous reset, active-high
        di:         in  std_logic;          -- input data
        do:         out std_logic           -- output data
    );

end entity syncdff;

architecture syncdff_arch of syncdff is

    -- flip-flops
    signal syncdff_ff1: std_ulogic := '0';
    signal syncdff_ff2: std_ulogic := '0';

    -- Vendor-neutral clock-domain-crossing synchronizer attributes. Each tool
    -- honours the attributes it recognises and ignores the rest, so the same
    -- source builds correctly on Xilinx, Intel and Lattice flows. The intent is
    -- identical everywhere: keep both flip-flops, do not merge, replicate or
    -- retime them, do not pack them into a shift register (SRL), and keep their
    -- net names so the CDC timing constraints in constraints/ can find them.
    -- Replaces the previous Xilinx-XST-only RLOC/SHIFT_EXTRACT/KEEP set, which
    -- was not portable (and RLOC is rejected by newer Xilinx tools).

    -- Xilinx Vivado: mark the two-stage synchronizer chain.
    attribute ASYNC_REG: string;
    attribute ASYNC_REG of syncdff_ff1: signal is "TRUE";
    attribute ASYNC_REG of syncdff_ff2: signal is "TRUE";

    -- Synopsys Synplify (Lattice, Microchip): preserve and never pack to an SRL.
    attribute syn_preserve: boolean;
    attribute syn_preserve of syncdff_ff1: signal is true;
    attribute syn_preserve of syncdff_ff2: signal is true;
    attribute syn_srlstyle: string;
    attribute syn_srlstyle of syncdff_ff1: signal is "registers";
    attribute syn_srlstyle of syncdff_ff2: signal is "registers";

    -- Intel Quartus: keep the registers (no merge/retime/removal).
    attribute preserve: boolean;
    attribute preserve of syncdff_ff1: signal is true;
    attribute preserve of syncdff_ff2: signal is true;

    -- Generic / Vivado: keep the flip-flop nets for the timing constraints.
    attribute keep: string;
    attribute keep of syncdff_ff1: signal is "true";
    attribute keep of syncdff_ff2: signal is "true";

begin

    -- second flip-flop drives the output signal
    do <= syncdff_ff2;

    process (clk, rst) is
    begin
        if rst = '1' then
            -- asynchronous reset
            syncdff_ff1 <= '0';
            syncdff_ff2 <= '0';
        elsif rising_edge(clk) then
            -- data synchronization
            syncdff_ff1 <= di;
            syncdff_ff2 <= syncdff_ff1;
        end if;
    end process;

end architecture syncdff_arch;
