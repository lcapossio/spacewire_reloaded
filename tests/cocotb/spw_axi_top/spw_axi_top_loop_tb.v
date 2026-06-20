/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 */

`timescale 1ns / 1ps

module spw_axi_top_loop_tb #(
    parameter integer SYS_CLOCK_HZ = 20000000,
    parameter integer TX_CLOCK_HZ = 50000000,
    parameter [10:0] RESET_TIME = 11'd0,
    parameter [7:0]  DISCONNECT_TIME = 8'd0,
    parameter [7:0]  DEFAULT_DIVCNT = 8'd0,
    parameter        RXIMPL = 0,
    parameter        TXIMPL = 0,
    parameter        RXCHUNK = 1,
    parameter        LOOPBACK = 1,
    parameter        RXFIFOSIZE_BITS = 6,
    parameter        TXFIFOSIZE_BITS = 4,
    parameter        STRICT_TIMECODES = 0
) (
    input  wire       clk,
    input  wire       rxclk,
    input  wire       txclk,
    input  wire       rst,

    input  wire [7:0] s_axi_awaddr,
    input  wire       s_axi_awvalid,
    output wire       s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0] s_axi_wstrb,
    input  wire       s_axi_wvalid,
    output wire       s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output wire       s_axi_bvalid,
    input  wire       s_axi_bready,
    input  wire [7:0] s_axi_araddr,
    input  wire       s_axi_arvalid,
    output wire       s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire       s_axi_rvalid,
    input  wire       s_axi_rready,

    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tvalid,
    output wire       s_axis_tready,
    input  wire       s_axis_tlast,
    input  wire [0:0] s_axis_tuser,

    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tvalid,
    input  wire       m_axis_tready,
    output wire       m_axis_tlast,
    output wire [0:0] m_axis_tuser,

    output wire       irq,

    input  wire       spw_di_ext,
    input  wire       spw_si_ext,
    output wire       spw_do,
    output wire       spw_so
);

    wire spw_di = LOOPBACK ? spw_do : spw_di_ext;
    wire spw_si = LOOPBACK ? spw_so : spw_si_ext;

    spw_axi_top #(
        .SYS_CLOCK_HZ(SYS_CLOCK_HZ),
        .TX_CLOCK_HZ(TX_CLOCK_HZ),
        .RESET_TIME(RESET_TIME),
        .DISCONNECT_TIME(DISCONNECT_TIME),
        .DEFAULT_DIVCNT(DEFAULT_DIVCNT),
        .RXIMPL(RXIMPL),
        .TXIMPL(TXIMPL),
        .RXCHUNK(RXCHUNK),
        .RXFIFOSIZE_BITS(RXFIFOSIZE_BITS),
        .TXFIFOSIZE_BITS(TXFIFOSIZE_BITS),
        .STRICT_TIMECODES(STRICT_TIMECODES)
    ) dut_inst (
        .clk(clk),
        .rxclk(rxclk),
        .txclk(txclk),
        .rst(rst),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser),
        .irq(irq),
        .spw_di(spw_di),
        .spw_si(spw_si),
        .spw_do(spw_do),
        .spw_so(spw_so)
    );

endmodule
