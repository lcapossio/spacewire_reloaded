/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * Test bench for link interface.
 *
 * Verilog 2001 stimulus translation of bench/vhdl/spwlink_tb.vhd from
 * SpaceWire Light. VHDL record ports are flattened to match the Verilog RTL.
 */

`timescale 1ns / 1ps

module spwlink_tb #(
    parameter TEST_ID = 0,
    parameter RXIMPL = 0,
    parameter RXCHUNK = 1,
    parameter TXIMPL = 0,
    parameter [7:0] TX_CLOCK_DIV = 8'd1,
    parameter STARTWAIT_CYCLES = 0,
    parameter real SYSCLK_HALF_NS = 25.0,
    parameter real RXCLK_HALF_NS = 25.0,
    parameter real TXCLK_HALF_NS = 25.0,
    parameter real INPUT_BIT_NS = 100.0,
    parameter RESET_TIME = 128,
    parameter DISCONNECT_TIME = 17
) (
    output reg done,
    output reg failed
);

    localparam integer MAX_BITS = 4096;
    localparam integer MAX_CHARS = 4096;

    reg sys_clock_enable;
    reg sysclk;
    reg rxclk;
    reg txclk;

    reg output_collect;
    integer output_ptr;
    reg [MAX_BITS-1:0] output_bits;
    integer output_nchars;
    reg [9:0] output_chars [0:MAX_CHARS-1];
    reg output_last_do;
    reg output_last_so;
    time output_last_time;

    reg input_par;
    reg input_idle;
    integer input_pattern;
    reg input_strobeflip = 1'b0;

    reg rst;
    reg autostart;
    reg linkstart;
    reg linkdis;
    reg [7:0] divcnt;
    reg tick_in;
    reg [1:0] ctrl_in;
    reg [5:0] time_in;
    reg [5:0] rxroom;
    reg txwrite;
    reg txflag;
    reg [7:0] txdata;
    wire txrdy;
    wire tick_out;
    wire [1:0] ctrl_out;
    wire [5:0] time_out;
    wire rxchar;
    wire rxflag;
    wire [7:0] rxdata;
    wire started;
    wire connecting;
    wire running;
    wire errdisc;
    wire errpar;
    wire erresc;
    wire errcred;
    reg spw_di;
    reg spw_si;
    wire spw_do_generic;
    wire spw_so_generic;
    wire spw_do_fast;
    wire spw_so_fast;
    wire spw_do;
    wire spw_so;

    wire rxen;
    wire recvo_gotbit;
    wire recvo_gotnull;
    wire recvo_gotfct;
    wire recvo_tick_out;
    wire [1:0] recvo_ctrl_out;
    wire [5:0] recvo_time_out;
    wire recvo_rxchar;
    wire recvo_rxflag;
    wire [7:0] recvo_rxdata;
    wire recvo_errdisc;
    wire recvo_errpar;
    wire recvo_erresc;
    wire xmiti_txen;
    wire xmiti_stnull;
    wire xmiti_stfct;
    wire xmiti_fct_in;
    wire xmiti_tick_in;
    wire [1:0] xmiti_ctrl_in;
    wire [5:0] xmiti_time_in;
    wire xmiti_txwrite;
    wire xmiti_txflag;
    wire [7:0] xmiti_txdata;
    wire xmito_fctack_generic;
    wire xmito_txack_generic;
    wire xmito_fctack_fast;
    wire xmito_txack_fast;
    wire xmito_fctack;
    wire xmito_txack;
    wire inact_generic;
    wire inbvalid_generic;
    wire inbit_generic;
    wire inact_fast;
    wire inbvalid_fast;
    wire [RXCHUNK-1:0] inbits_fast;
    wire inact;
    wire inbvalid;
    wire [RXCHUNK-1:0] inbits;
    wire errany;

    integer i;
    integer p;
    integer timeout;

    assign errany = errdisc | errpar | erresc | errcred;
    assign spw_do = TXIMPL ? spw_do_fast : spw_do_generic;
    assign spw_so = TXIMPL ? spw_so_fast : spw_so_generic;
    assign xmito_fctack = TXIMPL ? xmito_fctack_fast : xmito_fctack_generic;
    assign xmito_txack = TXIMPL ? xmito_txack_fast : xmito_txack_generic;
    assign inact = RXIMPL ? inact_fast : inact_generic;
    assign inbvalid = RXIMPL ? inbvalid_fast : inbvalid_generic;
    assign inbits = RXIMPL ? inbits_fast : {{(RXCHUNK-1){1'b0}}, inbit_generic};

    spwlink #(
        .RESET_TIME(RESET_TIME)
    ) link_inst (
        .clk(sysclk),
        .rst(rst),
        .linki_autostart(autostart),
        .linki_linkstart(linkstart),
        .linki_linkdis(linkdis),
        .linki_rxroom(rxroom),
        .linki_tick_in(tick_in),
        .linki_ctrl_in(ctrl_in),
        .linki_time_in(time_in),
        .linki_txwrite(txwrite),
        .linki_txflag(txflag),
        .linki_txdata(txdata),
        .linko_started(started),
        .linko_connecting(connecting),
        .linko_running(running),
        .linko_errdisc(errdisc),
        .linko_errpar(errpar),
        .linko_erresc(erresc),
        .linko_errcred(errcred),
        .linko_txack(txrdy),
        .linko_tick_out(tick_out),
        .linko_ctrl_out(ctrl_out),
        .linko_time_out(time_out),
        .linko_rxchar(rxchar),
        .linko_rxflag(rxflag),
        .linko_rxdata(rxdata),
        .rxen(rxen),
        .recvo_gotbit(recvo_gotbit),
        .recvo_gotnull(recvo_gotnull),
        .recvo_gotfct(recvo_gotfct),
        .recvo_tick_out(recvo_tick_out),
        .recvo_ctrl_out(recvo_ctrl_out),
        .recvo_time_out(recvo_time_out),
        .recvo_rxchar(recvo_rxchar),
        .recvo_rxflag(recvo_rxflag),
        .recvo_rxdata(recvo_rxdata),
        .recvo_errdisc(recvo_errdisc),
        .recvo_errpar(recvo_errpar),
        .recvo_erresc(recvo_erresc),
        .xmiti_txen(xmiti_txen),
        .xmiti_stnull(xmiti_stnull),
        .xmiti_stfct(xmiti_stfct),
        .xmiti_fct_in(xmiti_fct_in),
        .xmiti_tick_in(xmiti_tick_in),
        .xmiti_ctrl_in(xmiti_ctrl_in),
        .xmiti_time_in(xmiti_time_in),
        .xmiti_txwrite(xmiti_txwrite),
        .xmiti_txflag(xmiti_txflag),
        .xmiti_txdata(xmiti_txdata),
        .xmito_fctack(xmito_fctack),
        .xmito_txack(xmito_txack)
    );

    spwrecv #(
        .DISCONNECT_TIME(DISCONNECT_TIME),
        .RXCHUNK(RXCHUNK)
    ) recv_inst (
        .clk(sysclk),
        .rxen(rxen),
        .recvo_gotbit(recvo_gotbit),
        .recvo_gotnull(recvo_gotnull),
        .recvo_gotfct(recvo_gotfct),
        .recvo_tick_out(recvo_tick_out),
        .recvo_ctrl_out(recvo_ctrl_out),
        .recvo_time_out(recvo_time_out),
        .recvo_rxchar(recvo_rxchar),
        .recvo_rxflag(recvo_rxflag),
        .recvo_rxdata(recvo_rxdata),
        .recvo_errdisc(recvo_errdisc),
        .recvo_errpar(recvo_errpar),
        .recvo_erresc(recvo_erresc),
        .inact(inact),
        .inbvalid(inbvalid),
        .inbits(inbits)
    );

    spwxmit xmit_generic (
        .clk(sysclk),
        .rst(rst),
        .divcnt(divcnt),
        .xmiti_txen(TXIMPL ? 1'b0 : xmiti_txen),
        .xmiti_stnull(TXIMPL ? 1'b0 : xmiti_stnull),
        .xmiti_stfct(TXIMPL ? 1'b0 : xmiti_stfct),
        .xmiti_fct_in(TXIMPL ? 1'b0 : xmiti_fct_in),
        .xmiti_tick_in(TXIMPL ? 1'b0 : xmiti_tick_in),
        .xmiti_ctrl_in(TXIMPL ? 2'b00 : xmiti_ctrl_in),
        .xmiti_time_in(TXIMPL ? 6'b000000 : xmiti_time_in),
        .xmiti_txwrite(TXIMPL ? 1'b0 : xmiti_txwrite),
        .xmiti_txflag(TXIMPL ? 1'b0 : xmiti_txflag),
        .xmiti_txdata(TXIMPL ? 8'b00000000 : xmiti_txdata),
        .xmito_fctack(xmito_fctack_generic),
        .xmito_txack(xmito_txack_generic),
        .spw_do(spw_do_generic),
        .spw_so(spw_so_generic)
    );

    spwxmit_fast xmit_fast (
        .clk(sysclk),
        .txclk(txclk),
        .rst(rst),
        .divcnt(divcnt),
        .xmiti_txen(TXIMPL ? xmiti_txen : 1'b0),
        .xmiti_stnull(TXIMPL ? xmiti_stnull : 1'b0),
        .xmiti_stfct(TXIMPL ? xmiti_stfct : 1'b0),
        .xmiti_fct_in(TXIMPL ? xmiti_fct_in : 1'b0),
        .xmiti_tick_in(TXIMPL ? xmiti_tick_in : 1'b0),
        .xmiti_ctrl_in(TXIMPL ? xmiti_ctrl_in : 2'b00),
        .xmiti_time_in(TXIMPL ? xmiti_time_in : 6'b000000),
        .xmiti_txwrite(TXIMPL ? xmiti_txwrite : 1'b0),
        .xmiti_txflag(TXIMPL ? xmiti_txflag : 1'b0),
        .xmiti_txdata(TXIMPL ? xmiti_txdata : 8'b00000000),
        .xmito_fctack(xmito_fctack_fast),
        .xmito_txack(xmito_txack_fast),
        .spw_do(spw_do_fast),
        .spw_so(spw_so_fast)
    );

    spwrecvfront_generic recvfront_generic (
        .clk(sysclk),
        .rxen(RXIMPL ? 1'b0 : rxen),
        .inact(inact_generic),
        .inbvalid(inbvalid_generic),
        .inbits(inbit_generic),
        .spw_di(spw_di),
        .spw_si(spw_si)
    );

    spwrecvfront_fast #(
        .RXCHUNK(RXCHUNK)
    ) recvfront_fast (
        .clk(sysclk),
        .rxclk(rxclk),
        .rxen(RXIMPL ? rxen : 1'b0),
        .inact(inact_fast),
        .inbvalid(inbvalid_fast),
        .inbits(inbits_fast),
        .spw_di(spw_di),
        .spw_si(spw_si)
    );

    initial begin : sysclk_process
        sysclk = 1'b0;
        forever begin
            wait (sys_clock_enable === 1'b1 || done === 1'b1);
            if (done === 1'b1) disable sysclk_process;
            while (sys_clock_enable === 1'b1 && done !== 1'b1) begin
                sysclk = 1'b1;
                #SYSCLK_HALF_NS;
                sysclk = 1'b0;
                #SYSCLK_HALF_NS;
            end
        end
    end

    initial begin : rxclk_process
        rxclk = 1'b0;
        forever begin
            wait (sys_clock_enable === 1'b1 || done === 1'b1);
            if (done === 1'b1) disable rxclk_process;
            while (sys_clock_enable === 1'b1 && done !== 1'b1) begin
                rxclk = 1'b1;
                #RXCLK_HALF_NS;
                rxclk = 1'b0;
                #RXCLK_HALF_NS;
            end
        end
    end

    initial begin : txclk_process
        txclk = 1'b0;
        forever begin
            wait (sys_clock_enable === 1'b1 || done === 1'b1);
            if (done === 1'b1) disable txclk_process;
            while (sys_clock_enable === 1'b1 && done !== 1'b1) begin
                txclk = 1'b1;
                #TXCLK_HALF_NS;
                txclk = 1'b0;
                #TXCLK_HALF_NS;
            end
        end
    end

    always @(spw_do or spw_so) begin
        if (output_collect) begin
            if (output_ptr < MAX_BITS) begin
                output_bits[output_ptr] = spw_do;
                output_ptr = output_ptr + 1;
            end
            output_last_do = spw_do;
            output_last_so = spw_so;
            output_last_time = $time;
        end
    end

    always @(posedge sysclk) begin
        if (output_collect) begin
            if (tick_out) begin
                output_chars[output_nchars] <= {2'b10, ctrl_out, time_out};
                output_nchars <= output_nchars + 1;
            end else if (rxchar) begin
                output_chars[output_nchars] <= {1'b0, rxflag, rxdata};
                output_nchars <= output_nchars + 1;
            end
        end else if (output_nchars != 0) begin
            output_nchars <= 0;
        end
    end

    task fail;
        input [8*128-1:0] msg;
        begin
            if (!failed) begin
                $display("ERROR: spwlink test%0d", TEST_ID);
                $display("%0s", msg);
                $display("  optr=%0d bits0=%b bits8=%b state=%b%b%b spw=%b%b err=%b%b%b%b",
                         output_ptr, output_bits[7:0], output_bits[15:8],
                         started, connecting, running, spw_do, spw_so, errdisc, errpar, erresc, errcred);
                $display("  spw_do=%b spw_so=%b", spw_do, spw_so);
                $display("  spw_di=%b", spw_di);
                $display("  spw_si=%b", spw_si);
                $display("  rxen=%b", rxen);
                $display("  inact=%b", inact);
                $display("  inbvalid=%b", inbvalid);
                $display("  gotnull=%b", recvo_gotnull);
                $display("  gotfct=%b", recvo_gotfct);
            end
            failed = 1'b1;
            done = 1'b1;
        end
    endtask

    task check;
        input cond;
        input [8*128-1:0] msg;
        begin
            if (!cond) fail(msg);
        end
    endtask

    task wait_time;
        input real delay_ns;
        begin
            #delay_ns;
        end
    endtask

    task start_collect;
        begin
            output_ptr = 0;
            output_bits[0] = spw_do;
            output_ptr = 1;
            output_last_do = spw_do;
            output_last_so = spw_so;
            output_last_time = $time;
            output_collect = 1'b1;
        end
    endtask

    task wait_state_or_time;
        input real delay_ns;
        real target_time;
        reg old_started;
        reg old_connecting;
        reg old_running;
        reg old_errany;
        begin
            target_time = $realtime + delay_ns;
            old_started = started;
            old_connecting = connecting;
            old_running = running;
            old_errany = errany;
            while ($realtime < target_time &&
                   old_started === started &&
                   old_connecting === connecting &&
                   old_running === running &&
                   old_errany === errany &&
                   done !== 1'b1) begin
                #1;
            end
        end
    endtask

    task wait_spw_or_time;
        input real delay_ns;
        real target_time;
        reg old_spw_do;
        reg old_spw_so;
        begin
            target_time = $realtime + delay_ns;
            old_spw_do = spw_do;
            old_spw_so = spw_so;
            while ($realtime < target_time &&
                   old_spw_do === spw_do &&
                   old_spw_so === spw_so &&
                   done !== 1'b1) begin
                #1;
            end
        end
    endtask

    task wait_txrdy_or_time;
        input real delay_ns;
        real target_time;
        reg old_running;
        reg old_errany;
        reg old_txrdy;
        begin
            target_time = $realtime + delay_ns;
            old_running = running;
            old_errany = errany;
            old_txrdy = txrdy;
            while ($realtime < target_time &&
                   old_running === running &&
                   old_errany === errany &&
                   old_txrdy === txrdy &&
                   done !== 1'b1) begin
                #1;
            end
        end
    endtask

    task wait_connecting_or_time;
        input real delay_ns;
        real target_time;
        reg old_connecting;
        reg old_running;
        reg old_errany;
        begin
            target_time = $realtime + delay_ns;
            old_connecting = connecting;
            old_running = running;
            old_errany = errany;
            while ($realtime < target_time &&
                   old_connecting === connecting &&
                   old_running === running &&
                   old_errany === errany &&
                   done !== 1'b1) begin
                #1;
            end
        end
    endtask

    task input_reset;
        begin
            spw_di = 1'b0;
            spw_si = input_strobeflip;
            input_par = 1'b0;
        end
    endtask

    task genbit;
        input b;
        begin
            spw_si = !(spw_si ^ spw_di ^ b);
            spw_di = b;
            #INPUT_BIT_NS;
        end
    endtask

    task genfct;
        begin
            genbit(input_par);
            genbit(1'b1);
            genbit(1'b0);
            input_par = 1'b0;
            genbit(1'b0);
        end
    endtask

    task genesc;
        begin
            genbit(input_par);
            genbit(1'b1);
            genbit(1'b1);
            input_par = 1'b0;
            genbit(1'b1);
        end
    endtask

    task geneop;
        input e;
        begin
            genbit(input_par);
            genbit(1'b1);
            genbit(e);
            input_par = 1'b1;
            if (e) genbit(1'b0);
            else genbit(1'b1);
        end
    endtask

    task gendat;
        input [7:0] dat;
        begin
            genbit(!input_par);
            genbit(1'b0);
            genbit(dat[0]); genbit(dat[1]); genbit(dat[2]); genbit(dat[3]);
            genbit(dat[4]); genbit(dat[5]); genbit(dat[6]);
            input_par = dat[0] ^ dat[1] ^ dat[2] ^ dat[3] ^
                        dat[4] ^ dat[5] ^ dat[6] ^ dat[7];
            genbit(dat[7]);
        end
    endtask

    function check_null;
        input integer start;
        begin
            check_null =
                output_bits[start+0] === 1'b0 &&
                output_bits[start+1] === 1'b1 &&
                output_bits[start+2] === 1'b1 &&
                output_bits[start+3] === 1'b1 &&
                output_bits[start+4] === 1'b0 &&
                output_bits[start+5] === 1'b1 &&
                output_bits[start+6] === 1'b0 &&
                output_bits[start+7] === 1'b0;
        end
    endfunction

    initial begin : input_generator
        input_idle = 1'b1;
        input_reset;
        forever begin
            wait (input_pattern != 0 || done === 1'b1);
            if (done === 1'b1) disable input_generator;
            input_idle = 1'b0;
            #1;
            while (input_pattern != 0 && done !== 1'b1) begin
                case (input_pattern)
                    1: begin
                        genesc; genfct;
                    end
                    2: begin
                        genfct;
                    end
                    3: begin
                        genbit(1'b0); genbit(1'b1);
                    end
                    4: begin
                        geneop(1'b0);
                    end
                    5: begin
                        genfct;
                        genesc; gendat(8'b00111000);
                        gendat(8'b01010101);
                        gendat(8'b10101010);
                        gendat(8'b01010101);
                        gendat(8'b10101010);
                        gendat(8'b01010101);
                        gendat(8'b10101010);
                        gendat(8'b01010101);
                        gendat(8'b10101010);
                        while (input_pattern == 5 && done !== 1'b1) begin
                            genesc; genfct;
                        end
                    end
                    6: begin
                        genesc;
                    end
                    7: begin
                        genfct;
                        genesc; genfct;
                        genesc; genfct;
                        geneop(1'b0);
                        geneop(1'b1);
                        while (input_pattern == 7 && done !== 1'b1) begin
                            genesc; genfct;
                        end
                    end
                    8: begin
                        genfct;
                        genesc; genfct;
                        genesc; genfct;
                        genesc; genfct;
                        genesc; genfct;
                        genesc; genfct;
                        gendat(8'b01010101);
                        genbit(!input_par);
                        genbit(1'b0);
                        genbit(1'b1); genbit(1'b0); genbit(1'b1); genbit(1'b0);
                        genbit(1'b1); genbit(1'b0); genbit(1'b1);
                        input_par = 1'b1;
                        genbit(1'b0);
                        while (input_pattern == 8 && done !== 1'b1) begin
                            genesc; genfct;
                        end
                    end
                    9: begin
                        genfct;
                        genfct;
                        while (input_pattern == 9 && done !== 1'b1) begin
                            genesc; genfct;
                        end
                    end
                    10: begin
                        spw_di = 1'b1;
                        spw_si = !input_strobeflip;
                        wait (input_pattern != 10 || done === 1'b1);
                    end
                    default: begin
                        fail("unsupported input_pattern");
                    end
                endcase
            end
            input_idle = 1'b1;
            input_reset;
        end
    end

    initial begin : main_test
        done = 1'b0;
        failed = 1'b0;
        rst = 1'b1;
        autostart = 1'b0;
        linkstart = 1'b0;
        linkdis = 1'b0;
        divcnt = TX_CLOCK_DIV;
        tick_in = 1'b0;
        ctrl_in = 2'b00;
        time_in = 6'b000000;
        rxroom = 6'b000000;
        txwrite = 1'b0;
        txflag = 1'b0;
        txdata = 8'b00000000;
        sys_clock_enable = 1'b0;
        output_collect = 1'b0;
        output_ptr = 0;
        output_nchars = 0;
        input_pattern = 0;
        input_strobeflip = 1'b0;

        sys_clock_enable = 1'b1;
        for (i = 0; i < STARTWAIT_CYCLES; i = i + 1) @(posedge sysclk);

        /* reset_idle_assertions */
        autostart = 1'b0; linkstart = 1'b0; linkdis = 1'b0;
        divcnt = TX_CLOCK_DIV;
        tick_in = 1'b0; ctrl_in = 2'b00; time_in = 6'b000000; rxroom = 6'b000000;
        txwrite = 1'b0; txflag = 1'b0; txdata = 8'b00000000;
        @(posedge sysclk);
        @(posedge sysclk);
        #1;
        rst = 1'b0;
        check(txrdy == 1'b0, " 1. reset (txrdy = 0)");
        check(tick_out == 1'b0, " 1. reset (tick_out = 0)");
        check(rxchar == 1'b0, " 1. reset (rxchar = 0)");
        check(started == 1'b0, " 1. reset (started = 0)");
        check(connecting == 1'b0, " 1. reset (connecting = 0)");
        check(running == 1'b0, " 1. reset (running = 0)");
        check(errdisc == 1'b0, " 1. reset (errdisc = 0)");
        check(errpar == 1'b0, " 1. reset (errpar = 0)");
        check(erresc == 1'b0, " 1. reset (erresc = 0)");
        check(errcred == 1'b0, " 1. reset (errcred = 0)");
        check(spw_do == 1'b0, " 1. reset (spw_do = 0)");
        check(spw_so == 1'b0, " 1. reset (spw_so = 0)");

        @(posedge sysclk);
        @(negedge sysclk);
        check(started == 1'b0 && running == 1'b0, " 2. init (state)");
        check(spw_do == 1'b0 && spw_so == 1'b0, " 2. init (SPW idle)");

        wait_time(50000.0);
        check(started == 1'b0 && running == 1'b0, " 3. ready (state)");
        check(spw_do == 1'b0 && spw_so == 1'b0, " 3. ready (SPW idle)");

        /* started_null_generation */
        linkstart = 1'b1;
        rxroom = 6'b001111;
        wait_state_or_time(1000.0);
        check(started == 1'b1 && running == 1'b0, " 4. nullgen (started)");
        if (spw_so == 1'b0) wait_spw_or_time(1200.0);
        check(started == 1'b1 && connecting == 1'b0 && running == 1'b0 &&
              spw_do == 1'b0 && spw_so == 1'b1, " 4. nullgen (SPW strobe)");
        start_collect;
        wait_state_or_time(7.1 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS));
        check(started == 1'b1 && running == 1'b0, " 4. nullgen (state 2)");
        check(output_ptr >= 8 && check_null(0), " 4. nullgen (NULL 1)");
        wait_state_or_time(8.0 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS));
        check(started == 1'b1 && running == 1'b0, " 4. nullgen (state 3)");
        check(output_ptr >= 16 && check_null(8), " 4. nullgen (NULL 2)");
        output_collect = 1'b0;

        /* started_timeout */
        wait_state_or_time(9500.0 - 15.0 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS));
        check(started == 1'b1 && running == 1'b0 && errany == 1'b0, " 5. started_timeout (wait)");
        wait_state_or_time(4000.0);
        check(started == 1'b0 && connecting == 1'b0 && running == 1'b0 && errany == 1'b0,
              " 5. started_timeout (trigger)");
        wait_time(3.1 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS) + 20.0 * (2.0 * TXCLK_HALF_NS));
        check(spw_do == 1'b0 && spw_so == 1'b0, " 5. started_timeout (SPW to zero)");

        /* connecting_fct_generation */
        wait_state_or_time(18000.0 - (3.1 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS) + 20.0 * (2.0 * TXCLK_HALF_NS)));
        check(started == 1'b0 && connecting == 1'b0 && running == 1'b0 && spw_so == 1'b0,
              " 6. fctgen (SPW idle)");
        wait_state_or_time(2000.0);
        check(started == 1'b1 && connecting == 1'b0 && running == 1'b0, " 6. fctgen (started)");
        if (spw_so == 1'b0) wait_spw_or_time(1200.0);
        check(spw_do == 1'b0 && spw_so == 1'b1, " 6. fctgen (SPW strobe)");
        start_collect;
        input_pattern = 1;
        wait_state_or_time(8000.0);
        check(started == 1'b0 && connecting == 1'b1 && running == 1'b0, " 6. fctgen (detect NULL)");
        wait_time(2.0 * SYSCLK_HALF_NS + 1.0);
        wait_state_or_time(12000.0);
        check(started == 1'b0 && connecting == 1'b1 && running == 1'b0 && errany == 1'b0,
              " 6. fctgen (connecting failed early)");
        check(output_ptr > 7, " 6. fctgen (gen NULL)");
        output_collect = 1'b0;

        /* connecting_timeout */
        wait_state_or_time(4000.0);
        check(started == 1'b0 && connecting == 1'b0 && running == 1'b0 && errany == 1'b0,
              " 7. connecting_timeout");
        input_pattern = 0;
        @(posedge sysclk);

        /* autostart_to_run / link_disable */
        linkstart = 1'b0;
        autostart = 1'b1;
        rxroom = 6'b010000;
        wait_state_or_time(50000.0);
        check(started == 1'b0 && connecting == 1'b0 && running == 1'b0 && errany == 1'b0,
              " 8. autostart (wait)");
        start_collect;
        input_pattern = 1;
        wait_state_or_time(200.0 + 24.0 * INPUT_BIT_NS);
        check(started == 1'b1 && connecting == 1'b0 && running == 1'b0, " 8. autostart (Started)");
        input_pattern = 9;
        wait_state_or_time(1000.0);
        check(started == 1'b0 && connecting == 1'b1 && running == 1'b0, " 8. autostart (Connecting)");
        wait_state_or_time(200.0 + 24.0 * INPUT_BIT_NS);
        check(started == 1'b0 && connecting == 1'b0 && running == 1'b1 && errany == 1'b0,
              " 8. autostart (Run)");
        input_pattern = 1;
        txwrite = 1'b1;
        if (txrdy == 1'b0) wait_txrdy_or_time(20.0 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS));
        check(running == 1'b1 && errany == 1'b0 && txrdy == 1'b1, " 8. running (txrdy = 1)");
        txwrite = 1'b0;
        wait_state_or_time(50000.0);
        check(running == 1'b1 && errany == 1'b0, " 8. running stable");
        output_collect = 1'b0;
        linkdis = 1'b1;
        wait_state_or_time(2.1 * (2.0 * SYSCLK_HALF_NS));
        check(started == 1'b0 && running == 1'b0 && errany == 1'b0, " 8. link disable");
        autostart = 1'b0;
        linkdis = 1'b0;
        input_pattern = 0;
        @(posedge sysclk);

        /* running_disconnect_error */
        linkstart = 1'b1;
        rxroom = 6'b001000;
        input_pattern = 1;
        wait_state_or_time(20000.0);
        check(started == 1'b1 && connecting == 1'b0 && running == 1'b0,
              " 9. running_disconnect (Started)");
        linkstart = 1'b0;
        @(posedge sysclk);
        input_pattern = 9;
        wait_state_or_time(20.0 * INPUT_BIT_NS);
        check(started == 1'b0 && connecting == 1'b1 && running == 1'b0 && errany == 1'b0,
              " 9. running_disconnect (Connecting)");
        wait_state_or_time(200.0 + 24.0 * INPUT_BIT_NS);
        check(started == 1'b0 && connecting == 1'b0 && running == 1'b1 && errany == 1'b0,
              " 9. running_disconnect (Run)");
        input_pattern = 0;
        wait (input_idle == 1'b1);
        wait_state_or_time(1500.0);
        check(errdisc == 1'b1, " 9. running_disconnect (errdisc = 1)");
        if (running == 1'b1) wait_state_or_time(2.0 * SYSCLK_HALF_NS + 5.0);
        check(started == 1'b0 && connecting == 1'b0 && running == 1'b0,
              " 9. running_disconnect (running = 0)");
        @(posedge sysclk);
        check(started == 1'b0 && connecting == 1'b0 && running == 1'b0 && errany == 1'b0,
              " 9. running_disconnect (reset)");
        @(posedge sysclk);

        /* junk_signal_filtering */
        autostart = 1'b1;
        input_pattern = 3;
        wait_state_or_time(6000.0);
        check(started == 1'b0 && errany == 1'b0, "10. junk signal (ignore noise)");
        input_pattern = 2;
        wait_state_or_time(4000.0);
        check(started == 1'b0 && errany == 1'b0, "10. junk signal (ignore FCT)");
        input_pattern = 0;
        wait (input_idle == 1'b1);
        input_pattern = 1;
        wait (input_idle == 1'b0);
        #2;
        input_pattern = 3;
        wait_state_or_time(8000.0);
        check(started == 1'b0 && errany == 1'b0, "10. junk signal (hidden reset)");
        input_pattern = 1;
        wait_state_or_time(10000.0);
        check(started == 1'b0 && errany == 1'b0, "10. junk signal (waiting)");
        wait_state_or_time(10000.0);
        check(started == 1'b1 && errany == 1'b0, "10. junk signal (Started)");
        autostart = 1'b0;
        rst = 1'b1;
        @(posedge sysclk);
        rst = 1'b0;
        @(posedge sysclk);
        check(started == 1'b0 && errany == 1'b0, "10. junk signal (rst)");
        @(posedge sysclk);

        /* unexpected_eop_reset */
        linkstart = 1'b1;
        rxroom = 6'b001000;
        input_pattern = 1;
        wait_connecting_or_time(21000.0);
        check(connecting == 1'b1 && errany == 1'b0, "11. unexpected EOP (Connecting)");
        input_pattern = 4;
        linkstart = 1'b0;
        wait_connecting_or_time(200.0 + 24.0 * INPUT_BIT_NS);
        check(connecting == 1'b0 && running == 1'b0 && errany == 1'b0,
              "11. unexpected EOP (reset on EOP)");
        input_pattern = 0;
        wait_time(10.0 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS));

        /* timecode_and_data_receive / double_escape_error */
        @(negedge sysclk);
        linkstart = 1'b1;
        wait_state_or_time(21000.0);
        check(started == 1'b1 && errany == 1'b0, "12. characters (Started)");
        rxroom = 6'b001000;
        input_pattern = 1;
        start_collect;
        tick_in = 1'b1;
        wait_connecting_or_time(21000.0);
        check(connecting == 1'b1 && errany == 1'b0, "12. characters (Connecting)");
        timeout = 2000;
        while (output_ptr <= 9 && timeout > 0) begin #1; timeout = timeout - 1; end
        input_pattern = 5;
        time_in = 6'b000111;
        txwrite = 1'b1;
        txflag = 1'b0;
        txdata = 8'b01101100;
        wait_connecting_or_time(200.0 + 24.0 * INPUT_BIT_NS);
        check(running == 1'b1 && errany == 1'b0, "12. characters (Run)");
        @(posedge sysclk);
        check(running == 1'b1 && errany == 1'b0, "12. characters (running = 1)");
        tick_in = 1'b0;
        wait_time(4.0 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS));
        rxroom = 6'b000111;
        timeout = 2000;
        while (txrdy !== 1'b1 && timeout > 0) begin @(posedge sysclk); timeout = timeout - 1; end
        check(running == 1'b1 && txrdy == 1'b1, "12. characters (txrdy = 1)");
        wait_state_or_time(50000.0 + 80.0 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS));
        check(running == 1'b1 && errany == 1'b0, "12. characters (stable)");
        input_pattern = 6;
        wait_state_or_time(200.0 + 32.0 * INPUT_BIT_NS);
        check(erresc == 1'b1, "12. characters (erresc = 1)");
        @(posedge sysclk);
        #1;
        check(started == 1'b0 && connecting == 1'b0 && running == 1'b0, "12. characters (reset)");
        check(output_nchars > 0 && output_chars[0] == 10'b1000111000, "12. characters (got TimeCode)");
        check(output_nchars > 1 && output_chars[1] == 10'b0001010101, "12. characters (got byte 1)");
        output_collect = 1'b0;
        input_pattern = 0;
        txwrite = 1'b0;
        linkstart = 1'b0;
        wait_time(20.0 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS));

        /* eop_eep_receive / credit_error */
        linkstart = 1'b1;
        rxroom = 6'b001000;
        input_pattern = 1;
        start_collect;
        wait_connecting_or_time(21000.0);
        check(connecting == 1'b1 && errany == 1'b0, "13. eop, eep (Connecting)");
        timeout = 2000;
        while (output_ptr <= 9 && timeout > 0) begin #1; timeout = timeout - 1; end
        input_pattern = 7;
        wait_time(2.0 * SYSCLK_HALF_NS + 1.0);
        wait_connecting_or_time(12000.0);
        check(running == 1'b1 && errany == 1'b0, "13. eop, eep (Run)");
        #1;
        txwrite = 1'b1;
        txflag = 1'b1;
        txdata = 8'b01101100;
        for (i = 0; i < 8; i = i + 1) begin
            timeout = 4000;
            while (txrdy !== 1'b1 && timeout > 0) begin @(posedge sysclk); timeout = timeout - 1; end
            check(txrdy == 1'b1 && running == 1'b1 && errany == 1'b0, "13. eop, eep (txrdy)");
            if (i == 0) begin rxroom = 6'b000111; txdata = 8'b00000001; end
            else if (i == 1) txdata = 8'b00000000;
            else if (i == 2) txdata = 8'b11111111;
            else if (i == 3) txdata = 8'b11111110;
            else if (i == 4) txdata = 8'b01010101;
            else if (i == 5) txdata = 8'b10101010;
            else if (i == 6) txdata = 8'b01010101;
            else txdata = 8'b10101010;
            @(posedge sysclk);
        end
        txwrite = 1'b0;
        txflag = 1'b0;
        wait_state_or_time(10.0 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS));
        check(running == 1'b1 && errany == 1'b0, "13. eop, eep (flush out)");
        input_pattern = 2;
        wait_state_or_time(80.0 * INPUT_BIT_NS);
        check(errcred == 1'b1, "13. eop, eep (errcred = 1)");
        timeout = 4000;
        while (running !== 1'b0 && timeout > 0) begin @(posedge sysclk); timeout = timeout - 1; end
        check(output_nchars > 0 && output_chars[0] == 10'b0100000000, "13. eop, eep (got EOP)");
        check(output_nchars >= 2 && output_chars[1] == 10'b0100000001, "13. eop, eep (got EEP)");
        output_collect = 1'b0;
        input_pattern = 0;
        linkstart = 1'b0;
        @(posedge sysclk);

        /* parity_error */
        wait_time(10000.0);
        check(spw_do == 1'b0 && spw_so == 1'b0, "14. output still babbling");
        linkstart = 1'b1;
        rxroom = 6'b001000;
        input_pattern = 1;
        start_collect;
        #1;
        wait_connecting_or_time(21000.0);
        check(connecting == 1'b1 && errany == 1'b0, "14. parity (Connecting)");
        input_pattern = 8;
        wait_time(2.0 * SYSCLK_HALF_NS + 1.0);
        wait_connecting_or_time(12000.0);
        check(running == 1'b1 && errany == 1'b0, "14. parity (Run)");
        wait_connecting_or_time(150.0 + 84.0 * INPUT_BIT_NS);
        check(errpar == 1'b1, "14. parity (errpar = 1)");
        timeout = 4000;
        while (running !== 1'b0 && timeout > 0) begin @(posedge sysclk); timeout = timeout - 1; end
        check(output_nchars == 1 && output_chars[0] == 10'b0001010101,
              "14. parity (received char)");
        output_collect = 1'b0;
        input_pattern = 0;
        linkstart = 1'b0;
        @(posedge sysclk);

        /* inverted_strobe_start */
        input_strobeflip = 1'b1;
        linkstart = 1'b1;
        rxroom = 6'b001000;
        input_pattern = 1;
        wait_state_or_time(20000.0);
        check(started == 1'b1 && connecting == 1'b0 && running == 1'b0, "15. weird_strobe (Started)");
        linkstart = 1'b0;
        @(posedge sysclk);
        input_pattern = 9;
        wait_state_or_time(20.0 * INPUT_BIT_NS);
        check(started == 1'b0 && connecting == 1'b1 && running == 1'b0 && errany == 1'b0,
              "15. weird_strobe (Connecting)");
        wait_state_or_time(200.0 + 24.0 * INPUT_BIT_NS);
        check(started == 1'b0 && connecting == 1'b0 && running == 1'b1 && errany == 1'b0,
              "15. weird_strobe (Run)");
        linkdis = 1'b1;
        @(posedge sysclk);
        input_pattern = 0;
        input_strobeflip = 1'b0;
        wait (input_idle == 1'b1);
        linkdis = 1'b0;
        @(posedge sysclk);

        /* data_strobe_both_high */
        input_pattern = 10;
        linkstart = 1'b1;
        rxroom = 6'b001111;
        wait_state_or_time(25000.0);
        check(started == 1'b1 && running == 1'b0, "16. weird_data (started)");
        if (spw_so == 1'b0) wait_spw_or_time(1200.0);
        check(started == 1'b1 && connecting == 1'b0 && running == 1'b0 &&
              spw_do == 1'b0 && spw_so == 1'b1, "16. weird_data (SPW strobe)");
        start_collect;
        wait_state_or_time(7.1 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS));
        check(started == 1'b1 && running == 1'b0, "16. weird_data (state 2)");
        check(output_ptr >= 8 && check_null(0), "16. weird_data (NULL 1)");
        wait_state_or_time(8.0 * (TX_CLOCK_DIV + 1) * (2.0 * TXCLK_HALF_NS));
        check(started == 1'b1 && running == 1'b0, "16. weird_data (state 3)");
        check(output_ptr >= 16 && check_null(8), "16. weird_data (NULL 2)");
        output_collect = 1'b0;
        linkstart = 1'b0;
        linkdis = 1'b1;
        input_pattern = 0;
        @(posedge sysclk);
        linkdis = 1'b0;
        @(posedge sysclk);

        input_pattern = 0;
        wait_time(100000.0);
        sys_clock_enable = 1'b0;
        done = 1'b1;
    end

endmodule
