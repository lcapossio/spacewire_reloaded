--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- Simulation stub for mpfs_por (rtl/microchip/mpfs_por.v). Models the
-- PolarFire INIT block's fabric power-on reset: fabric_por_n is low for the
-- first 200 ns of simulation time, then high.
--

library ieee;
use ieee.std_logic_1164.all;

entity mpfs_por is
    port (
        fabric_por_n: out std_logic
    );
end entity mpfs_por;

architecture sim of mpfs_por is
begin
    fabric_por_n <= '0', '1' after 200 ns;
end architecture sim;
