-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com (2026)
-- Thin interface wrapper for formal SEC of spacewire_light spwxmit_fast.
--
-- The VHDL spwxmit_fast entity uses record ports from spwpkg. The Verilog 2001
-- translation exposes the same leaf fields as flattened ports. This wrapper
-- exposes VHDL std_logic/std_logic_vector ports with the Verilog names, maps
-- those ports to records, and instantiates the original VHDL spwxmit_fast.

library ieee;
use ieee.std_logic_1164.all;
use work.spwpkg.all;

entity spwxmit_fast_flat is
    port (
        clk           : in  std_logic;
        txclk         : in  std_logic;
        rst           : in  std_logic;
        divcnt        : in  std_logic_vector(7 downto 0);
        xmiti_txen    : in  std_logic;
        xmiti_stnull  : in  std_logic;
        xmiti_stfct   : in  std_logic;
        xmiti_fct_in  : in  std_logic;
        xmiti_tick_in : in  std_logic;
        xmiti_ctrl_in : in  std_logic_vector(1 downto 0);
        xmiti_time_in : in  std_logic_vector(5 downto 0);
        xmiti_txwrite : in  std_logic;
        xmiti_txflag  : in  std_logic;
        xmiti_txdata  : in  std_logic_vector(7 downto 0);
        xmito_fctack  : out std_logic;
        xmito_txack   : out std_logic;
        spw_do        : out std_logic;
        spw_so        : out std_logic
    );
end entity spwxmit_fast_flat;

architecture rtl of spwxmit_fast_flat is
    signal xmiti : spw_xmit_in_type;
    signal xmito : spw_xmit_out_type;
begin
    xmiti.txen    <= xmiti_txen;
    xmiti.stnull  <= xmiti_stnull;
    xmiti.stfct   <= xmiti_stfct;
    xmiti.fct_in  <= xmiti_fct_in;
    xmiti.tick_in <= xmiti_tick_in;
    xmiti.ctrl_in <= xmiti_ctrl_in;
    xmiti.time_in <= xmiti_time_in;
    xmiti.txwrite <= xmiti_txwrite;
    xmiti.txflag  <= xmiti_txflag;
    xmiti.txdata  <= xmiti_txdata;

    xmito_fctack  <= xmito.fctack;
    xmito_txack   <= xmito.txack;

    u_xmit : entity work.spwxmit_fast
        port map (
            clk    => clk,
            txclk  => txclk,
            rst    => rst,
            divcnt => divcnt,
            xmiti  => xmiti,
            xmito  => xmito,
            spw_do => spw_do,
            spw_so => spw_so
        );
end architecture rtl;
