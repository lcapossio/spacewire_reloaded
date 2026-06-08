/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2009-2013 Joris van Rantwijk
 * Verilog translation Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 * Fast SpaceWire Transmitter.
 *
 * Hand-written Verilog 2001 translation of rtl/vhdl/spwxmit_fast.vhd from
 * SpaceWire Light. VHDL record ports are flattened for Verilog 2001
 * compatibility.
 */

`timescale 1ns / 1ps

module spwxmit_fast (
    input  wire       clk,
    input  wire       txclk,
    input  wire       rst,
    input  wire [7:0] divcnt,

    input  wire       xmiti_txen,
    input  wire       xmiti_stnull,
    input  wire       xmiti_stfct,
    input  wire       xmiti_fct_in,
    input  wire       xmiti_tick_in,
    input  wire [1:0] xmiti_ctrl_in,
    input  wire [5:0] xmiti_time_in,
    input  wire       xmiti_txwrite,
    input  wire       xmiti_txflag,
    input  wire [7:0] xmiti_txdata,

    output reg        xmito_fctack,
    output reg        xmito_txack,
    output wire       spw_do,
    output wire       spw_so
);

    wire synctx_rstn;
    wire synctx_sysflip0;
    wire synctx_sysflip1;
    wire synctx_txen;
    wire synctx_txdivsafe;
    wire syncsys_txflip0;
    wire syncsys_txflip1;

    reg txflip0;
    reg txflip1;
    reg b_update;
    reg b_mux;
    reg b_txflip;
    reg b_valid;
    reg b_token_tick;
    reg b_token_fct;
    reg b_token_fctpiggy;
    reg b_token_flag;
    reg [7:0] b_token_char;
    reg c_update;
    reg c_busy;
    reg c_esc;
    reg c_fct;
    reg [8:0] c_bits;
    reg [8:0] d_bits;
    reg d_cnt4;
    reg d_cnt10;
    reg e_valid;
    reg [9:0] e_shift;
    reg [9:0] e_count;
    reg e_parity;
    reg f_spwdo;
    reg f_spwso;
    reg txclken;
    reg txclkpre;
    reg [7:0] txclkcnt;
    reg [2:0] txclkcy;
    reg [1:0] txclkdone;
    reg [7:0] txclkdiv;
    reg txdivnorm_tx;
    reg spwdo_r;
    reg spwso_r;

    reg v_txflip0;
    reg v_txflip1;
    reg v_b_update;
    reg v_b_mux;
    reg v_b_txflip;
    reg v_b_valid;
    reg v_b_token_tick;
    reg v_b_token_fct;
    reg v_b_token_fctpiggy;
    reg v_b_token_flag;
    reg [7:0] v_b_token_char;
    reg v_c_update;
    reg v_c_busy;
    reg v_c_esc;
    reg v_c_fct;
    reg [8:0] v_c_bits;
    reg [8:0] v_d_bits;
    reg v_d_cnt4;
    reg v_d_cnt10;
    reg v_e_valid;
    reg [9:0] v_e_shift;
    reg [9:0] v_e_count;
    reg v_e_parity;
    reg v_f_spwdo;
    reg v_f_spwso;
    reg v_txclken;
    reg v_txclkpre;
    reg [7:0] v_txclkcnt;
    reg [2:0] v_txclkcy;
    reg [1:0] v_txclkdone;
    reg [7:0] v_txclkdiv;
    reg v_txdivnorm_tx;

    reg txenreg;
    reg [7:0] txdivreg;
    reg txdivnorm;
    reg [1:0] txdivtmp;
    reg txdivsafe;
    reg sysflip0;
    reg sysflip1;
    reg token0_tick;
    reg token0_fct;
    reg token0_fctpiggy;
    reg token0_flag;
    reg [7:0] token0_char;
    reg token1_tick;
    reg token1_fct;
    reg token1_fctpiggy;
    reg token1_flag;
    reg [7:0] token1_char;
    reg tokmux;
    reg pend_fct;
    reg pend_char;
    reg [8:0] pend_data;
    reg pend_tick;
    reg [7:0] pend_time;
    reg allow_fct;
    reg allow_char;
    reg sent_fct;

    reg v_txenreg;
    reg [7:0] v_txdivreg;
    reg v_txdivnorm;
    reg [1:0] v_txdivtmp;
    reg v_txdivsafe;
    reg v_sysflip0;
    reg v_sysflip1;
    reg v_token0_tick;
    reg v_token0_fct;
    reg v_token0_fctpiggy;
    reg v_token0_flag;
    reg [7:0] v_token0_char;
    reg v_token1_tick;
    reg v_token1_fct;
    reg v_token1_fctpiggy;
    reg v_token1_flag;
    reg [7:0] v_token1_char;
    reg v_tokmux;
    reg v_pend_fct;
    reg v_pend_char;
    reg [8:0] v_pend_data;
    reg v_pend_tick;
    reg [7:0] v_pend_time;
    reg v_allow_fct;
    reg v_allow_char;
    reg v_sent_fct;

    reg needtoken;
    reg havetoken;
    reg token_tick;
    reg token_fct;
    reg token_fctpiggy;
    reg token_flag;
    reg [7:0] token_char;

    syncdff synctx_rst (
        .clk(txclk), .rst(rst), .di(1'b1), .do(synctx_rstn)
    );
    syncdff synctx_sysflip0_sync (
        .clk(txclk), .rst(rst), .di(sysflip0), .do(synctx_sysflip0)
    );
    syncdff synctx_sysflip1_sync (
        .clk(txclk), .rst(rst), .di(sysflip1), .do(synctx_sysflip1)
    );
    syncdff synctx_txen_sync (
        .clk(txclk), .rst(rst), .di(txenreg), .do(synctx_txen)
    );
    syncdff synctx_txdivsafe_sync (
        .clk(txclk), .rst(rst), .di(txdivsafe), .do(synctx_txdivsafe)
    );
    syncdff syncsys_txflip0_sync (
        .clk(clk), .rst(rst), .di(txflip0), .do(syncsys_txflip0)
    );
    syncdff syncsys_txflip1_sync (
        .clk(clk), .rst(rst), .di(txflip1), .do(syncsys_txflip1)
    );

    assign spw_do = spwdo_r;
    assign spw_so = spwso_r;

    always @* begin
        v_txflip0 = txflip0;
        v_txflip1 = txflip1;
        v_b_update = b_update;
        v_b_mux = b_mux;
        v_b_txflip = b_txflip;
        v_b_valid = b_valid;
        v_b_token_tick = b_token_tick;
        v_b_token_fct = b_token_fct;
        v_b_token_fctpiggy = b_token_fctpiggy;
        v_b_token_flag = b_token_flag;
        v_b_token_char = b_token_char;
        v_c_update = c_update;
        v_c_busy = c_busy;
        v_c_esc = c_esc;
        v_c_fct = c_fct;
        v_c_bits = c_bits;
        v_d_bits = d_bits;
        v_d_cnt4 = d_cnt4;
        v_d_cnt10 = d_cnt10;
        v_e_valid = e_valid;
        v_e_shift = e_shift;
        v_e_count = e_count;
        v_e_parity = e_parity;
        v_f_spwdo = f_spwdo;
        v_f_spwso = f_spwso;
        v_txclken = txclken;
        v_txclkpre = txclkpre;
        v_txclkcnt = txclkcnt;
        v_txclkcy = txclkcy;
        v_txclkdone = txclkdone;
        v_txclkdiv = txclkdiv;
        v_txdivnorm_tx = txdivnorm_tx;

        v_txenreg = txenreg;
        v_txdivreg = txdivreg;
        v_txdivnorm = txdivnorm;
        v_txdivtmp = txdivtmp;
        v_txdivsafe = txdivsafe;
        v_sysflip0 = sysflip0;
        v_sysflip1 = sysflip1;
        v_token0_tick = token0_tick;
        v_token0_fct = token0_fct;
        v_token0_fctpiggy = token0_fctpiggy;
        v_token0_flag = token0_flag;
        v_token0_char = token0_char;
        v_token1_tick = token1_tick;
        v_token1_fct = token1_fct;
        v_token1_fctpiggy = token1_fctpiggy;
        v_token1_flag = token1_flag;
        v_token1_char = token1_char;
        v_tokmux = tokmux;
        v_pend_fct = pend_fct;
        v_pend_char = pend_char;
        v_pend_data = pend_data;
        v_pend_tick = pend_tick;
        v_pend_time = pend_time;
        v_allow_fct = allow_fct;
        v_allow_char = allow_char;
        v_sent_fct = sent_fct;

        needtoken = 1'b0;
        havetoken = 1'b0;
        token_tick = 1'b0;
        token_fct = 1'b0;
        token_fctpiggy = 1'b0;
        token_flag = 1'b0;
        token_char = 8'd0;

        v_b_update = txclken && e_count[0] && !c_busy;
        v_b_txflip = b_mux ? txflip1 : txflip0;
        if (b_update) begin
            if (!b_mux) begin
                v_b_valid = synctx_sysflip0 ^ b_txflip;
                v_b_token_tick = token0_tick;
                v_b_token_fct = token0_fct;
                v_b_token_fctpiggy = token0_fctpiggy;
                v_b_token_flag = token0_flag;
                v_b_token_char = token0_char;
                v_b_mux = synctx_sysflip0 ^ b_txflip;
                v_txflip0 = synctx_sysflip0;
                v_txflip1 = txflip1;
            end else begin
                v_b_valid = synctx_sysflip1 ^ b_txflip;
                v_b_token_tick = token1_tick;
                v_b_token_fct = token1_fct;
                v_b_token_fctpiggy = token1_fctpiggy;
                v_b_token_flag = token1_flag;
                v_b_token_char = token1_char;
                v_b_mux = !(synctx_sysflip1 ^ b_txflip);
                v_txflip0 = txflip0;
                v_txflip1 = synctx_sysflip1;
            end
        end

        v_c_update = txclken && e_count[3];
        if (c_update) begin
            v_c_esc = (b_token_tick || !b_valid) && !c_esc;
            v_c_fct = (b_token_fct && !c_busy) || !b_valid;
            v_c_busy = (b_token_tick || !b_valid || b_token_fctpiggy) && !c_busy;
            if (b_token_flag) begin
                if (!b_token_char[0]) begin
                    v_c_bits = 9'b000000101;
                end else begin
                    v_c_bits = 9'b000000011;
                end
            end else begin
                v_c_bits = {b_token_char, 1'b0};
            end
        end

        if (c_esc) begin
            v_d_bits = 9'b000000111;
            v_d_cnt4 = 1'b1;
            v_d_cnt10 = 1'b0;
        end else if (c_fct) begin
            v_d_bits = 9'b000000001;
            v_d_cnt4 = 1'b1;
            v_d_cnt10 = 1'b0;
        end else begin
            v_d_bits = c_bits;
            v_d_cnt4 = c_bits[0];
            v_d_cnt10 = !c_bits[0];
        end

        if (txclken) begin
            if (e_count[0]) begin
                v_e_valid = 1'b1;
                v_e_shift[9:1] = d_bits;
                v_e_shift[0] = !(e_parity ^ d_bits[0]);
                v_e_count = {d_cnt10, 5'b00000, d_cnt4, 3'b000};
                v_e_parity = d_bits[0];
            end else begin
                v_e_shift = {1'b0, e_shift[9:1]};
                v_e_count = {1'b0, e_count[9:1]};
                v_e_parity = e_parity ^ e_shift[1];
            end
        end

        if (txclken) begin
            if (e_valid) begin
                v_f_spwdo = e_shift[0];
                v_f_spwso = !(e_shift[0] ^ f_spwdo ^ f_spwso);
            end else begin
                v_f_spwdo = f_spwdo & f_spwso;
                v_f_spwso = 1'b0;
            end
        end

        v_txclkcnt[1:0] = txclkcnt[1:0] - 2'd1;
        v_txclkcnt[3:2] = txclkcnt[3:2] - {1'b0, txclkcy[0]};
        v_txclkcnt[5:4] = txclkcnt[5:4] - {1'b0, txclkcy[1]};
        v_txclkcnt[7:6] = txclkcnt[7:6] - {1'b0, txclkcy[2]};
        v_txclkcy[0] = (txclkcnt[1:0] == 2'b00);
        v_txclkcy[1] = txclkcy[0] && (txclkcnt[3:2] == 2'b00);
        v_txclkcy[2] = txclkcy[1] && (txclkcnt[5:4] == 2'b00);
        v_txclkdone[0] = (txclkcnt[3:0] == 4'b0010);
        v_txclkdone[1] = (txclkcnt[7:4] == 4'b0000);
        v_txclken = (txclkdone[0] && txclkdone[1]) || txclkpre;
        v_txclkpre = !txdivnorm_tx && (!txclkpre || !txclkdiv[0]);
        if (txclken) begin
            v_txclkcnt = txclkdiv;
            v_txclkcy = 3'b000;
            v_txclkdone = 2'b00;
        end

        if (synctx_txdivsafe) begin
            v_txclkdiv = txdivreg;
            v_txdivnorm_tx = txdivnorm;
        end

        if (!synctx_txen) begin
            v_txflip0 = 1'b0;
            v_txflip1 = 1'b0;
            v_b_update = 1'b0;
            v_b_mux = 1'b0;
            v_b_valid = 1'b0;
            v_c_update = 1'b0;
            v_c_busy = 1'b1;
            v_c_esc = 1'b1;
            v_c_fct = 1'b1;
            v_d_bits = 9'b000000111;
            v_d_cnt4 = 1'b1;
            v_d_cnt10 = 1'b0;
            v_e_valid = 1'b0;
            v_e_parity = 1'b0;
            v_e_count = 10'b0000000001;
        end

        if (!synctx_rstn) begin
            v_f_spwdo = 1'b0;
            v_f_spwso = 1'b0;
            v_txclken = 1'b0;
            v_txclkpre = 1'b1;
            v_txclkcnt = 8'd0;
            v_txclkdiv = 8'd0;
            v_txdivnorm_tx = 1'b0;
        end

        v_txdivtmp = txdivtmp - 2'd1;
        if (txdivtmp == 2'b00) begin
            if (!txdivsafe) begin
                v_txdivsafe = 1'b1;
                v_txdivtmp = 2'b01;
                v_txdivreg = divcnt;
                v_txdivnorm = (divcnt[7:1] != 7'd0);
                v_txenreg = xmiti_txen;
            end else begin
                v_txdivsafe = 1'b0;
            end
        end

        if (!xmiti_txen) begin
            v_txenreg = 1'b0;
        end

        if (xmiti_fct_in && allow_fct) begin
            v_pend_fct = 1'b1;
        end

        if (!xmiti_txen) begin
            v_sysflip0 = 1'b0;
            v_sysflip1 = 1'b0;
            v_tokmux = 1'b0;
            v_pend_fct = 1'b0;
            v_pend_char = 1'b0;
            v_pend_tick = 1'b0;
            v_allow_fct = 1'b0;
            v_allow_char = 1'b0;
            v_sent_fct = 1'b0;
        end else begin
            if (!tokmux) begin
                if (sysflip0 == syncsys_txflip0) begin
                    needtoken = 1'b1;
                end
            end else begin
                if (sysflip1 == syncsys_txflip1) begin
                    needtoken = 1'b1;
                end
            end

            if (allow_char && pend_tick) begin
                token_tick = 1'b1;
                token_fct = 1'b0;
                token_fctpiggy = 1'b0;
                token_flag = 1'b0;
                token_char = pend_time;
                havetoken = 1'b1;
                if (needtoken) begin
                    v_pend_tick = 1'b0;
                end
            end else begin
                if (allow_fct && (xmiti_fct_in || pend_fct)) begin
                    token_fct = 1'b1;
                    havetoken = 1'b1;
                    if (needtoken) begin
                        v_pend_fct = 1'b0;
                        v_sent_fct = 1'b1;
                    end
                end
                if (allow_char && pend_char) begin
                    token_fctpiggy = token_fct;
                    token_flag = pend_data[8];
                    token_char = pend_data[7:0];
                    havetoken = 1'b1;
                    if (needtoken) begin
                        v_pend_char = 1'b0;
                    end
                end
            end

            if (havetoken) begin
                if (!tokmux) begin
                    if (sysflip0 == syncsys_txflip0) begin
                        v_sysflip0 = !sysflip0;
                        v_token0_tick = token_tick;
                        v_token0_fct = token_fct;
                        v_token0_fctpiggy = token_fctpiggy;
                        v_token0_flag = token_flag;
                        v_token0_char = token_char;
                        v_tokmux = 1'b1;
                    end
                end else begin
                    if (sysflip1 == syncsys_txflip1) begin
                        v_sysflip1 = !sysflip1;
                        v_token1_tick = token_tick;
                        v_token1_fct = token_fct;
                        v_token1_fctpiggy = token_fctpiggy;
                        v_token1_flag = token_flag;
                        v_token1_char = token_char;
                        v_tokmux = 1'b0;
                    end
                end
            end

            v_allow_fct = !xmiti_stnull;
            v_allow_char = !xmiti_stnull && !xmiti_stfct && sent_fct;

            if (xmiti_txwrite && allow_char && !pend_char) begin
                v_pend_char = 1'b1;
                v_pend_data = {xmiti_txflag, xmiti_txdata};
            end

            if (xmiti_tick_in) begin
                v_pend_tick = 1'b1;
                v_pend_time = {xmiti_ctrl_in, xmiti_time_in};
            end
        end

        if (rst) begin
            v_txenreg = 1'b0;
            v_txdivreg = 8'd0;
            v_txdivnorm = 1'b0;
            v_txdivtmp = 2'b00;
            v_txdivsafe = 1'b0;
            v_sysflip0 = 1'b0;
            v_sysflip1 = 1'b0;
            v_token0_tick = 1'b0;
            v_token0_fct = 1'b0;
            v_token0_fctpiggy = 1'b0;
            v_token0_flag = 1'b0;
            v_token0_char = 8'd0;
            v_token1_tick = 1'b0;
            v_token1_fct = 1'b0;
            v_token1_fctpiggy = 1'b0;
            v_token1_flag = 1'b0;
            v_token1_char = 8'd0;
            v_tokmux = 1'b0;
            v_pend_fct = 1'b0;
            v_pend_char = 1'b0;
            v_pend_data = 9'd0;
            v_pend_tick = 1'b0;
            v_pend_time = 8'd0;
            v_allow_fct = 1'b0;
            v_allow_char = 1'b0;
            v_sent_fct = 1'b0;
        end

        xmito_fctack = xmiti_fct_in && xmiti_txen && allow_fct && !pend_fct;
        xmito_txack = xmiti_txwrite && xmiti_txen && allow_char && !pend_char;
    end

    always @(posedge txclk) begin
        spwdo_r <= f_spwdo;
        spwso_r <= f_spwso;
        txflip0 <= v_txflip0;
        txflip1 <= v_txflip1;
        b_update <= v_b_update;
        b_mux <= v_b_mux;
        b_txflip <= v_b_txflip;
        b_valid <= v_b_valid;
        b_token_tick <= v_b_token_tick;
        b_token_fct <= v_b_token_fct;
        b_token_fctpiggy <= v_b_token_fctpiggy;
        b_token_flag <= v_b_token_flag;
        b_token_char <= v_b_token_char;
        c_update <= v_c_update;
        c_busy <= v_c_busy;
        c_esc <= v_c_esc;
        c_fct <= v_c_fct;
        c_bits <= v_c_bits;
        d_bits <= v_d_bits;
        d_cnt4 <= v_d_cnt4;
        d_cnt10 <= v_d_cnt10;
        e_valid <= v_e_valid;
        e_shift <= v_e_shift;
        e_count <= v_e_count;
        e_parity <= v_e_parity;
        f_spwdo <= v_f_spwdo;
        f_spwso <= v_f_spwso;
        txclken <= v_txclken;
        txclkpre <= v_txclkpre;
        txclkcnt <= v_txclkcnt;
        txclkcy <= v_txclkcy;
        txclkdone <= v_txclkdone;
        txclkdiv <= v_txclkdiv;
        txdivnorm_tx <= v_txdivnorm_tx;
    end

    always @(posedge clk) begin
        txenreg <= v_txenreg;
        txdivreg <= v_txdivreg;
        txdivnorm <= v_txdivnorm;
        txdivtmp <= v_txdivtmp;
        txdivsafe <= v_txdivsafe;
        sysflip0 <= v_sysflip0;
        sysflip1 <= v_sysflip1;
        token0_tick <= v_token0_tick;
        token0_fct <= v_token0_fct;
        token0_fctpiggy <= v_token0_fctpiggy;
        token0_flag <= v_token0_flag;
        token0_char <= v_token0_char;
        token1_tick <= v_token1_tick;
        token1_fct <= v_token1_fct;
        token1_fctpiggy <= v_token1_fctpiggy;
        token1_flag <= v_token1_flag;
        token1_char <= v_token1_char;
        tokmux <= v_tokmux;
        pend_fct <= v_pend_fct;
        pend_char <= v_pend_char;
        pend_data <= v_pend_data;
        pend_tick <= v_pend_tick;
        pend_time <= v_pend_time;
        allow_fct <= v_allow_fct;
        allow_char <= v_allow_char;
        sent_fct <= v_sent_fct;
    end

    initial begin
        txflip0 = 1'b0;
        txflip1 = 1'b0;
        b_update = 1'b0;
        b_mux = 1'b0;
        b_txflip = 1'b0;
        b_valid = 1'b0;
        b_token_tick = 1'b0;
        b_token_fct = 1'b0;
        b_token_fctpiggy = 1'b0;
        b_token_flag = 1'b0;
        b_token_char = 8'd0;
        c_update = 1'b0;
        c_busy = 1'b1;
        c_esc = 1'b1;
        c_fct = 1'b1;
        c_bits = 9'd0;
        d_bits = 9'b000000111;
        d_cnt4 = 1'b1;
        d_cnt10 = 1'b0;
        e_valid = 1'b0;
        e_shift = 10'd0;
        e_count = 10'b0000000001;
        e_parity = 1'b0;
        f_spwdo = 1'b0;
        f_spwso = 1'b0;
        txclken = 1'b0;
        txclkpre = 1'b1;
        txclkcnt = 8'd0;
        txclkcy = 3'd0;
        txclkdone = 2'd0;
        txclkdiv = 8'd0;
        txdivnorm_tx = 1'b0;
        spwdo_r = 1'b0;
        spwso_r = 1'b0;

        txenreg = 1'b0;
        txdivreg = 8'd0;
        txdivnorm = 1'b0;
        txdivtmp = 2'b00;
        txdivsafe = 1'b0;
        sysflip0 = 1'b0;
        sysflip1 = 1'b0;
        token0_tick = 1'b0;
        token0_fct = 1'b0;
        token0_fctpiggy = 1'b0;
        token0_flag = 1'b0;
        token0_char = 8'd0;
        token1_tick = 1'b0;
        token1_fct = 1'b0;
        token1_fctpiggy = 1'b0;
        token1_flag = 1'b0;
        token1_char = 8'd0;
        tokmux = 1'b0;
        pend_fct = 1'b0;
        pend_char = 1'b0;
        pend_data = 9'd0;
        pend_tick = 1'b0;
        pend_time = 8'd0;
        allow_fct = 1'b0;
        allow_char = 1'b0;
        sent_fct = 1'b0;
    end

endmodule
