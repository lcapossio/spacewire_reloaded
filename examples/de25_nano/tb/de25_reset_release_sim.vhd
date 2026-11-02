--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- Simulation stub for de25_reset_release (rtl/intel/de25_reset_release.v).
-- Models the Agilex configuration reset release: ninit_done is high for the
-- first 500 ns of simulation time, then low (user mode).
--

library ieee;
use ieee.std_logic_1164.all;

entity de25_reset_release is
    port (
        ninit_done: out std_logic
    );
end entity de25_reset_release;

architecture sim of de25_reset_release is
begin
    ninit_done <= '1', '0' after 500 ns;
end architecture sim;
