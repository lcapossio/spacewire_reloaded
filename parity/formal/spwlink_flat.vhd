-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Thin interface wrapper for formal SEC of spacewire_light spwlink.
--
-- The VHDL spwlink entity uses record ports from spwpkg. The Verilog 2001
-- translation exposes the same leaf fields as flattened ports. This wrapper
-- exposes VHDL std_logic/std_logic_vector ports with the Verilog names, maps
-- those ports to records, and instantiates the original VHDL spwlink.

library ieee;
use ieee.std_logic_1164.all;
use work.spwpkg.all;

entity spwlink_flat is
    generic (
        reset_time : integer
    );
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;

        linki_autostart  : in  std_logic;
        linki_linkstart  : in  std_logic;
        linki_linkdis    : in  std_logic;
        linki_rxroom     : in  std_logic_vector(5 downto 0);
        linki_tick_in    : in  std_logic;
        linki_ctrl_in    : in  std_logic_vector(1 downto 0);
        linki_time_in    : in  std_logic_vector(5 downto 0);
        linki_txwrite    : in  std_logic;
        linki_txflag     : in  std_logic;
        linki_txdata     : in  std_logic_vector(7 downto 0);

        linko_started    : out std_logic;
        linko_connecting : out std_logic;
        linko_running    : out std_logic;
        linko_errdisc    : out std_logic;
        linko_errpar     : out std_logic;
        linko_erresc     : out std_logic;
        linko_errcred    : out std_logic;
        linko_txack      : out std_logic;
        linko_tick_out   : out std_logic;
        linko_ctrl_out   : out std_logic_vector(1 downto 0);
        linko_time_out   : out std_logic_vector(5 downto 0);
        linko_rxchar     : out std_logic;
        linko_rxflag     : out std_logic;
        linko_rxdata     : out std_logic_vector(7 downto 0);

        rxen             : out std_logic;

        recvo_gotbit     : in  std_logic;
        recvo_gotnull    : in  std_logic;
        recvo_gotfct     : in  std_logic;
        recvo_tick_out   : in  std_logic;
        recvo_ctrl_out   : in  std_logic_vector(1 downto 0);
        recvo_time_out   : in  std_logic_vector(5 downto 0);
        recvo_rxchar     : in  std_logic;
        recvo_rxflag     : in  std_logic;
        recvo_rxdata     : in  std_logic_vector(7 downto 0);
        recvo_errdisc    : in  std_logic;
        recvo_errpar     : in  std_logic;
        recvo_erresc     : in  std_logic;

        xmiti_txen       : out std_logic;
        xmiti_stnull     : out std_logic;
        xmiti_stfct      : out std_logic;
        xmiti_fct_in     : out std_logic;
        xmiti_tick_in    : out std_logic;
        xmiti_ctrl_in    : out std_logic_vector(1 downto 0);
        xmiti_time_in    : out std_logic_vector(5 downto 0);
        xmiti_txwrite    : out std_logic;
        xmiti_txflag     : out std_logic;
        xmiti_txdata     : out std_logic_vector(7 downto 0);

        xmito_fctack     : in  std_logic;
        xmito_txack      : in  std_logic
    );
end entity spwlink_flat;

architecture wrap of spwlink_flat is
    signal linki : spw_link_in_type;
    signal linko : spw_link_out_type;
    signal recvo : spw_recv_out_type;
    signal xmiti : spw_xmit_in_type;
    signal xmito : spw_xmit_out_type;
begin

    linki.autostart <= linki_autostart;
    linki.linkstart <= linki_linkstart;
    linki.linkdis   <= linki_linkdis;
    linki.rxroom    <= linki_rxroom;
    linki.tick_in   <= linki_tick_in;
    linki.ctrl_in   <= linki_ctrl_in;
    linki.time_in   <= linki_time_in;
    linki.txwrite   <= linki_txwrite;
    linki.txflag    <= linki_txflag;
    linki.txdata    <= linki_txdata;

    recvo.gotbit   <= recvo_gotbit;
    recvo.gotnull  <= recvo_gotnull;
    recvo.gotfct   <= recvo_gotfct;
    recvo.tick_out <= recvo_tick_out;
    recvo.ctrl_out <= recvo_ctrl_out;
    recvo.time_out <= recvo_time_out;
    recvo.rxchar   <= recvo_rxchar;
    recvo.rxflag   <= recvo_rxflag;
    recvo.rxdata   <= recvo_rxdata;
    recvo.errdisc  <= recvo_errdisc;
    recvo.errpar   <= recvo_errpar;
    recvo.erresc   <= recvo_erresc;

    xmito.fctack <= xmito_fctack;
    xmito.txack  <= xmito_txack;

    linko_started    <= linko.started;
    linko_connecting <= linko.connecting;
    linko_running    <= linko.running;
    linko_errdisc    <= linko.errdisc;
    linko_errpar     <= linko.errpar;
    linko_erresc     <= linko.erresc;
    linko_errcred    <= linko.errcred;
    linko_txack      <= linko.txack;
    linko_tick_out   <= linko.tick_out;
    linko_ctrl_out   <= linko.ctrl_out;
    linko_time_out   <= linko.time_out;
    linko_rxchar     <= linko.rxchar;
    linko_rxflag     <= linko.rxflag;
    linko_rxdata     <= linko.rxdata;

    xmiti_txen    <= xmiti.txen;
    xmiti_stnull  <= xmiti.stnull;
    xmiti_stfct   <= xmiti.stfct;
    xmiti_fct_in  <= xmiti.fct_in;
    xmiti_tick_in <= xmiti.tick_in;
    xmiti_ctrl_in <= xmiti.ctrl_in;
    xmiti_time_in <= xmiti.time_in;
    xmiti_txwrite <= xmiti.txwrite;
    xmiti_txflag  <= xmiti.txflag;
    xmiti_txdata  <= xmiti.txdata;

    dut : entity work.spwlink
        generic map (
            reset_time => reset_time
        )
        port map (
            clk   => clk,
            rst   => rst,
            linki => linki,
            linko => linko,
            rxen  => rxen,
            recvo => recvo,
            xmiti => xmiti,
            xmito => xmito
        );

end architecture wrap;
