/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * SpaceWire Reloaded - Arty A7-100T loopback hardware-validation top-level.
 *
 * A single SpaceWire link (spw_axi_top) is wired in loopback: its transmit
 * outputs (spw_do/spw_so) feed its own receive inputs (spw_di/spw_si), either
 * internally inside the FPGA (LOOPBACK_INTERNAL=1, default) or externally
 * through a Pmod wire (LOOPBACK_INTERNAL=0: wire JA do->di, so->si).
 *
 * Verification is done with fpgacapZero ("fcapz") over JTAG:
 *  - EJTAG-AXI bridge (USER4) -> spw_loopback_axi engine register file. The
 *    host reads the example ID and the SpaceWire CORE_ID (proving the AXI-Lite
 *    path), drives a host loopback through TXDATA/RXDATA, and reads the fabric
 *    self-check result/counters.
 *  - debug_multi (USER1): two ELAs capture the SpaceWire D/S lines and the
 *    received N-Char byte; two EIOs expose link/self-check status.
 *  - LEDs show standalone status so the board self-tests with no host attached.
 *
 * The fcapz_*_xilinx7 wrappers and the SpaceWire RTL are added by the Vivado
 * build scripts in this directory.
 */

`timescale 1ns/1ps

module spw_arty_a7100t_top #(
    parameter integer LOOPBACK_INTERNAL = 1,
    // RX/TX front-end implementation: 0 = generic (single clock), 1 = fast.
    // The fast build uses an MMCM to run rxclk/txclk in their own domains so
    // the gray-coded rxclk->clk crossing and clk<->txclk crossings (and the
    // constraints/spw_cdc.xdc) are actually exercised on hardware.
    parameter integer RXIMPL   = 0,
    parameter integer TXIMPL   = 0,
    parameter integer RXCHUNK  = 1,
    parameter integer USE_MMCM = 0,  // 1 -> generate separate rxclk/txclk
    // SpaceWire run-state TX divider: bit rate = txclk/(LINK_TXDIVCNT+1).
    // 9 -> ~10 Mbit/s at 100 MHz; 0 -> 100 Mbit/s (fast build).
    parameter integer LINK_TXDIVCNT = 9
) (
    input  wire       clk,          // 100 MHz board oscillator (E3)
    input  wire [3:0] btn,          // btn[0] = reset
    output wire [3:0] led,
    // SpaceWire data/strobe on Pmod JA (used for external loopback)
    output wire       spw_do_pin,
    output wire       spw_so_pin,
    input  wire       spw_di_pin,
    input  wire       spw_si_pin
);

    // ---- Sample/transmit clocks ----
    // Generic build: rxclk = txclk = clk (single 100 MHz domain).
    // Fast build: MMCM derives rxclk (150 MHz) and txclk (100 MHz) in their own
    // domains, so the SpaceWire CDCs are real crossings on hardware.
    wire clk_sys = clk;
    wire rxclk, txclk, mmcm_locked;

    generate
    if (USE_MMCM != 0) begin : g_mmcm
        wire rxclk_raw, txclk_raw, clkfb, clkfb_buf;
        MMCME2_BASE #(
            .BANDWIDTH("OPTIMIZED"),
            .CLKFBOUT_MULT_F(9.0),
            .CLKIN1_PERIOD(10.000),
            .CLKOUT0_DIVIDE_F(6.0),   // 900/6  = 150 MHz rxclk
            .CLKOUT1_DIVIDE(9),       // 900/9  = 100 MHz txclk
            .DIVCLK_DIVIDE(1),
            .STARTUP_WAIT("FALSE")
        ) u_mmcm (
            .CLKIN1(clk), .CLKFBIN(clkfb_buf), .CLKFBOUT(clkfb),
            .CLKOUT0(rxclk_raw), .CLKOUT1(txclk_raw),
            .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
            .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
            .CLKFBOUTB(), .LOCKED(mmcm_locked), .PWRDWN(1'b0), .RST(1'b0)
        );
        BUFG u_fb (.I(clkfb), .O(clkfb_buf));
        BUFG u_rx (.I(rxclk_raw), .O(rxclk));
        BUFG u_tx (.I(txclk_raw), .O(txclk));
    end else begin : g_noclk
        assign rxclk = clk;
        assign txclk = clk;
        assign mmcm_locked = 1'b1;
    end
    endgenerate

    // ---- Reset: power-on pulse + synchronized btn[0], held until MMCM lock ----
    reg [3:0] por_sr = 4'hF;
    always @(posedge clk) por_sr <= {por_sr[2:0], 1'b0};

    (* ASYNC_REG = "TRUE" *) reg btn0_meta;
    (* ASYNC_REG = "TRUE" *) reg btn0_sync;
    always @(posedge clk) begin
        btn0_meta <= btn[0];
        btn0_sync <= btn0_meta;
    end
    wire rst = por_sr[3] | btn0_sync | ~mmcm_locked;

    // ---- SpaceWire link signals ----
    wire spw_do, spw_so, spw_di, spw_si;

    // Loopback select: internal ties do->di / so->si inside the FPGA.
    // Internal loopback with optional host-controlled error injection:
    //   inj_freeze -> hold D/S static (disconnect); inj_invert -> corrupt D.
    assign spw_di     = (LOOPBACK_INTERNAL != 0)
                          ? (inj_freeze ? 1'b0 : (spw_do ^ inj_invert))
                          : spw_di_pin;
    assign spw_si     = (LOOPBACK_INTERNAL != 0)
                          ? (inj_freeze ? 1'b0 : spw_so)
                          : spw_si_pin;
    assign spw_do_pin = spw_do;   // always driven so external wiring/scope works
    assign spw_so_pin = spw_so;

    // ---- AXI4 bridge <-> engine ----
    wire [31:0] ax_awaddr, ax_wdata, ax_araddr, ax_rdata;
    wire [7:0]  ax_awlen, ax_arlen;
    wire [2:0]  ax_awsize, ax_arsize, ax_awprot, ax_arprot;
    wire [1:0]  ax_awburst, ax_arburst, ax_bresp, ax_rresp;
    wire [3:0]  ax_wstrb;
    wire        ax_awvalid, ax_awready, ax_wvalid, ax_wready, ax_wlast;
    wire        ax_bvalid, ax_bready;
    wire        ax_arvalid, ax_arready, ax_rvalid, ax_rready, ax_rlast;

    // ---- engine <-> spw_axi_top AXI-Lite ----
    wire [7:0]  cs_awaddr, cs_araddr;
    wire [31:0] cs_wdata, cs_rdata;
    wire [3:0]  cs_wstrb;
    wire [1:0]  cs_bresp, cs_rresp;
    wire        cs_awvalid, cs_awready, cs_wvalid, cs_wready;
    wire        cs_bvalid, cs_bready, cs_arvalid, cs_arready, cs_rvalid, cs_rready;

    // ---- engine <-> spw_axi_top AXI-Stream ----
    wire [7:0]  tx_tdata, rx_tdata;
    wire        tx_tvalid, tx_tready, tx_tlast;
    wire [0:0]  tx_tuser;
    wire        rx_tvalid, rx_tready, rx_tlast;
    wire [0:0]  rx_tuser;

    wire link_running, selftest_pass, selftest_done, bringup_done;
    wire inj_freeze, inj_invert;
    wire spw_irq;

    // ====================================================================
    // SpaceWire core. Generic build: single 100 MHz domain. Fast build:
    // rxclk/txclk in their own MMCM domains (real CDCs).
    // Default RESET_TIME/DISCONNECT_TIME/DEFAULT_DIVCNT already target 100 MHz.
    // ====================================================================
    spw_axi_top #(
        .RXIMPL(RXIMPL),
        .TXIMPL(TXIMPL),
        .RXCHUNK(RXCHUNK),
        .RXFIFOSIZE_BITS(11),
        .TXFIFOSIZE_BITS(11),
        .AXI_ADDR_WIDTH(8),
        .CORE_ID(32'h53505752),  // "SPWR"
        .VERSION(32'h00010000)
    ) u_spw (
        .clk(clk_sys), .rxclk(rxclk), .txclk(txclk), .rst(rst),
        .s_axi_awaddr(cs_awaddr), .s_axi_awvalid(cs_awvalid), .s_axi_awready(cs_awready),
        .s_axi_wdata(cs_wdata), .s_axi_wstrb(cs_wstrb), .s_axi_wvalid(cs_wvalid), .s_axi_wready(cs_wready),
        .s_axi_bresp(cs_bresp), .s_axi_bvalid(cs_bvalid), .s_axi_bready(cs_bready),
        .s_axi_araddr(cs_araddr), .s_axi_arvalid(cs_arvalid), .s_axi_arready(cs_arready),
        .s_axi_rdata(cs_rdata), .s_axi_rresp(cs_rresp), .s_axi_rvalid(cs_rvalid), .s_axi_rready(cs_rready),
        .s_axis_tdata(tx_tdata), .s_axis_tvalid(tx_tvalid), .s_axis_tready(tx_tready),
        .s_axis_tlast(tx_tlast), .s_axis_tuser(tx_tuser),
        .m_axis_tdata(rx_tdata), .m_axis_tvalid(rx_tvalid), .m_axis_tready(rx_tready),
        .m_axis_tlast(rx_tlast), .m_axis_tuser(rx_tuser),
        .irq(spw_irq),
        .spw_di(spw_di), .spw_si(spw_si), .spw_do(spw_do), .spw_so(spw_so)
    );

    // ====================================================================
    // Loopback engine (AXI4 slave to bridge, AXI-Lite master to core, AXIS
    // owner, self-check + host data-mover).
    // ====================================================================
    spw_loopback_axi #(
        .EXAMPLE_ID(32'h5350574C),   // "SPWL"
        .EXAMPLE_VER(32'h00010056),  // low byte 'V' = Verilog build fingerprint
        .LINK_TXDIVCNT(LINK_TXDIVCNT[7:0]),
        .SELFTEST_LEN(8'd16)
    ) u_engine (
        .clk(clk), .rst(rst),
        .s_axi_awaddr(ax_awaddr), .s_axi_awlen(ax_awlen), .s_axi_awsize(ax_awsize),
        .s_axi_awburst(ax_awburst), .s_axi_awvalid(ax_awvalid), .s_axi_awready(ax_awready),
        .s_axi_wdata(ax_wdata), .s_axi_wstrb(ax_wstrb), .s_axi_wlast(ax_wlast),
        .s_axi_wvalid(ax_wvalid), .s_axi_wready(ax_wready),
        .s_axi_bresp(ax_bresp), .s_axi_bvalid(ax_bvalid), .s_axi_bready(ax_bready),
        .s_axi_araddr(ax_araddr), .s_axi_arlen(ax_arlen), .s_axi_arsize(ax_arsize),
        .s_axi_arburst(ax_arburst), .s_axi_arvalid(ax_arvalid), .s_axi_arready(ax_arready),
        .s_axi_rdata(ax_rdata), .s_axi_rresp(ax_rresp), .s_axi_rlast(ax_rlast),
        .s_axi_rvalid(ax_rvalid), .s_axi_rready(ax_rready),
        .m_axil_awaddr(cs_awaddr), .m_axil_awvalid(cs_awvalid), .m_axil_awready(cs_awready),
        .m_axil_wdata(cs_wdata), .m_axil_wstrb(cs_wstrb), .m_axil_wvalid(cs_wvalid), .m_axil_wready(cs_wready),
        .m_axil_bresp(cs_bresp), .m_axil_bvalid(cs_bvalid), .m_axil_bready(cs_bready),
        .m_axil_araddr(cs_araddr), .m_axil_arvalid(cs_arvalid), .m_axil_arready(cs_arready),
        .m_axil_rdata(cs_rdata), .m_axil_rresp(cs_rresp), .m_axil_rvalid(cs_rvalid), .m_axil_rready(cs_rready),
        .m_axis_tdata(tx_tdata), .m_axis_tvalid(tx_tvalid), .m_axis_tready(tx_tready),
        .m_axis_tlast(tx_tlast), .m_axis_tuser(tx_tuser),
        .s_axis_tdata(rx_tdata), .s_axis_tvalid(rx_tvalid), .s_axis_tready(rx_tready),
        .s_axis_tlast(rx_tlast), .s_axis_tuser(rx_tuser),
        .link_running(link_running), .selftest_pass(selftest_pass),
        .selftest_done(selftest_done), .bringup_done(bringup_done),
        .inj_freeze(inj_freeze), .inj_invert(inj_invert)
    );

    // ====================================================================
    // fpgacapZero EJTAG-AXI bridge (USER4): JTAG -> AXI4 master.
    // ====================================================================
    fcapz_ejtagaxi_xilinx7 #(
        .ADDR_W(32), .DATA_W(32),
        .FIFO_DEPTH(16), .CMD_FIFO_DEPTH(16), .RESP_FIFO_DEPTH(16),
        .CMD_FIFO_MEMORY_TYPE("distributed"), .TIMEOUT(4096), .DEBUG_EN(0)
    ) u_ejtagaxi (
        .axi_clk(clk), .axi_rst(rst),
        .m_axi_awaddr(ax_awaddr), .m_axi_awlen(ax_awlen),
        .m_axi_awsize(ax_awsize), .m_axi_awburst(ax_awburst),
        .m_axi_awvalid(ax_awvalid), .m_axi_awready(ax_awready),
        .m_axi_awprot(ax_awprot),
        .m_axi_wdata(ax_wdata), .m_axi_wstrb(ax_wstrb),
        .m_axi_wvalid(ax_wvalid), .m_axi_wready(ax_wready),
        .m_axi_wlast(ax_wlast),
        .m_axi_bresp(ax_bresp), .m_axi_bvalid(ax_bvalid), .m_axi_bready(ax_bready),
        .m_axi_araddr(ax_araddr), .m_axi_arlen(ax_arlen),
        .m_axi_arsize(ax_arsize), .m_axi_arburst(ax_arburst),
        .m_axi_arvalid(ax_arvalid), .m_axi_arready(ax_arready),
        .m_axi_arprot(ax_arprot),
        .m_axi_rdata(ax_rdata), .m_axi_rresp(ax_rresp),
        .m_axi_rvalid(ax_rvalid), .m_axi_rready(ax_rready), .m_axi_rlast(ax_rlast)
    );

    // ====================================================================
    // fpgacapZero debug manager (USER1): 2 ELAs + 2 EIOs.
    //   ELA0: SpaceWire D/S lines + status
    //   ELA1: received N-Char byte
    //   EIO0: status probe-in, host scratch probe-out (bit4 -> ELA trigger)
    //   EIO1: button visibility
    // ====================================================================
    wire [1:0] ela_trig_in;
    wire [1:0] ela_trig_out;
    wire [1:0] ela_armed;
    wire [7:0] eio0_pin, eio0_pout, eio1_pin, eio1_pout;

    wire [7:0] ela0_probe = {spw_do, spw_so, spw_di, spw_si,
                             bringup_done, link_running, selftest_done, selftest_pass};
    wire [7:0] ela1_probe = rx_tdata;

    assign eio0_pin = {1'b0, link_running, selftest_done, selftest_pass,
                       2'b0, bringup_done, |{selftest_done, selftest_pass}};
    assign eio1_pin = {btn, eio0_pout[3:0]};
    assign ela_trig_in = {1'b0, eio0_pout[4]};

    fcapz_debug_multi_xilinx7 #(
        .NUM_ELAS(2), .EIO_EN(1), .NUM_EIOS(2),
        .SAMPLE_W(8), .DEPTH(1024), .INPUT_PIPE(1),
        .DECIM_EN(1), .EXT_TRIG_EN(1), .TIMESTAMP_W(32),
        .NUM_SEGMENTS(4), .STARTUP_ARM(1), .DEFAULT_TRIG_EXT(2),
        .EIO_IN_W(8), .EIO_OUT_W(8)
    ) u_debug (
        .ela_sample_clk ({clk, clk}),
        .ela_sample_rst ({rst, rst}),
        .ela_probe_in   ({ela1_probe, ela0_probe}),
        .ela_trigger_in (ela_trig_in),
        .ela_trigger_out(ela_trig_out),
        .ela_armed_out  (ela_armed),
        .eio_probe_in   ({eio1_pin, eio0_pin}),
        .eio_probe_out  ({eio1_pout, eio0_pout})
    );

    // ---- LEDs: standalone status ----
    assign led[0] = bringup_done;
    assign led[1] = link_running;
    assign led[2] = selftest_done;
    assign led[3] = selftest_pass;

endmodule
