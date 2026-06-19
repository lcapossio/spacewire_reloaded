/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 Leonardo Capossio - bard0 design
 * Author: Leonardo Capossio - bard0 design - hello@bard0.com
 *
 * AXI4-Lite control and status registers for SpaceWire Reloaded.
 */

`timescale 1ns / 1ps

module spw_axi_lite_regs #(
    parameter ADDR_WIDTH = 8,
    parameter [31:0] CORE_ID = 32'h53505752,
    parameter [31:0] VERSION = 32'h00010000
) (
    input  wire                  clk,
    input  wire                  rst,

    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire [31:0]           s_axi_wdata,
    input  wire [3:0]            s_axi_wstrb,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    output wire [31:0]           s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready,

    output wire                  core_rst,
    output wire                  autostart,
    output wire                  linkstart,
    output wire                  linkdis,
    output wire [7:0]            txdivcnt,

    output wire                  tick_in,
    output wire [1:0]            ctrl_in,
    output wire [5:0]            time_in,

    input  wire                  tick_out,
    input  wire [1:0]            ctrl_out,
    input  wire [5:0]            time_out,

    input  wire                  txrdy,
    input  wire                  txhalff,
    input  wire                  rxvalid,
    input  wire                  rxhalff,
    input  wire                  started,
    input  wire                  connecting,
    input  wire                  running,
    input  wire                  errdisc,
    input  wire                  errpar,
    input  wire                  erresc,
    input  wire                  errcred,

    output wire                  irq
);

    localparam REG_CORE_ID     = 4'd0;
    localparam REG_VERSION     = 4'd1;
    localparam REG_CONTROL     = 4'd2;
    localparam REG_STATUS      = 4'd3;
    localparam REG_TXDIVCNT    = 4'd4;
    localparam REG_TIMECODE_TX = 4'd5;
    localparam REG_TIMECODE_RX = 4'd6;
    localparam REG_ERROR       = 4'd7;
    localparam REG_IRQ_ENABLE  = 4'd8;
    localparam REG_IRQ_STATUS  = 4'd9;

    reg [ADDR_WIDTH-1:0] awaddr_r;
    reg aw_holding_r;
    reg [31:0] wdata_r;
    reg [3:0] wstrb_r;
    reg w_holding_r;
    reg bvalid_r;
    reg [31:0] rdata_r;
    reg rvalid_r;
    reg [31:0] control_r;
    reg [7:0] txdivcnt_r;
    reg tick_pulse_r;
    reg [1:0] tick_ctrl_r;
    reg [5:0] tick_time_r;
    reg rx_tick_valid_r;
    reg [1:0] rx_tick_ctrl_r;
    reg [5:0] rx_tick_time_r;
    reg [3:0] error_r;
    reg [31:0] irq_enable_r;

    wire [31:0] status_word;
    wire [31:0] rx_timecode_word;
    wire [31:0] irq_status;
    wire [3:0] write_index;
    wire write_fire;
    wire [ADDR_WIDTH-1:0] write_addr;
    wire [31:0] write_data;
    wire [3:0] write_strb;
    wire [3:0] error_inputs;
    // The register file occupies the low 64-byte (16-word) aperture. Any access
    // with an address bit above [5] set is unmapped: it must read as zero and
    // ignore writes, not alias the low bank.
    wire write_in_range;
    wire read_in_range;

    assign s_axi_awready = !aw_holding_r && !bvalid_r;
    assign s_axi_wready = !w_holding_r && !bvalid_r;
    assign s_axi_bresp = 2'b00;
    assign s_axi_bvalid = bvalid_r;
    assign s_axi_arready = !rvalid_r;
    assign s_axi_rdata = rdata_r;
    assign s_axi_rresp = 2'b00;
    assign s_axi_rvalid = rvalid_r;

    assign core_rst = control_r[0];
    assign autostart = control_r[1];
    assign linkstart = control_r[2];
    assign linkdis = control_r[3];
    assign txdivcnt = txdivcnt_r;
    assign tick_in = tick_pulse_r;
    assign ctrl_in = tick_ctrl_r;
    assign time_in = tick_time_r;

    assign status_word = {
        20'd0,
        error_r,
        rx_tick_valid_r,
        rxhalff,
        rxvalid,
        txhalff,
        txrdy,
        running,
        connecting,
        started
    };
    assign rx_timecode_word = {rx_tick_valid_r, 23'd0, rx_tick_ctrl_r, rx_tick_time_r};
    assign irq_status = {27'd0, (started | connecting | running), txrdy, rxvalid, rx_tick_valid_r, |error_r};
    assign irq = |(irq_status & irq_enable_r);
    assign error_inputs = {errcred, erresc, errpar, errdisc};

    assign write_fire = !bvalid_r &&
        (aw_holding_r || (s_axi_awvalid && s_axi_awready)) &&
        (w_holding_r || (s_axi_wvalid && s_axi_wready));
    assign write_addr = aw_holding_r ? awaddr_r : s_axi_awaddr;
    assign write_data = w_holding_r ? wdata_r : s_axi_wdata;
    assign write_strb = w_holding_r ? wstrb_r : s_axi_wstrb;
    assign write_index = write_addr[5:2];
    assign write_in_range = ((write_addr >> 6) == 0);
    assign read_in_range = ((s_axi_araddr >> 6) == 0);

    initial begin
        // The 64-byte register aperture needs at least address bits [5:0].
        if (ADDR_WIDTH < 6) begin
            $display("spw_axi_lite_regs: ADDR_WIDTH must be >= 6 for the 64-byte register aperture");
            $finish;
        end
    end

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] strobe;
        integer i;
        begin
            apply_wstrb = old_value;
            for (i = 0; i < 4; i = i + 1) begin
                if (strobe[i]) begin
                    apply_wstrb[(8*i) +: 8] = new_value[(8*i) +: 8];
                end
            end
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            awaddr_r <= {ADDR_WIDTH{1'b0}};
            aw_holding_r <= 1'b0;
            wdata_r <= 32'd0;
            wstrb_r <= 4'd0;
            w_holding_r <= 1'b0;
            bvalid_r <= 1'b0;
            rdata_r <= 32'd0;
            rvalid_r <= 1'b0;
            control_r <= 32'd0;
            txdivcnt_r <= 8'd0;
            tick_pulse_r <= 1'b0;
            tick_ctrl_r <= 2'd0;
            tick_time_r <= 6'd0;
            rx_tick_valid_r <= 1'b0;
            rx_tick_ctrl_r <= 2'd0;
            rx_tick_time_r <= 6'd0;
            error_r <= 4'd0;
            irq_enable_r <= 32'd0;
        end else begin
            tick_pulse_r <= 1'b0;
            error_r <= error_r | error_inputs;

            if (tick_out) begin
                rx_tick_valid_r <= 1'b1;
                rx_tick_ctrl_r <= ctrl_out;
                rx_tick_time_r <= time_out;
            end

            if (bvalid_r && s_axi_bready) begin
                bvalid_r <= 1'b0;
            end

            if (s_axi_awready && s_axi_awvalid) begin
                awaddr_r <= s_axi_awaddr;
                aw_holding_r <= 1'b1;
            end

            if (s_axi_wready && s_axi_wvalid) begin
                wdata_r <= s_axi_wdata;
                wstrb_r <= s_axi_wstrb;
                w_holding_r <= 1'b1;
            end

            if (write_fire) begin
                if (write_in_range) begin
                case (write_index)
                    REG_CONTROL: begin
                        control_r <= apply_wstrb(control_r, write_data, write_strb);
                    end
                    REG_TXDIVCNT: begin
                        if (write_strb[0]) begin
                            txdivcnt_r <= write_data[7:0];
                        end
                    end
                    REG_TIMECODE_TX: begin
                        if (write_strb[0]) begin
                            tick_time_r <= write_data[5:0];
                            tick_ctrl_r <= write_data[7:6];
                        end
                        if (write_strb[3] && write_data[31]) begin
                            tick_pulse_r <= 1'b1;
                        end
                    end
                    REG_TIMECODE_RX: begin
                        if (write_strb[3] && write_data[31]) begin
                            rx_tick_valid_r <= tick_out;
                        end
                    end
                    REG_ERROR: begin
                        if (write_strb[0]) begin
                            error_r <= (error_r & ~write_data[3:0]) | error_inputs;
                        end
                    end
                    REG_IRQ_ENABLE: begin
                        irq_enable_r <= apply_wstrb(irq_enable_r, write_data, write_strb);
                    end
                    REG_IRQ_STATUS: begin
                        if (write_strb[0] && write_data[0]) begin
                            error_r <= error_inputs;
                        end
                        if (write_strb[0] && write_data[1]) begin
                            rx_tick_valid_r <= tick_out;
                        end
                    end
                    default: begin
                    end
                endcase
                end
                aw_holding_r <= 1'b0;
                w_holding_r <= 1'b0;
                bvalid_r <= 1'b1;
            end

            if (rvalid_r && s_axi_rready) begin
                rvalid_r <= 1'b0;
            end

            if (s_axi_arready && s_axi_arvalid) begin
                if (read_in_range) begin
                case (s_axi_araddr[5:2])
                    REG_CORE_ID:     rdata_r <= CORE_ID;
                    REG_VERSION:     rdata_r <= VERSION;
                    REG_CONTROL:     rdata_r <= control_r;
                    REG_STATUS:      rdata_r <= status_word;
                    REG_TXDIVCNT:    rdata_r <= {24'd0, txdivcnt_r};
                    REG_TIMECODE_RX: rdata_r <= rx_timecode_word;
                    REG_ERROR:       rdata_r <= {28'd0, error_r};
                    REG_IRQ_ENABLE:  rdata_r <= irq_enable_r;
                    REG_IRQ_STATUS:  rdata_r <= irq_status;
                    default:         rdata_r <= 32'd0;
                endcase
                end else begin
                    rdata_r <= 32'd0;
                end
                rvalid_r <= 1'b1;
            end
        end
    end

endmodule
