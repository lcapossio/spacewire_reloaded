// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Leonardo Capossio - bard0 design
// Author: Leonardo Capossio - bard0 design - hello@bard0.com
//
// Miter: VHDL spwxmit_fast (GHDL-synthesized via spwxmit_fast_flat, renamed
// gold_tx) vs the Verilog spwxmit_fast.
module miter_tx #(
    // Minimum reset length: rising edges of clk / txclk while rst is high.
    parameter RST_CLK = 4, RST_TXCLK = 4
) (
    input wire clk, txclk, rst,
    input wire [7:0] divcnt,
    input wire txen, stnull, stfct, fct_in, tick_in,
    input wire [1:0] ctrl_in,
    input wire [5:0] time_in,
    input wire txwrite, txflag,
    input wire [7:0] txdata
);
    wire g_fctack, g_txack, g_do, g_so, c_fctack, c_txack, c_do, c_so;

    gold_tx g (.clk(clk), .txclk(txclk), .rst(rst), .divcnt(divcnt),
        .xmiti_txen(txen), .xmiti_stnull(stnull), .xmiti_stfct(stfct),
        .xmiti_fct_in(fct_in), .xmiti_tick_in(tick_in), .xmiti_ctrl_in(ctrl_in),
        .xmiti_time_in(time_in), .xmiti_txwrite(txwrite), .xmiti_txflag(txflag),
        .xmiti_txdata(txdata), .xmito_fctack(g_fctack), .xmito_txack(g_txack),
        .spw_do(g_do), .spw_so(g_so));
    spwxmit_fast c (.clk(clk), .txclk(txclk), .rst(rst), .divcnt(divcnt),
        .xmiti_txen(txen), .xmiti_stnull(stnull), .xmiti_stfct(stfct),
        .xmiti_fct_in(fct_in), .xmiti_tick_in(tick_in), .xmiti_ctrl_in(ctrl_in),
        .xmiti_time_in(time_in), .xmiti_txwrite(txwrite), .xmiti_txflag(txflag),
        .xmiti_txdata(txdata), .xmito_fctack(c_fctack), .xmito_txack(c_txack),
        .spw_do(c_do), .spw_so(c_so));

    // Environment: once rst is high it stays high until clk has had RST_CLK
    // and txclk RST_TXCLK rising edges (the design starts in reset). The
    // design registers rst as sampled on the previous formal step, so an edge
    // counts only when rst was already high then.
    reg [2:0] hic = 0, hit = 0;
    reg clk_q = 0, txclk_q = 0, rst_q = 1;
    always @($global_clock) begin
        clk_q <= clk; txclk_q <= txclk; rst_q <= rst;
        if (!rst || !rst_q) begin
            hic <= 0; hit <= 0;
        end else begin
            if (clk && !clk_q && hic != 7) hic <= hic + 1;
            if (txclk && !txclk_q && hit != 7) hit <= hit + 1;
        end
    end
    // Both clocks start low, so the first step cannot be a rising edge that
    // the counters see but the design (whose previous clock sample is
    // arbitrary) does not.
    reg first = 1;
    always @($global_clock) first <= 0;
    always @* if (first) assume (!clk && !txclk);

    wire rst_done = hic >= RST_CLK && hit >= RST_TXCLK;
    always @* if (rst_q && !rst_done) assume (rst);

    // Outputs are compared from the end of the first complete reset. The
    // flag is latched on the formal step clock, before the counters clear.
    reg started = 0, released = 0;
    always @($global_clock) begin
        if (rst_done) started <= 1;
        if (rst_q && !rst) released <= 1;
    end

    always @* begin
        // Every reset release must have enabled the comparison.
        assert (!released || started);
        if (started) begin
            assert (g_fctack == c_fctack);
            assert (g_txack == c_txack);
            assert (g_do == c_do);
            assert (g_so == c_so);
        end
    end
endmodule
