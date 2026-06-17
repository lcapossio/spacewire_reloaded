/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * Simulation top for the Arty loopback example: spw_axi_top + spw_loopback_axi
 * with internal SpaceWire loopback, exposing the engine's AXI4 slave so a
 * cocotb host model can drive it exactly like the fpgacapZero EJTAG-AXI bridge
 * (single-beat AXI). No Xilinx/JTAG primitives, so it runs under Icarus/GHDL.
 */

`timescale 1ns/1ps

module spw_loopback_sim_top (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] s_axi_awaddr,
    input  wire [7:0]  s_axi_awlen,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wlast,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,
    input  wire [7:0]  s_axi_arlen,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rlast,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    output wire        link_running,
    output wire        selftest_pass,
    output wire        selftest_done,
    output wire        bringup_done
);

    wire spw_do, spw_so, spw_di, spw_si;
    wire inj_freeze, inj_invert;
    // internal loopback with host-controlled error injection
    assign spw_di = inj_freeze ? 1'b0 : (spw_do ^ inj_invert);
    assign spw_si = inj_freeze ? 1'b0 : spw_so;

    wire [7:0]  cs_awaddr, cs_araddr;
    wire [31:0] cs_wdata, cs_rdata;
    wire [3:0]  cs_wstrb;
    wire [1:0]  cs_bresp, cs_rresp;
    wire        cs_awvalid, cs_awready, cs_wvalid, cs_wready;
    wire        cs_bvalid, cs_bready, cs_arvalid, cs_arready, cs_rvalid, cs_rready;

    wire [7:0]  tx_tdata, rx_tdata;
    wire        tx_tvalid, tx_tready, tx_tlast;
    wire [0:0]  tx_tuser;
    wire        rx_tvalid, rx_tready, rx_tlast;
    wire [0:0]  rx_tuser;
    wire        spw_irq;

    spw_axi_top #(
        .RXIMPL(0), .TXIMPL(0), .RXCHUNK(1),
        .RXFIFOSIZE_BITS(11), .TXFIFOSIZE_BITS(11),
        .AXI_ADDR_WIDTH(8),
        .CORE_ID(32'h53505752), .VERSION(32'h00010000)
    ) u_spw (
        .clk(clk), .rxclk(clk), .txclk(clk), .rst(rst),
        .s_axi_awaddr(cs_awaddr), .s_axi_awvalid(cs_awvalid), .s_axi_awready(cs_awready),
        .s_axi_wdata(cs_wdata), .s_axi_wstrb(cs_wstrb), .s_axi_wvalid(cs_wvalid), .s_axi_wready(cs_wready),
        .s_axi_bresp(cs_bresp), .s_axi_bvalid(cs_bvalid), .s_axi_bready(cs_bready),
        .s_axi_araddr(cs_araddr), .s_axi_arvalid(cs_arvalid), .s_axi_arready(cs_arready),
        .s_axi_rdata(cs_rdata), .s_axi_rresp(cs_rresp), .s_axi_rvalid(cs_rvalid), .s_axi_rready(cs_rready),
        .s_axis_tdata(tx_tdata), .s_axis_tvalid(tx_tvalid), .s_axis_tready(tx_tready),
        .s_axis_tlast(tx_tlast), .s_axis_tuser(tx_tuser),
        .m_axis_tdata(rx_tdata), .m_axis_tvalid(rx_tvalid), .m_axis_tready(rx_tready),
        .m_axis_tlast(rx_tlast), .m_axis_tuser(rx_tuser),
        .irq(spw_irq),
        .spw_di(spw_di), .spw_si(spw_si), .spw_do(spw_do), .spw_so(spw_so)
    );

    spw_loopback_axi #(
        .EXAMPLE_ID(32'h5350574C), .EXAMPLE_VER(32'h00010056), // 'V' = Verilog
        .LINK_TXDIVCNT(8'd9), .SELFTEST_LEN(8'd16)
    ) u_engine (
        .clk(clk), .rst(rst),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awlen(s_axi_awlen), .s_axi_awsize(3'd2),
        .s_axi_awburst(2'b01), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arlen(s_axi_arlen), .s_axi_arsize(3'd2),
        .s_axi_arburst(2'b01), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .m_axil_awaddr(cs_awaddr), .m_axil_awvalid(cs_awvalid), .m_axil_awready(cs_awready),
        .m_axil_wdata(cs_wdata), .m_axil_wstrb(cs_wstrb), .m_axil_wvalid(cs_wvalid), .m_axil_wready(cs_wready),
        .m_axil_bresp(cs_bresp), .m_axil_bvalid(cs_bvalid), .m_axil_bready(cs_bready),
        .m_axil_araddr(cs_araddr), .m_axil_arvalid(cs_arvalid), .m_axil_arready(cs_arready),
        .m_axil_rdata(cs_rdata), .m_axil_rresp(cs_rresp), .m_axil_rvalid(cs_rvalid), .m_axil_rready(cs_rready),
        .m_axis_tdata(tx_tdata), .m_axis_tvalid(tx_tvalid), .m_axis_tready(tx_tready),
        .m_axis_tlast(tx_tlast), .m_axis_tuser(tx_tuser),
        .s_axis_tdata(rx_tdata), .s_axis_tvalid(rx_tvalid), .s_axis_tready(rx_tready),
        .s_axis_tlast(rx_tlast), .s_axis_tuser(rx_tuser),
        .link_running(link_running), .selftest_pass(selftest_pass),
        .selftest_done(selftest_done), .bringup_done(bringup_done),
        .inj_freeze(inj_freeze), .inj_invert(inj_invert)
    );

endmodule
