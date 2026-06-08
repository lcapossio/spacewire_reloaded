/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * Basic Verilog smoke test for the translated generic spwstream path.
 *
 * This is intentionally small: two SpaceWire stream cores are connected
 * back-to-back, one data byte and one EOP are sent from A to B, and the
 * received characters are checked.
 */

`timescale 1ns / 1ps

module spwstream_fast_smoke_tb;

    reg clk;
    reg rxclk;
    reg txclk;
    reg rst;

    reg a_txwrite;
    reg a_txflag;
    reg [7:0] a_txdata;
    wire a_txrdy;
    wire a_txhalff;
    wire a_tick_out;
    wire [1:0] a_ctrl_out;
    wire [5:0] a_time_out;
    wire a_rxvalid;
    wire a_rxhalff;
    wire a_rxflag;
    wire [7:0] a_rxdata;
    reg a_rxread;
    wire a_started;
    wire a_connecting;
    wire a_running;
    wire a_errdisc;
    wire a_errpar;
    wire a_erresc;
    wire a_errcred;
    wire a_do;
    wire a_so;

    reg b_txwrite;
    reg b_txflag;
    reg [7:0] b_txdata;
    wire b_txrdy;
    wire b_txhalff;
    wire b_tick_out;
    wire [1:0] b_ctrl_out;
    wire [5:0] b_time_out;
    wire b_rxvalid;
    wire b_rxhalff;
    wire b_rxflag;
    wire [7:0] b_rxdata;
    reg b_rxread;
    wire b_started;
    wire b_connecting;
    wire b_running;
    wire b_errdisc;
    wire b_errpar;
    wire b_erresc;
    wire b_errcred;
    wire b_do;
    wire b_so;

    integer timeout;

    initial begin
        clk = 1'b0;
        forever #25 clk = !clk;
    end

    initial begin
        rxclk = 1'b0;
        forever #10 rxclk = !rxclk;
    end

    initial begin
        txclk = 1'b0;
        forever #10 txclk = !txclk;
    end

    spwstream #(
        .RESET_TIME(11'd20),
        .DISCONNECT_TIME(8'd20),
        .DEFAULT_DIVCNT(8'd3),
        .RXIMPL(1),
        .TXIMPL(1),
        .RXCHUNK(4),
        .RXFIFOSIZE_BITS(6),
        .TXFIFOSIZE_BITS(4)
    ) dut_a (
        .clk(clk),
        .rxclk(rxclk),
        .txclk(txclk),
        .rst(rst),
        .autostart(1'b1),
        .linkstart(1'b1),
        .linkdis(1'b0),
        .txdivcnt(8'd1),
        .tick_in(1'b0),
        .ctrl_in(2'b00),
        .time_in(6'b000000),
        .txwrite(a_txwrite),
        .txflag(a_txflag),
        .txdata(a_txdata),
        .txrdy(a_txrdy),
        .txhalff(a_txhalff),
        .tick_out(a_tick_out),
        .ctrl_out(a_ctrl_out),
        .time_out(a_time_out),
        .rxvalid(a_rxvalid),
        .rxhalff(a_rxhalff),
        .rxflag(a_rxflag),
        .rxdata(a_rxdata),
        .rxread(a_rxread),
        .started(a_started),
        .connecting(a_connecting),
        .running(a_running),
        .errdisc(a_errdisc),
        .errpar(a_errpar),
        .erresc(a_erresc),
        .errcred(a_errcred),
        .spw_di(b_do),
        .spw_si(b_so),
        .spw_do(a_do),
        .spw_so(a_so)
    );

    spwstream #(
        .RESET_TIME(11'd20),
        .DISCONNECT_TIME(8'd20),
        .DEFAULT_DIVCNT(8'd3),
        .RXIMPL(1),
        .TXIMPL(1),
        .RXCHUNK(4),
        .RXFIFOSIZE_BITS(6),
        .TXFIFOSIZE_BITS(4)
    ) dut_b (
        .clk(clk),
        .rxclk(rxclk),
        .txclk(txclk),
        .rst(rst),
        .autostart(1'b1),
        .linkstart(1'b1),
        .linkdis(1'b0),
        .txdivcnt(8'd1),
        .tick_in(1'b0),
        .ctrl_in(2'b00),
        .time_in(6'b000000),
        .txwrite(b_txwrite),
        .txflag(b_txflag),
        .txdata(b_txdata),
        .txrdy(b_txrdy),
        .txhalff(b_txhalff),
        .tick_out(b_tick_out),
        .ctrl_out(b_ctrl_out),
        .time_out(b_time_out),
        .rxvalid(b_rxvalid),
        .rxhalff(b_rxhalff),
        .rxflag(b_rxflag),
        .rxdata(b_rxdata),
        .rxread(b_rxread),
        .started(b_started),
        .connecting(b_connecting),
        .running(b_running),
        .errdisc(b_errdisc),
        .errpar(b_errpar),
        .erresc(b_erresc),
        .errcred(b_errcred),
        .spw_di(a_do),
        .spw_si(a_so),
        .spw_do(b_do),
        .spw_so(b_so)
    );

    task wait_link_running;
        begin
            timeout = 20000;
            while (!(a_running && b_running) && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                $display("ERROR: link did not enter Run state");
                $finish;
            end
        end
    endtask

    task write_a_char;
        input flag;
        input [7:0] data;
        begin
            @(posedge clk);
            while (!a_txrdy) begin
                @(posedge clk);
            end
            a_txflag <= flag;
            a_txdata <= data;
            a_txwrite <= 1'b1;
            @(posedge clk);
            a_txwrite <= 1'b0;
        end
    endtask

    task expect_b_char;
        input flag;
        input [7:0] data;
        begin
            timeout = 20000;
            while (!b_rxvalid && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                $display("ERROR: timed out waiting for RX character");
                $finish;
            end
            if (b_rxflag !== flag || b_rxdata !== data) begin
                $display("ERROR: expected flag=%b data=%02x, got flag=%b data=%02x",
                         flag, data, b_rxflag, b_rxdata);
                $finish;
            end
            b_rxread <= 1'b1;
            @(posedge clk);
            b_rxread <= 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        rst = 1'b1;
        a_txwrite = 1'b0;
        a_txflag = 1'b0;
        a_txdata = 8'h00;
        a_rxread = 1'b0;
        b_txwrite = 1'b0;
        b_txflag = 1'b0;
        b_txdata = 8'h00;
        b_rxread = 1'b0;

        repeat (8) @(posedge clk);
        rst = 1'b0;

        wait_link_running;
        write_a_char(1'b0, 8'ha5);
        write_a_char(1'b1, 8'h00);
        expect_b_char(1'b0, 8'ha5);
        expect_b_char(1'b1, 8'h00);

        if (a_errdisc || a_errpar || a_erresc || a_errcred ||
            b_errdisc || b_errpar || b_erresc || b_errcred) begin
            $display("ERROR: unexpected link error");
            $finish;
        end

        $display("PASS: spwstream fast smoke test");
        $finish;
    end

endmodule
