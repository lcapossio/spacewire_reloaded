/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * Simulation stub for de25_reset_release (rtl/intel/de25_reset_release.v).
 * Models the Agilex configuration reset release: ninit_done is high for the
 * first RELEASE_NS of simulation time, then low (user mode).
 */

`timescale 1ns/1ps

module de25_reset_release #(
    parameter integer RELEASE_NS = 500
) (
    output reg ninit_done
);

    initial begin
        ninit_done = 1'b1;
        #(RELEASE_NS) ninit_done = 1'b0;
    end

endmodule
