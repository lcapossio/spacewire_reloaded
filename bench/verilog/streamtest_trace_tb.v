/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * Deterministic trace bench for VHDL/Verilog parity comparison.
 */

`timescale 1ns / 1ps

module streamtest_trace_tb;

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
    reg [1023:0] wave_path;

    assign spw_di = loopback ? spw_do : 1'b0;
    assign spw_si = loopback ? spw_so : 1'b0;

    initial begin
        if ($value$plusargs("WAVE=%s", wave_path)) begin
            $dumpfile(wave_path);
            $dumpvars(0, streamtest_trace_tb);
        end
    end

    initial begin
        clk = 1'b0;
        forever #25 clk = !clk;
    end

    streamtest #(
        .RESET_TIME(11'd128),
        .DISCONNECT_TIME(8'd17),
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
            $display("ERROR: link=%0d data=%0d tick=%0d", linkerror, dataerror, tickerror);
            $finish;
        end
    end

    task wait_cycles;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    task wait_run;
        integer timeout;
        begin
            timeout = 20000;
            while (!linkrun && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                $display("ERROR: link failed to run");
                $finish;
            end
        end
    endtask

    task trace;
        input [8*16-1:0] phase;
        begin
            $display("TRACE phase=%0s rx=%0d run=%0d linkerr=%0d dataerr=%0d tickerr=%0d",
                     phase, nreceived, linkrun, linkerror, dataerror, tickerror);
        end
    endtask

    initial begin
        loopback = 1'b1;
        rst = 1'b1;
        linkstart = 1'b0;
        autostart = 1'b0;
        linkdisable = 1'b0;
        txdivcnt = 8'd1;
        nreceived = 0;

        wait_cycles(8);
        rst = 1'b0;
        linkstart = 1'b1;
        wait_run;
        trace("RUN");

        wait_cycles(10000);
        trace("DIV1");

        txdivcnt = 8'd2;
        wait_cycles(3000);
        trace("DIV2");

        txdivcnt = 8'd3;
        wait_cycles(3000);
        trace("DIV3");

        linkdisable = 1'b1;
        txdivcnt = 8'd1;
        wait_cycles(1000);
        trace("DISABLED");

        linkdisable = 1'b0;
        wait_run;
        trace("REENABLED");

        loopback = 1'b0;
        wait_cycles(1000);
        loopback = 1'b1;
        wait_run;
        trace("RECONNECTED");

        wait_cycles(3000);
        trace("FINAL");
        $display("PASS: streamtest trace Verilog test bench");
        $finish;
    end

endmodule
