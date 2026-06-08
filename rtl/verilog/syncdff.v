/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * Double flip-flop synchronizer.
 *
 * Verilog 2001 translation of rtl/vhdl/syncdff.vhd from SpaceWire Light.
 */

`timescale 1ns / 1ps

module syncdff (
    input  wire clk,
    input  wire rst,
    input  wire di,
    output wire do
);

    reg syncdff_ff1;
    reg syncdff_ff2;

    assign do = syncdff_ff2;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            syncdff_ff1 <= 1'b0;
            syncdff_ff2 <= 1'b0;
        end else begin
            syncdff_ff1 <= di;
            syncdff_ff2 <= syncdff_ff1;
        end
    end

endmodule

