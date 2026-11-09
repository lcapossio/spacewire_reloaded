/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * PolarFire SoC Discovery Kit vendor wrapper: fpgacapZero ("fcapz") JTAG debug
 * cores for Microchip PolarFire / PolarFire SoC (Libero only). The top-level
 * sees the same vendor-neutral interface as the DE25-Nano's de25_debug -- an
 * AXI4 master, an ELA probe bus and EIO in/out bits -- plus the five dedicated
 * JTAG pins, which UJTAG must reach as top-level ports (Libero binds them; the
 * PDC leaves them out). Simulation uses tb/mpfs_debug_sim.v (same module name,
 * idle master).
 *
 * PolarFire has a single user TAP primitive (UJTAG), so every core shares it.
 * jtag_tap_polarfire decodes two user instructions:
 *   USER1 (IR 0x20)  fcapz_debug_multi: core manager, slot 0 = ELA (ELA_W
 *                    bits, registers and burst readout on this one chain),
 *                    slot 1 = EIO (EIO_W in / EIO_W out)
 *   USER2 (IR 0x21)  EJTAG-AXI bridge (AXI4 master -> loopback engine)
 * These are the fcapz host's PolarFire IR codes (chains 1 and 2). 0x10/0x11
 * are left alone: the PolarFire SoC MSS debug module answers there.
 */

`timescale 1ns/1ps

module mpfs_debug #(
    parameter integer ELA_W = 16,
    parameter integer EIO_W = 8
) (
    input  wire             clk,
    input  wire             rst,
    // Power-on reset, active high (FABRIC_POR_N inverted): resets the fcapz
    // hub and its slots, whose registers have no power-up value on PolarFire
    input  wire             hub_por,
    // dedicated JTAG pins (straight to top-level ports)
    input  wire             tck,
    input  wire             tms,
    input  wire             tdi,
    input  wire             trstb,
    output wire             tdo,
    // AXI4 master (JTAG host -> fabric)
    output wire [31:0]      m_axi_awaddr,
    output wire [7:0]       m_axi_awlen,
    output wire [2:0]       m_axi_awsize,
    output wire [1:0]       m_axi_awburst,
    output wire             m_axi_awvalid,
    input  wire             m_axi_awready,
    output wire [31:0]      m_axi_wdata,
    output wire [3:0]       m_axi_wstrb,
    output wire             m_axi_wlast,
    output wire             m_axi_wvalid,
    input  wire             m_axi_wready,
    input  wire [1:0]       m_axi_bresp,
    input  wire             m_axi_bvalid,
    output wire             m_axi_bready,
    output wire [31:0]      m_axi_araddr,
    output wire [7:0]       m_axi_arlen,
    output wire [2:0]       m_axi_arsize,
    output wire [1:0]       m_axi_arburst,
    output wire             m_axi_arvalid,
    input  wire             m_axi_arready,
    input  wire [31:0]      m_axi_rdata,
    input  wire [1:0]       m_axi_rresp,
    input  wire             m_axi_rlast,
    input  wire             m_axi_rvalid,
    output wire             m_axi_rready,
    // logic analyzer probes (sampled on clk) and external trigger
    input  wire [ELA_W-1:0] ela_probe,
    input  wire             ela_trigger_in,
    // host-visible I/O bits
    input  wire [EIO_W-1:0] eio_in,
    output wire [EIO_W-1:0] eio_out
);

    wire       c1_tck, c1_tdi, c1_tdo, c1_capture, c1_shift, c1_update, c1_sel;
    wire       c2_tck, c2_tdi, c2_tdo, c2_capture, c2_shift, c2_update, c2_sel;
    wire [2:0] awprot_unused, arprot_unused;
    wire       ela_trigger_out, ela_armed;

    jtag_tap_polarfire #(.IR_USER1(8'h20), .IR_USER2(8'h21)) u_tap (
        .tck_pad_i(tck), .tms_pad_i(tms), .tdi_pad_i(tdi),
        .trstb_pad_i(trstb), .tdo_pad_o(tdo),
        .ch1_tck(c1_tck), .ch1_tdi(c1_tdi), .ch1_tdo(c1_tdo),
        .ch1_capture(c1_capture), .ch1_shift(c1_shift),
        .ch1_update(c1_update), .ch1_sel(c1_sel),
        .ch2_tck(c2_tck), .ch2_tdi(c2_tdi), .ch2_tdo(c2_tdo),
        .ch2_capture(c2_capture), .ch2_shift(c2_shift),
        .ch2_update(c2_update), .ch2_sel(c2_sel)
    );

    // ELA + EIO behind the fcapz core manager on USER1. UJTAG has no
    // Test-Logic-Reset output, so tlr is tied off (TLR_RESET_EN = 0).
    // hub_por clears the hub state that otherwise relies on register initial
    // values, which Libero drops on PolarFire.
    fcapz_debug_multi #(
        .NUM_ELAS(1), .EIO_EN(1), .NUM_EIOS(1),
        .SAMPLE_W(ELA_W), .DEPTH(1024), .INPUT_PIPE(1),
        .DECIM_EN(1), .EXT_TRIG_EN(1), .TIMESTAMP_W(32),
        .NUM_SEGMENTS(4), .STARTUP_ARM(1), .DEFAULT_TRIG_EXT(2),
        .TLR_RESET_EN(0),
        .EIO_IN_W(EIO_W), .EIO_OUT_W(EIO_W)
    ) u_multi (
        .tck(c1_tck), .tdi(c1_tdi), .tdo(c1_tdo), .tdo_next(),
        .capture(c1_capture), .shift(c1_shift),
        .update(c1_update), .sel(c1_sel),
        .tlr(1'b0),
        .hub_por(hub_por),
        .ela_sample_clk(clk),
        .ela_sample_rst(rst),
        .ela_probe_in(ela_probe),
        .ela_trigger_in(ela_trigger_in),
        .ela_trigger_out(ela_trigger_out),
        .ela_armed_out(ela_armed),
        .eio_probe_in(eio_in),
        .eio_probe_out(eio_out)
    );

    // EJTAG-AXI on USER2: the vendor-neutral core, with the behavioral
    // (vendor-neutral) async FIFOs, same sizing as the DE25-Nano build.
    fcapz_ejtagaxi #(
        .ADDR_W(32), .DATA_W(32),
        .FIFO_DEPTH(16), .CMD_FIFO_DEPTH(16), .RESP_FIFO_DEPTH(16),
        .TIMEOUT(4096), .DEBUG_EN(0),
        .USE_BEHAV_ASYNC_FIFO(1), .ASYNC_FIFO_IMPL(0)
    ) u_ejtagaxi (
        .tck(c2_tck), .tdi(c2_tdi), .tdo(c2_tdo),
        .capture(c2_capture), .shift_en(c2_shift),
        .update(c2_update), .sel(c2_sel),
        .axi_clk(clk), .axi_rst(rst),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_awprot(awprot_unused),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_arprot(arprot_unused),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready), .m_axi_rlast(m_axi_rlast),
        .debug_tck(), .debug_tck_edge(), .debug_axi(), .debug_axi_edge()
    );

endmodule
