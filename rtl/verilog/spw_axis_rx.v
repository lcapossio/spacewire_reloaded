/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * SpaceWire N-Char receive to AXI-Stream bridge.
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

    wire output_valid = rxvalid && !rst;

    assign m_axis_tdata = rxdata;
    assign m_axis_tvalid = output_valid;
    assign m_axis_tlast = rxflag;
    assign m_axis_tuser[0] = rxflag;
    assign rxread = output_valid && m_axis_tready;

endmodule
