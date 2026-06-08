--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2009-2013 Joris van Rantwijk
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- Deterministic trace bench for VHDL/Verilog parity comparison.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
use work.spwpkg.all;

entity streamtest_trace_tb is
end entity;

architecture tb_arch of streamtest_trace_tb is

    constant sys_clock_freq: real := 20.0e6;

    component streamtest is
        generic (
            sysfreq:    real;
            txclkfreq:  real;
            tickdiv:    integer range 12 to 24 := 20;
            rximpl:     spw_implementation_type := impl_generic;
            rxchunk:    integer range 1 to 4 := 1;
            tximpl:     spw_implementation_type := impl_generic;
            rxfifosize_bits: integer range 6 to 14 := 11;
            txfifosize_bits: integer range 2 to 14 := 11 );
        port (
            clk:        in  std_logic;
            rxclk:      in  std_logic;
            txclk:      in  std_logic;
            rst:        in  std_logic;
            linkstart:  in  std_logic;
            autostart:  in  std_logic;
            linkdisable: in std_logic;
            senddata:   in  std_logic;
            sendtick:   in  std_logic;
            txdivcnt:   in  std_logic_vector(7 downto 0);
            linkstarted: out std_logic;
            linkconnecting: out std_logic;
            linkrun:    out std_logic;
            linkerror:  out std_logic;
            gotdata:    out std_logic;
            dataerror:  out std_logic;
            tickerror:  out std_logic;
            spw_di:     in  std_logic;
            spw_si:     in  std_logic;
            spw_do:     out std_logic;
            spw_so:     out std_logic );
    end component;

    signal sysclk:      std_logic := '0';
    signal s_loopback:  std_logic := '1';
    signal s_nreceived: integer := 0;
    signal s_rst:       std_logic := '1';
    signal s_linkstart: std_logic := '0';
    signal s_autostart: std_logic := '0';
    signal s_linkdisable: std_logic := '0';
    signal s_divcnt:    std_logic_vector(7 downto 0) := x"01";
    signal s_linkrun:   std_logic;
    signal s_linkerror: std_logic;
    signal s_gotdata:   std_logic;
    signal s_dataerror: std_logic;
    signal s_tickerror: std_logic;
    signal s_spwdi:     std_logic;
    signal s_spwsi:     std_logic;
    signal s_spwdo:     std_logic;
    signal s_spwso:     std_logic;

    procedure print_trace(
        constant phase: in string;
        constant rxcount: in integer;
        constant linkrun: in std_logic;
        constant linkerror: in std_logic;
        constant dataerror: in std_logic;
        constant tickerror: in std_logic) is
        variable vline: line;
    begin
        write(vline, string'("TRACE phase="));
        write(vline, phase);
        write(vline, string'(" rx="));
        write(vline, rxcount);
        write(vline, string'(" run="));
        write(vline, std_logic'image(linkrun)(2));
        write(vline, string'(" linkerr="));
        write(vline, std_logic'image(linkerror)(2));
        write(vline, string'(" dataerr="));
        write(vline, std_logic'image(dataerror)(2));
        write(vline, string'(" tickerr="));
        write(vline, std_logic'image(tickerror)(2));
        writeline(output, vline);
    end procedure;

begin

    streamtest_inst: streamtest
        generic map (
            sysfreq     => sys_clock_freq,
            txclkfreq   => sys_clock_freq,
            tickdiv     => 12,
            rximpl      => impl_generic,
            rxchunk     => 1,
            tximpl      => impl_generic,
            rxfifosize_bits => 9,
            txfifosize_bits => 8 )
        port map (
            clk         => sysclk,
            rxclk       => sysclk,
            txclk       => sysclk,
            rst         => s_rst,
            linkstart   => s_linkstart,
            autostart   => s_autostart,
            linkdisable => s_linkdisable,
            senddata    => '1',
            sendtick    => '1',
            txdivcnt    => s_divcnt,
            linkstarted => open,
            linkconnecting => open,
            linkrun     => s_linkrun,
            linkerror   => s_linkerror,
            gotdata     => s_gotdata,
            dataerror   => s_dataerror,
            tickerror   => s_tickerror,
            spw_di      => s_spwdi,
            spw_si      => s_spwsi,
            spw_do      => s_spwdo,
            spw_so      => s_spwso );

    s_spwdi <= s_spwdo when (s_loopback = '1') else '0';
    s_spwsi <= s_spwso when (s_loopback = '1') else '0';

    process is
    begin
        sysclk <= '0';
        wait for 25 ns;
        sysclk <= '1';
        wait for 25 ns;
    end process;

    process is
    begin
        wait until rising_edge(sysclk);
        if s_gotdata = '1' then
            s_nreceived <= s_nreceived + 1;
        end if;
        assert s_dataerror = '0' report "Detected data error";
        assert s_tickerror = '0' report "Detected time code error";
        if s_loopback = '1' then
            assert s_linkerror = '0' report "Unexpected link error";
        end if;
    end process;

    process
        procedure wait_cycles(constant count: in natural) is
        begin
            for i in 1 to count loop
                wait until rising_edge(sysclk);
            end loop;
        end procedure;

        procedure wait_run is
            variable timeout: natural := 20000;
        begin
            while s_linkrun /= '1' and timeout > 0 loop
                wait until rising_edge(sysclk);
                timeout := timeout - 1;
            end loop;
            assert timeout > 0 report "Link failed to run";
        end procedure;
    begin
        wait_cycles(8);
        s_rst <= '0';
        s_linkstart <= '1';
        wait_run;
        print_trace("RUN", s_nreceived, s_linkrun, s_linkerror, s_dataerror, s_tickerror);

        wait_cycles(10000);
        print_trace("DIV1", s_nreceived, s_linkrun, s_linkerror, s_dataerror, s_tickerror);

        s_divcnt <= x"02";
        wait_cycles(3000);
        print_trace("DIV2", s_nreceived, s_linkrun, s_linkerror, s_dataerror, s_tickerror);

        s_divcnt <= x"03";
        wait_cycles(3000);
        print_trace("DIV3", s_nreceived, s_linkrun, s_linkerror, s_dataerror, s_tickerror);

        s_linkdisable <= '1';
        s_divcnt <= x"01";
        wait_cycles(1000);
        print_trace("DISABLED", s_nreceived, s_linkrun, s_linkerror, s_dataerror, s_tickerror);

        s_linkdisable <= '0';
        wait_run;
        print_trace("REENABLED", s_nreceived, s_linkrun, s_linkerror, s_dataerror, s_tickerror);

        s_loopback <= '0';
        wait_cycles(1000);
        s_loopback <= '1';
        wait_run;
        print_trace("RECONNECTED", s_nreceived, s_linkrun, s_linkerror, s_dataerror, s_tickerror);

        wait_cycles(3000);
        print_trace("FINAL", s_nreceived, s_linkrun, s_linkerror, s_dataerror, s_tickerror);
        report "PASS: streamtest trace VHDL test bench";
        stop;
        wait;
    end process;

end architecture tb_arch;
