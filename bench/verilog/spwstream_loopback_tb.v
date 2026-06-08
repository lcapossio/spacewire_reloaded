/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * Broader Verilog loopback test for the translated spwstream core.
 *
 * Exercises generic and fast configurations with packet data, EOP,
 * timecode transfer, link disable/re-enable and physical disconnect/reconnect.
 */

`timescale 1ns / 1ps

module spwstream_loopback_case #(
    parameter RXIMPL = 0,
    parameter TXIMPL = 0,
    parameter RXCHUNK = 1
) (
    output reg done,
    output reg failed
);

    reg clk;
    reg rxclk;
    reg txclk;
    reg rst;
    reg linkstart;
    reg autostart;
    reg linkdis;
    reg loopback;
    reg [7:0] txdivcnt;
    reg tick_in;
    reg [1:0] ctrl_in;
    reg [5:0] time_in;
    reg txwrite;
    reg txflag;
    reg [7:0] txdata;
    wire txrdy;
    wire txhalff;
    wire tick_out;
    wire [1:0] ctrl_out;
    wire [5:0] time_out;
    wire rxvalid;
    wire rxhalff;
    wire rxflag;
    wire [7:0] rxdata;
    reg rxread;
    wire started;
    wire connecting;
    wire running;
    wire errdisc;
    wire errpar;
    wire erresc;
    wire errcred;
    wire spw_di;
    wire spw_si;
    wire spw_do;
    wire spw_so;

    integer timeout;
    integer i;

    assign spw_di = loopback ? spw_do : 1'b0;
    assign spw_si = loopback ? spw_so : 1'b0;

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
        .DEFAULT_DIVCNT(TXIMPL ? 8'd3 : 8'd1),
        .RXIMPL(RXIMPL),
        .TXIMPL(TXIMPL),
        .RXCHUNK(RXCHUNK),
        .RXFIFOSIZE_BITS(6),
        .TXFIFOSIZE_BITS(4)
    ) dut (
        .clk(clk),
        .rxclk(rxclk),
        .txclk(txclk),
        .rst(rst),
        .autostart(autostart),
        .linkstart(linkstart),
        .linkdis(linkdis),
        .txdivcnt(txdivcnt),
        .tick_in(tick_in),
        .ctrl_in(ctrl_in),
        .time_in(time_in),
        .txwrite(txwrite),
        .txflag(txflag),
        .txdata(txdata),
        .txrdy(txrdy),
        .txhalff(txhalff),
        .tick_out(tick_out),
        .ctrl_out(ctrl_out),
        .time_out(time_out),
        .rxvalid(rxvalid),
        .rxhalff(rxhalff),
        .rxflag(rxflag),
        .rxdata(rxdata),
        .rxread(rxread),
        .started(started),
        .connecting(connecting),
        .running(running),
        .errdisc(errdisc),
        .errpar(errpar),
        .erresc(erresc),
        .errcred(errcred),
        .spw_di(spw_di),
        .spw_si(spw_si),
        .spw_do(spw_do),
        .spw_so(spw_so)
    );

    task fail;
        input [8*80-1:0] msg;
        begin
            $display("ERROR: %0s", msg);
            failed = 1'b1;
            done = 1'b1;
        end
    endtask

    task wait_running;
        begin
            timeout = 30000;
            while (!running && timeout > 0 && !failed) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail("link did not enter Run state");
            end
        end
    endtask

    task write_char;
        input flag;
        input [7:0] data;
        begin
            timeout = 30000;
            while (!txrdy && timeout > 0 && !failed) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail("TX FIFO did not become ready");
            end else begin
                txflag <= flag;
                txdata <= data;
                txwrite <= 1'b1;
                @(posedge clk);
                txwrite <= 1'b0;
            end
        end
    endtask

    task expect_char;
        input flag;
        input [7:0] data;
        begin
            timeout = 30000;
            while (!rxvalid && timeout > 0 && !failed) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail("RX FIFO did not produce expected character");
            end else if (rxflag !== flag || rxdata !== data) begin
                $display("ERROR: expected flag=%b data=%02x, got flag=%b data=%02x",
                         flag, data, rxflag, rxdata);
                failed = 1'b1;
                done = 1'b1;
            end else begin
                rxread <= 1'b1;
                @(posedge clk);
                rxread <= 1'b0;
                @(posedge clk);
            end
        end
    endtask

    task expect_timecode;
        input [1:0] ctrl;
        input [5:0] tim;
        begin
            timeout = 30000;
            while (!tick_out && timeout > 0 && !failed) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                fail("timecode was not received");
            end else if (ctrl_out !== ctrl || time_out !== tim) begin
                $display("ERROR: expected timecode ctrl=%b time=%02x, got ctrl=%b time=%02x",
                         ctrl, tim, ctrl_out, time_out);
                failed = 1'b1;
                done = 1'b1;
            end
        end
    endtask

    task send_timecode;
        input [1:0] ctrl;
        input [5:0] tim;
        begin
            @(posedge clk);
            ctrl_in <= ctrl;
            time_in <= tim;
            tick_in <= 1'b1;
            @(posedge clk);
            tick_in <= 1'b0;
            expect_timecode(ctrl, tim);
        end
    endtask

    initial begin
        done = 1'b0;
        failed = 1'b0;
        rst = 1'b1;
        linkstart = 1'b0;
        autostart = 1'b1;
        linkdis = 1'b0;
        loopback = 1'b1;
        txdivcnt = TXIMPL ? 8'd3 : 8'd1;
        tick_in = 1'b0;
        ctrl_in = 2'b00;
        time_in = 6'b000000;
        txwrite = 1'b0;
        txflag = 1'b0;
        txdata = 8'h00;
        rxread = 1'b0;

        repeat (8) @(posedge clk);
        rst = 1'b0;
        linkstart = 1'b1;
        wait_running;

        for (i = 0; i < 12 && !failed; i = i + 1) begin
            write_char(1'b0, 8'h40 + i[7:0]);
        end
        write_char(1'b1, 8'h00);

        for (i = 0; i < 12 && !failed; i = i + 1) begin
            expect_char(1'b0, 8'h40 + i[7:0]);
        end
        expect_char(1'b1, 8'h00);

        send_timecode(2'b10, 6'h15);

        txdivcnt = TXIMPL ? 8'd4 : 8'd2;
        repeat (200) @(posedge clk);
        write_char(1'b0, 8'hc3);
        write_char(1'b1, 8'h00);
        expect_char(1'b0, 8'hc3);
        expect_char(1'b1, 8'h00);

        linkdis = 1'b1;
        repeat (200) @(posedge clk);
        linkdis = 1'b0;
        wait_running;
        write_char(1'b0, 8'h5a);
        write_char(1'b1, 8'h00);
        expect_char(1'b0, 8'h5a);
        expect_char(1'b1, 8'h00);

        loopback = 1'b0;
        repeat (200) @(posedge clk);
        loopback = 1'b1;
        wait_running;
        write_char(1'b0, 8'ha6);
        write_char(1'b1, 8'h00);
        expect_char(1'b0, 8'ha6);
        expect_char(1'b1, 8'h00);

        if (errpar || erresc || errcred) begin
            fail("unexpected persistent error flag");
        end

        done = 1'b1;
    end

endmodule

module spwstream_loopback_tb;

    wire generic_done;
    wire generic_failed;
    wire fast_done;
    wire fast_failed;

    spwstream_loopback_case #(
        .RXIMPL(0),
        .TXIMPL(0),
        .RXCHUNK(1)
    ) generic_case (
        .done(generic_done),
        .failed(generic_failed)
    );

    spwstream_loopback_case #(
        .RXIMPL(1),
        .TXIMPL(1),
        .RXCHUNK(4)
    ) fast_case (
        .done(fast_done),
        .failed(fast_failed)
    );

    initial begin
        wait (generic_done && fast_done);
        if (generic_failed || fast_failed) begin
            $display("FAIL: spwstream loopback test");
            $finish;
        end
        $display("PASS: spwstream loopback test");
        $finish;
    end

endmodule

