/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * PolarFire / PolarFire SoC fabric power-on reset (Libero only).
 *
 * PolarFire fabric registers have no power-up value: Synplify ignores register
 * initial values, and reprogramming the device over JTAG keeps the registers'
 * previous contents (measured on the Discovery Kit, see the example README).
 * A reset built from fabric registers alone, such as a counter that is assumed
 * to start at 0, therefore never fires after a reprogram. The device's INIT
 * block drives FABRIC_POR_N low while the fabric is being initialized, which
 * is the only reset source that does not depend on register state.
 *
 * fabric_por_n is asynchronous to every fabric clock; the top-level uses it as
 * the asynchronous assert of its reset synchronizer.
 *
 * Simulation uses tb/mpfs_por_sim.v (or .vhd) instead of this file.
 */

`timescale 1ns/1ps

module mpfs_por (
    output wire fabric_por_n
);

    INIT u_init (
        .FABRIC_POR_N(fabric_por_n),
        .GPIO_ACTIVE(),
        .HSIO_ACTIVE(),
        .PCIE_INIT_DONE(),
        .RFU(),
        .SRAM_INIT_DONE(),
        .UIC_INIT_DONE(),
        .USRAM_INIT_DONE()
    );

endmodule
