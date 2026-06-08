/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * SpaceWire Transmitter.
 *
 * Verilog 2001 translation of rtl/vhdl/spwxmit.vhd from SpaceWire Light.
 * VHDL record ports are flattened for Verilog 2001 compatibility.
 */

`timescale 1ns / 1ps

module spwxmit (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] divcnt,

    input  wire       xmiti_txen,
    input  wire       xmiti_stnull,
    input  wire       xmiti_stfct,
    input  wire       xmiti_fct_in,
    input  wire       xmiti_tick_in,
    input  wire [1:0] xmiti_ctrl_in,
    input  wire [5:0] xmiti_time_in,
    input  wire       xmiti_txwrite,
    input  wire       xmiti_txflag,
    input  wire [7:0] xmiti_txdata,

    output reg        xmito_fctack,
    output reg        xmito_txack,
    output reg        spw_do,
    output reg        spw_so
);

    reg        txclken;
    reg [7:0]  txclkcnt;
    reg [12:0] bitshift;
    reg [3:0]  bitcnt;
    reg        out_data;
    reg        out_strobe;
    reg        parity;
    reg        pend_tick;
    reg [7:0]  pend_time;
    reg        allow_fct;
    reg        allow_char;
    reg        sent_null;
    reg        sent_fct;

    reg        v_txclken;
    reg [7:0]  v_txclkcnt;
    reg [12:0] v_bitshift;
    reg [3:0]  v_bitcnt;
    reg        v_out_data;
    reg        v_out_strobe;
    reg        v_parity;
    reg        v_pend_tick;
    reg [7:0]  v_pend_time;
    reg        v_allow_fct;
    reg        v_allow_char;
    reg        v_sent_null;
    reg        v_sent_fct;

    always @* begin
        v_txclken    = txclken;
        v_txclkcnt   = txclkcnt;
        v_bitshift   = bitshift;
        v_bitcnt     = bitcnt;
        v_out_data   = out_data;
        v_out_strobe = out_strobe;
        v_parity     = parity;
        v_pend_tick  = pend_tick;
        v_pend_time  = pend_time;
        v_allow_fct  = allow_fct;
        v_allow_char = allow_char;
        v_sent_null  = sent_null;
        v_sent_fct   = sent_fct;

        if (txclkcnt == 8'd0) begin
            v_txclkcnt = divcnt;
            v_txclken  = 1'b1;
        end else begin
            v_txclkcnt = txclkcnt - 8'd1;
            v_txclken  = 1'b0;
        end

        if (!xmiti_txen) begin
            v_bitcnt     = 4'd0;
            v_parity     = 1'b0;
            v_pend_tick  = 1'b0;
            v_allow_fct  = 1'b0;
            v_allow_char = 1'b0;
            v_sent_null  = 1'b0;
            v_sent_fct   = 1'b0;

            if (txclken) begin
                v_out_data   = out_data & out_strobe;
                v_out_strobe = 1'b0;
            end
        end else begin
            v_allow_fct  = !xmiti_stnull && sent_null;
            v_allow_char = !xmiti_stnull && sent_null && !xmiti_stfct && sent_fct;

            if (txclken) begin
                if (bitcnt == 4'd0) begin
                    if (allow_char && pend_tick) begin
                        v_out_data          = parity;
                        v_bitshift[12:5]    = pend_time;
                        v_bitshift[4:0]     = 5'b01111;
                        v_bitcnt            = 4'd13;
                        v_parity            = 1'b0;
                        v_pend_tick         = 1'b0;
                    end else if (allow_fct && xmiti_fct_in) begin
                        v_out_data          = parity;
                        v_bitshift[2:0]     = 3'b001;
                        v_bitcnt            = 4'd3;
                        v_parity            = 1'b1;
                        v_sent_fct          = 1'b1;
                    end else if (allow_char && xmiti_txwrite) begin
                        v_bitshift[0]       = xmiti_txflag;
                        v_parity            = xmiti_txflag;
                        if (!xmiti_txflag) begin
                            v_out_data      = !parity;
                            v_bitshift[8:1] = xmiti_txdata;
                            v_bitcnt        = 4'd9;
                        end else begin
                            v_out_data      = parity;
                            v_bitshift[1]   = xmiti_txdata[0];
                            v_bitshift[2]   = !xmiti_txdata[0];
                            v_bitcnt        = 4'd3;
                        end
                    end else begin
                        v_out_data          = parity;
                        v_bitshift[6:0]     = 7'b0010111;
                        v_bitcnt            = 4'd7;
                        v_parity            = 1'b0;
                        v_sent_null         = 1'b1;
                    end
                end else begin
                    v_out_data   = bitshift[0];
                    v_parity     = parity ^ bitshift[0];
                    v_bitshift   = {1'b0, bitshift[12:1]};
                    v_bitcnt     = bitcnt - 4'd1;
                end

                v_out_strobe = !(out_strobe ^ out_data ^ v_out_data);
            end

            if (xmiti_tick_in) begin
                v_pend_tick = 1'b1;
                v_pend_time = {xmiti_ctrl_in, xmiti_time_in};
            end
        end

        if (rst) begin
            v_txclken    = 1'b0;
            v_txclkcnt   = 8'd0;
            v_bitshift   = 13'd0;
            v_bitcnt     = 4'd0;
            v_out_data   = 1'b0;
            v_out_strobe = 1'b0;
            v_parity     = 1'b0;
            v_pend_tick  = 1'b0;
            v_pend_time  = 8'd0;
            v_allow_fct  = 1'b0;
            v_allow_char = 1'b0;
            v_sent_null  = 1'b0;
            v_sent_fct   = 1'b0;
        end

        if (xmiti_txen && txclken && (bitcnt == 4'd0) && allow_fct &&
            (!allow_char || !pend_tick)) begin
            xmito_fctack = xmiti_fct_in;
        end else begin
            xmito_fctack = 1'b0;
        end

        if (xmiti_txen && txclken && (bitcnt == 4'd0) && allow_char &&
            !pend_tick && !xmiti_fct_in) begin
            xmito_txack = xmiti_txwrite;
        end else begin
            xmito_txack = 1'b0;
        end
    end

    always @(posedge clk) begin
        txclken    <= v_txclken;
        txclkcnt   <= v_txclkcnt;
        bitshift   <= v_bitshift;
        bitcnt     <= v_bitcnt;
        out_data   <= v_out_data;
        out_strobe <= v_out_strobe;
        parity     <= v_parity;
        pend_tick  <= v_pend_tick;
        pend_time  <= v_pend_time;
        allow_fct  <= v_allow_fct;
        allow_char <= v_allow_char;
        sent_null  <= v_sent_null;
        sent_fct   <= v_sent_fct;

        spw_do <= out_data;
        spw_so <= out_strobe;
    end

    initial begin
        txclken    = 1'b0;
        txclkcnt   = 8'd0;
        bitshift   = 13'd0;
        bitcnt     = 4'd0;
        out_data   = 1'b0;
        out_strobe = 1'b0;
        parity     = 1'b0;
        pend_tick  = 1'b0;
        pend_time  = 8'd0;
        allow_fct  = 1'b0;
        allow_char = 1'b0;
        sent_null  = 1'b0;
        sent_fct   = 1'b0;
        spw_do     = 1'b0;
        spw_so     = 1'b0;
    end

endmodule

