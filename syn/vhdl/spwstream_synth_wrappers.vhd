-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2009-2013 Joris van Rantwijk
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- Concrete synthesis wrappers for CI.

library ieee;
use ieee.std_logic_1164.all;
use work.spwpkg.all;

entity spwstream_synth_generic is
    port (
        clk:        in  std_logic;
        rxclk:      in  std_logic;
        txclk:      in  std_logic;
        rst:        in  std_logic;
        autostart:  in  std_logic;
        linkstart:  in  std_logic;
        linkdis:    in  std_logic;
        txdivcnt:   in  std_logic_vector(7 downto 0);
        tick_in:    in  std_logic;
        ctrl_in:    in  std_logic_vector(1 downto 0);
        time_in:    in  std_logic_vector(5 downto 0);
        txwrite:    in  std_logic;
        txflag:     in  std_logic;
        txdata:     in  std_logic_vector(7 downto 0);
        txrdy:      out std_logic;
        txhalff:    out std_logic;
        tick_out:   out std_logic;
        ctrl_out:   out std_logic_vector(1 downto 0);
        time_out:   out std_logic_vector(5 downto 0);
        rxvalid:    out std_logic;
        rxhalff:    out std_logic;
        rxflag:     out std_logic;
        rxdata:     out std_logic_vector(7 downto 0);
        rxread:     in  std_logic;
        started:    out std_logic;
        connecting: out std_logic;
        running:    out std_logic;
        errdisc:    out std_logic;
        errpar:     out std_logic;
        erresc:     out std_logic;
        errcred:    out std_logic;
        spw_di:     in  std_logic;
        spw_si:     in  std_logic;
        spw_do:     out std_logic;
        spw_so:     out std_logic
    );
end entity;

architecture wrapper of spwstream_synth_generic is
begin
    u_core: spwstream
        generic map (
            sysfreq         => 20.0e6,
            txclkfreq       => 20.0e6,
            rximpl          => impl_generic,
            rxchunk         => 1,
            tximpl          => impl_generic,
            rxfifosize_bits => 9,
            txfifosize_bits => 8 )
        port map (
            clk => clk, rxclk => rxclk, txclk => txclk, rst => rst,
            autostart => autostart, linkstart => linkstart, linkdis => linkdis,
            txdivcnt => txdivcnt, tick_in => tick_in, ctrl_in => ctrl_in,
            time_in => time_in, txwrite => txwrite, txflag => txflag,
            txdata => txdata, txrdy => txrdy, txhalff => txhalff,
            tick_out => tick_out, ctrl_out => ctrl_out, time_out => time_out,
            rxvalid => rxvalid, rxhalff => rxhalff, rxflag => rxflag,
            rxdata => rxdata, rxread => rxread, started => started,
            connecting => connecting, running => running, errdisc => errdisc,
            errpar => errpar, erresc => erresc, errcred => errcred,
            spw_di => spw_di, spw_si => spw_si, spw_do => spw_do,
            spw_so => spw_so );
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use work.spwpkg.all;

entity spwstream_synth_fast is
    port (
        clk:        in  std_logic;
        rxclk:      in  std_logic;
        txclk:      in  std_logic;
        rst:        in  std_logic;
        autostart:  in  std_logic;
        linkstart:  in  std_logic;
        linkdis:    in  std_logic;
        txdivcnt:   in  std_logic_vector(7 downto 0);
        tick_in:    in  std_logic;
        ctrl_in:    in  std_logic_vector(1 downto 0);
        time_in:    in  std_logic_vector(5 downto 0);
        txwrite:    in  std_logic;
        txflag:     in  std_logic;
        txdata:     in  std_logic_vector(7 downto 0);
        txrdy:      out std_logic;
        txhalff:    out std_logic;
        tick_out:   out std_logic;
        ctrl_out:   out std_logic_vector(1 downto 0);
        time_out:   out std_logic_vector(5 downto 0);
        rxvalid:    out std_logic;
        rxhalff:    out std_logic;
        rxflag:     out std_logic;
        rxdata:     out std_logic_vector(7 downto 0);
        rxread:     in  std_logic;
        started:    out std_logic;
        connecting: out std_logic;
        running:    out std_logic;
        errdisc:    out std_logic;
        errpar:     out std_logic;
        erresc:     out std_logic;
        errcred:    out std_logic;
        spw_di:     in  std_logic;
        spw_si:     in  std_logic;
        spw_do:     out std_logic;
        spw_so:     out std_logic
    );
end entity;

architecture wrapper of spwstream_synth_fast is
begin
    u_core: spwstream
        generic map (
            sysfreq         => 20.0e6,
            txclkfreq       => 80.0e6,
            rximpl          => impl_fast,
            rxchunk         => 4,
            tximpl          => impl_fast,
            rxfifosize_bits => 9,
            txfifosize_bits => 8 )
        port map (
            clk => clk, rxclk => rxclk, txclk => txclk, rst => rst,
            autostart => autostart, linkstart => linkstart, linkdis => linkdis,
            txdivcnt => txdivcnt, tick_in => tick_in, ctrl_in => ctrl_in,
            time_in => time_in, txwrite => txwrite, txflag => txflag,
            txdata => txdata, txrdy => txrdy, txhalff => txhalff,
            tick_out => tick_out, ctrl_out => ctrl_out, time_out => time_out,
            rxvalid => rxvalid, rxhalff => rxhalff, rxflag => rxflag,
            rxdata => rxdata, rxread => rxread, started => started,
            connecting => connecting, running => running, errdisc => errdisc,
            errpar => errpar, erresc => erresc, errcred => errcred,
            spw_di => spw_di, spw_si => spw_si, spw_do => spw_do,
            spw_so => spw_so );
end architecture;
