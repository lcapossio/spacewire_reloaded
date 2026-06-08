/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * Synchronous two-port RAM with separate clocks for read and write ports.
 *
 * Verilog 2001 translation of rtl/vhdl/spwram.vhd from SpaceWire Light.
 */

`timescale 1ns / 1ps

module spwram #(
    parameter ABITS = 11,
    parameter DBITS = 9
) (
    input  wire                  rclk,
    input  wire                  wclk,
    input  wire                  ren,
    input  wire [ABITS-1:0]      raddr,
    output reg  [DBITS-1:0]      rdata,
    input  wire                  wen,
    input  wire [ABITS-1:0]      waddr,
    input  wire [DBITS-1:0]      wdata
);

    reg [DBITS-1:0] mem [0:(1 << ABITS)-1];

    always @(posedge rclk) begin
        if (ren) begin
            rdata <= mem[raddr];
        end
    end

    always @(posedge wclk) begin
        if (wen) begin
            mem[waddr] <= wdata;
        end
    end

endmodule

