/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * SpaceWire loopback example engine for the Arty A7-100T fpgacapZero design.
 *
 * One module that:
 *  - presents an AXI4 (no-ID, single + INCR burst) slave to the fpgacapZero
 *    EJTAG-AXI bridge, exposing a small example register file (host interface);
 *  - is the sole AXI4-Lite master of spw_axi_top, performing link bring-up
 *    (CONTROL/TXDIVCNT writes), reading back the SpaceWire CORE_ID, and polling
 *    STATUS so link state is visible to the host, LEDs and EIO;
 *  - owns the SpaceWire N-Char AXI-Stream TX/RX ports and drives them either
 *    from a fabric self-check pattern generator/checker (selftest mode, the
 *    reset default so the board self-tests with no host) or from host
 *    register accesses (data-mover mode).
 *
 * The host register map (AXI4 slave, byte offsets, 32-bit little-endian):
 *   0x00 EXAMPLE_ID  RO  ASCII "SPWL"
 *   0x04 EXAMPLE_VER RO  example design version
 *   0x08 SCRATCH     RW  free R/W word for a host sanity check
 *   0x0C CTRL        RW  [0] selftest_en (reset 1)
 *                        [1] selftest_start (write-1 pulse, restart self-check)
 *                        [2] soft_reset    (write-1 pulse, restart bring-up)
 *                        [3] selftest_loop (continuous free-running self-check)
 *   0x10 STATUS      RO  [0] link_running   [1] selftest_busy
 *                        [2] selftest_done  [3] selftest_pass
 *                        [4] tx_ready       [5] rx_valid
 *                        [6] bringup_done   [11:8] spw error flags
 *   0x14 SPW_COREID  RO  CORE_ID read back from spw_axi_top over AXI-Lite
 *   0x18 SPW_STATUS  RO  last raw spw_axi_top STATUS word polled
 *   0x1C TXDATA      WO  data-mover push: [7:0]=data [8]=tlast [9]=tuser(EEP)
 *   0x20 RXDATA      RO  data-mover pop:  [7:0]=data [8]=tlast [9]=tuser
 *                        [31]=valid (1 if a beat was returned, else FIFO empty)
 *   0x24 TXCOUNT     RO  N-Chars transmitted (self-check or data-mover)
 *   0x28 RXCOUNT     RO  N-Chars received
 *   0x2C ERRCOUNT    RO  self-check PRBS/framing mismatches
 *   0x30 PKTCOUNT    RO  self-check packets received (EOP count)
 *   0x34 ERRINJ      RW  transmit-side error injection (the top applies these to
 *                        the outgoing D/S before the pins, so it works on both
 *                        internal and external loopback):
 *                        [0] freeze (hold D/S static -> disconnect/errdisc)
 *                        [1] invert (invert outgoing D -> parity/char error)
 *   0x38 TIMECODE    RW  SpaceWire TimeCode loopback:
 *                        write [7:0]=time-code (ctrl[7:6]+time[5:0]) -> the engine
 *                          clears the received-timecode valid then sends this
 *                          time-code over the link;
 *                        read  [5:0]=last received time [7:6]=ctrl [31]=valid
 *                          (mirrors spw_axi_top TIMECODE_RX, refreshed every poll)
 *
 * spw error bits are visible in STATUS[11:8] and SPW_STATUS[11:8] (sticky). A
 * CTRL[2] soft_reset re-runs bring-up, which first W1C-clears the sticky errors
 * and restarts the link, so after removing an injected error the link recovers.
 *
 * The fabric self-check sends SELFTEST_PKTS back-to-back packets, each
 * SELFTEST_LEN PRBS bytes (shared 8-bit LFSR, seed 0xFF) followed by EOP, with
 * the PRBS sequence continuing across packets so any dropped or duplicated char
 * desyncs the RX checker and is counted in ERRCOUNT. With CTRL[3] (selftest_loop)
 * set the run never ends: packets stream back-to-back at link rate indefinitely
 * and TXCOUNT/RXCOUNT/ERRCOUNT/PKTCOUNT accumulate, for multi-minute soak tests.
 */

