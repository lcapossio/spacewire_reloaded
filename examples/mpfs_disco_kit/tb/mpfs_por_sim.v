/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * Simulation stub for mpfs_por (rtl/microchip/mpfs_por.v). Models the
 * PolarFire INIT block's fabric power-on reset: fabric_por_n is low for the
 * first RELEASE_NS of simulation time, then high.
 */

`timescale 1ns/1ps

module mpfs_por #(
    parameter integer RELEASE_NS = 200
) (
    output reg fabric_por_n
);

    initial begin
        fabric_por_n = 1'b0;
        #(RELEASE_NS) fabric_por_n = 1'b1;
    end

endmodule
