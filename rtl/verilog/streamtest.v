/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * Test application for spwstream.
 *
 * Verilog 2001 translation of rtl/vhdl/streamtest.vhd from SpaceWire Light.
 */

`timescale 1ns / 1ps

module streamtest #(
    parameter [10:0] RESET_TIME = 11'd128,
    parameter [7:0] DISCONNECT_TIME = 8'd17,
    parameter [7:0] DEFAULT_DIVCNT = 8'd1,
    parameter TICKDIV = 16,
    parameter RXIMPL = 0,
    parameter RXCHUNK = 1,
    parameter TXIMPL = 0,
    parameter RXFIFOSIZE_BITS = 9,
    parameter TXFIFOSIZE_BITS = 8
) (
    input wire clk,
    input wire rxclk,
    input wire txclk,
    input wire rst,
    input wire linkstart,
    input wire autostart,
    input wire linkdisable,
    input wire senddata,
    input wire sendtick,
    input wire [7:0] txdivcnt,
    output wire linkstarted,
    output wire linkconnecting,
    output wire linkrun,
    output wire linkerror,
    output wire gotdata,
    output wire dataerror,
    output wire tickerror,
    input wire spw_di,
    input wire spw_si,
    output wire spw_do,
    output wire spw_so
);

    localparam TX_IDLE = 2'd0;
    localparam TX_PREPARE = 2'd1;
    localparam TX_DATA = 2'd2;
    localparam RX_IDLE = 1'd0;
    localparam RX_DATA = 1'd1;

    function [15:0] lfsr16;
        input [15:0] x;
        begin
            lfsr16[7:0] = x[15:8];
            lfsr16[15:8] = x[7:0] ^ x[9:2] ^ x[10:3] ^ x[12:5];
        end
    endfunction

    reg [1:0] tx_state;
    reg [TICKDIV-1:0] tx_timecnt;
    reg [15:0] tx_quietcnt;
    reg [15:0] tx_pktlen;
    reg [15:0] tx_lfsr;
    reg tx_enabledata;
    reg rx_state;
    reg [15:0] rx_quietcnt;
    reg rx_enabledata;
    reg rx_gottick;
    reg rx_expecttick;
    reg [5:0] rx_expectglitch;
    reg rx_badpacket;
    reg [15:0] rx_pktlen;
    reg [15:0] rx_prev;
    reg [15:0] rx_lfsr;
    reg running_r;
    reg tick_in_r;
    reg [5:0] time_in_r;
    reg txwrite_r;
    reg txflag_r;
    reg [7:0] txdata_r;
    reg rxread_r;
    reg gotdata_r;
    reg dataerror_r;
    reg tickerror_r;

    wire txrdy;
    wire tick_out;
    wire [5:0] time_out;
    wire rxvalid;
    wire rxflag;
    wire [7:0] rxdata;
    wire running;
    wire errdisc;
    wire errpar;
    wire erresc;
    wire errcred;

    assign linkrun = running;
    assign linkerror = errdisc | errpar | erresc | errcred;
    assign gotdata = gotdata_r;
    assign dataerror = dataerror_r;
    assign tickerror = tickerror_r;

    spwstream #(
        .RESET_TIME(RESET_TIME),
        .DISCONNECT_TIME(DISCONNECT_TIME),
        .DEFAULT_DIVCNT(DEFAULT_DIVCNT),
        .RXIMPL(RXIMPL),
        .TXIMPL(TXIMPL),
        .RXCHUNK(RXCHUNK),
        .RXFIFOSIZE_BITS(RXFIFOSIZE_BITS),
        .TXFIFOSIZE_BITS(TXFIFOSIZE_BITS)
    ) spwstream_inst (
        .clk(clk),
        .rxclk(rxclk),
        .txclk(txclk),
        .rst(rst),
        .autostart(autostart),
        .linkstart(linkstart),
        .linkdis(linkdisable),
        .txdivcnt(txdivcnt),
        .tick_in(tick_in_r),
        .ctrl_in(2'b00),
        .time_in(time_in_r),
        .txwrite(txwrite_r),
        .txflag(txflag_r),
        .txdata(txdata_r),
        .txrdy(txrdy),
        .txhalff(),
        .tick_out(tick_out),
        .ctrl_out(),
        .time_out(time_out),
        .rxvalid(rxvalid),
        .rxhalff(),
        .rxflag(rxflag),
        .rxdata(rxdata),
        .rxread(rxread_r),
        .started(linkstarted),
        .connecting(linkconnecting),
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

    always @(posedge clk) begin
        if (rst) begin
            tx_state <= TX_IDLE;
            tx_timecnt <= {TICKDIV{1'b0}};
            tx_quietcnt <= 16'd0;
            tx_pktlen <= 16'd0;
            tx_lfsr <= 16'h0002;
            tx_enabledata <= 1'b0;
            rx_state <= RX_IDLE;
            rx_quietcnt <= 16'd0;
            rx_enabledata <= 1'b0;
            rx_gottick <= 1'b0;
            rx_expecttick <= 1'b0;
            rx_expectglitch <= 6'b000001;
            rx_badpacket <= 1'b0;
            rx_pktlen <= 16'd0;
            rx_prev <= 16'd0;
            rx_lfsr <= 16'd0;
            running_r <= 1'b0;
            tick_in_r <= 1'b0;
            time_in_r <= 6'd0;
            txwrite_r <= 1'b0;
            txflag_r <= 1'b0;
            txdata_r <= 8'd0;
            rxread_r <= 1'b0;
            gotdata_r <= 1'b0;
            dataerror_r <= 1'b0;
            tickerror_r <= 1'b0;
        end else begin
            tx_timecnt <= tx_timecnt + {{(TICKDIV-1){1'b0}}, 1'b1};
            tick_in_r <= (&tx_timecnt) ? sendtick : 1'b0;
            if (tick_in_r) begin
                time_in_r <= time_in_r + 6'd1;
                rx_expecttick <= 1'b1;
                rx_gottick <= 1'b0;
            end

            tx_quietcnt <= (tx_quietcnt == 16'd61000) ? 16'd0 : tx_quietcnt + 16'd1;
            tx_enabledata <= senddata && !tx_quietcnt[15];

            case (tx_state)
                TX_IDLE: begin
                    tx_state <= TX_PREPARE;
                    tx_pktlen <= tx_lfsr;
                    txwrite_r <= 1'b0;
                    tx_lfsr <= lfsr16(tx_lfsr);
                end
                TX_PREPARE: begin
                    tx_state <= TX_DATA;
                    txwrite_r <= tx_enabledata;
                    txflag_r <= 1'b0;
                    txdata_r <= tx_lfsr[15:8];
                    tx_lfsr <= lfsr16(tx_lfsr);
                end
                default: begin
                    txwrite_r <= tx_enabledata;
                    if (txwrite_r && txrdy) begin
                        tx_pktlen <= tx_pktlen - 16'd1;
                        if (tx_pktlen == 16'd0) begin
                            tx_state <= TX_IDLE;
                            txwrite_r <= 1'b0;
                        end else if (tx_pktlen == 16'd1) begin
                            txwrite_r <= tx_enabledata;
                            txflag_r <= 1'b1;
                            txdata_r <= 8'd0;
                            tx_lfsr <= lfsr16(tx_lfsr);
                        end else begin
                            txwrite_r <= tx_enabledata;
                            txflag_r <= 1'b0;
                            txdata_r <= tx_lfsr[15:8];
                            tx_lfsr <= lfsr16(tx_lfsr);
                        end
                    end
                end
            endcase

            gotdata_r <= rxvalid && rxread_r;

            if (tick_in_r && rx_expecttick) begin
                tickerror_r <= 1'b1;
            end
            if (tick_out) begin
                if ((time_out + 6'd1) != time_in_r) begin
                    tickerror_r <= 1'b1;
                end
                if (rx_gottick) begin
                    tickerror_r <= 1'b1;
                end
                rx_expecttick <= 1'b0;
                rx_gottick <= 1'b1;
            end

            rx_quietcnt <= (rx_quietcnt == 16'd55000) ? 16'd0 : rx_quietcnt + 16'd1;
            rx_enabledata <= !rx_quietcnt[15];

            case (rx_state)
                RX_IDLE: begin
                    rx_state <= RX_DATA;
                    rx_pktlen <= rx_lfsr;
                    rx_lfsr <= lfsr16(rx_lfsr);
                    rx_prev <= 16'd0;
                end
                default: begin
                    rxread_r <= rx_enabledata;
                    if (rxread_r && rxvalid) begin
                        rx_pktlen <= rx_pktlen - 16'd1;
                        rx_prev <= {rxdata, rx_prev[15:8]};
                        if (rxflag) begin
                            rxread_r <= 1'b0;
                            rx_state <= RX_IDLE;
                            if (rxdata == 8'd0) begin
                                if (rx_pktlen != 16'd0) begin
                                    rx_badpacket <= 1'b1;
                                end
                                if (rx_badpacket) begin
                                    if (rx_expectglitch == 6'd0) begin
                                        dataerror_r <= 1'b1;
                                    end else begin
                                        rx_expectglitch <= rx_expectglitch - 6'd1;
                                    end
                                end
                                rx_lfsr <= lfsr16(lfsr16(rx_prev));
                            end else begin
                                rx_badpacket <= 1'b1;
                            end
                            rx_badpacket <= 1'b0;
                        end else begin
                            rx_lfsr <= lfsr16(rx_lfsr);
                            if (rx_pktlen == 16'd0) begin
                                rx_badpacket <= 1'b1;
                            end
                            if (rxdata != rx_lfsr[15:8]) begin
                                rx_badpacket <= 1'b1;
                            end
                        end
                    end
                end
            endcase

            running_r <= running;
            if (running_r && !running && rx_expectglitch != 6'b111111) begin
                rx_expectglitch <= rx_expectglitch + 6'd1;
            end
            if (!running) begin
                rx_expecttick <= 1'b0;
            end
        end
    end

endmodule

