/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * SpaceWire Reloaded - Microchip PolarFire SoC Discovery Kit (MPFS095T)
 * loopback hardware-validation top-level. FPGA fabric only; the MSS (RISC-V
 * processor subsystem) is not used.
 *
 * Same design as the DE25-Nano example: a single SpaceWire link (spw_axi_top)
 * is wired in internal loopback (its transmit outputs spw_do/spw_so feed its
 * own receive inputs spw_di/spw_si), driven by the shared spw_loopback_axi
 * engine, and the link/self-check status is shown on the board LEDs. The
 * SpaceWire core and engine are the same vendor-neutral RTL used on Artix-7
 * and Agilex 5; the only vendor-specific piece is the fpgacapZero ("fcapz")
 * JTAG debug wrapper mpfs_debug (rtl/microchip/, Libero only; behavioral stub
 * under tb/ for simulation). No PLL is used.
 *
 * Bring-up (CONTROL/TXDIVCNT writes, CORE_ID read-back, STATUS polling) and the
 * PRBS self-check are autonomous (CTRL[0] selftest_en resets to 1), so the
 * board self-tests with no host attached and lights its LEDs. With a host, the
 * same verification as on the Arty board runs over fcapz/JTAG (the on-board
 * FlashPro5, through the device's single UJTAG user TAP):
 *  - EJTAG-AXI bridge -> engine AXI4 slave: identity, CORE_ID, self-check
 *    counters, host data-mover loopback, TimeCodes, error injection;
 *  - ELA: SpaceWire D/S lines, status and received byte;
 *  - EIO: link/self-check status and switch state.
 */

`timescale 1ns/1ps

module spw_mpfs_disco_kit_top #(
    // Board oscillator frequency (Hz). Must match the SDC create_clock period
    // and the pin driven into `clk` (REF_CLK_50MHz on the Discovery Kit); this
    // drives the SpaceWire reset/disconnect/startup timing derivation.
    parameter integer SYS_CLOCK_HZ = 50000000,
    // RX/TX front-end implementation: 0 = generic (single clock domain).
    parameter integer RXIMPL   = 0,
    parameter integer TXIMPL   = 0,
    parameter integer RXCHUNK  = 1,
    // SpaceWire run-state TX divider: bit rate = clk/(LINK_TXDIVCNT+1).
    // 4 -> 10 Mbit/s at 50 MHz.
    parameter integer LINK_TXDIVCNT = 4,
    // Reset button active level: the Discovery Kit push-buttons (SWITCH1/2)
    // read 0 when pressed.
    parameter integer RST_ACTIVE_LOW = 1,
    // LED active level: the Discovery Kit LEDs light when the pin is driven high.
    parameter integer LED_ACTIVE_LOW = 0
) (
    input  wire       clk,       // REF_CLK_50MHz (see SYS_CLOCK_HZ)
    input  wire [1:0] btn,       // btn[0]=SWITCH1 reset, btn[1]=SWITCH2
    output wire [3:0] led,       // status LEDs (LED1..LED4)
    // Dedicated JTAG pins, used by the UJTAG user TAP in mpfs_debug. They must
    // be top-level ports; Libero binds them to the JTAG pins (no PDC entry).
    input  wire       TCK,
    input  wire       TMS,
    input  wire       TDI,
    input  wire       TRSTB,
    output wire       TDO
);

    // Generic build: rxclk = txclk = clk (single clock domain).
    wire clk_sys = clk;
    wire rxclk   = clk;
    wire txclk   = clk;

    // ---- Reset: fabric power-on reset + SWITCH1 ----
    // PolarFire fabric registers have no power-up value (Synplify ignores
    // initial values) and keep their contents across a JTAG reprogram, so a
    // register-only power-on reset can start already released. The device's
    // fabric power-on reset (FABRIC_POR_N, rtl/microchip/mpfs_por.v) clears
    // the synchronizer and the counter asynchronously, because no register
    // state can be trusted and clk may not be running yet; inverted, it also
    // resets the fcapz hub (hub_por). Release is synchronous: the counter
    // runs 16 clocks after the synchronized release and rst follows one clock
    // later (17 in all). SWITCH1 is synchronized
    // before joining the synchronous reset. rst comes straight from a
    // register (set by FABRIC_POR_N): it also feeds asynchronous resets
    // inside the fcapz cores, so it must not glitch.
    wire fabric_por_n;
    mpfs_por u_por (.fabric_por_n(fabric_por_n));

    wire btn0_raw = (RST_ACTIVE_LOW != 0) ? ~btn[0] : btn[0];
    reg  btn0_meta = 1'b0, btn0_sync = 1'b0;
    always @(posedge clk) begin
        btn0_meta <= btn0_raw;
        btn0_sync <= btn0_meta;
    end

    reg       por_meta, por_sync;
    reg [4:0] por_cnt;
    reg       rst;
    always @(posedge clk or negedge fabric_por_n) begin
        if (!fabric_por_n) begin
            por_meta <= 1'b0;
            por_sync <= 1'b0;
            por_cnt  <= 5'd0;
            rst      <= 1'b1;
        end else begin
            por_meta <= 1'b1;
            por_sync <= por_meta;
            if (por_sync && !por_cnt[4]) por_cnt <= por_cnt + 5'd1;
            rst      <= ~por_cnt[4] | btn0_sync;
        end
    end

    // ---- SpaceWire link signals (internal loopback) ----
    // Host-controlled error injection on the transmit side, before the
    // loopback, as on the Arty board:
    //   inj_freeze -> hold D/S static (the line stops -> disconnect/errdisc);
    //   inj_invert -> invert the outgoing D (corrupts the line -> parity error).
    wire spw_do, spw_so, spw_di, spw_si;
    wire inj_freeze, inj_invert;   // from the engine ERRINJ register
    wire spw_do_tx = inj_freeze ? 1'b0 : (spw_do ^ inj_invert);
    wire spw_so_tx = inj_freeze ? 1'b0 : spw_so;
    assign spw_di = spw_do_tx;
    assign spw_si = spw_so_tx;

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
    wire spw_irq;

    // ---- JTAG bridge (mpfs_debug) <-> engine AXI4 host slave ----
    wire [31:0] ax_awaddr, ax_wdata, ax_araddr, ax_rdata;
    wire [7:0]  ax_awlen, ax_arlen;
    wire [2:0]  ax_awsize, ax_arsize;
    wire [1:0]  ax_awburst, ax_arburst, ax_bresp, ax_rresp;
    wire [3:0]  ax_wstrb;
    wire        ax_awvalid, ax_awready, ax_wvalid, ax_wready, ax_wlast;
    wire        ax_bvalid, ax_bready;
    wire        ax_arvalid, ax_arready, ax_rvalid, ax_rready, ax_rlast;

    // ====================================================================
    // SpaceWire core (generic front ends, single 50 MHz domain).
    // ====================================================================
    spw_axi_top #(
        .SYS_CLOCK_HZ(SYS_CLOCK_HZ),
        .TX_CLOCK_HZ(SYS_CLOCK_HZ),   // single clock domain: txclk = clk
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
    // Loopback engine (AXI4 slave to the JTAG bridge, AXI-Lite master to the
    // core, AXIS owner, self-check + host data-mover).
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
    // JTAG debug (vendor wrapper; fcapz cores on the PolarFire UJTAG in
    // Libero, idle stub in simulation).
    //   ELA probe [7:0]  = D/S out, D/S in, bring-up, link, done, pass
    //   ELA probe [15:8] = received N-Char byte
    //   EIO in  = {2'b0, SWITCH2, SWITCH1 (1 = pressed), pass, done, bring-up, link}
    //   EIO out bit 4 -> ELA external trigger
    // ====================================================================
    wire [7:0] eio_in, eio_out;
    wire [1:0] key_pressed = (RST_ACTIVE_LOW != 0) ? ~btn : btn;
    assign eio_in = {2'b00, key_pressed,
                     selftest_pass, selftest_done, bringup_done, link_running};

    mpfs_debug #(.ELA_W(16), .EIO_W(8)) u_debug (
        .clk(clk), .rst(rst), .hub_por(~fabric_por_n),
        .tck(TCK), .tms(TMS), .tdi(TDI), .trstb(TRSTB), .tdo(TDO),
        .m_axi_awaddr(ax_awaddr), .m_axi_awlen(ax_awlen), .m_axi_awsize(ax_awsize),
        .m_axi_awburst(ax_awburst), .m_axi_awvalid(ax_awvalid), .m_axi_awready(ax_awready),
        .m_axi_wdata(ax_wdata), .m_axi_wstrb(ax_wstrb), .m_axi_wlast(ax_wlast),
        .m_axi_wvalid(ax_wvalid), .m_axi_wready(ax_wready),
        .m_axi_bresp(ax_bresp), .m_axi_bvalid(ax_bvalid), .m_axi_bready(ax_bready),
        .m_axi_araddr(ax_araddr), .m_axi_arlen(ax_arlen), .m_axi_arsize(ax_arsize),
        .m_axi_arburst(ax_arburst), .m_axi_arvalid(ax_arvalid), .m_axi_arready(ax_arready),
        .m_axi_rdata(ax_rdata), .m_axi_rresp(ax_rresp), .m_axi_rlast(ax_rlast),
        .m_axi_rvalid(ax_rvalid), .m_axi_rready(ax_rready),
        .ela_probe({rx_tdata, spw_do_tx, spw_so_tx, spw_di, spw_si,
                    bringup_done, link_running, selftest_done, selftest_pass}),
        .ela_trigger_in(eio_out[4]),
        .eio_in(eio_in),
        .eio_out(eio_out)
    );

    // ---- LEDs: standalone status (Discovery Kit LEDs are active-high) ----
    wire [3:0] led_status = {selftest_pass, selftest_done, link_running, bringup_done};
    assign led = (LED_ACTIVE_LOW != 0) ? ~led_status : led_status;

endmodule
