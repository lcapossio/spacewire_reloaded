--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- VHDL simulation top for the Arty loopback example: spw_axi_top + the VHDL
-- spw_loopback_axi engine with internal SpaceWire loopback. Same port names as
-- the Verilog spw_loopback_sim_top so the shared cocotb test drives both.
--

library ieee;
use ieee.std_logic_1164.all;
use work.spwpkg.all;

entity spw_loopback_sim_top is
    port (
        clk: in std_logic;
        rst: in std_logic;

        s_axi_awaddr:  in  std_logic_vector(31 downto 0);
        s_axi_awlen:   in  std_logic_vector(7 downto 0);
        s_axi_awvalid: in  std_logic;
        s_axi_awready: out std_logic;
        s_axi_wdata:   in  std_logic_vector(31 downto 0);
        s_axi_wstrb:   in  std_logic_vector(3 downto 0);
        s_axi_wlast:   in  std_logic;
        s_axi_wvalid:  in  std_logic;
        s_axi_wready:  out std_logic;
        s_axi_bresp:   out std_logic_vector(1 downto 0);
        s_axi_bvalid:  out std_logic;
        s_axi_bready:  in  std_logic;
        s_axi_araddr:  in  std_logic_vector(31 downto 0);
        s_axi_arlen:   in  std_logic_vector(7 downto 0);
        s_axi_arvalid: in  std_logic;
        s_axi_arready: out std_logic;
        s_axi_rdata:   out std_logic_vector(31 downto 0);
        s_axi_rresp:   out std_logic_vector(1 downto 0);
        s_axi_rlast:   out std_logic;
        s_axi_rvalid:  out std_logic;
        s_axi_rready:  in  std_logic;

        link_running:  out std_logic;
        selftest_pass: out std_logic;
        selftest_done: out std_logic;
        bringup_done:  out std_logic
    );
end entity spw_loopback_sim_top;

architecture rtl of spw_loopback_sim_top is
    signal spw_do, spw_so, spw_di, spw_si: std_logic;

    signal cs_awaddr, cs_araddr: std_logic_vector(7 downto 0);
    signal cs_wdata, cs_rdata:   std_logic_vector(31 downto 0);
    signal cs_wstrb:             std_logic_vector(3 downto 0);
    signal cs_bresp, cs_rresp:   std_logic_vector(1 downto 0);
    signal cs_awvalid, cs_awready, cs_wvalid, cs_wready: std_logic;
    signal cs_bvalid, cs_bready, cs_arvalid, cs_arready, cs_rvalid, cs_rready: std_logic;

    signal tx_tdata, rx_tdata: std_logic_vector(7 downto 0);
    signal tx_tvalid, tx_tready, tx_tlast: std_logic;
    signal tx_tuser: std_logic_vector(0 downto 0);
    signal rx_tvalid, rx_tready, rx_tlast: std_logic;
    signal rx_tuser: std_logic_vector(0 downto 0);
    signal spw_irq: std_logic;
begin
    spw_di <= spw_do;   -- internal loopback
    spw_si <= spw_so;

    u_spw: entity work.spw_axi_top
        generic map (
            sysfreq         => 100.0e6,
            txclkfreq       => 0.0,
            rximpl          => impl_generic,
            rxchunk         => 1,
            tximpl          => impl_generic,
            rxfifosize_bits => 11,
            txfifosize_bits => 11,
            AXI_ADDR_WIDTH  => 8,
            CORE_ID         => x"53505752",
            VERSION         => x"00010000")
        port map (
            clk => clk, rxclk => clk, txclk => clk, rst => rst,
            s_axi_awaddr => cs_awaddr, s_axi_awvalid => cs_awvalid, s_axi_awready => cs_awready,
            s_axi_wdata => cs_wdata, s_axi_wstrb => cs_wstrb, s_axi_wvalid => cs_wvalid, s_axi_wready => cs_wready,
            s_axi_bresp => cs_bresp, s_axi_bvalid => cs_bvalid, s_axi_bready => cs_bready,
            s_axi_araddr => cs_araddr, s_axi_arvalid => cs_arvalid, s_axi_arready => cs_arready,
            s_axi_rdata => cs_rdata, s_axi_rresp => cs_rresp, s_axi_rvalid => cs_rvalid, s_axi_rready => cs_rready,
            s_axis_tdata => tx_tdata, s_axis_tvalid => tx_tvalid, s_axis_tready => tx_tready,
            s_axis_tlast => tx_tlast, s_axis_tuser => tx_tuser,
            m_axis_tdata => rx_tdata, m_axis_tvalid => rx_tvalid, m_axis_tready => rx_tready,
            m_axis_tlast => rx_tlast, m_axis_tuser => rx_tuser,
            irq => spw_irq,
            spw_di => spw_di, spw_si => spw_si, spw_do => spw_do, spw_so => spw_so);

    u_engine: entity work.spw_loopback_axi
        generic map (
            EXAMPLE_ID    => x"5350574C",
            EXAMPLE_VER   => x"00010048", -- low byte 'H' = VHDL build
            LINK_TXDIVCNT => x"09",
            SELFTEST_LEN  => 16)
        port map (
            clk => clk, rst => rst,
            s_axi_awaddr => s_axi_awaddr, s_axi_awlen => s_axi_awlen, s_axi_awsize => "010",
            s_axi_awburst => "01", s_axi_awvalid => s_axi_awvalid, s_axi_awready => s_axi_awready,
            s_axi_wdata => s_axi_wdata, s_axi_wstrb => s_axi_wstrb, s_axi_wlast => s_axi_wlast,
            s_axi_wvalid => s_axi_wvalid, s_axi_wready => s_axi_wready,
            s_axi_bresp => s_axi_bresp, s_axi_bvalid => s_axi_bvalid, s_axi_bready => s_axi_bready,
            s_axi_araddr => s_axi_araddr, s_axi_arlen => s_axi_arlen, s_axi_arsize => "010",
            s_axi_arburst => "01", s_axi_arvalid => s_axi_arvalid, s_axi_arready => s_axi_arready,
            s_axi_rdata => s_axi_rdata, s_axi_rresp => s_axi_rresp, s_axi_rlast => s_axi_rlast,
            s_axi_rvalid => s_axi_rvalid, s_axi_rready => s_axi_rready,
            m_axil_awaddr => cs_awaddr, m_axil_awvalid => cs_awvalid, m_axil_awready => cs_awready,
            m_axil_wdata => cs_wdata, m_axil_wstrb => cs_wstrb, m_axil_wvalid => cs_wvalid, m_axil_wready => cs_wready,
            m_axil_bresp => cs_bresp, m_axil_bvalid => cs_bvalid, m_axil_bready => cs_bready,
            m_axil_araddr => cs_araddr, m_axil_arvalid => cs_arvalid, m_axil_arready => cs_arready,
            m_axil_rdata => cs_rdata, m_axil_rresp => cs_rresp, m_axil_rvalid => cs_rvalid, m_axil_rready => cs_rready,
            m_axis_tdata => tx_tdata, m_axis_tvalid => tx_tvalid, m_axis_tready => tx_tready,
            m_axis_tlast => tx_tlast, m_axis_tuser => tx_tuser,
            s_axis_tdata => rx_tdata, s_axis_tvalid => rx_tvalid, s_axis_tready => rx_tready,
            s_axis_tlast => rx_tlast, s_axis_tuser => rx_tuser,
            link_running => link_running, selftest_pass => selftest_pass,
            selftest_done => selftest_done, bringup_done => bringup_done);

end architecture rtl;
