--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- Simulation stub for the DE25-Nano JTAG debug wrapper (rtl/intel/de25_debug.v,
-- Quartus only). Same entity name and ports as the component in
-- rtl/spw_de25_nano_top.vhd: the AXI4 master stays idle (no host attached),
-- EIO outputs are 0 and the probes are ignored.
--

library ieee;
use ieee.std_logic_1164.all;

entity de25_debug is
    port (
        clk, rst       : in  std_logic;
        m_axi_awaddr   : out std_logic_vector(31 downto 0);
        m_axi_awlen    : out std_logic_vector(7 downto 0);
        m_axi_awsize   : out std_logic_vector(2 downto 0);
        m_axi_awburst  : out std_logic_vector(1 downto 0);
        m_axi_awvalid  : out std_logic;
        m_axi_awready  : in  std_logic;
        m_axi_wdata    : out std_logic_vector(31 downto 0);
        m_axi_wstrb    : out std_logic_vector(3 downto 0);
        m_axi_wlast    : out std_logic;
        m_axi_wvalid   : out std_logic;
        m_axi_wready   : in  std_logic;
        m_axi_bresp    : in  std_logic_vector(1 downto 0);
        m_axi_bvalid   : in  std_logic;
        m_axi_bready   : out std_logic;
        m_axi_araddr   : out std_logic_vector(31 downto 0);
        m_axi_arlen    : out std_logic_vector(7 downto 0);
        m_axi_arsize   : out std_logic_vector(2 downto 0);
        m_axi_arburst  : out std_logic_vector(1 downto 0);
        m_axi_arvalid  : out std_logic;
        m_axi_arready  : in  std_logic;
        m_axi_rdata    : in  std_logic_vector(31 downto 0);
        m_axi_rresp    : in  std_logic_vector(1 downto 0);
        m_axi_rlast    : in  std_logic;
        m_axi_rvalid   : in  std_logic;
        m_axi_rready   : out std_logic;
        ela_probe      : in  std_logic_vector(15 downto 0);
        ela_trigger_in : in  std_logic;
        eio_in         : in  std_logic_vector(7 downto 0);
        eio_out        : out std_logic_vector(7 downto 0));
end entity de25_debug;

architecture sim of de25_debug is
begin
    m_axi_awaddr  <= (others => '0');
    m_axi_awlen   <= (others => '0');
    m_axi_awsize  <= (others => '0');
    m_axi_awburst <= (others => '0');
    m_axi_awvalid <= '0';
    m_axi_wdata   <= (others => '0');
    m_axi_wstrb   <= (others => '0');
    m_axi_wlast   <= '0';
    m_axi_wvalid  <= '0';
    m_axi_bready  <= '1';
    m_axi_araddr  <= (others => '0');
    m_axi_arlen   <= (others => '0');
    m_axi_arsize  <= (others => '0');
    m_axi_arburst <= (others => '0');
    m_axi_arvalid <= '0';
    m_axi_rready  <= '1';
    eio_out       <= (others => '0');
end architecture sim;
