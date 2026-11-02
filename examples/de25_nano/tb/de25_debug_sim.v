/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * Simulation stub for the DE25-Nano JTAG debug wrapper (rtl/intel/de25_debug.v,
 * Quartus only). Same module name and ports: the AXI4 master stays idle (no
 * host attached), EIO outputs are 0 and the probes are ignored, so the
 * board-level simulation sees the design exactly as it runs with no JTAG host.
 */

`timescale 1ns/1ps

module de25_debug #(
    parameter integer ELA_W = 16,
    parameter integer EIO_W = 8
) (
    input  wire             clk,
    input  wire             rst,
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
    input  wire [ELA_W-1:0] ela_probe,
    input  wire             ela_trigger_in,
    input  wire [EIO_W-1:0] eio_in,
    output wire [EIO_W-1:0] eio_out
);

    assign m_axi_awaddr  = 32'b0;
    assign m_axi_awlen   = 8'b0;
    assign m_axi_awsize  = 3'b0;
    assign m_axi_awburst = 2'b0;
    assign m_axi_awvalid = 1'b0;
    assign m_axi_wdata   = 32'b0;
    assign m_axi_wstrb   = 4'b0;
    assign m_axi_wlast   = 1'b0;
    assign m_axi_wvalid  = 1'b0;
    assign m_axi_bready  = 1'b1;
    assign m_axi_araddr  = 32'b0;
    assign m_axi_arlen   = 8'b0;
    assign m_axi_arsize  = 3'b0;
    assign m_axi_arburst = 2'b0;
    assign m_axi_arvalid = 1'b0;
    assign m_axi_rready  = 1'b1;
    assign eio_out       = {EIO_W{1'b0}};

endmodule
