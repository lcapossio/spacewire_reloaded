/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * AXI-Stream to SpaceWire N-Char transmit bridge.
 */

`timescale 1ns / 1ps

module spw_axis_tx (
    input  wire       clk,
    input  wire       rst,

    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tvalid,
    output wire       s_axis_tready,
    input  wire       s_axis_tlast,
    input  wire [0:0] s_axis_tuser,

    output wire       txwrite,
    output wire       txflag,
    output wire [7:0] txdata,
    input  wire       txrdy
);

    assign s_axis_tready = txrdy && !rst;
    assign txwrite = s_axis_tvalid && txrdy && !rst;
    assign txflag = s_axis_tuser[0];
    assign txdata = s_axis_tdata;

endmodule
