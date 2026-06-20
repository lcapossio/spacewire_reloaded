/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * SpaceWire Reloaded AXI top-level wrapper.
 */

`timescale 1ns / 1ps

module spw_axi_top #(
    parameter integer SYS_CLOCK_HZ = 20000000,
    parameter integer TX_CLOCK_HZ = 20000000,
    // Optional compatibility overrides. Leave at zero to derive SpaceWire
    // timing from SYS_CLOCK_HZ/TX_CLOCK_HZ, matching the VHDL top-level.
    parameter [10:0] RESET_TIME = 11'd0,
    parameter [7:0]  DISCONNECT_TIME = 8'd0,
    parameter [7:0]  DEFAULT_DIVCNT = 8'd0,
    parameter        RXIMPL = 0,
    parameter        TXIMPL = 0,
    parameter        RXCHUNK = 1,
    parameter        RXFIFOSIZE_BITS = 11,
    parameter        TXFIFOSIZE_BITS = 11,
    parameter        STRICT_TIMECODES = 0,
    parameter        AXI_ADDR_WIDTH = 8,
    parameter [31:0] CORE_ID = 32'h53505752,
    parameter [31:0] VERSION = 32'h00010000
) (
    input  wire                      clk,
    input  wire                      rxclk,
    input  wire                      txclk,
    input  wire                      rst,

    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                      s_axi_awvalid,
    output wire                      s_axi_awready,
    input  wire [31:0]               s_axi_wdata,
    input  wire [3:0]                s_axi_wstrb,
    input  wire                      s_axi_wvalid,
    output wire                      s_axi_wready,
    output wire [1:0]                s_axi_bresp,
    output wire                      s_axi_bvalid,
    input  wire                      s_axi_bready,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                      s_axi_arvalid,
    output wire                      s_axi_arready,
    output wire [31:0]               s_axi_rdata,
    output wire [1:0]                s_axi_rresp,
    output wire                      s_axi_rvalid,
    input  wire                      s_axi_rready,

    input  wire [7:0]                s_axis_tdata,
    input  wire                      s_axis_tvalid,
    output wire                      s_axis_tready,
    input  wire                      s_axis_tlast,
    input  wire [0:0]                s_axis_tuser,

    output wire [7:0]                m_axis_tdata,
    output wire                      m_axis_tvalid,
    input  wire                      m_axis_tready,
    output wire                      m_axis_tlast,
    output wire [0:0]                m_axis_tuser,

    output wire                      irq,

    input  wire                      spw_di,
    input  wire                      spw_si,
    output wire                      spw_do,
    output wire                      spw_so
);

    wire soft_rst;
    wire core_rst = rst | soft_rst;
    wire autostart;
    wire linkstart;
    wire linkdis;
    wire [7:0] txdivcnt;
    wire tick_in;
    wire [1:0] ctrl_in;
    wire [5:0] time_in;
    wire txwrite;
    wire txflag;
    wire [7:0] txdata;
    wire txrdy;
    wire txhalff;
    wire tick_out;
    wire [1:0] ctrl_out;
    wire [5:0] time_out;
    wire rxvalid;
    wire rxhalff;
    wire rxflag;
    wire [7:0] rxdata;
    wire rxread;
    wire started;
    wire connecting;
    wire running;
    wire errdisc;
    wire errpar;
    wire erresc;
    wire errcred;

    initial begin
        // Parameter-range guards mirroring the VHDL constrained generics, so
        // invalid Verilog parameters fail with an intentional diagnostic at the
        // wrapper level (the underlying spwstream/regs also guard these).
        if (RXIMPL != 0 && RXIMPL != 1) begin
            $display("spw_axi_top: RXIMPL must be 0 (generic) or 1 (fast), got %0d", RXIMPL);
            $finish;
        end
        if (TXIMPL != 0 && TXIMPL != 1) begin
            $display("spw_axi_top: TXIMPL must be 0 (generic) or 1 (fast), got %0d", TXIMPL);
            $finish;
        end
        if (RXCHUNK < 1 || RXCHUNK > 4) begin
            $display("spw_axi_top: RXCHUNK must be in [1,4], got %0d", RXCHUNK);
            $finish;
        end
        if (RXFIFOSIZE_BITS < 6 || RXFIFOSIZE_BITS > 14) begin
            $display("spw_axi_top: RXFIFOSIZE_BITS must be in [6,14], got %0d", RXFIFOSIZE_BITS);
            $finish;
        end
        if (TXFIFOSIZE_BITS < 2 || TXFIFOSIZE_BITS > 14) begin
            $display("spw_axi_top: TXFIFOSIZE_BITS must be in [2,14], got %0d", TXFIFOSIZE_BITS);
            $finish;
        end
        if (AXI_ADDR_WIDTH < 6) begin
            $display("spw_axi_top: AXI_ADDR_WIDTH must be >= 6 for the register aperture, got %0d", AXI_ADDR_WIDTH);
            $finish;
        end
    end

    spw_axi_lite_regs #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .CORE_ID(CORE_ID),
        .VERSION(VERSION)
    ) regs_inst (
        .clk(clk),
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
        .core_rst(soft_rst),
        .autostart(autostart),
        .linkstart(linkstart),
        .linkdis(linkdis),
        .txdivcnt(txdivcnt),
        .tick_in(tick_in),
        .ctrl_in(ctrl_in),
        .time_in(time_in),
        .tick_out(tick_out),
        .ctrl_out(ctrl_out),
        .time_out(time_out),
        .txrdy(txrdy),
        .txhalff(txhalff),
        .rxvalid(rxvalid),
        .rxhalff(rxhalff),
        .started(started),
        .connecting(connecting),
        .running(running),
        .errdisc(errdisc),
        .errpar(errpar),
        .erresc(erresc),
        .errcred(errcred),
        .irq(irq)
    );

    spw_axis_tx axis_tx_inst (
        .clk(clk),
        .rst(core_rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .txwrite(txwrite),
        .txflag(txflag),
        .txdata(txdata),
        .txrdy(txrdy)
    );

    spw_axis_rx axis_rx_inst (
        .clk(clk),
        .rst(core_rst),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser),
        .rxvalid(rxvalid),
        .rxflag(rxflag),
        .rxdata(rxdata),
        .rxread(rxread)
    );

    spwstream #(
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
    ) core_inst (
        .clk(clk),
        .rxclk(rxclk),
        .txclk(txclk),
        .rst(core_rst),
        .autostart(autostart),
        .linkstart(linkstart),
        .linkdis(linkdis),
        .txdivcnt(txdivcnt),
        .tick_in(tick_in),
        .ctrl_in(ctrl_in),
        .time_in(time_in),
        .txwrite(txwrite),
        .txflag(txflag),
        .txdata(txdata),
        .txrdy(txrdy),
        .txhalff(txhalff),
        .tick_out(tick_out),
        .ctrl_out(ctrl_out),
        .time_out(time_out),
        .rxvalid(rxvalid),
        .rxhalff(rxhalff),
        .rxflag(rxflag),
        .rxdata(rxdata),
        .rxread(rxread),
        .started(started),
        .connecting(connecting),
        .running(running),
        .errdisc(errdisc),
        .errpar(errpar),
        .erresc(erresc),
        .errcred(errcred),
        .spw_di(spw_di),
        .spw_si(spw_si),
        .spw_do(spw_do),
        .spw_so(spw_so)
    );

endmodule
