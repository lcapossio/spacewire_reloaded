/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * DE25-Nano vendor wrapper: fpgacapZero ("fcapz") JTAG debug cores for
 * Intel/Altera devices (Quartus only). The top-level sees a vendor-neutral
 * interface -- an AXI4 master, an ELA probe bus and EIO in/out bits -- and this
 * file maps it onto the fcapz Intel wrappers, which use sld_virtual_jtag.
 * Simulation uses the stub tb/de25_debug_sim.v (same module name, idle master).
 *
 * sld_virtual_jtag instance map (host: fcapz --backend usb_blaster):
 *   1  ELA control/registers   (probe = ELA_W bits)
 *   2  ELA burst readout
 *   3  EIO                      (EIO_W in / EIO_W out)
 *   4  EJTAG-AXI bridge         (AXI4 master -> loopback engine)
 * This is the same map as the fpgacapZero DE25-Nano reference design.
 */

`timescale 1ns/1ps

module de25_debug #(
    parameter integer ELA_W = 16,
    parameter integer EIO_W = 8
) (
    input  wire             clk,
    input  wire             rst,
    // AXI4 master (JTAG host -> fabric)
    output wire [31:0]      m_axi_awaddr,
    output wire [7:0]       m_axi_awlen,
    output wire [2:0]       m_axi_awsize,
    output wire [1:0]       m_axi_awburst,
    output wire             m_axi_awvalid,
    input  wire             m_axi_awready,
    output wire [31:0]      m_axi_wdata,
    output wire [3:0]       m_axi_wstrb,
    output wire             m_axi_wlast,
    output wire             m_axi_wvalid,
    input  wire             m_axi_wready,
    input  wire [1:0]       m_axi_bresp,
    input  wire             m_axi_bvalid,
    output wire             m_axi_bready,
    output wire [31:0]      m_axi_araddr,
    output wire [7:0]       m_axi_arlen,
    output wire [2:0]       m_axi_arsize,
    output wire [1:0]       m_axi_arburst,
    output wire             m_axi_arvalid,
    input  wire             m_axi_arready,
    input  wire [31:0]      m_axi_rdata,
    input  wire [1:0]       m_axi_rresp,
    input  wire             m_axi_rlast,
    input  wire             m_axi_rvalid,
    output wire             m_axi_rready,
    // logic analyzer probes (sampled on clk) and external trigger
    input  wire [ELA_W-1:0] ela_probe,
    input  wire             ela_trigger_in,
    // host-visible I/O bits
    input  wire [EIO_W-1:0] eio_in,
    output wire [EIO_W-1:0] eio_out
);

    wire [2:0] awprot_unused, arprot_unused;
    wire       ela_trigger_out, ela_armed;

    fcapz_ela_intel #(
        .SAMPLE_W(ELA_W), .DEPTH(1024),
        .CTRL_CHAIN(1), .DATA_CHAIN(2),
        .INPUT_PIPE(1), .DECIM_EN(1), .EXT_TRIG_EN(1),
        .TIMESTAMP_W(32), .NUM_SEGMENTS(4),
        .STARTUP_ARM(1), .DEFAULT_TRIG_EXT(2)
    ) u_ela (
        .sample_clk(clk), .sample_rst(rst),
        .probe_in(ela_probe),
        .trigger_in(ela_trigger_in),
        .trigger_out(ela_trigger_out),
        .armed_out(ela_armed)
    );

    fcapz_eio_intel #(
        .IN_W(EIO_W), .OUT_W(EIO_W), .CHAIN(3)
    ) u_eio (
        .probe_in(eio_in),
        .probe_out(eio_out)
    );

    fcapz_ejtagaxi_intel #(
        .ADDR_W(32), .DATA_W(32),
        .FIFO_DEPTH(16), .CMD_FIFO_DEPTH(16), .RESP_FIFO_DEPTH(16),
        .CMD_FIFO_MEMORY_TYPE("distributed"), .TIMEOUT(4096), .DEBUG_EN(0),
        .ASYNC_FIFO_IMPL(0), .CHAIN(4)
    ) u_ejtagaxi (
        .axi_clk(clk), .axi_rst(rst),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_awprot(awprot_unused),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_arprot(arprot_unused),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready), .m_axi_rlast(m_axi_rlast)
    );

endmodule
