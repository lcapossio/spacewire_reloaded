/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * SpaceWire Receiver.
 *
 * Verilog 2001 translation of rtl/vhdl/spwrecv.vhd from SpaceWire Light.
 * VHDL record ports are flattened for Verilog 2001 compatibility.
 */

`timescale 1ns / 1ps

module spwrecv #(
    parameter [7:0] DISCONNECT_TIME = 8'd85,
    parameter RXCHUNK = 1
) (
    input  wire                 clk,
    input  wire                 rxen,

    output reg                  recvo_gotbit,
    output reg                  recvo_gotnull,
    output reg                  recvo_gotfct,
    output reg                  recvo_tick_out,
    output reg  [1:0]           recvo_ctrl_out,
    output reg  [5:0]           recvo_time_out,
    output reg                  recvo_rxchar,
    output reg                  recvo_rxflag,
    output reg  [7:0]           recvo_rxdata,
    output reg                  recvo_errdisc,
    output reg                  recvo_errpar,
    output reg                  recvo_erresc,

    input  wire                 inact,
    input  wire                 inbvalid,
    input  wire [RXCHUNK-1:0]   inbits
);

    reg        bit_seen;
    reg        null_seen;
    reg [8:0]  bitshift;
    reg [9:0]  bitcnt;
    reg        parity;
    reg        control;
    reg        escaped;
    reg        gotfct;
    reg        tick_out;
    reg        rxchar;
    reg        rxflag;
    reg [7:0]  timereg;
    reg [7:0]  datareg;
    reg [7:0]  disccnt;
    reg        errpar;
    reg        erresc;

    reg        v_bit_seen;
    reg        v_null_seen;
    reg [8:0]  v_bitshift;
    reg [9:0]  v_bitcnt;
    reg        v_parity;
    reg        v_control;
    reg        v_escaped;
    reg        v_gotfct;
    reg        v_tick_out;
    reg        v_rxchar;
    reg        v_rxflag;
    reg [7:0]  v_timereg;
    reg [7:0]  v_datareg;
    reg [7:0]  v_disccnt;
    reg        v_errpar;
    reg        v_erresc;
    reg        v_inbit;
    integer    i;

    always @* begin
        v_bit_seen = bit_seen;
        v_null_seen = null_seen;
        v_bitshift = bitshift;
        v_bitcnt = bitcnt;
        v_parity = parity;
        v_control = control;
        v_escaped = escaped;
        v_gotfct = gotfct;
        v_tick_out = tick_out;
        v_rxchar = rxchar;
        v_rxflag = rxflag;
        v_timereg = timereg;
        v_datareg = datareg;
        v_disccnt = disccnt;
        v_errpar = errpar;
        v_erresc = erresc;
        v_inbit = 1'b0;

        if (inact) begin
            v_disccnt = DISCONNECT_TIME;
        end else if (disccnt != 8'd0) begin
            v_disccnt = disccnt - 8'd1;
        end

        v_gotfct = 1'b0;
        v_tick_out = 1'b0;
        v_rxchar = 1'b0;

        if (inbvalid) begin
            for (i = 0; i < RXCHUNK; i = i + 1) begin
                v_inbit = inbits[i];
                v_bit_seen = 1'b1;

                if (v_bitcnt[0]) begin
                    if ((v_parity ^ v_inbit) == 1'b0) begin
                        v_errpar = 1'b1;
                    end else begin
                        if (v_control) begin
                            case (v_bitshift[7:6])
                                2'b00: begin
                                    v_gotfct = !escaped;
                                    v_escaped = 1'b0;
                                end
                                2'b10: begin
                                    if (escaped) begin
                                        v_erresc = 1'b1;
                                    end
                                    v_escaped = 1'b0;
                                    v_rxchar = !escaped;
                                    v_rxflag = 1'b1;
                                    v_datareg = 8'b00000000;
                                end
                                2'b01: begin
                                    if (escaped) begin
                                        v_erresc = 1'b1;
                                    end
                                    v_escaped = 1'b0;
                                    v_rxchar = !escaped;
                                    v_rxflag = 1'b1;
                                    v_datareg = 8'b00000001;
                                end
                                default: begin
                                    if (escaped) begin
                                        v_erresc = 1'b1;
                                    end
                                    v_escaped = 1'b1;
                                end
                            endcase
                        end else begin
                            if (escaped) begin
                                v_tick_out = 1'b1;
                                v_timereg = v_bitshift[7:0];
                            end else begin
                                v_rxflag = 1'b0;
                                v_rxchar = 1'b1;
                                v_datareg = v_bitshift[7:0];
                            end
                            v_escaped = 1'b0;
                        end
                    end

                    v_parity = 1'b0;
                    v_control = v_inbit;
                    if (v_inbit) begin
                        v_bitcnt = 10'b0000001000;
                    end else begin
                        v_bitcnt = 10'b1000000000;
                    end
                end else begin
                    v_bitcnt = {1'b0, v_bitcnt[9:1]};
                    v_parity = v_parity ^ v_inbit;
                end

                if (!v_null_seen) begin
                    if (v_bitshift == 9'b000101110) begin
                        v_null_seen = 1'b1;
                        v_control = v_inbit;
                        v_parity = 1'b0;
                        v_bitcnt = 10'b0000001000;
                    end
                end

                v_bitshift = {v_inbit, v_bitshift[8:1]};
            end
        end

        if (!rxen) begin
            v_bit_seen = 1'b0;
            v_null_seen = 1'b0;
            v_bitshift = 9'b111111111;
            v_bitcnt = 10'b0000000000;
            v_gotfct = 1'b0;
            v_tick_out = 1'b0;
            v_rxchar = 1'b0;
            v_rxflag = 1'b0;
            v_escaped = 1'b0;
            v_timereg = 8'b00000000;
            v_datareg = 8'b00000000;
            v_disccnt = 8'b00000000;
            v_errpar = 1'b0;
            v_erresc = 1'b0;
        end

        recvo_gotbit = bit_seen;
        recvo_gotnull = null_seen;
        recvo_gotfct = gotfct;
        recvo_tick_out = tick_out;
        recvo_ctrl_out = timereg[7:6];
        recvo_time_out = timereg[5:0];
        recvo_rxchar = rxchar;
        recvo_rxflag = rxflag;
        recvo_rxdata = datareg;
        recvo_errdisc = bit_seen && (disccnt == 8'd0);
        recvo_errpar = errpar;
        recvo_erresc = erresc;
    end

    always @(posedge clk) begin
        bit_seen <= v_bit_seen;
        null_seen <= v_null_seen;
        bitshift <= v_bitshift;
        bitcnt <= v_bitcnt;
        parity <= v_parity;
        control <= v_control;
        escaped <= v_escaped;
        gotfct <= v_gotfct;
        tick_out <= v_tick_out;
        rxchar <= v_rxchar;
        rxflag <= v_rxflag;
        timereg <= v_timereg;
        datareg <= v_datareg;
        disccnt <= v_disccnt;
        errpar <= v_errpar;
        erresc <= v_erresc;
    end

    initial begin
        bit_seen = 1'b0;
        null_seen = 1'b0;
        bitshift = 9'b111111111;
        bitcnt = 10'b0000000000;
        parity = 1'b0;
        control = 1'b0;
        escaped = 1'b0;
        gotfct = 1'b0;
        tick_out = 1'b0;
        rxchar = 1'b0;
        rxflag = 1'b0;
        timereg = 8'b00000000;
        datareg = 8'b00000000;
        disccnt = 8'b00000000;
        errpar = 1'b0;
        erresc = 1'b0;
    end

endmodule
