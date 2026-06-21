/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * SpaceWire N-Char receive to AXI-Stream bridge.
 *
 * The output is a 1-deep registered (skid) AXI-Stream stage whose holding
 * register is reset ONLY by the AXI bus reset (rst). A beat already presented
 * on m_axis therefore survives a SpaceWire-core flush (e.g. the CONTROL[0] soft
 * reset, which resets the core/RX FIFO but not the AXI bus): TVALID stays
 * asserted with stable payload until TREADY completes the handshake, as
 * AXI-Stream requires. A purely combinational bridge would retract TVALID when
 * the soft reset cleared rxvalid -- an AXI-Stream protocol violation.
 */

`timescale 1ns / 1ps

module spw_axis_rx (
    input  wire       clk,
    input  wire       rst,

    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tvalid,
    input  wire       m_axis_tready,
    output wire       m_axis_tlast,
    output wire [0:0] m_axis_tuser,

    input  wire       rxvalid,
    input  wire       rxflag,
    input  wire [7:0] rxdata,
    output wire       rxread
);

    reg       beat_valid;
    reg       beat_flag;
    reg [7:0] beat_data;

    // Accept a char from the core RX FIFO when the holding register is empty or
    // is being drained this cycle (no-bubble, full throughput).
    assign rxread = rxvalid && (!beat_valid || m_axis_tready) && !rst;

    assign m_axis_tvalid   = beat_valid && !rst;
    assign m_axis_tlast    = beat_flag;
    assign m_axis_tuser[0] = beat_flag && beat_data[0];
    assign m_axis_tdata    = beat_flag ? {7'd0, beat_data[0]} : beat_data;

    always @(posedge clk) begin
        if (rst) begin
            beat_valid <= 1'b0;
        end else begin
            if (m_axis_tready) begin
                beat_valid <= 1'b0;
            end
            if (rxread) begin
                beat_valid <= 1'b1;
                beat_flag  <= rxflag;
                beat_data  <= rxdata;
            end
        end
    end

    initial begin
        beat_valid = 1'b0;
        beat_flag  = 1'b0;
        beat_data  = 8'd0;
    end

endmodule
