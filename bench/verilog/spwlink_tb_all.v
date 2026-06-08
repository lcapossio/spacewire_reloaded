/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * Run the spwlink test bench in several configurations.
 *
 * Verilog 2001 translation of bench/vhdl/spwlink_tb_all.vhd from SpaceWire
 * Light. The configuration sweep mirrors the 23 VHDL cases; start offsets are
 * compressed for CI runtime because these instances are independent.
 */

`timescale 1ns / 1ps

module spwlink_tb_all;

    wire [22:0] done;
    wire [22:0] failed;

    spwlink_tb #(.TEST_ID(1),  .RXIMPL(0), .RXCHUNK(1), .TXIMPL(0), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(0),     .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(25.0))   test1  (.done(done[0]),  .failed(failed[0]));
    spwlink_tb #(.TEST_ID(2),  .RXIMPL(0), .RXCHUNK(1), .TXIMPL(0), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(1000),  .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(25.0))   test2  (.done(done[1]),  .failed(failed[1]));
    spwlink_tb #(.TEST_ID(3),  .RXIMPL(0), .RXCHUNK(1), .TXIMPL(0), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(2000),  .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(25.0))   test3  (.done(done[2]),  .failed(failed[2]));
    spwlink_tb #(.TEST_ID(4),  .RXIMPL(0), .RXCHUNK(1), .TXIMPL(0), .TX_CLOCK_DIV(8'd0),  .STARTWAIT_CYCLES(3000),  .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(25.0))   test4  (.done(done[3]),  .failed(failed[3]));
    spwlink_tb #(.TEST_ID(5),  .RXIMPL(1), .RXCHUNK(1), .TXIMPL(0), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(4000),  .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(25.0))   test5  (.done(done[4]),  .failed(failed[4]));
    spwlink_tb #(.TEST_ID(6),  .RXIMPL(1), .RXCHUNK(1), .TXIMPL(0), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(5000),  .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(25.0))   test6  (.done(done[5]),  .failed(failed[5]));
    spwlink_tb #(.TEST_ID(7),  .RXIMPL(1), .RXCHUNK(2), .TXIMPL(0), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(6000),  .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(25.0))   test7  (.done(done[6]),  .failed(failed[6]));
    spwlink_tb #(.TEST_ID(8),  .RXIMPL(1), .RXCHUNK(3), .TXIMPL(0), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(7000),  .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(16.667), .TXCLK_HALF_NS(25.0))   test8  (.done(done[7]),  .failed(failed[7]));
    spwlink_tb #(.TEST_ID(9),  .RXIMPL(1), .RXCHUNK(4), .TXIMPL(0), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(8000),  .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(12.5),   .TXCLK_HALF_NS(25.0))   test9  (.done(done[8]),  .failed(failed[8]));
    spwlink_tb #(.TEST_ID(10), .RXIMPL(1), .RXCHUNK(4), .TXIMPL(0), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(9000),  .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(5.0),    .TXCLK_HALF_NS(25.0))   test10 (.done(done[9]),  .failed(failed[9]));
    spwlink_tb #(.TEST_ID(11), .RXIMPL(1), .RXCHUNK(4), .TXIMPL(0), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(10000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(5.0),    .TXCLK_HALF_NS(25.0))   test11 (.done(done[10]), .failed(failed[10]));
    spwlink_tb #(.TEST_ID(12), .RXIMPL(1), .RXCHUNK(4), .TXIMPL(0), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(11000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(11.628), .TXCLK_HALF_NS(25.0))   test12 (.done(done[11]), .failed(failed[11]));
    spwlink_tb #(.TEST_ID(13), .RXIMPL(0), .RXCHUNK(1), .TXIMPL(1), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(12000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(12.821)) test13 (.done(done[12]), .failed(failed[12]));
    spwlink_tb #(.TEST_ID(14), .RXIMPL(0), .RXCHUNK(1), .TXIMPL(1), .TX_CLOCK_DIV(8'd0),  .STARTWAIT_CYCLES(13000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(12.821)) test14 (.done(done[13]), .failed(failed[13]));
    spwlink_tb #(.TEST_ID(15), .RXIMPL(0), .RXCHUNK(1), .TXIMPL(1), .TX_CLOCK_DIV(8'd0),  .STARTWAIT_CYCLES(14000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(6.25))   test15 (.done(done[14]), .failed(failed[14]));
    spwlink_tb #(.TEST_ID(16), .RXIMPL(0), .RXCHUNK(1), .TXIMPL(1), .TX_CLOCK_DIV(8'd2),  .STARTWAIT_CYCLES(15000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(25.0))   test16 (.done(done[15]), .failed(failed[15]));
    spwlink_tb #(.TEST_ID(17), .RXIMPL(0), .RXCHUNK(1), .TXIMPL(1), .TX_CLOCK_DIV(8'd3),  .STARTWAIT_CYCLES(16000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(6.25))   test17 (.done(done[16]), .failed(failed[16]));
    spwlink_tb #(.TEST_ID(18), .RXIMPL(0), .RXCHUNK(1), .TXIMPL(1), .TX_CLOCK_DIV(8'd4),  .STARTWAIT_CYCLES(17000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(6.25))   test18 (.done(done[17]), .failed(failed[17]));
    spwlink_tb #(.TEST_ID(19), .RXIMPL(0), .RXCHUNK(1), .TXIMPL(1), .TX_CLOCK_DIV(8'd39), .STARTWAIT_CYCLES(18000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(6.25))   test19 (.done(done[18]), .failed(failed[18]));
    spwlink_tb #(.TEST_ID(20), .RXIMPL(0), .RXCHUNK(1), .TXIMPL(1), .TX_CLOCK_DIV(8'd96), .STARTWAIT_CYCLES(19000), .SYSCLK_HALF_NS(10.0), .RXCLK_HALF_NS(10.0),   .TXCLK_HALF_NS(2.5), .RESET_TIME(320), .DISCONNECT_TIME(42)) test20 (.done(done[19]), .failed(failed[19]));
    spwlink_tb #(.TEST_ID(21), .RXIMPL(0), .RXCHUNK(1), .TXIMPL(1), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(20000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(25.0),   .TXCLK_HALF_NS(6.369))  test21 (.done(done[20]), .failed(failed[20]));
    spwlink_tb #(.TEST_ID(22), .RXIMPL(1), .RXCHUNK(4), .TXIMPL(1), .TX_CLOCK_DIV(8'd0),  .STARTWAIT_CYCLES(21000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(11.628), .TXCLK_HALF_NS(6.369))  test22 (.done(done[21]), .failed(failed[21]));
    spwlink_tb #(.TEST_ID(23), .RXIMPL(1), .RXCHUNK(4), .TXIMPL(1), .TX_CLOCK_DIV(8'd1),  .STARTWAIT_CYCLES(22000), .SYSCLK_HALF_NS(25.0), .RXCLK_HALF_NS(11.628), .TXCLK_HALF_NS(6.452))  test23 (.done(done[22]), .failed(failed[22]));

    initial begin
        wait (&done);
        if (|failed) begin
            $display("FAIL: spwlink_tb_all");
            $finish;
        end
        $display("PASS: spwlink_tb_all");
        $finish;
    end

    initial begin
        #50000000;
        $display("FAIL: spwlink_tb_all timeout");
        $finish;
    end

endmodule
