// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Leonardo Capossio - bard0 design
// Author: Leonardo Capossio - bard0 design - hello@bard0.com
//
// Miter: VHDL spwrecvfront_fast (GHDL-synthesized, renamed gold_rx) vs Verilog.
module miter_rx #(parameter RXCHUNK = 1) (
    input wire clk, rxclk, rxen, spw_di, spw_si
);
    wire g_inact, g_inbvalid, c_inact, c_inbvalid;
    wire [RXCHUNK-1:0] g_inbits, c_inbits;

    gold_rx g (.clk(clk), .rxclk(rxclk), .rxen(rxen), .inact(g_inact),
               .inbvalid(g_inbvalid), .inbits(g_inbits), .spw_di(spw_di), .spw_si(spw_si));
    spwrecvfront_fast #(.RXCHUNK(RXCHUNK)) c (.clk(clk), .rxclk(rxclk), .rxen(rxen),
               .inact(c_inact), .inbvalid(c_inbvalid), .inbits(c_inbits),
               .spw_di(spw_di), .spw_si(spw_si));

    // Environment (what spwlink guarantees: rxen is low only in ErrorReset,
    // for reset_time = sysfreq * 6.4 us clk cycles): once rxen is low it
    // stays low until both clocks have had RSTN rising edges. This also
    // makes the design start in reset.
    localparam RSTN = 4;
    // Rising edges of each clock seen while rxen is low (any high level of
    // rxen clears them). rxclk edges count only once a clk edge has
    // registered the reset (rxdis), i.e. both clocks keep running.
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
    always @* if (!rxen_q && (lowc < RSTN || lowr < RSTN)) assume (!rxen);

    // Outputs are compared once the first reset has completed.
    reg started = 0;
    always @(posedge clk) if (lowc >= RSTN && lowr >= RSTN) started <= 1;

    always @* begin
        if (started) begin
            assert (g_inact == c_inact);
            assert (g_inbvalid == c_inbvalid);
            // inbits is only meaningful while inbvalid is high.
            if (g_inbvalid) assert (g_inbits == c_inbits);
        end
    end
endmodule
