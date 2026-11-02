/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * Vendor wrapper: Intel/Altera Agilex 5 configuration reset release.
 *
 * ninit_done is high while the device is still entering user mode and drops
 * low once the whole fabric is configured and released. Agilex devices release
 * sectors of the fabric at different times, so user logic must be held in
 * reset until ninit_done falls.
 *
 * Implemented with the Altera "Reset Release" IP (de25_reset_release_ip.ip,
 * component altera_s10_user_rst_clkgate), which Quartus generates at compile
 * time. The packaged IP is used rather than its underlying atom because the
 * Quartus Agilex 5 design rules (RES-10204) require exactly one Reset Release
 * IP instance per project.
 *
 * This file is Quartus-only. Simulation uses a behavioral stub with the same
 * module name (examples/de25_nano/tb/de25_reset_release_sim.v / .vhd). Port
 * the example to another vendor by supplying a different implementation of
 * this one-output module.
 */

`timescale 1ns/1ps

module de25_reset_release (
    output wire ninit_done
);

    de25_reset_release_ip u_reset_release (
        .ninit_done(ninit_done)
    );

endmodule
