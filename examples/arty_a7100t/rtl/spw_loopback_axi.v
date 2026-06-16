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
 *   0x2C ERRCOUNT    RO  self-check comparison mismatches
 */

`timescale 1ns/1ps

module spw_loopback_axi #(
    parameter [31:0] EXAMPLE_ID  = 32'h5350574C, // "SPWL"
    parameter [31:0] EXAMPLE_VER = 32'h00010000,
    parameter [7:0]  LINK_TXDIVCNT = 8'd9,       // ~ sysfreq/(divcnt+1) run rate
    parameter [7:0]  SELFTEST_LEN  = 8'd16       // N data bytes before EOP
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
    output wire        bringup_done
);

    // spw_axi_lite_regs register byte offsets (see rtl/.../spw_axi_lite_regs).
    localparam [7:0] SPW_REG_CORE_ID  = 8'h00;
    localparam [7:0] SPW_REG_CONTROL  = 8'h08;
    localparam [7:0] SPW_REG_STATUS   = 8'h0C;
    localparam [7:0] SPW_REG_TXDIVCNT = 8'h10;

    // ---- Example register file ----
    reg [31:0] scratch_r;
    reg        selftest_en_r;
    reg [31:0] spw_coreid_r;
    reg [31:0] spw_status_r;
    reg [31:0] txcount_r;
    reg [31:0] rxcount_r;
    reg [31:0] errcount_r;
    reg        selftest_busy_r;
    reg        selftest_done_r;
    reg        selftest_pass_r;
    reg        bringup_done_r;

    reg        selftest_start_pulse;
    reg        soft_reset_pulse;

    assign m_axil_wstrb   = 4'hF;
    assign link_running   = spw_status_r[2];
    assign selftest_pass  = selftest_pass_r;
    assign selftest_done  = selftest_done_r;
    assign bringup_done   = bringup_done_r;

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
    // Sequence: write CONTROL (autostart|linkstart), write TXDIVCNT, read
    // CORE_ID, then loop reading STATUS forever.
    // ====================================================================
    localparam [3:0]
        M_RST       = 4'd0,
        M_CTRL_AW   = 4'd1,
        M_CTRL_B    = 4'd2,
        M_DIV_AW    = 4'd3,
        M_DIV_B     = 4'd4,
        M_ID_AR     = 4'd5,
        M_ID_R      = 4'd6,
        M_STAT_AR   = 4'd7,
        M_STAT_R    = 4'd8;
    reg [3:0] mstate;

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
        end else begin
            if (soft_reset_pulse) begin
                mstate         <= M_RST;
                bringup_done_r <= 1'b0;
            end
            case (mstate)
                M_RST: begin
                    m_axil_awaddr  <= SPW_REG_CONTROL;
                    m_axil_wdata   <= 32'h0000_0006; // autostart|linkstart
                    m_axil_awvalid <= 1'b1;
                    m_axil_wvalid  <= 1'b1;
                    mstate         <= M_CTRL_AW;
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
                        mstate         <= M_STAT_AR; // poll again
                    end
                end
                default: mstate <= M_RST;
            endcase
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
    reg [7:0]  tx_idx;
    reg [7:0]  exp_idx;       // expected RX byte index for the checker
    reg        check_active;

    // Combolike defaults driven in the clocked block below.
    always @(posedge clk) begin
        if (rst) begin
            tstate          <= T_IDLE;
            tx_idx          <= 8'd0;
            exp_idx         <= 8'd0;
            check_active    <= 1'b0;
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
                        // Present the current data char; hold it until accepted.
                        m_axis_tdata  <= tx_idx;
                        m_axis_tlast  <= 1'b0;
                        m_axis_tuser  <= 1'b0;
                        m_axis_tvalid <= 1'b1;
                        if (m_axis_tvalid && m_axis_tready) begin
                            txcount_r <= txcount_r + 1'b1;
                            if (tx_idx == (SELFTEST_LEN - 1)) begin
                                // Last data accepted: present the EOP beat next
                                // (overrides the data presentation above).
                                m_axis_tdata  <= 8'd0; // 0 => EOP
                                m_axis_tlast  <= 1'b1;
                                m_axis_tuser  <= 1'b0;
                                m_axis_tvalid <= 1'b1;
                                tstate        <= T_EOP;
                            end else begin
                                tx_idx        <= tx_idx + 1'b1;
                                m_axis_tdata  <= tx_idx + 1'b1; // present next char
                            end
                        end
                    end
                    T_EOP: begin
                        // EOP beat already presented; wait for it to be accepted.
                        if (m_axis_tvalid && m_axis_tready) begin
                            txcount_r     <= txcount_r + 1'b1;
                            m_axis_tvalid <= 1'b0;
                            m_axis_tlast  <= 1'b0;
                            tstate        <= T_DONE;
                        end
                    end
                    T_DONE: begin
                        m_axis_tvalid <= 1'b0;
                    end
                    default: tstate <= T_IDLE;
                endcase

                // ---- Self-check receiver/comparator ----
                if (check_active && s_axis_tvalid && s_axis_tready) begin
                    rxcount_r <= rxcount_r + 1'b1;
                    if (s_axis_tlast) begin
                        // Terminal beat: expect EOP (tuser=0) after SELFTEST_LEN data
                        if (s_axis_tuser[0] || (exp_idx != SELFTEST_LEN))
                            errcount_r <= errcount_r + 1'b1;
                        check_active    <= 1'b0;
                        selftest_busy_r <= 1'b0;
                        selftest_done_r <= 1'b1;
                        selftest_pass_r <= (errcount_r == 32'd0) &&
                                           !s_axis_tuser[0] &&
                                           (exp_idx == SELFTEST_LEN) &&
                                           (s_axis_tdata == 8'd0);
                    end else begin
                        if (s_axis_tdata != exp_idx[7:0])
                            errcount_r <= errcount_r + 1'b1;
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
            selftest_start_pulse <= 1'b0;
            soft_reset_pulse     <= 1'b0;
            dm_tx_push    <= 1'b0;
            dm_tx_beat    <= 10'd0;
        end else begin
            selftest_start_pulse <= 1'b0;
            soft_reset_pulse     <= 1'b0;
            dm_tx_push           <= 1'b0;
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
                                end
                            end
                            8'h1C: begin // TXDATA push (data-mover)
                                dm_tx_beat <= s_axi_wdata[9:0];
                                dm_tx_push <= 1'b1;
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
        input [7:0] off;
        begin
            case (off)
                8'h00: reg_read = EXAMPLE_ID;
                8'h04: reg_read = EXAMPLE_VER;
                8'h08: reg_read = scratch_r;
                8'h0C: reg_read = {31'd0, selftest_en_r};
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
                        s_axi_rdata   <= reg_read(s_axi_araddr[7:0]);
                        s_axi_rresp   <= 2'b00;
                        s_axi_rvalid  <= 1'b1;
                        s_axi_rlast   <= (s_axi_arlen == 8'd0);
                        // Pop RX FIFO once per RXDATA read that returns data.
                        if ((s_axi_araddr[7:0] == 8'h20) && !rxfifo_empty)
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
                            s_axi_rdata <= reg_read(r_addr[7:0] + 8'd4);
                            s_axi_rlast <= (r_len == 8'd1);
                            if ((r_addr[7:0] + 8'd4) == 8'h20 && !rxfifo_empty)
                                rxfifo_pop <= 1'b1;
                        end
                    end
                end
                default: r_state <= R_IDLE;
            endcase
        end
    end

endmodule
