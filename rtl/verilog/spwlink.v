/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * SpaceWire Exchange Level Controller.
 *
 * Verilog 2001 translation of rtl/vhdl/spwlink.vhd from SpaceWire Light.
 * VHDL record ports are flattened for Verilog 2001 compatibility.
 */

`timescale 1ns / 1ps

module spwlink #(
    parameter [10:0] RESET_TIME = 11'd640
) (
    input  wire       clk,
    input  wire       rst,

    input  wire       linki_autostart,
    input  wire       linki_linkstart,
    input  wire       linki_linkdis,
    input  wire [5:0] linki_rxroom,
    input  wire       linki_tick_in,
    input  wire [1:0] linki_ctrl_in,
    input  wire [5:0] linki_time_in,
    input  wire       linki_txwrite,
    input  wire       linki_txflag,
    input  wire [7:0] linki_txdata,

    output reg        linko_started,
    output reg        linko_connecting,
    output reg        linko_running,
    output reg        linko_errdisc,
    output reg        linko_errpar,
    output reg        linko_erresc,
    output reg        linko_errcred,
    output reg        linko_txack,
    output reg        linko_tick_out,
    output reg  [1:0] linko_ctrl_out,
    output reg  [5:0] linko_time_out,
    output reg        linko_rxchar,
    output reg        linko_rxflag,
    output reg  [7:0] linko_rxdata,

    output reg        rxen,

    input  wire       recvo_gotbit,
    input  wire       recvo_gotnull,
    input  wire       recvo_gotfct,
    input  wire       recvo_tick_out,
    input  wire [1:0] recvo_ctrl_out,
    input  wire [5:0] recvo_time_out,
    input  wire       recvo_rxchar,
    input  wire       recvo_rxflag,
    input  wire [7:0] recvo_rxdata,
    input  wire       recvo_errdisc,
    input  wire       recvo_errpar,
    input  wire       recvo_erresc,

    output reg        xmiti_txen,
    output reg        xmiti_stnull,
    output reg        xmiti_stfct,
    output reg        xmiti_fct_in,
    output reg        xmiti_tick_in,
    output reg  [1:0] xmiti_ctrl_in,
    output reg  [5:0] xmiti_time_in,
    output reg        xmiti_txwrite,
    output reg        xmiti_txflag,
    output reg  [7:0] xmiti_txdata,

    input  wire       xmito_fctack,
    input  wire       xmito_txack
);

    localparam S_ERROR_RESET = 3'd0;
    localparam S_ERROR_WAIT  = 3'd1;
    localparam S_READY       = 3'd2;
    localparam S_STARTED     = 3'd3;
    localparam S_CONNECTING  = 3'd4;
    localparam S_RUN         = 3'd5;

    reg [2:0]  state;
    reg [5:0]  tx_credit;
    reg [5:0]  rx_credit;
    reg        errcred;
    reg [10:0] timercnt;
    reg        timerdone;
    reg        xmit_fct_in;

    reg [2:0]  v_state;
    reg [5:0]  v_tx_credit;
    reg [5:0]  v_rx_credit;
    reg        v_errcred;
    reg [10:0] v_timercnt;
    reg        v_timerdone;
    reg        v_xmit_fct_in;
    reg        v_timerrst;

    wire recv_error = recvo_errdisc | recvo_errpar | recvo_erresc;
    wire recv_early = recvo_gotfct | recvo_tick_out | recvo_rxchar;

    always @* begin
        v_state       = state;
        v_tx_credit   = tx_credit;
        v_rx_credit   = rx_credit;
        v_errcred     = errcred;
        v_timercnt    = timercnt;
        v_timerdone   = timerdone;
        v_xmit_fct_in = xmit_fct_in;
        v_timerrst    = 1'b0;

        case (state)
            S_ERROR_RESET: begin
                if (timercnt == 11'd0) begin
                    v_state    = S_ERROR_WAIT;
                    v_timerrst = 1'b1;
                end
                v_errcred     = 1'b0;
                v_xmit_fct_in = 1'b0;
            end

            S_ERROR_WAIT: begin
                if (recv_error || recv_early) begin
                    v_state    = S_ERROR_RESET;
                    v_timerrst = 1'b1;
                end else if (timercnt == 11'd0) begin
                    if (timerdone) begin
                        v_state    = S_READY;
                        v_timerrst = 1'b1;
                    end
                end
            end

            S_READY: begin
                if (recv_error || recv_early) begin
                    v_state    = S_ERROR_RESET;
                    v_timerrst = 1'b1;
                end else if (!linki_linkdis && xmit_fct_in &&
                             (linki_linkstart || (linki_autostart && recvo_gotnull))) begin
                    v_state    = S_STARTED;
                    v_timerrst = 1'b1;
                end
            end

            S_STARTED: begin
                if (recv_error || recv_early || ((timercnt == 11'd0) && timerdone)) begin
                    v_state    = S_ERROR_RESET;
                    v_timerrst = 1'b1;
                end else if (recvo_gotnull) begin
                    v_state    = S_CONNECTING;
                    v_timerrst = 1'b1;
                end
            end

            S_CONNECTING: begin
                if (recv_error || recvo_tick_out || recvo_rxchar ||
                    ((timercnt == 11'd0) && timerdone)) begin
                    v_state    = S_ERROR_RESET;
                    v_timerrst = 1'b1;
                end else if (recvo_gotfct) begin
                    v_state = S_RUN;
                end
            end

            S_RUN: begin
                if (recv_error || errcred || linki_linkdis) begin
                    v_state    = S_ERROR_RESET;
                    v_timerrst = 1'b1;
                end
            end

            default: begin
                v_state    = S_ERROR_RESET;
                v_timerrst = 1'b1;
            end
        endcase

        if (state == S_ERROR_RESET) begin
            v_tx_credit = 6'd0;
            v_rx_credit = 6'd0;
        end else begin
            if (recvo_gotfct) begin
                v_tx_credit = v_tx_credit + 6'd8;
                if (tx_credit > 6'd48) begin
                    v_errcred = 1'b1;
                end
            end

            if (xmito_txack) begin
                v_tx_credit = v_tx_credit - 6'd1;
            end

            if (xmito_fctack) begin
                v_rx_credit = v_rx_credit + 6'd8;
            end

            v_xmit_fct_in = (v_rx_credit <= 6'd48) &&
                             ((v_rx_credit + 6'd8) <= linki_rxroom);

            if (recvo_rxchar) begin
                v_rx_credit = v_rx_credit - 6'd1;
                if (rx_credit == 6'd0) begin
                    v_errcred = 1'b1;
                end
            end
        end

        if (v_timerrst) begin
            v_timercnt  = RESET_TIME;
            v_timerdone = 1'b0;
        end else begin
            if (timercnt == 11'd0) begin
                v_timercnt  = RESET_TIME;
                v_timerdone = 1'b1;
            end else begin
                v_timercnt = timercnt - 11'd1;
            end
        end

        if (rst) begin
            v_state       = S_ERROR_RESET;
            v_tx_credit   = 6'd0;
            v_rx_credit   = 6'd0;
            v_errcred     = 1'b0;
            v_timercnt    = RESET_TIME;
            v_timerdone   = 1'b0;
            v_xmit_fct_in = 1'b0;
        end

        linko_started    = (state == S_STARTED);
        linko_connecting = (state == S_CONNECTING);
        linko_running    = (state == S_RUN);
        linko_errdisc    = recvo_errdisc && (state == S_RUN);
        linko_errpar     = recvo_errpar  && (state == S_RUN);
        linko_erresc     = recvo_erresc  && (state == S_RUN);
        linko_errcred    = errcred;
        linko_txack      = xmito_txack;
        linko_tick_out   = recvo_tick_out && (state == S_RUN);
        linko_ctrl_out   = recvo_ctrl_out;
        linko_time_out   = recvo_time_out;
        linko_rxchar     = recvo_rxchar && (state == S_RUN);
        linko_rxflag     = recvo_rxflag;
        linko_rxdata     = recvo_rxdata;

        rxen             = (state != S_ERROR_RESET);

        xmiti_txen       = (state == S_STARTED) || (state == S_CONNECTING) || (state == S_RUN);
        xmiti_stnull     = (state == S_STARTED);
        xmiti_stfct      = (state == S_CONNECTING);
        xmiti_fct_in     = xmit_fct_in;
        xmiti_tick_in    = linki_tick_in && (state == S_RUN);
        xmiti_ctrl_in    = linki_ctrl_in;
        xmiti_time_in    = linki_time_in;
        xmiti_txwrite    = linki_txwrite && (tx_credit != 6'd0);
        xmiti_txflag     = linki_txflag;
        xmiti_txdata     = linki_txdata;
    end

    always @(posedge clk) begin
        state       <= v_state;
        tx_credit   <= v_tx_credit;
        rx_credit   <= v_rx_credit;
        errcred     <= v_errcred;
        timercnt    <= v_timercnt;
        timerdone   <= v_timerdone;
        xmit_fct_in <= v_xmit_fct_in;
    end

    initial begin
        state       = S_ERROR_RESET;
        tx_credit   = 6'd0;
        rx_credit   = 6'd0;
        errcred     = 1'b0;
        timercnt    = RESET_TIME;
        timerdone   = 1'b0;
        xmit_fct_in = 1'b0;
    end

endmodule
