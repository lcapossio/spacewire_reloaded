/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * SpaceWire core with character-stream interface.
 *
 * Verilog 2001 translation of the generic RX/TX path in
 * rtl/vhdl/spwstream.vhd from SpaceWire Light. VHDL record ports are
 * flattened internally, and real-valued VHDL generics are replaced by
 * integer parameters.
 */

`timescale 1ns / 1ps

module spwstream #(
    parameter integer SYS_CLOCK_HZ = 20000000,
    parameter integer TX_CLOCK_HZ = 20000000,
    // Optional compatibility overrides. Leave at zero to derive SpaceWire
    // timing from SYS_CLOCK_HZ/TX_CLOCK_HZ, matching the VHDL generics.
    parameter [10:0] RESET_TIME = 11'd0,
    parameter [7:0]  DISCONNECT_TIME = 8'd0,
    parameter [7:0]  DEFAULT_DIVCNT = 8'd0,
    parameter        RXIMPL = 0,
    parameter        TXIMPL = 0,
    parameter        RXCHUNK = 1,
    parameter        RXFIFOSIZE_BITS = 11,
    parameter        TXFIFOSIZE_BITS = 11,
    // Strict TimeCode reception. When 0 (default) the core is a transparent
    // TimeCode pipe: every received TimeCode pulses tick_out. When 1, tick_out
    // pulses only for an in-sequence TimeCode (count == previous + 1 mod 64);
    // out-of-sequence values still update the local count but do not pulse
    // tick_out (per the SpaceWire time-code / lost-time-code rules).
    parameter        STRICT_TIMECODES = 0
) (
    input  wire       clk,
    input  wire       rxclk,
    input  wire       txclk,
    input  wire       rst,

    input  wire       autostart,
    input  wire       linkstart,
    input  wire       linkdis,
    input  wire [7:0] txdivcnt,

    input  wire       tick_in,
    input  wire [1:0] ctrl_in,
    input  wire [5:0] time_in,

    input  wire       txwrite,
    input  wire       txflag,
    input  wire [7:0] txdata,
    output reg        txrdy,
    output reg        txhalff,

    output reg        tick_out,
    output reg  [1:0] ctrl_out,
    output reg  [5:0] time_out,

    output reg        rxvalid,
    output reg        rxhalff,
    output reg        rxflag,
    output reg  [7:0] rxdata,
    input  wire       rxread,

    output reg        started,
    output reg        connecting,
    output reg        running,
    output reg        errdisc,
    output reg        errpar,
    output reg        erresc,
    output reg        errcred,

    input  wire       spw_di,
    input  wire       spw_si,
    output wire       spw_do,
    output wire       spw_so
);

    localparam integer RESET_TIME_DERIVED = (SYS_CLOCK_HZ + 78125) / 156250;
    localparam integer DISCONNECT_TIME_QUOT = SYS_CLOCK_HZ / 20000000;
    localparam integer DISCONNECT_TIME_REM = SYS_CLOCK_HZ % 20000000;
    localparam integer DISCONNECT_TIME_DERIVED =
        (DISCONNECT_TIME_QUOT * 17) + ((DISCONNECT_TIME_REM * 17 + 10000000) / 20000000);
    localparam [10:0] RESET_TIME_COUNT = (RESET_TIME != 0) ? RESET_TIME : RESET_TIME_DERIVED[10:0];
    localparam [7:0] DISCONNECT_TIME_COUNT =
        (DISCONNECT_TIME != 0) ? DISCONNECT_TIME : DISCONNECT_TIME_DERIVED[7:0];
    localparam integer EFFECTIVE_TX_CLOCK_HZ = TXIMPL ? TX_CLOCK_HZ : SYS_CLOCK_HZ;
    localparam integer STARTUP_DIVCNT_DERIVED = ((EFFECTIVE_TX_CLOCK_HZ + 5000000) / 10000000) - 1;
    localparam [7:0] STARTUP_DIVCNT =
        (DEFAULT_DIVCNT != 0) ? DEFAULT_DIVCNT : STARTUP_DIVCNT_DERIVED[7:0];
    // Zero-padding for the 6-bit rxroom threshold. Clamped so an out-of-range
    // RXFIFOSIZE_BITS (caught by the elaboration guard below) does not produce a
    // negative replication count before the guard can report it.
    localparam integer RXROOM_PAD = (RXFIFOSIZE_BITS > 6) ? (RXFIFOSIZE_BITS - 6) : 0;

    initial begin
        if (RESET_TIME == 0 && (RESET_TIME_DERIVED < 1 || RESET_TIME_DERIVED > 2047)) begin
            $display("spwstream: derived RESET_TIME %0d is outside 11-bit range", RESET_TIME_DERIVED);
            $finish;
        end
        if (DISCONNECT_TIME == 0 && (DISCONNECT_TIME_DERIVED < 1 || DISCONNECT_TIME_DERIVED > 255)) begin
            $display("spwstream: derived DISCONNECT_TIME %0d is outside 8-bit range", DISCONNECT_TIME_DERIVED);
            $finish;
        end
        if (DEFAULT_DIVCNT == 0 && (STARTUP_DIVCNT_DERIVED < 0 || STARTUP_DIVCNT_DERIVED > 255)) begin
            $display("spwstream: derived startup divider %0d is outside 8-bit range", STARTUP_DIVCNT_DERIVED);
            $finish;
        end
        // The SpaceWire standard requires the link-handshake signalling rate to
        // be 10 Mbit/s +/- 10% ([9, 11] Mbit/s). When the startup divider is
        // auto-derived, reject clocks that have no integer divider inside that
        // window (e.g. 25 MHz -> 8.33 Mbit/s). Equivalent to
        // 9e6*(divcnt+1) <= clk <= 11e6*(divcnt+1) with no division.
        if (DEFAULT_DIVCNT == 0 &&
            (EFFECTIVE_TX_CLOCK_HZ < 9000000 * (STARTUP_DIVCNT_DERIVED + 1) ||
             EFFECTIVE_TX_CLOCK_HZ > 11000000 * (STARTUP_DIVCNT_DERIVED + 1))) begin
            $display("spwstream: derived startup rate %0d bit/s (clk %0d / %0d) is outside the SpaceWire 10 Mbit/s +/-10%% startup window; choose a clock with a compliant integer divider",
                     EFFECTIVE_TX_CLOCK_HZ / (STARTUP_DIVCNT_DERIVED + 1),
                     EFFECTIVE_TX_CLOCK_HZ, STARTUP_DIVCNT_DERIVED + 1);
            $finish;
        end
        // Parameter-range guards mirroring the VHDL constrained generics, so
        // invalid Verilog parameters fail with an intentional diagnostic instead
        // of an obscure expression error or a silently wrong implementation.
        if (RXIMPL != 0 && RXIMPL != 1) begin
            $display("spwstream: RXIMPL must be 0 (generic) or 1 (fast), got %0d", RXIMPL);
            $finish;
        end
        if (TXIMPL != 0 && TXIMPL != 1) begin
            $display("spwstream: TXIMPL must be 0 (generic) or 1 (fast), got %0d", TXIMPL);
            $finish;
        end
        if (RXCHUNK < 1 || RXCHUNK > 4) begin
            $display("spwstream: RXCHUNK must be in [1,4], got %0d", RXCHUNK);
            $finish;
        end
        if (RXFIFOSIZE_BITS < 6 || RXFIFOSIZE_BITS > 14) begin
            $display("spwstream: RXFIFOSIZE_BITS must be in [6,14], got %0d", RXFIFOSIZE_BITS);
            $finish;
        end
        if (TXFIFOSIZE_BITS < 2 || TXFIFOSIZE_BITS > 14) begin
            $display("spwstream: TXFIFOSIZE_BITS must be in [2,14], got %0d", TXFIFOSIZE_BITS);
            $finish;
        end
    end

    reg rxpacket;
    reg rxeep;
    reg txpacket;
    reg txdiscard;
    reg [RXFIFOSIZE_BITS-1:0] rxfifo_raddr;
    reg [RXFIFOSIZE_BITS-1:0] rxfifo_waddr;
    reg [TXFIFOSIZE_BITS-1:0] txfifo_raddr;
    reg [TXFIFOSIZE_BITS-1:0] txfifo_waddr;
    reg rxfifo_rvalid;
    reg txfifo_rvalid;
    reg rxfull;
    reg rxhalff_r;
    reg txfull;
    reg txhalff_r;
    reg [5:0] rxroom;
    reg [5:0] last_time;

    reg v_rxpacket;
    reg v_rxeep;
    reg v_txpacket;
    reg v_txdiscard;
    reg [RXFIFOSIZE_BITS-1:0] v_rxfifo_raddr;
    reg [RXFIFOSIZE_BITS-1:0] v_rxfifo_waddr;
    reg [TXFIFOSIZE_BITS-1:0] v_txfifo_raddr;
    reg [TXFIFOSIZE_BITS-1:0] v_txfifo_waddr;
    reg v_rxfifo_rvalid;
    reg v_txfifo_rvalid;
    reg v_rxfull;
    reg v_rxhalff;
    reg v_txfull;
    reg v_txhalff;
    reg [5:0] v_rxroom;
    reg [5:0] v_last_time;
    reg [RXFIFOSIZE_BITS-1:0] v_tmprxroom;
    reg [TXFIFOSIZE_BITS-1:0] v_tmptxroom;

    wire recv_rxen;
    wire recv_inact;
    wire recv_inbvalid;
    wire [RXCHUNK-1:0] recv_inbits;

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

    wire linko_started;
    wire linko_connecting;
    wire linko_running;
    wire linko_errdisc;
    wire linko_errpar;
    wire linko_erresc;
    wire linko_errcred;
    wire linko_txack;
    wire linko_tick_out;
    wire [1:0] linko_ctrl_out;
    wire [5:0] linko_time_out;
    wire linko_rxchar;
    wire linko_rxflag;
    wire [7:0] linko_rxdata;

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
    wire xmito_fctack;
    wire xmito_txack;

    reg [7:0] xmit_divcnt;

    reg [RXFIFOSIZE_BITS-1:0] s_rxfifo_raddr;
    wire [8:0] s_rxfifo_rdata;
    reg s_rxfifo_wen;
    reg [RXFIFOSIZE_BITS-1:0] s_rxfifo_waddr;
    reg [8:0] s_rxfifo_wdata;

    reg [TXFIFOSIZE_BITS-1:0] s_txfifo_raddr;
    wire [8:0] s_txfifo_rdata;
    reg s_txfifo_wen;
    reg [TXFIFOSIZE_BITS-1:0] s_txfifo_waddr;
    wire [8:0] s_txfifo_wdata;

    assign s_txfifo_wdata = {txflag, txdata};

    spwlink #(
        .RESET_TIME(RESET_TIME_COUNT)
    ) link_inst (
        .clk(clk),
        .rst(rst),
        .linki_autostart(autostart),
        .linki_linkstart(linkstart),
        .linki_linkdis(linkdis),
        .linki_rxroom(rxroom),
        .linki_tick_in(tick_in),
        .linki_ctrl_in(ctrl_in),
        .linki_time_in(time_in),
        .linki_txwrite(txfifo_rvalid && !txdiscard),
        .linki_txflag(s_txfifo_rdata[8]),
        .linki_txdata(s_txfifo_rdata[7:0]),
        .linko_started(linko_started),
        .linko_connecting(linko_connecting),
        .linko_running(linko_running),
        .linko_errdisc(linko_errdisc),
        .linko_errpar(linko_errpar),
        .linko_erresc(linko_erresc),
        .linko_errcred(linko_errcred),
        .linko_txack(linko_txack),
        .linko_tick_out(linko_tick_out),
        .linko_ctrl_out(linko_ctrl_out),
        .linko_time_out(linko_time_out),
        .linko_rxchar(linko_rxchar),
        .linko_rxflag(linko_rxflag),
        .linko_rxdata(linko_rxdata),
        .rxen(recv_rxen),
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
        .DISCONNECT_TIME(DISCONNECT_TIME_COUNT),
        .RXCHUNK(RXCHUNK)
    ) recv_inst (
        .clk(clk),
        .rxen(recv_rxen),
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
        .inact(recv_inact),
        .inbvalid(recv_inbvalid),
        .inbits(recv_inbits)
    );

    generate
        if (TXIMPL == 0) begin : xmit_generic_gen
            spwxmit xmit_inst (
                .clk(clk),
                .rst(rst),
                .divcnt(xmit_divcnt),
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
                .xmito_txack(xmito_txack),
                .spw_do(spw_do),
                .spw_so(spw_so)
            );
        end else begin : xmit_fast_gen
            spwxmit_fast xmit_fast_inst (
                .clk(clk),
                .txclk(txclk),
                .rst(rst),
                .divcnt(xmit_divcnt),
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
                .xmito_txack(xmito_txack),
                .spw_do(spw_do),
                .spw_so(spw_so)
            );
        end

        if (RXIMPL == 0) begin : recvfront_generic_gen
            spwrecvfront_generic recvfront_generic_inst (
                .clk(clk),
                .rxen(recv_rxen),
                .inact(recv_inact),
                .inbvalid(recv_inbvalid),
                .inbits(recv_inbits[0]),
                .spw_di(spw_di),
                .spw_si(spw_si)
            );
        end else begin : recvfront_fast_gen
            spwrecvfront_fast #(
                .RXCHUNK(RXCHUNK)
            ) recvfront_fast_inst (
                .clk(clk),
                .rxclk(rxclk),
                .rxen(recv_rxen),
                .inact(recv_inact),
                .inbvalid(recv_inbvalid),
                .inbits(recv_inbits),
                .spw_di(spw_di),
                .spw_si(spw_si)
            );
        end
    endgenerate

    spwram #(
        .ABITS(RXFIFOSIZE_BITS),
        .DBITS(9)
    ) rxmem (
        .rclk(clk),
        .wclk(clk),
        .ren(1'b1),
        .raddr(s_rxfifo_raddr),
        .rdata(s_rxfifo_rdata),
        .wen(s_rxfifo_wen),
        .waddr(s_rxfifo_waddr),
        .wdata(s_rxfifo_wdata)
    );

    spwram #(
        .ABITS(TXFIFOSIZE_BITS),
        .DBITS(9)
    ) txmem (
        .rclk(clk),
        .wclk(clk),
        .ren(1'b1),
        .raddr(s_txfifo_raddr),
        .rdata(s_txfifo_rdata),
        .wen(s_txfifo_wen),
        .waddr(s_txfifo_waddr),
        .wdata(s_txfifo_wdata)
    );

    always @* begin
        v_rxpacket = rxpacket;
        v_rxeep = rxeep;
        v_txpacket = txpacket;
        v_txdiscard = txdiscard;
        v_rxfifo_raddr = rxfifo_raddr;
        v_rxfifo_waddr = rxfifo_waddr;
        v_txfifo_raddr = txfifo_raddr;
        v_txfifo_waddr = txfifo_waddr;
        v_rxfifo_rvalid = rxfifo_rvalid;
        v_txfifo_rvalid = txfifo_rvalid;
        v_rxfull = rxfull;
        v_rxhalff = rxhalff_r;
        v_txfull = txfull;
        v_txhalff = txhalff_r;
        v_rxroom = rxroom;
        v_last_time = last_time;
        v_tmprxroom = {RXFIFOSIZE_BITS{1'b0}};
        v_tmptxroom = {TXFIFOSIZE_BITS{1'b0}};

        if (linko_rxchar) begin
            v_rxpacket = !linko_rxflag;
        end

        if (linko_txack) begin
            v_txpacket = !s_txfifo_rdata[8];
        end

        if (rxread && rxfifo_rvalid) begin
            v_rxfifo_raddr = rxfifo_raddr + {{(RXFIFOSIZE_BITS-1){1'b0}}, 1'b1};
        end

        if (!rxfull) begin
            if (linko_rxchar || rxeep) begin
                v_rxfifo_waddr = rxfifo_waddr + {{(RXFIFOSIZE_BITS-1){1'b0}}, 1'b1};
            end
            v_rxeep = 1'b0;
        end

        v_rxfifo_rvalid = (v_rxfifo_raddr != rxfifo_waddr);

        v_tmprxroom = rxfifo_raddr - v_rxfifo_waddr - {{(RXFIFOSIZE_BITS-1){1'b0}}, 1'b1};
        v_rxfull = (v_tmprxroom == {RXFIFOSIZE_BITS{1'b0}});
        v_rxhalff = !v_tmprxroom[RXFIFOSIZE_BITS-1];
        if (v_tmprxroom > {{RXROOM_PAD{1'b0}}, 6'd63}) begin
            v_rxroom = 6'b111111;
        end else begin
            v_rxroom = v_tmprxroom[5:0];
        end

        if (txfifo_rvalid && (linko_txack || txdiscard)) begin
            v_txfifo_raddr = txfifo_raddr + {{(TXFIFOSIZE_BITS-1){1'b0}}, 1'b1};
            if (s_txfifo_rdata[8]) begin
                v_txdiscard = 1'b0;
            end
        end

        if (!txfull && txwrite) begin
            v_txfifo_waddr = txfifo_waddr + {{(TXFIFOSIZE_BITS-1){1'b0}}, 1'b1};
        end

        v_txfifo_rvalid = (v_txfifo_raddr != txfifo_waddr);

        v_tmptxroom = txfifo_raddr - v_txfifo_waddr - {{(TXFIFOSIZE_BITS-1){1'b0}}, 1'b1};
        v_txfull = (v_tmptxroom == {TXFIFOSIZE_BITS{1'b0}});
        v_txhalff = !v_tmptxroom[TXFIFOSIZE_BITS-1];

        if (!linko_running) begin
            v_rxeep = v_rxeep | v_rxpacket;
            v_txdiscard = v_txdiscard | v_txpacket;
            v_rxpacket = 1'b0;
            v_txpacket = 1'b0;
        end

        if (linkdis) begin
            v_txdiscard = 1'b0;
        end

        s_rxfifo_raddr = v_rxfifo_raddr;
        s_rxfifo_wen = !rxfull && (linko_rxchar || rxeep);
        s_rxfifo_waddr = rxfifo_waddr;
        if (rxeep) begin
            s_rxfifo_wdata = 9'b100000001;
        end else begin
            s_rxfifo_wdata = {linko_rxflag, linko_rxdata};
        end

        s_txfifo_raddr = v_txfifo_raddr;
        s_txfifo_wen = !txfull && txwrite;
        s_txfifo_waddr = txfifo_waddr;

        if (linko_running) begin
            xmit_divcnt = txdivcnt;
        end else begin
            xmit_divcnt = STARTUP_DIVCNT;
        end

        txrdy = !txfull;
        txhalff = txhalff_r;
        // Strict TimeCode filter: a received TimeCode always updates the local
        // count, but in strict mode only an in-sequence value (previous+1 mod 64)
        // pulses tick_out. The comparison uses the registered last_time, so
        // tick_out stays combinational as in the transparent (default) mode.
        if (linko_tick_out) begin
            v_last_time = linko_time_out;
        end
        if (STRICT_TIMECODES != 0) begin
            tick_out = linko_tick_out &&
                       (linko_time_out == ((last_time + 6'd1) & 6'h3f));
        end else begin
            tick_out = linko_tick_out;
        end
        ctrl_out = linko_ctrl_out;
        time_out = linko_time_out;
        rxvalid = rxfifo_rvalid;
        rxhalff = rxhalff_r;
        rxflag = s_rxfifo_rdata[8];
        rxdata = s_rxfifo_rdata[7:0];
        started = linko_started;
        connecting = linko_connecting;
        running = linko_running;
        errdisc = linko_errdisc;
        errpar = linko_errpar;
        erresc = linko_erresc;
        errcred = linko_errcred;

        if (rst) begin
            v_rxpacket = 1'b0;
            v_rxeep = 1'b0;
            v_txpacket = 1'b0;
            v_txdiscard = 1'b0;
            v_rxfifo_raddr = {RXFIFOSIZE_BITS{1'b0}};
            v_rxfifo_waddr = {RXFIFOSIZE_BITS{1'b0}};
            v_txfifo_raddr = {TXFIFOSIZE_BITS{1'b0}};
            v_txfifo_waddr = {TXFIFOSIZE_BITS{1'b0}};
            v_rxfifo_rvalid = 1'b0;
            v_txfifo_rvalid = 1'b0;
            v_last_time = 6'h3f;
        end
    end

    always @(posedge clk) begin
        rxpacket <= v_rxpacket;
        rxeep <= v_rxeep;
        txpacket <= v_txpacket;
        txdiscard <= v_txdiscard;
        rxfifo_raddr <= v_rxfifo_raddr;
        rxfifo_waddr <= v_rxfifo_waddr;
        txfifo_raddr <= v_txfifo_raddr;
        txfifo_waddr <= v_txfifo_waddr;
        rxfifo_rvalid <= v_rxfifo_rvalid;
        txfifo_rvalid <= v_txfifo_rvalid;
        rxfull <= v_rxfull;
        rxhalff_r <= v_rxhalff;
        txfull <= v_txfull;
        txhalff_r <= v_txhalff;
        rxroom <= v_rxroom;
        last_time <= v_last_time;
    end

    initial begin
        rxpacket = 1'b0;
        rxeep = 1'b0;
        txpacket = 1'b0;
        txdiscard = 1'b0;
        rxfifo_raddr = {RXFIFOSIZE_BITS{1'b0}};
        rxfifo_waddr = {RXFIFOSIZE_BITS{1'b0}};
        txfifo_raddr = {TXFIFOSIZE_BITS{1'b0}};
        txfifo_waddr = {TXFIFOSIZE_BITS{1'b0}};
        rxfifo_rvalid = 1'b0;
        txfifo_rvalid = 1'b0;
        rxfull = 1'b0;
        rxhalff_r = 1'b0;
        txfull = 1'b0;
        txhalff_r = 1'b0;
        rxroom = 6'b000000;
        last_time = 6'h3f;
    end

endmodule
