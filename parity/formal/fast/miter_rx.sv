// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Leonardo Capossio - bard0 design
// Author: Leonardo Capossio - bard0 design - hello@bard0.com
//
// Miter: VHDL spwrecvfront_fast (GHDL-synthesized, renamed gold_rx) vs Verilog.
module miter_rx #(
    parameter RXCHUNK = 1,
    // Minimum reset length: rising edges of clk / rxclk while rxen is low.
    parameter RST_CLK = 4, RST_RXCLK = 4
) (
    input wire clk, rxclk, rxen, spw_di, spw_si
);
    wire g_inact, g_inbvalid, c_inact, c_inbvalid;
    wire [RXCHUNK-1:0] g_inbits, c_inbits;

    gold_rx g (.clk(clk), .rxclk(rxclk), .rxen(rxen), .inact(g_inact),
               .inbvalid(g_inbvalid), .inbits(g_inbits), .spw_di(spw_di), .spw_si(spw_si));
    spwrecvfront_fast #(.RXCHUNK(RXCHUNK)) c (.clk(clk), .rxclk(rxclk), .rxen(rxen),
               .inact(c_inact), .inbvalid(c_inbvalid), .inbits(c_inbits),
               .spw_di(spw_di), .spw_si(spw_si));

    // Environment: once rxen is low it stays low until clk has had RST_CLK
    // and rxclk RST_RXCLK rising edges; the design also starts in reset.
    // spwlink drives rxen low only in ErrorReset, for reset_time =
    // sysfreq * 6.4 us clk cycles, and rxclk must run at least as fast as clk,
    // so this holds with running clocks. Any high level of rxen clears the
    // counts. rxclk edges count only once a clk edge has registered the reset
    // (rxdis).
    reg [2:0] lowc = 0, lowr = 0;
    reg clk_q = 0, rxclk_q = 0, rxen_q = 0;
    always @($global_clock) begin
        clk_q <= clk; rxclk_q <= rxclk; rxen_q <= rxen;
        // The design registers rxen as sampled on the previous step.
        if (rxen || rxen_q) begin
            lowc <= 0; lowr <= 0;
        end else begin
            if (clk && !clk_q && lowc != 7) lowc <= lowc + 1;
            if (rxclk && !rxclk_q && lowc != 0 && lowr != 7) lowr <= lowr + 1;
        end
    end
    // Both clocks start low, so the first step cannot be a rising edge that
    // the counters see but the design (whose previous clock sample is
    // arbitrary) does not.
    reg first = 1;
    always @($global_clock) first <= 0;
    always @* if (first) assume (!clk && !rxclk);

    wire rst_done = lowc >= RST_CLK && lowr >= RST_RXCLK;
    always @* if (!rxen_q && !rst_done) assume (!rxen);

    // Outputs are compared from the end of the first complete reset. The
    // flag is latched on the formal step clock, before the counters clear.
    reg started = 0, released = 0;
    always @($global_clock) begin
        if (rst_done) started <= 1;
        if (!rxen_q && rxen) released <= 1;
    end

    always @* begin
        // Every reset release must have enabled the comparison.
        assert (!released || started);
        if (started) begin
            assert (g_inact == c_inact);
            assert (g_inbvalid == c_inbvalid);
            // inbits is only meaningful while inbvalid is high.
            if (g_inbvalid) assert (g_inbits == c_inbits);
        end
    end
endmodule