`timescale 1ns/1ps

module spw_loopback_axi #(
    parameter [31:0] EXAMPLE_ID  = 32'h5350574C, // "SPWL"
    parameter [31:0] EXAMPLE_VER = 32'h00010000,
    parameter [7:0]  LINK_TXDIVCNT = 8'd9,       // ~ sysfreq/(divcnt+1) run rate
    parameter [7:0]  SELFTEST_LEN  = 8'd16,      // PRBS data bytes per packet
    parameter [7:0]  SELFTEST_PKTS = 8'd4        // back-to-back packets per run
) (
    input  wire        clk,
    input  wire        rst,

    // ---- AXI4 slave (from fpgacapZero EJTAG-AXI bridge) ----
    input  wire [31:0] s_axi_awaddr,
    input  wire [7:0]  s_axi_awlen,
    input  wire [2:0]  s_axi_awsize,
    input  wire [1:0]  s_axi_awburst,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wlast,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,
    input  wire [7:0]  s_axi_arlen,
    input  wire [2:0]  s_axi_arsize,
    input  wire [1:0]  s_axi_arburst,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rlast,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    // ---- AXI4-Lite master (to spw_axi_top CSRs) ----
    output reg  [7:0]  m_axil_awaddr,
    output reg         m_axil_awvalid,
    input  wire        m_axil_awready,
    output reg  [31:0] m_axil_wdata,
    output wire [3:0]  m_axil_wstrb,
    output reg         m_axil_wvalid,
    input  wire        m_axil_wready,
    input  wire [1:0]  m_axil_bresp,
    input  wire        m_axil_bvalid,
    output reg         m_axil_bready,
    output reg  [7:0]  m_axil_araddr,
    output reg         m_axil_arvalid,
    input  wire        m_axil_arready,
    input  wire [31:0] m_axil_rdata,
    input  wire [1:0]  m_axil_rresp,
    input  wire        m_axil_rvalid,
    output reg         m_axil_rready,

    // ---- AXI-Stream master: SpaceWire N-Char TX (to spw_axi_top s_axis) ----
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast,
    output reg  [0:0]  m_axis_tuser,

    // ---- AXI-Stream slave: SpaceWire N-Char RX (from spw_axi_top m_axis) ----
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output reg         s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire [0:0]  s_axis_tuser,

    // ---- Status sideband (EIO / LED / ELA) ----
    output wire        link_running,
    output wire        selftest_pass,
    output wire        selftest_done,
    output wire        bringup_done,

    // ---- Internal-loopback error injection (to the top's loopback mux) ----
    output wire        inj_freeze,   // hold outgoing D/S static -> disconnect
    output wire        inj_invert    // invert outgoing D -> parity/char error
);

    // spw_axi_lite_regs register byte offsets (see rtl/.../spw_axi_lite_regs).
    localparam [7:0] SPW_REG_CORE_ID     = 8'h00;
    localparam [7:0] SPW_REG_CONTROL     = 8'h08;
    localparam [7:0] SPW_REG_STATUS      = 8'h0C;
    localparam [7:0] SPW_REG_TXDIVCNT    = 8'h10;
    localparam [7:0] SPW_REG_TIMECODE_TX = 8'h14;  // [31] tick, [7:0] time-code
    localparam [7:0] SPW_REG_TIMECODE_RX = 8'h18;  // [31] valid, [7:0] time-code
    localparam [7:0] SPW_REG_ERROR       = 8'h1C;  // W1C sticky link-error bits

    // ---- Example register file ----
    reg [31:0] scratch_r;
    reg        selftest_en_r;
    reg        selftest_loop_r;   // continuous (free-running) self-check
    reg [31:0] spw_coreid_r;
    reg [31:0] spw_status_r;
    reg [31:0] txcount_r;
    reg [31:0] rxcount_r;
    reg [31:0] errcount_r;
    reg        selftest_busy_r;
    reg        selftest_done_r;
    reg        selftest_pass_r;
    reg        bringup_done_r;
    reg [1:0]  errinj_r;          // [0]=freeze (disconnect), [1]=invert D (parity)
    reg [31:0] spw_tc_rx_r;       // mirror of spw_axi_top TIMECODE_RX
    reg [7:0]  tc_send_value;     // time-code byte to send (ctrl[7:6]+time[5:0])
    reg        tc_send_push;      // 1-cycle pulse from W FSM: host requested a send
    reg        tc_send_pending;   // owned by master FSM: a send is queued

    reg        selftest_start_pulse;
    reg        soft_reset_pulse;

    assign m_axil_wstrb   = 4'hF;
    assign link_running   = spw_status_r[2];
    assign selftest_pass  = selftest_pass_r;
    assign selftest_done  = selftest_done_r;
    assign bringup_done   = bringup_done_r;
    assign inj_freeze     = errinj_r[0];
    assign inj_invert     = errinj_r[1];

    // ====================================================================
    // RX capture FIFO (data-mover mode): small synchronous FIFO so a slow
    // JTAG host can pop received N-Chars without stalling the SpaceWire core.
    // Stores {tuser, tlast, tdata} = 10 bits.
    // ====================================================================
    localparam RXFIFO_AW = 6;
    reg  [9:0] rxfifo_mem [0:(1<<RXFIFO_AW)-1];
    reg  [RXFIFO_AW:0] rxfifo_wptr;
    reg  [RXFIFO_AW:0] rxfifo_rptr;
    wire rxfifo_empty = (rxfifo_wptr == rxfifo_rptr);
    wire rxfifo_full  = (rxfifo_wptr[RXFIFO_AW-1:0] == rxfifo_rptr[RXFIFO_AW-1:0]) &&
                        (rxfifo_wptr[RXFIFO_AW] != rxfifo_rptr[RXFIFO_AW]);
    reg  rxfifo_push;
    reg  rxfifo_pop;
    reg  [9:0] rxfifo_wdata;   // beat captured at the RX handshake cycle
    wire [9:0] rxfifo_dout = rxfifo_mem[rxfifo_rptr[RXFIFO_AW-1:0]];

    // ---- Data-mover TX one-beat holding register ----
    // dm_tx_push: one-cycle pulse from the AXI write FSM signalling a new beat
    // in dm_tx_beat. dm_tx_pending is owned solely by the TX-path block so every
    // register has exactly one driver.
    reg [9:0] dm_tx_beat;       // {tuser,tlast,tdata}
    reg       dm_tx_pending;
    reg       dm_tx_push;

    // ====================================================================
    // AXI-Lite master bring-up + status poll FSM.
    // Sequence: clear sticky errors (W1C REG_ERROR), write CONTROL
    // (autostart|linkstart), write TXDIVCNT, read CORE_ID, then loop reading
    // STATUS forever. soft_reset re-runs from the error clear, so the link
    // recovers and the sticky error bits are cleared.
    // ====================================================================
    localparam [4:0]
        M_RST       = 5'd0,
        M_CRST_AW   = 5'd1,     // pulse spw core reset (flush RX FIFO/bridges)
        M_CRST_B    = 5'd2,
        M_CTRL_AW   = 5'd3,
        M_CTRL_B    = 5'd4,
        M_DIV_AW    = 5'd5,
        M_DIV_B     = 5'd6,
        M_ID_AR     = 5'd7,
        M_ID_R      = 5'd8,
        M_STAT_AR   = 5'd9,
        M_STAT_R    = 5'd10,
        M_CLR_AW    = 5'd11,
        M_CLR_B     = 5'd12,
        M_TC_CLR_AW = 5'd13,    // W1C the spw received-timecode valid bit
        M_TC_CLR_B  = 5'd14,
        M_TC_TX_AW  = 5'd15,    // write spw TIMECODE_TX (send the time-code)
        M_TC_TX_B   = 5'd16,
        M_TCRX_R    = 5'd17;    // read spw TIMECODE_RX, mirror into spw_tc_rx_r
    reg [4:0] mstate;
    reg       errclr_pending;   // clear sticky spw errors once after link is up

    always @(posedge clk) begin
        if (rst) begin
            mstate         <= M_RST;
            m_axil_awaddr  <= 8'd0;
            m_axil_awvalid <= 1'b0;
            m_axil_wdata   <= 32'd0;
            m_axil_wvalid  <= 1'b0;
            m_axil_bready  <= 1'b0;
            m_axil_araddr  <= 8'd0;
            m_axil_arvalid <= 1'b0;
            m_axil_rready  <= 1'b0;
            spw_coreid_r   <= 32'd0;
            spw_status_r   <= 32'd0;
            bringup_done_r <= 1'b0;
            errclr_pending <= 1'b0;
            spw_tc_rx_r    <= 32'd0;
            tc_send_pending<= 1'b0;
        end else begin
            case (mstate)
                M_RST: begin
                    errclr_pending <= 1'b1;  // clear sticky errors once link is up
                    // assert spw core reset first: flushes the core RX FIFO and
                    // AXIS bridges so a recovery after a mid-stream error starts
                    // from a clean datapath (no stale buffered N-Chars).
                    m_axil_awaddr  <= SPW_REG_CONTROL;
                    m_axil_wdata   <= 32'h0000_0001; // core_rst=1
                    m_axil_awvalid <= 1'b1;
                    m_axil_wvalid  <= 1'b1;
                    mstate         <= M_CRST_AW;
                end
                M_CRST_AW: begin
                    if (m_axil_awready) m_axil_awvalid <= 1'b0;
                    if (m_axil_wready)  m_axil_wvalid  <= 1'b0;
                    if (!m_axil_awvalid && !m_axil_wvalid) begin
                        m_axil_bready <= 1'b1;
                        mstate        <= M_CRST_B;
                    end
                end
                M_CRST_B: begin
                    if (m_axil_bvalid) begin
                        m_axil_bready  <= 1'b0;
                        m_axil_awaddr  <= SPW_REG_CONTROL;
                        m_axil_wdata   <= 32'h0000_0006; // core_rst=0, autostart|linkstart
                        m_axil_awvalid <= 1'b1;
                        m_axil_wvalid  <= 1'b1;
                        mstate         <= M_CTRL_AW;
                    end
                end
                M_CLR_AW: begin
                    if (m_axil_awready) m_axil_awvalid <= 1'b0;
                    if (m_axil_wready)  m_axil_wvalid  <= 1'b0;
                    if (!m_axil_awvalid && !m_axil_wvalid) begin
                        m_axil_bready <= 1'b1;
                        mstate        <= M_CLR_B;
                    end
                end
                M_CLR_B: begin
                    if (m_axil_bvalid) begin
                        m_axil_bready <= 1'b0;
                        mstate        <= M_STAT_AR;  // resume polling
                    end
                end
                M_CTRL_AW: begin
                    if (m_axil_awready) m_axil_awvalid <= 1'b0;
                    if (m_axil_wready)  m_axil_wvalid  <= 1'b0;
                    if (!m_axil_awvalid && !m_axil_wvalid) begin
                        m_axil_bready <= 1'b1;
                        mstate        <= M_CTRL_B;
                    end
                end
                M_CTRL_B: begin
                    if (m_axil_bvalid) begin
                        m_axil_bready  <= 1'b0;
                        m_axil_awaddr  <= SPW_REG_TXDIVCNT;
                        m_axil_wdata   <= {24'd0, LINK_TXDIVCNT};
                        m_axil_awvalid <= 1'b1;
                        m_axil_wvalid  <= 1'b1;
                        mstate         <= M_DIV_AW;
                    end
                end
                M_DIV_AW: begin
                    if (m_axil_awready) m_axil_awvalid <= 1'b0;
                    if (m_axil_wready)  m_axil_wvalid  <= 1'b0;
                    if (!m_axil_awvalid && !m_axil_wvalid) begin
                        m_axil_bready <= 1'b1;
                        mstate        <= M_DIV_B;
                    end
                end
                M_DIV_B: begin
                    if (m_axil_bvalid) begin
                        m_axil_bready  <= 1'b0;
                        m_axil_araddr  <= SPW_REG_CORE_ID;
                        m_axil_arvalid <= 1'b1;
                        m_axil_rready  <= 1'b1;
                        mstate         <= M_ID_AR;
                    end
                end
                M_ID_AR: begin
                    if (m_axil_arready) m_axil_arvalid <= 1'b0;
                    mstate <= M_ID_R;
                end
                M_ID_R: begin
                    if (m_axil_rvalid) begin
                        spw_coreid_r  <= m_axil_rdata;
                        m_axil_rready <= 1'b0;
                        mstate        <= M_STAT_AR;
                    end
                end
                M_STAT_AR: begin
                    m_axil_araddr  <= SPW_REG_STATUS;
                    m_axil_arvalid <= 1'b1;
                    m_axil_rready  <= 1'b1;
                    mstate <= M_STAT_R;
                end
                M_STAT_R: begin
                    if (m_axil_arready) m_axil_arvalid <= 1'b0;
                    if (m_axil_rvalid) begin
                        spw_status_r   <= m_axil_rdata;
                        m_axil_rready  <= 1'b0;
                        bringup_done_r <= 1'b1;
                        if (m_axil_rdata[2] && errclr_pending) begin
                            // link up after (re)bring-up: W1C-clear sticky errors once
                            errclr_pending <= 1'b0;
                            m_axil_awaddr  <= SPW_REG_ERROR;
                            m_axil_wdata   <= 32'h0000_000F;
                            m_axil_awvalid <= 1'b1;
                            m_axil_wvalid  <= 1'b1;
                            mstate         <= M_CLR_AW;
                        end else if (tc_send_pending) begin
                            // host requested a time-code send: first W1C the
                            // received-timecode valid so a stale one can't pass.
                            tc_send_pending <= 1'b0;
                            m_axil_awaddr   <= SPW_REG_TIMECODE_RX;
                            m_axil_wdata    <= 32'h8000_0000;
                            m_axil_awvalid  <= 1'b1;
                            m_axil_wvalid   <= 1'b1;
                            mstate          <= M_TC_CLR_AW;
                        end else begin
                            // mirror the received time-code every poll cycle
                            m_axil_araddr  <= SPW_REG_TIMECODE_RX;
                            m_axil_arvalid <= 1'b1;
                            m_axil_rready  <= 1'b1;
                            mstate         <= M_TCRX_R;
                        end
                    end
                end
                M_TC_CLR_AW: begin
                    if (m_axil_awready) m_axil_awvalid <= 1'b0;
                    if (m_axil_wready)  m_axil_wvalid  <= 1'b0;
                    if (!m_axil_awvalid && !m_axil_wvalid) begin
                        m_axil_bready <= 1'b1;
                        mstate        <= M_TC_CLR_B;
                    end
                end
                M_TC_CLR_B: begin
                    if (m_axil_bvalid) begin
                        m_axil_bready  <= 1'b0;
                        // now send the requested time-code (tick + ctrl/time)
                        m_axil_awaddr  <= SPW_REG_TIMECODE_TX;
                        m_axil_wdata   <= {1'b1, 23'd0, tc_send_value};
                        m_axil_awvalid <= 1'b1;
                        m_axil_wvalid  <= 1'b1;
                        mstate         <= M_TC_TX_AW;
                    end
                end
                M_TC_TX_AW: begin
                    if (m_axil_awready) m_axil_awvalid <= 1'b0;
                    if (m_axil_wready)  m_axil_wvalid  <= 1'b0;
                    if (!m_axil_awvalid && !m_axil_wvalid) begin
                        m_axil_bready <= 1'b1;
                        mstate        <= M_TC_TX_B;
                    end
                end
                M_TC_TX_B: begin
                    if (m_axil_bvalid) begin
                        m_axil_bready <= 1'b0;
                        mstate        <= M_STAT_AR;
                    end
                end
                M_TCRX_R: begin
                    if (m_axil_arready) m_axil_arvalid <= 1'b0;
                    if (m_axil_rvalid) begin
                        spw_tc_rx_r   <= m_axil_rdata;
                        m_axil_rready <= 1'b0;
                        mstate        <= M_STAT_AR;
                    end
                end
                default: mstate <= M_RST;
            endcase
            // Latch a host time-code send request (pulse from the W FSM). After
            // the case so a request arriving as one is consumed isn't lost.
            if (tc_send_push) tc_send_pending <= 1'b1;
            // soft_reset must override the case's mstate assignment, so place
            // it after the case (last non-blocking write wins).
            if (soft_reset_pulse) begin
                mstate         <= M_RST;
                bringup_done_r <= 1'b0;
            end
        end
    end

    // ====================================================================
    // AXIS ownership: self-check FSM vs host data-mover, selected by
    // selftest_en_r. The two never drive the AXIS concurrently.
    // ====================================================================
    localparam [2:0]
        T_IDLE = 3'd0,
        T_WAIT = 3'd1,
        T_DATA = 3'd2,
        T_EOP  = 3'd3,
        T_DONE = 3'd4;
    reg [2:0]  tstate;
    reg [7:0]  tx_idx;        // PRBS byte index within the current TX packet
    reg [7:0]  exp_idx;       // PRBS byte index within the current RX packet
    reg        check_active;
    reg [7:0]  tx_lfsr;       // PRBS generator (TX) - same sequence as rx_lfsr
    reg [7:0]  rx_lfsr;       // PRBS checker (RX)
    reg [31:0] tx_pkt;        // packets transmitted this run (free-running in loop mode)
    reg [31:0] rx_pkt;        // packets received this run (EOP count)
    localparam [7:0] PRBS_SEED = 8'hFF;
    localparam [7:0] PRBS_POLY = 8'hB8; // maximal 8-bit Galois LFSR (period 255)

    function [7:0] prbs_next;
        input [7:0] s;
        begin
            prbs_next = s[0] ? ((s >> 1) ^ PRBS_POLY) : (s >> 1);
        end
    endfunction

    // Combolike defaults driven in the clocked block below.
    always @(posedge clk) begin
        if (rst) begin
            tstate          <= T_IDLE;
            tx_idx          <= 8'd0;
            exp_idx         <= 8'd0;
            check_active    <= 1'b0;
            tx_lfsr         <= PRBS_SEED;
            rx_lfsr         <= PRBS_SEED;
            tx_pkt          <= 32'd0;
            rx_pkt          <= 32'd0;
            selftest_busy_r <= 1'b0;
            selftest_done_r <= 1'b0;
            selftest_pass_r <= 1'b0;
            txcount_r       <= 32'd0;
            rxcount_r       <= 32'd0;
            errcount_r      <= 32'd0;
            m_axis_tdata    <= 8'd0;
            m_axis_tvalid   <= 1'b0;
            m_axis_tlast    <= 1'b0;
            m_axis_tuser    <= 1'b0;
            s_axis_tready   <= 1'b0;
            rxfifo_push     <= 1'b0;
            dm_tx_pending   <= 1'b0;
        end else begin
            rxfifo_push <= 1'b0;

            // ----- TX path -----
            if (selftest_en_r) begin
                dm_tx_pending <= 1'b0;
                // ---- Self-check transmitter ----
                s_axis_tready <= 1'b1; // checker always accepts RX
                case (tstate)
                    T_IDLE: begin
                        m_axis_tvalid <= 1'b0;
                        if (bringup_done_r && link_running &&
                            (selftest_start_pulse || !selftest_done_r)) begin
                            tx_idx          <= 8'd0;
                            exp_idx         <= 8'd0;
                            tx_pkt          <= 32'd0;
                            rx_pkt          <= 32'd0;
                            tx_lfsr         <= PRBS_SEED;
                            rx_lfsr         <= PRBS_SEED;
                            errcount_r      <= 32'd0;
                            txcount_r       <= 32'd0;
                            rxcount_r       <= 32'd0;
                            selftest_busy_r <= 1'b1;
                            selftest_done_r <= 1'b0;
                            selftest_pass_r <= 1'b0;
                            check_active    <= 1'b1;
                            tstate          <= T_DATA;
                        end
                    end
                    T_DATA: begin
                        // Present the current PRBS byte; hold it until accepted.
                        m_axis_tdata  <= tx_lfsr;
                        m_axis_tlast  <= 1'b0;
                        m_axis_tuser  <= 1'b0;
                        m_axis_tvalid <= 1'b1;
                        if (m_axis_tvalid && m_axis_tready) begin
                            txcount_r <= txcount_r + 1'b1;
                            tx_lfsr   <= prbs_next(tx_lfsr);
                            if (tx_idx == (SELFTEST_LEN - 1)) begin
                                // End of packet: present EOP next.
                                m_axis_tdata  <= 8'd0; // 0 => EOP
                                m_axis_tlast  <= 1'b1;
                                m_axis_tuser  <= 1'b0;
                                m_axis_tvalid <= 1'b1;
                                tstate        <= T_EOP;
                            end else begin
                                tx_idx        <= tx_idx + 1'b1;
                                m_axis_tdata  <= prbs_next(tx_lfsr); // next PRBS byte
                            end
                        end
                    end
                    T_EOP: begin
                        // EOP presented; on accept start the next packet
                        // back-to-back (PRBS continues across packets) or finish.
                        // In loop mode the run never ends until selftest_en clears.
                        if (m_axis_tvalid && m_axis_tready) begin
                            txcount_r <= txcount_r + 1'b1;
                            if (!selftest_loop_r && (tx_pkt == (SELFTEST_PKTS - 1))) begin
                                m_axis_tvalid <= 1'b0;
                                m_axis_tlast  <= 1'b0;
                                tstate        <= T_DONE;
                            end else begin
                                tx_pkt        <= tx_pkt + 1'b1;
                                tx_idx        <= 8'd0;
                                m_axis_tdata  <= tx_lfsr; // first byte of next packet
                                m_axis_tlast  <= 1'b0;
                                m_axis_tuser  <= 1'b0;
                                m_axis_tvalid <= 1'b1;
                                tstate        <= T_DATA;
                            end
                        end
                    end
                    T_DONE: begin
                        m_axis_tvalid <= 1'b0;
                    end
                    default: tstate <= T_IDLE;
                endcase

                // ---- Self-check receiver/comparator (PRBS, multi-packet) ----
                if (check_active && s_axis_tvalid && s_axis_tready) begin
                    rxcount_r <= rxcount_r + 1'b1;
                    if (s_axis_tlast) begin
                        // EOP must be a real EOP (tuser=0, data=0) closing a packet
                        // of exactly SELFTEST_LEN PRBS bytes.
                        if (s_axis_tuser[0] || (exp_idx != SELFTEST_LEN) ||
                            (s_axis_tdata != 8'd0))
                            errcount_r <= errcount_r + 1'b1;
                        exp_idx <= 8'd0;
                        rx_pkt  <= rx_pkt + 1'b1;
                        // In loop mode never finish: keep checking and accumulating
                        // ERRCOUNT until the host clears selftest_en.
                        if (!selftest_loop_r && (rx_pkt == (SELFTEST_PKTS - 1))) begin
                            check_active    <= 1'b0;
                            selftest_busy_r <= 1'b0;
                            selftest_done_r <= 1'b1;
                            selftest_pass_r <= (errcount_r == 32'd0) &&
                                               !s_axis_tuser[0] &&
                                               (exp_idx == SELFTEST_LEN) &&
                                               (s_axis_tdata == 8'd0);
                        end
                    end else begin
                        if (s_axis_tdata != rx_lfsr)
                            errcount_r <= errcount_r + 1'b1;
                        rx_lfsr <= prbs_next(rx_lfsr);
                        exp_idx <= exp_idx + 1'b1;
                    end
                end
                if (selftest_start_pulse) begin
                    selftest_done_r <= 1'b0;
                    tstate          <= T_IDLE;
                end
            end else begin
                // ---- Host data-mover ----
                selftest_busy_r <= 1'b0;
                // TX: drain the one-beat holding register into AXIS.
                if (dm_tx_pending && !m_axis_tvalid) begin
                    m_axis_tdata  <= dm_tx_beat[7:0];
                    m_axis_tlast  <= dm_tx_beat[8];
                    m_axis_tuser  <= dm_tx_beat[9];
                    m_axis_tvalid <= 1'b1;
                end
                if (m_axis_tvalid && m_axis_tready) begin
                    m_axis_tvalid <= 1'b0;
                    txcount_r     <= txcount_r + 1'b1;
                    dm_tx_pending <= 1'b0;
                end
                // RX: capture into FIFO whenever space allows. Latch the beat
                // at the handshake cycle so the FIFO write (next cycle) uses the
                // correct data, not the following beat.
                s_axis_tready <= !rxfifo_full;
                if (s_axis_tvalid && s_axis_tready) begin
                    rxfifo_push  <= 1'b1;
                    rxfifo_wdata <= {s_axis_tuser[0], s_axis_tlast, s_axis_tdata};
                    rxcount_r    <= rxcount_r + 1'b1;
                end
                // A new host push wins over a same-cycle drain (rare for a
                // slow JTAG host that writes one beat at a time).
                if (dm_tx_push) dm_tx_pending <= 1'b1;
            end
        end
    end

    // ---- RX FIFO pointer maintenance ----
    always @(posedge clk) begin
        if (rst) begin
            rxfifo_wptr <= 0;
            rxfifo_rptr <= 0;
        end else begin
            if (rxfifo_push && !rxfifo_full) begin
                rxfifo_mem[rxfifo_wptr[RXFIFO_AW-1:0]] <= rxfifo_wdata;
                rxfifo_wptr <= rxfifo_wptr + 1'b1;
            end
            if (rxfifo_pop && !rxfifo_empty) begin
                rxfifo_rptr <= rxfifo_rptr + 1'b1;
            end
        end
    end

    // ====================================================================
    // AXI4 slave: write FSM and read FSM (single + INCR burst), serving the
    // example register file. Modeled on tb/axi4_test_slave.v.
    // ====================================================================
    localparam [1:0] W_IDLE=2'd0, W_DATA=2'd1, W_RESP=2'd2;
    reg [1:0]  w_state;
    reg [31:0] w_addr;
    reg [7:0]  w_len;

    always @(posedge clk) begin
        if (rst) begin
            w_state       <= W_IDLE;
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            w_addr        <= 32'd0;
            w_len         <= 8'd0;
            scratch_r     <= 32'd0;
            selftest_en_r <= 1'b1;  // self-test on by default
            selftest_loop_r <= 1'b0;
            errinj_r      <= 2'b00;
            selftest_start_pulse <= 1'b0;
            soft_reset_pulse     <= 1'b0;
            dm_tx_push    <= 1'b0;
            dm_tx_beat    <= 10'd0;
            tc_send_push  <= 1'b0;
            tc_send_value <= 8'd0;
        end else begin
            selftest_start_pulse <= 1'b0;
            soft_reset_pulse     <= 1'b0;
            dm_tx_push           <= 1'b0;
            tc_send_push         <= 1'b0;
            case (w_state)
                W_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    if (s_axi_awvalid && s_axi_awready) begin
                        w_addr        <= s_axi_awaddr;
                        w_len         <= s_axi_awlen;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        w_state       <= W_DATA;
                    end
                end
                W_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        if (w_addr[31:8] == 24'd0)
                        case (w_addr[7:0])
                            8'h08: begin
                                if (s_axi_wstrb[0]) scratch_r[7:0]   <= s_axi_wdata[7:0];
                                if (s_axi_wstrb[1]) scratch_r[15:8]  <= s_axi_wdata[15:8];
                                if (s_axi_wstrb[2]) scratch_r[23:16] <= s_axi_wdata[23:16];
                                if (s_axi_wstrb[3]) scratch_r[31:24] <= s_axi_wdata[31:24];
                            end
                            8'h0C: begin
                                if (s_axi_wstrb[0]) begin
                                    selftest_en_r        <= s_axi_wdata[0];
                                    selftest_start_pulse <= s_axi_wdata[1];
                                    soft_reset_pulse     <= s_axi_wdata[2];
                                    selftest_loop_r      <= s_axi_wdata[3];
                                end
                            end
                            8'h1C: begin // TXDATA push (data-mover)
                                dm_tx_beat <= s_axi_wdata[9:0];
                                dm_tx_push <= 1'b1;
                            end
                            8'h34: begin // ERRINJ (internal-loopback error inject)
                                if (s_axi_wstrb[0]) errinj_r <= s_axi_wdata[1:0];
                            end
                            8'h38: begin // TIMECODE: send the requested time-code
                                if (s_axi_wstrb[0]) tc_send_value <= s_axi_wdata[7:0];
                                tc_send_push <= 1'b1;
                            end
                            default: ; // RO or unmapped: ignore
                        endcase
                        w_addr <= w_addr + 32'd4;
                        if (s_axi_wlast || (w_len == 8'd0)) begin
                            s_axi_wready <= 1'b0;
                            s_axi_bvalid <= 1'b1;
                            s_axi_bresp  <= 2'b00;
                            w_state      <= W_RESP;
                        end else begin
                            w_len <= w_len - 8'd1;
                        end
                    end
                end
                W_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid  <= 1'b0;
                        s_axi_awready <= 1'b1;
                        w_state       <= W_IDLE;
                    end
                end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    // ---- Read FSM ----
    localparam [1:0] R_IDLE=2'd0, R_DATA=2'd1;
    reg [1:0]  r_state;
    reg [31:0] r_addr;
    reg [7:0]  r_len;

    function [31:0] reg_read;
        input [31:0] addr;
        begin
            if (|addr[31:8]) reg_read = 32'd0;  // out of range: no aliasing
            else
            case (addr[7:0])
                8'h00: reg_read = EXAMPLE_ID;
                8'h04: reg_read = EXAMPLE_VER;
                8'h08: reg_read = scratch_r;
                8'h0C: reg_read = {28'd0, selftest_loop_r, 2'b0, selftest_en_r};
                8'h10: reg_read = {20'd0, spw_status_r[11:8], 1'b0,
                                   bringup_done_r, ~rxfifo_empty, ~dm_tx_pending,
                                   selftest_pass_r, selftest_done_r,
                                   selftest_busy_r, link_running};
                8'h14: reg_read = spw_coreid_r;
                8'h18: reg_read = spw_status_r;
                8'h20: reg_read = rxfifo_empty ? 32'd0
                                  : {1'b1, 21'd0, rxfifo_dout[9], rxfifo_dout[8], rxfifo_dout[7:0]};
                8'h24: reg_read = txcount_r;
                8'h28: reg_read = rxcount_r;
                8'h2C: reg_read = errcount_r;
                8'h30: reg_read = rx_pkt;             // packets received (EOP count)
                8'h34: reg_read = {30'd0, errinj_r};  // error-injection control
                8'h38: reg_read = spw_tc_rx_r;        // received time-code mirror
                default: reg_read = 32'd0;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            r_state       <= R_IDLE;
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= 2'b00;
            s_axi_rlast   <= 1'b0;
            r_addr        <= 32'd0;
            r_len         <= 8'd0;
            rxfifo_pop    <= 1'b0;
        end else begin
            rxfifo_pop <= 1'b0;
            case (r_state)
                R_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast  <= 1'b0;
                    if (s_axi_arvalid && s_axi_arready) begin
                        r_addr        <= s_axi_araddr;
                        r_len         <= s_axi_arlen;
                        s_axi_arready <= 1'b0;
                        s_axi_rdata   <= reg_read(s_axi_araddr);
                        s_axi_rresp   <= 2'b00;
                        s_axi_rvalid  <= 1'b1;
                        s_axi_rlast   <= (s_axi_arlen == 8'd0);
                        // Pop RX FIFO once per RXDATA read that returns data.
                        if ((s_axi_araddr[31:8] == 24'd0) &&
                            (s_axi_araddr[7:0] == 8'h20) && !rxfifo_empty)
                            rxfifo_pop <= 1'b1;
                        r_state <= R_DATA;
                    end
                end
                R_DATA: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (r_len == 8'd0) begin
                            s_axi_rvalid  <= 1'b0;
                            s_axi_rlast   <= 1'b0;
                            s_axi_arready <= 1'b1;
                            r_state       <= R_IDLE;
                        end else begin
                            r_addr      <= r_addr + 32'd4;
                            r_len       <= r_len - 8'd1;
                            s_axi_rdata <= reg_read(r_addr + 32'd4);
                            s_axi_rlast <= (r_len == 8'd1);
                            if (((r_addr + 32'd4) == 32'h20) && !rxfifo_empty)
                                rxfifo_pop <= 1'b1;
                        end
                    end
                end
                default: r_state <= R_IDLE;
            endcase
        end
    end

endmodule
