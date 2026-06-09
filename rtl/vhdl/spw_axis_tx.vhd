--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- AXI-Stream to SpaceWire N-Char transmit bridge.
--

library ieee;
use ieee.std_logic_1164.all;

entity spw_axis_tx is
    port (
        clk:            in  std_logic;
        rst:            in  std_logic;

        s_axis_tdata:   in  std_logic_vector(7 downto 0);
        s_axis_tvalid:  in  std_logic;
        s_axis_tready:  out std_logic;
        s_axis_tlast:   in  std_logic;
        s_axis_tuser:   in  std_logic_vector(0 downto 0);

        txwrite:        out std_logic;
        txflag:         out std_logic;
        txdata:         out std_logic_vector(7 downto 0);
        txrdy:          in  std_logic
    );
end entity spw_axis_tx;

architecture rtl of spw_axis_tx is
    signal accept_char: std_logic;
begin

    accept_char   <= s_axis_tvalid and txrdy and not rst;
    s_axis_tready <= txrdy and not rst;

    txwrite <= accept_char;
    txflag  <= s_axis_tlast;
    txdata  <= "0000000" & s_axis_tuser(0) when s_axis_tlast = '1' else s_axis_tdata;

end architecture rtl;
