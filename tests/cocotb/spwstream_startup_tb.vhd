-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- Minimal elaboration harness for the Bug 20 startup-rate guard. GHDL cannot
-- override a real-typed generic from the command line, so this wrapper takes an
-- integer sys_hz generic and converts it to the real sysfreq generic expected by
-- spwstream. All ports are tied off; only elaboration of the concurrent
-- startup-rate assertion in spwstream is exercised.

library ieee;
use ieee.std_logic_1164.all;
use work.spwpkg.all;

entity spwstream_startup_tb is
    generic ( sys_hz : integer := 20000000 );
end entity spwstream_startup_tb;

architecture tb of spwstream_startup_tb is
begin

    dut: entity work.spwstream
        generic map (
            sysfreq   => real(sys_hz),
            txclkfreq => real(sys_hz),
            rximpl    => impl_generic,
            tximpl    => impl_generic )
        port map (
            clk        => '0',
            rxclk      => '0',
            txclk      => '0',
            rst        => '1',
            autostart  => '0',
            linkstart  => '0',
            linkdis    => '0',
            txdivcnt   => (others => '0'),
            tick_in    => '0',
            ctrl_in    => (others => '0'),
            time_in    => (others => '0'),
            txwrite    => '0',
            txflag     => '0',
            txdata     => (others => '0'),
            txrdy      => open,
            txhalff    => open,
            tick_out   => open,
            ctrl_out   => open,
            time_out   => open,
            rxvalid    => open,
            rxhalff    => open,
            rxflag     => open,
            rxdata     => open,
            rxread     => '0',
            started    => open,
            connecting => open,
            running    => open,
            errdisc    => open,
            errpar     => open,
            erresc     => open,
            errcred    => open,
            spw_di     => '0',
            spw_si     => '0',
            spw_do     => open,
            spw_so     => open );

end architecture tb;
