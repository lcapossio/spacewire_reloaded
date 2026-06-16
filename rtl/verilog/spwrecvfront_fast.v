/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * Fast front-end for SpaceWire Receiver.
 *
 * Verilog 2001 translation of rtl/vhdl/spwrecvfront_fast.vhd from
 * SpaceWire Light. The implementation keeps the original dual-clock
 * cyclic-buffer structure.
 */

`timescale 1ns / 1ps

module spwrecvfront_fast #(
    parameter RXCHUNK = 1
) (
    input  wire               clk,
    input  wire               rxclk,
    input  wire               rxen,
    output reg                inact,
    output reg                inbvalid,
    output reg  [RXCHUNK-1:0] inbits,
    input  wire               spw_di,
    input  wire               spw_si
);

    localparam MEMWIDTH = (RXCHUNK <= 2) ? 2 : RXCHUNK;

    reg [2:0] tailptr;
    reg       inbvalid_r;
    reg       splitbit;
    reg       splitinx;
    reg       splitvalid;
    reg [2:0] bitcntp;
    reg       inact_r;
    reg       rxdis;

    reg [2:0] v_tailptr;
    reg       v_inbvalid_r;
    reg       v_splitbit;
    reg       v_splitinx;
    reg       v_splitvalid;
    reg [2:0] v_bitcntp;
    reg       v_inact_r;
    reg       v_rxdis;

    reg       b_di0;
    reg       b_si0;
    reg       b_di1;
    reg       b_si1;
    reg [1:0] c_bit;
    reg [1:0] c_val;
    reg       c_xor1;
    reg [MEMWIDTH-1:0] d_shift;
    reg [MEMWIDTH-1:0] d_count;
    reg [MEMWIDTH-1:0] bufdata;
    reg       bufwrite;
    reg [2:0] headptr;
    reg [2:0] headptr_gray;
    reg [2:0] bitcnt;

    reg       v_b_di0;
    reg       v_b_si0;
    reg       v_b_di1;
    reg       v_b_si1;
    reg [1:0] v_c_bit;
    reg [1:0] v_c_val;
    reg       v_c_xor1;
    reg [MEMWIDTH-1:0] v_d_shift;
    reg [MEMWIDTH-1:0] v_d_count;
    reg [MEMWIDTH-1:0] v_bufdata;
    reg       v_bufwrite;
    reg [2:0] v_headptr;
    reg [2:0] v_headptr_gray;
    reg [2:0] v_headptr_bin;
    reg [2:0] v_bitcnt;

    wire syncrx_rstn;
    wire [2:0] syncsys_headptr_gray;
    wire [2:0] syncsys_bitcnt;
    wire [MEMWIDTH-1:0] bufdout;

    reg a_di0;
    reg a_si0;
    reg a_di1;
    reg a_si1;
    reg a_di2;
    reg a_si2;

    function [MEMWIDTH-1:0] shift_in_one;
        input [MEMWIDTH-1:0] din;
        input bit0;
        integer k;
        begin
            for (k = 0; k < MEMWIDTH; k = k + 1) begin
                if (k == MEMWIDTH-1) begin
                    shift_in_one[k] = bit0;
                end else begin
                    shift_in_one[k] = din[k+1];
                end
            end
        end
    endfunction

    function [MEMWIDTH-1:0] shift_in_two;
        input [MEMWIDTH-1:0] din;
        input [1:0] bits;
        integer k;
        begin
            for (k = 0; k < MEMWIDTH; k = k + 1) begin
                if (k < MEMWIDTH-2) begin
                    shift_in_two[k] = din[k+2];
                end else begin
                    shift_in_two[k] = bits[k-(MEMWIDTH-2)];
                end
            end
        end
    endfunction

    function [MEMWIDTH-1:0] rotate_one;
        input [MEMWIDTH-1:0] din;
        integer k;
        begin
            for (k = 0; k < MEMWIDTH; k = k + 1) begin
                if (k == MEMWIDTH-1) begin
                    rotate_one[k] = din[0];
                end else begin
                    rotate_one[k] = din[k+1];
                end
            end
        end
    endfunction

    function [MEMWIDTH-1:0] rotate_two;
        input [MEMWIDTH-1:0] din;
        integer k;
        begin
            for (k = 0; k < MEMWIDTH; k = k + 1) begin
                if (k < MEMWIDTH-2) begin
                    rotate_two[k] = din[k+2];
                end else begin
                    rotate_two[k] = din[k-(MEMWIDTH-2)];
                end
            end
        end
    endfunction

    spwram #(
        .ABITS(3),
        .DBITS(MEMWIDTH)
    ) bufmem (
        .rclk(clk),
        .wclk(rxclk),
        .ren(1'b1),
        .raddr(tailptr),
        .rdata(bufdout),
        .wen(bufwrite),
        .waddr(headptr),
        .wdata(bufdata)
    );

    // The head pointer is gray-coded before crossing so the system clock
    // domain can never sample an illegal intermediate value while the pointer
    // increments (gray code changes only one bit per +1 step).
    syncdff syncrx_reset (.clk(rxclk), .rst(rxdis), .di(1'b1), .do(syncrx_rstn));
    syncdff syncsys_headptr0 (.clk(clk), .rst(rxdis), .di(headptr_gray[0]), .do(syncsys_headptr_gray[0]));
    syncdff syncsys_headptr1 (.clk(clk), .rst(rxdis), .di(headptr_gray[1]), .do(syncsys_headptr_gray[1]));
    syncdff syncsys_headptr2 (.clk(clk), .rst(rxdis), .di(headptr_gray[2]), .do(syncsys_headptr_gray[2]));
    syncdff syncsys_bitcnt0 (.clk(clk), .rst(rxdis), .di(bitcnt[0]), .do(syncsys_bitcnt[0]));
    syncdff syncsys_bitcnt1 (.clk(clk), .rst(rxdis), .di(bitcnt[1]), .do(syncsys_bitcnt[1]));
    syncdff syncsys_bitcnt2 (.clk(clk), .rst(rxdis), .di(bitcnt[2]), .do(syncsys_bitcnt[2]));

    always @(posedge rxclk) begin
        a_di1 <= spw_di;
        a_si1 <= spw_si;
    end

    always @(negedge rxclk) begin
        a_di2 <= spw_di;
        a_si2 <= spw_si;
        a_di0 <= a_di2;
        a_si0 <= a_si2;
    end

    always @* begin
        v_b_di0 = b_di0;
        v_b_si0 = b_si0;
        v_b_di1 = b_di1;
        v_b_si1 = b_si1;
        v_c_bit = c_bit;
        v_c_val = c_val;
        v_c_xor1 = c_xor1;
        v_d_shift = d_shift;
        v_d_count = d_count;
        v_bufdata = bufdata;
        v_bufwrite = bufwrite;
        v_headptr = headptr;
        v_headptr_gray = headptr_gray;
        v_bitcnt = bitcnt;

        v_tailptr = tailptr;
        v_inbvalid_r = inbvalid_r;
        v_splitbit = splitbit;
        v_splitinx = splitinx;
        v_splitvalid = splitvalid;
        v_bitcntp = bitcntp;
        v_inact_r = inact_r;
        v_rxdis = rxdis;

        v_b_di0 = a_di0;
        v_b_si0 = a_si0;
        v_b_di1 = a_di1;
        v_b_si1 = a_si1;

        if ((b_di0 ^ b_si0 ^ c_xor1) == 1'b1) begin
            v_c_bit[0] = b_di0;
        end else begin
            v_c_bit[0] = b_di1;
        end
        v_c_bit[1] = b_di1;
        v_c_val[0] = (b_di0 ^ b_si0 ^ c_xor1) |
                     (b_di0 ^ b_si0 ^ b_di1 ^ b_si1);
        v_c_val[1] = (b_di0 ^ b_si0 ^ c_xor1) &
                     (b_di0 ^ b_si0 ^ b_di1 ^ b_si1);
        v_c_xor1 = b_di1 ^ b_si1;

        if (c_val[0]) begin
            if (c_val[1]) begin
                v_d_shift = shift_in_two(d_shift, c_bit);
            end else begin
                v_d_shift = shift_in_one(d_shift, c_bit[0]);
            end

            if (d_count[0]) begin
                v_bufdata = shift_in_one(d_shift, c_bit[0]);
            end else begin
                v_bufdata = shift_in_two(d_shift, c_bit);
            end

            if (c_val[1]) begin
                v_d_count = rotate_two(d_count);
            end else begin
                v_d_count = rotate_one(d_count);
            end
        end

        v_bufwrite = c_val[0] && (d_count[0] || (c_val[1] && d_count[1]));

        if (bufwrite) begin
            v_headptr = headptr + 3'd1;
        end

        if (c_val[0]) begin
            v_bitcnt = bitcnt + 3'd1;
        end

        if (!syncrx_rstn) begin
            v_c_val = 2'b00;
            v_c_xor1 = 1'b0;
            v_d_count = {MEMWIDTH{1'b0}};
            v_d_count[MEMWIDTH-1] = 1'b1;
            v_bufwrite = 1'b0;
            v_headptr = 3'b000;
            v_bitcnt = 3'b000;
        end

        // Gray-code the head pointer for the clock-domain crossing. Derived
        // from the next-state binary value so headptr_gray tracks headptr in
        // lockstep (gray(0) = 0, so this also holds after reset).
        v_headptr_gray = v_headptr ^ {1'b0, v_headptr[2:1]};

        // Convert the synchronized gray-coded head pointer back to binary.
        v_headptr_bin[2] = syncsys_headptr_gray[2];
        v_headptr_bin[1] = syncsys_headptr_gray[2] ^ syncsys_headptr_gray[1];
        v_headptr_bin[0] = syncsys_headptr_gray[2] ^ syncsys_headptr_gray[1] ^
                           syncsys_headptr_gray[0];

        if (tailptr == v_headptr_bin) begin
            v_inbvalid_r = 1'b0;
        end else begin
            v_inbvalid_r = 1'b1;
            if (RXCHUNK != 1) begin
                v_tailptr = tailptr + 3'd1;
            end
        end

        if (RXCHUNK == 1) begin
            if (!splitinx) begin
                v_splitbit = bufdout[0];
            end else begin
                v_splitbit = bufdout[1];
            end
            v_splitvalid = inbvalid_r;
            if (inbvalid_r) begin
                v_splitinx = !splitinx;
                if (!splitinx) begin
                    v_tailptr = tailptr + 3'd1;
                end
            end
        end

        v_bitcntp = syncsys_bitcnt;
        v_inact_r = (bitcntp != syncsys_bitcnt);

        if (!rxen) begin
            v_tailptr = 3'b000;
            v_inbvalid_r = 1'b0;
            v_splitbit = 1'b0;
            v_splitinx = 1'b0;
            v_splitvalid = 1'b0;
            v_bitcntp = 3'b000;
            v_inact_r = 1'b0;
            v_rxdis = 1'b1;
        end

        v_rxdis = !rxen;

        inact = inact_r;
        if (RXCHUNK == 1) begin
            inbvalid = splitvalid;
            inbits[0] = splitbit;
        end else begin
            inbvalid = inbvalid_r;
            inbits = bufdout[RXCHUNK-1:0];
        end
    end

    always @(posedge rxclk) begin
        b_di0 <= v_b_di0;
        b_si0 <= v_b_si0;
        b_di1 <= v_b_di1;
        b_si1 <= v_b_si1;
        c_bit <= v_c_bit;
        c_val <= v_c_val;
        c_xor1 <= v_c_xor1;
        d_shift <= v_d_shift;
        d_count <= v_d_count;
        bufdata <= v_bufdata;
        bufwrite <= v_bufwrite;
        headptr <= v_headptr;
        headptr_gray <= v_headptr_gray;
        bitcnt <= v_bitcnt;
    end

    always @(posedge clk) begin
        tailptr <= v_tailptr;
        inbvalid_r <= v_inbvalid_r;
        splitbit <= v_splitbit;
        splitinx <= v_splitinx;
        splitvalid <= v_splitvalid;
        bitcntp <= v_bitcntp;
        inact_r <= v_inact_r;
        rxdis <= v_rxdis;
    end

    initial begin
        tailptr = 3'b000;
        inbvalid_r = 1'b0;
        splitbit = 1'b0;
        splitinx = 1'b0;
        splitvalid = 1'b0;
        bitcntp = 3'b000;
        inact_r = 1'b0;
        rxdis = 1'b1;
        b_di0 = 1'b0;
        b_si0 = 1'b0;
        b_di1 = 1'b0;
        b_si1 = 1'b0;
        c_bit = 2'b00;
        c_val = 2'b00;
        c_xor1 = 1'b0;
        d_shift = {MEMWIDTH{1'b0}};
        d_count = {MEMWIDTH{1'b0}};
        d_count[MEMWIDTH-1] = 1'b1;
        bufdata = {MEMWIDTH{1'b0}};
        bufwrite = 1'b0;
        headptr = 3'b000;
        headptr_gray = 3'b000;
        bitcnt = 3'b000;
        a_di0 = 1'b0;
        a_si0 = 1'b0;
        a_di1 = 1'b0;
        a_si1 = 1'b0;
        a_di2 = 1'b0;
        a_si2 = 1'b0;
    end

endmodule
