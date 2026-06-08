/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * Front-end for SpaceWire Receiver.
 *
 * Verilog 2001 translation of rtl/vhdl/spwrecvfront_generic.vhd from
 * SpaceWire Light.
 */

`timescale 1ns / 1ps

module spwrecvfront_generic (
    input  wire clk,
    input  wire rxen,
    output wire inact,
    output wire inbvalid,
    output wire inbits,
    input  wire spw_di,
    input  wire spw_si
);

    reg spwdi1;
    reg spwsi1;
    reg spwdi2;
    reg spwsi2;
    reg spwsi3;
    reg inbvalid_r;
    reg inbit;

    assign inact = inbvalid_r;
    assign inbvalid = inbvalid_r;
    assign inbits = inbit;

    always @(posedge clk) begin
        spwdi1 <= spw_di;
        spwsi1 <= spw_si;

        spwdi2 <= spwdi1;
        spwsi2 <= spwsi1;

        spwsi3 <= spwsi2;
        inbit <= spwdi2;

        if (rxen) begin
            inbvalid_r <= spwdi2 ^ spwsi2 ^ inbit ^ spwsi3;
        end else begin
            inbvalid_r <= 1'b0;
        end
    end

    initial begin
        spwdi1 = 1'b0;
        spwsi1 = 1'b0;
        spwdi2 = 1'b0;
        spwsi2 = 1'b0;
        spwsi3 = 1'b0;
        inbvalid_r = 1'b0;
        inbit = 1'b0;
    end

endmodule

