--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- SpaceWire N-Char receive to AXI-Stream bridge.
--

library ieee;
use ieee.std_logic_1164.all;

entity spw_axis_rx is
    port (
        clk:            in  std_logic;
        rst:            in  std_logic;

        m_axis_tdata:   out std_logic_vector(7 downto 0);
        m_axis_tvalid:  out std_logic;
        m_axis_tready:  in  std_logic;
        m_axis_tlast:   out std_logic;
        m_axis_tuser:   out std_logic_vector(0 downto 0);

        rxvalid:        in  std_logic;
        rxflag:         in  std_logic;
        rxdata:         in  std_logic_vector(7 downto 0);
        rxread:         out std_logic
    );
end entity spw_axis_rx;

architecture rtl of spw_axis_rx is
    signal output_valid: std_logic;
begin

    output_valid <= rxvalid and not rst;

    m_axis_tdata    <= rxdata;
    m_axis_tvalid   <= output_valid;
    m_axis_tlast    <= rxflag;
    m_axis_tuser(0) <= rxflag;

    rxread <= output_valid and m_axis_tready;

end architecture rtl;
