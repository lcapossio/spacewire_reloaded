--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- SpaceWire N-Char receive to AXI-Stream bridge.
--
-- The output is a 1-deep registered (skid) AXI-Stream stage whose holding
-- register is reset ONLY by the AXI bus reset (rst), so a beat already presented
-- on m_axis survives a SpaceWire-core flush (e.g. the CONTROL[0] soft reset):
-- TVALID stays asserted with stable payload until TREADY, as AXI-Stream requires.
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
    signal beat_valid: std_logic := '0';
    signal beat_flag:  std_logic := '0';
    signal beat_data:  std_logic_vector(7 downto 0) := (others => '0');
    signal rxread_i:   std_logic;
begin

    -- Accept a char from the core RX FIFO when the holding register is empty or
    -- is being drained this cycle (no-bubble, full throughput).
    rxread_i <= rxvalid and ((not beat_valid) or m_axis_tready) and (not rst);
    rxread   <= rxread_i;

    m_axis_tvalid   <= beat_valid and not rst;
    m_axis_tlast    <= beat_flag;
    m_axis_tuser(0) <= beat_flag and beat_data(0);
    m_axis_tdata    <= ("0000000" & beat_data(0)) when beat_flag = '1' else beat_data;

    process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                beat_valid <= '0';
            else
                if m_axis_tready = '1' then
                    beat_valid <= '0';
                end if;
                if rxread_i = '1' then
                    beat_valid <= '1';
                    beat_flag  <= rxflag;
                    beat_data  <= rxdata;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
