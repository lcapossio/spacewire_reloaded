/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * Test bench for streamtest.
 *
 * Verilog 2001 translation of bench/vhdl/streamtest_tb.vhd from SpaceWire
 * Light, shortened for CI while retaining data, timecode, disable and
 * disconnect coverage.
 */

`timescale 1ns / 1ps

module streamtest_tb;

    reg clk;
    reg rst;
    reg loopback;
    reg linkstart;
    reg autostart;
    reg linkdisable;
    reg [7:0] txdivcnt;
    wire linkrun;
    wire linkerror;
    wire gotdata;
    wire dataerror;
    wire tickerror;
    wire spw_di;
    wire spw_si;
    wire spw_do;
    wire spw_so;
    integer nreceived;

    assign spw_di = loopback ? spw_do : 1'b0;
    assign spw_si = loopback ? spw_so : 1'b0;

    initial begin
        clk = 1'b0;
        forever #25 clk = !clk;
    end

    streamtest #(
        .RESET_TIME(11'd20),
        .DISCONNECT_TIME(8'd20),
        .DEFAULT_DIVCNT(8'd1),
        .TICKDIV(12),
        .RXIMPL(0),
        .RXCHUNK(1),
        .TXIMPL(0),
        .RXFIFOSIZE_BITS(9),
        .TXFIFOSIZE_BITS(8)
    ) streamtest_inst (
        .clk(clk),
        .rxclk(clk),
        .txclk(clk),
        .rst(rst),
        .linkstart(linkstart),
        .autostart(autostart),
        .linkdisable(linkdisable),
        .senddata(1'b1),
        .sendtick(1'b1),
        .txdivcnt(txdivcnt),
        .linkstarted(),
        .linkconnecting(),
        .linkrun(linkrun),
        .linkerror(linkerror),
        .gotdata(gotdata),
        .dataerror(dataerror),
        .tickerror(tickerror),
        .spw_di(spw_di),
        .spw_si(spw_si),
        .spw_do(spw_do),
        .spw_so(spw_so)
    );

    always @(posedge clk) begin
        if (gotdata) begin
            nreceived <= nreceived + 1;
        end
        if (dataerror || tickerror || (loopback && linkerror)) begin
            $display("ERROR: streamtest error link=%b data=%b tick=%b", linkerror, dataerror, tickerror);
            $finish;
        end
    end

    task wait_run;
        integer timeout;
        begin
            timeout = 20000;
            while (!linkrun && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                $display("ERROR: streamtest link failed to run");
                $finish;
            end
        end
    endtask

    initial begin
        $display("Starting streamtest Verilog test bench");
        loopback = 1'b1;
        rst = 1'b1;
        linkstart = 1'b0;
        autostart = 1'b0;
        linkdisable = 1'b0;
        txdivcnt = 8'd1;
        nreceived = 0;
        repeat (8) @(posedge clk);
        rst = 1'b0;
        linkstart = 1'b1;
        wait_run;
        repeat (40000) @(posedge clk);
        if (nreceived < 16) begin
            $display("ERROR: too few streamtest characters received: %0d", nreceived);
            $finish;
        end
        txdivcnt = 8'd2;
        repeat (5000) @(posedge clk);
        txdivcnt = 8'd3;
        repeat (5000) @(posedge clk);
        linkdisable = 1'b1;
        repeat (2000) @(posedge clk);
        linkdisable = 1'b0;
        wait_run;
        loopback = 1'b0;
        repeat (2000) @(posedge clk);
        loopback = 1'b1;
        wait_run;
        repeat (5000) @(posedge clk);
        rst = 1'b1;
        repeat (8) @(posedge clk);
        $display("PASS: streamtest Verilog test bench");
        $finish;
    end

endmodule

