--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- SpaceWire Reloaded - Arty A7-100T loopback hardware-validation top-level
-- (VHDL, mixed-language). Functional mirror of rtl/spw_arty_a7100t_top.v: the
-- VHDL spw_axi_top + spw_loopback_axi are driven by the Verilog fpgacapZero
-- fcapz_*_xilinx7 wrappers (declared as components below; Vivado binds them).
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spwpkg.all;

entity spw_arty_a7100t_top is
    generic (
        LOOPBACK_INTERNAL: integer := 1;
        -- RX/TX front-end: 0 = generic (single clock), 1 = fast. The fast build
        -- uses an MMCM so rxclk/txclk run in their own domains, exercising the
        -- gray-coded rxclk->clk and clk<->txclk crossings (and spw_cdc.xdc) on HW.
        RXIMPL:   integer := 0;
        TXIMPL:   integer := 0;
        RXCHUNK:  integer := 1;
        USE_MMCM: integer := 0;
        -- SpaceWire run-state TX divider: bit rate = txclk/(LINK_TXDIVCNT+1).
        -- 9 -> ~10 Mbit/s at 100 MHz; 0 -> 100 Mbit/s (fast build).
        LINK_TXDIVCNT: integer := 9
    );
    port (
        clk: in  std_logic;            -- 100 MHz board oscillator (E3)
        btn: in  std_logic_vector(3 downto 0);
        led: out std_logic_vector(3 downto 0);
        spw_do_pin: out std_logic;
        spw_so_pin: out std_logic;
        spw_di_pin: in  std_logic;
        spw_si_pin: in  std_logic
    );
end entity spw_arty_a7100t_top;

architecture rtl of spw_arty_a7100t_top is

    component fcapz_ejtagaxi_xilinx7 is
        generic (
            ADDR_W               : integer := 32;
            DATA_W               : integer := 32;
            FIFO_DEPTH           : integer := 16;
            CMD_FIFO_DEPTH       : integer := 16;
            RESP_FIFO_DEPTH      : integer := 16;
            CMD_FIFO_MEMORY_TYPE : string  := "distributed";
            TIMEOUT              : integer := 4096;
            DEBUG_EN             : integer := 0
        );
        port (
            axi_clk       : in  std_logic;
            axi_rst       : in  std_logic;
            m_axi_awaddr  : out std_logic_vector(ADDR_W - 1 downto 0);
            m_axi_awlen   : out std_logic_vector(7 downto 0);
            m_axi_awsize  : out std_logic_vector(2 downto 0);
            m_axi_awburst : out std_logic_vector(1 downto 0);
            m_axi_awvalid : out std_logic;
            m_axi_awready : in  std_logic;
            m_axi_awprot  : out std_logic_vector(2 downto 0);
            m_axi_wdata   : out std_logic_vector(DATA_W - 1 downto 0);
            m_axi_wstrb   : out std_logic_vector((DATA_W / 8) - 1 downto 0);
            m_axi_wvalid  : out std_logic;
            m_axi_wready  : in  std_logic;
            m_axi_wlast   : out std_logic;
            m_axi_bresp   : in  std_logic_vector(1 downto 0);
            m_axi_bvalid  : in  std_logic;
            m_axi_bready  : out std_logic;
            m_axi_araddr  : out std_logic_vector(ADDR_W - 1 downto 0);
            m_axi_arlen   : out std_logic_vector(7 downto 0);
            m_axi_arsize  : out std_logic_vector(2 downto 0);
            m_axi_arburst : out std_logic_vector(1 downto 0);
            m_axi_arvalid : out std_logic;
            m_axi_arready : in  std_logic;
            m_axi_arprot  : out std_logic_vector(2 downto 0);
            m_axi_rdata   : in  std_logic_vector(DATA_W - 1 downto 0);
            m_axi_rresp   : in  std_logic_vector(1 downto 0);
            m_axi_rvalid  : in  std_logic;
            m_axi_rready  : out std_logic;
            m_axi_rlast   : in  std_logic
        );
    end component;

    component fcapz_debug_multi_xilinx7 is
        generic (
            NUM_ELAS         : integer := 2;
            EIO_EN           : integer := 1;
            NUM_EIOS         : integer := 2;
            SAMPLE_W         : integer := 8;
            DEPTH            : integer := 1024;
            INPUT_PIPE       : integer := 1;
            DECIM_EN         : integer := 1;
            EXT_TRIG_EN      : integer := 1;
            TIMESTAMP_W      : integer := 32;
            NUM_SEGMENTS     : integer := 4;
            STARTUP_ARM      : integer := 1;
            DEFAULT_TRIG_EXT : integer := 2;
            EIO_IN_W         : integer := 8;
            EIO_OUT_W        : integer := 8
        );
        port (
            ela_sample_clk  : in  std_logic_vector(NUM_ELAS - 1 downto 0);
            ela_sample_rst  : in  std_logic_vector(NUM_ELAS - 1 downto 0);
            ela_probe_in    : in  std_logic_vector(NUM_ELAS * SAMPLE_W - 1 downto 0);
            ela_trigger_in  : in  std_logic_vector(NUM_ELAS - 1 downto 0);
            ela_trigger_out : out std_logic_vector(NUM_ELAS - 1 downto 0);
            ela_armed_out   : out std_logic_vector(NUM_ELAS - 1 downto 0);
            eio_probe_in    : in  std_logic_vector(NUM_EIOS * EIO_IN_W - 1 downto 0);
            eio_probe_out   : out std_logic_vector(NUM_EIOS * EIO_OUT_W - 1 downto 0)
        );
    end component;

    component MMCME2_BASE is
        generic (
            BANDWIDTH        : string := "OPTIMIZED";
            CLKFBOUT_MULT_F  : real := 5.0;
            CLKIN1_PERIOD    : real := 0.0;
            CLKOUT0_DIVIDE_F : real := 1.0;
            CLKOUT1_DIVIDE   : integer := 1;
            DIVCLK_DIVIDE    : integer := 1;
            STARTUP_WAIT     : string := "FALSE"
        );
        port (
            CLKIN1   : in  std_logic;
            CLKFBIN  : in  std_logic;
            CLKFBOUT : out std_logic;
            CLKFBOUTB: out std_logic;
            CLKOUT0  : out std_logic;
            CLKOUT0B : out std_logic;
            CLKOUT1  : out std_logic;
            CLKOUT1B : out std_logic;
            CLKOUT2  : out std_logic;
            CLKOUT2B : out std_logic;
            CLKOUT3  : out std_logic;
            CLKOUT3B : out std_logic;
            CLKOUT4  : out std_logic;
            CLKOUT5  : out std_logic;
            CLKOUT6  : out std_logic;
            LOCKED   : out std_logic;
            PWRDWN   : in  std_logic;
            RST      : in  std_logic
        );
    end component;

    component BUFG is
        port ( I : in std_logic; O : out std_logic );
    end component;

    function impl_of(n: integer) return spw_implementation_type is
    begin
        if n = 1 then return impl_fast; else return impl_generic; end if;
    end function;
    constant RX_IMPL_T : spw_implementation_type := impl_of(RXIMPL);
    constant TX_IMPL_T : spw_implementation_type := impl_of(TXIMPL);

    -- sample/transmit clocks
    signal rxclk, txclk, mmcm_locked : std_logic;

    -- reset
    signal por_sr    : std_logic_vector(3 downto 0) := (others => '1');
    signal btn0_meta : std_logic;
    signal btn0_sync : std_logic;
    signal rst       : std_logic;
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of btn0_meta : signal is "TRUE";
    attribute ASYNC_REG of btn0_sync : signal is "TRUE";

    signal spw_do, spw_so, spw_di, spw_si : std_logic;
    signal spw_irq : std_logic;

    -- AXI4 bridge <-> engine
    signal ax_awaddr, ax_wdata, ax_araddr, ax_rdata : std_logic_vector(31 downto 0);
    signal ax_awlen, ax_arlen   : std_logic_vector(7 downto 0);
    signal ax_awsize, ax_arsize, ax_awprot, ax_arprot : std_logic_vector(2 downto 0);
    signal ax_awburst, ax_arburst, ax_bresp, ax_rresp : std_logic_vector(1 downto 0);
    signal ax_wstrb : std_logic_vector(3 downto 0);
    signal ax_awvalid, ax_awready, ax_wvalid, ax_wready, ax_wlast : std_logic;
    signal ax_bvalid, ax_bready : std_logic;
    signal ax_arvalid, ax_arready, ax_rvalid, ax_rready, ax_rlast : std_logic;

    -- engine <-> spw_axi_top AXI-Lite
    signal cs_awaddr, cs_araddr : std_logic_vector(7 downto 0);
    signal cs_wdata, cs_rdata   : std_logic_vector(31 downto 0);
    signal cs_wstrb : std_logic_vector(3 downto 0);
    signal cs_bresp, cs_rresp : std_logic_vector(1 downto 0);
    signal cs_awvalid, cs_awready, cs_wvalid, cs_wready : std_logic;
    signal cs_bvalid, cs_bready, cs_arvalid, cs_arready, cs_rvalid, cs_rready : std_logic;

    -- engine <-> spw_axi_top AXI-Stream
    signal tx_tdata, rx_tdata : std_logic_vector(7 downto 0);
    signal tx_tvalid, tx_tready, tx_tlast : std_logic;
    signal tx_tuser : std_logic_vector(0 downto 0);
    signal rx_tvalid, rx_tready, rx_tlast : std_logic;
    signal rx_tuser : std_logic_vector(0 downto 0);

    signal link_running, selftest_pass, selftest_done, bringup_done : std_logic;
    signal inj_freeze, inj_invert : std_logic;
    signal spw_do_tx, spw_so_tx : std_logic;  -- transmit signals after error injection

    -- debug
    signal ela_trig_in  : std_logic_vector(1 downto 0);
    signal ela_trig_out : std_logic_vector(1 downto 0);
    signal ela_armed    : std_logic_vector(1 downto 0);
    signal eio0_pin, eio0_pout, eio1_pin, eio1_pout : std_logic_vector(7 downto 0);
    signal eio_pout_all : std_logic_vector(15 downto 0);
    signal ela0_probe, ela1_probe : std_logic_vector(7 downto 0);

begin

    -- ---- sample/transmit clocks ----
    -- Generic build: rxclk = txclk = clk. Fast build: MMCM derives 150 MHz
    -- rxclk and 100 MHz txclk in their own domains (real SpaceWire CDCs).
    g_mmcm: if USE_MMCM /= 0 generate
        signal rxclk_raw, txclk_raw, clkfb, clkfb_buf : std_logic;
    begin
        u_mmcm: MMCME2_BASE
            generic map (
                BANDWIDTH => "OPTIMIZED", CLKFBOUT_MULT_F => 9.0,
                CLKIN1_PERIOD => 10.000, CLKOUT0_DIVIDE_F => 6.0,
                CLKOUT1_DIVIDE => 9, DIVCLK_DIVIDE => 1, STARTUP_WAIT => "FALSE")
            port map (
                CLKIN1 => clk, CLKFBIN => clkfb_buf, CLKFBOUT => clkfb,
                CLKFBOUTB => open, CLKOUT0 => rxclk_raw, CLKOUT0B => open,
                CLKOUT1 => txclk_raw, CLKOUT1B => open, CLKOUT2 => open,
                CLKOUT2B => open, CLKOUT3 => open, CLKOUT3B => open,
                CLKOUT4 => open, CLKOUT5 => open, CLKOUT6 => open,
                LOCKED => mmcm_locked, PWRDWN => '0', RST => '0');
        u_fb: BUFG port map (I => clkfb,     O => clkfb_buf);
        u_rx: BUFG port map (I => rxclk_raw, O => rxclk);
        u_tx: BUFG port map (I => txclk_raw, O => txclk);
    end generate;
    g_noclk: if USE_MMCM = 0 generate
        rxclk       <= clk;
        txclk       <= clk;
        mmcm_locked <= '1';
    end generate;

    -- ---- reset ----
    process (clk) is
    begin
        if rising_edge(clk) then
            por_sr    <= por_sr(2 downto 0) & '0';
            btn0_meta <= btn(0);
            btn0_sync <= btn0_meta;
        end if;
    end process;
    rst <= por_sr(3) or btn0_sync or (not mmcm_locked);

    -- ---- error injection on the transmit side (before pins + loopback) ----
    -- so an injected fault leaves the FPGA on the wire and is seen by the
    -- receiver on both internal and external loopback:
    --   inj_freeze -> hold D/S static (disconnect); inj_invert -> invert out D.
    spw_do_tx  <= '0' when inj_freeze = '1' else (spw_do xor inj_invert);
    spw_so_tx  <= '0' when inj_freeze = '1' else spw_so;
    -- loopback select: internal ties do->di inside the FPGA; external via pins.
    spw_di     <= spw_do_tx when LOOPBACK_INTERNAL /= 0 else spw_di_pin;
    spw_si     <= spw_so_tx when LOOPBACK_INTERNAL /= 0 else spw_si_pin;
    spw_do_pin <= spw_do_tx;  -- injected TX signal goes out the wire
    spw_so_pin <= spw_so_tx;

    u_spw: entity work.spw_axi_top
        generic map (
            sysfreq => 100.0e6, txclkfreq => 100.0e6,
            rximpl => RX_IMPL_T, rxchunk => RXCHUNK, tximpl => TX_IMPL_T,
            rxfifosize_bits => 11, txfifosize_bits => 11,
            AXI_ADDR_WIDTH => 8, CORE_ID => x"53505752", VERSION => x"00010000")
        port map (
            clk => clk, rxclk => rxclk, txclk => txclk, rst => rst,
            s_axi_awaddr => cs_awaddr, s_axi_awvalid => cs_awvalid, s_axi_awready => cs_awready,
            s_axi_wdata => cs_wdata, s_axi_wstrb => cs_wstrb, s_axi_wvalid => cs_wvalid, s_axi_wready => cs_wready,
            s_axi_bresp => cs_bresp, s_axi_bvalid => cs_bvalid, s_axi_bready => cs_bready,
            s_axi_araddr => cs_araddr, s_axi_arvalid => cs_arvalid, s_axi_arready => cs_arready,
            s_axi_rdata => cs_rdata, s_axi_rresp => cs_rresp, s_axi_rvalid => cs_rvalid, s_axi_rready => cs_rready,
            s_axis_tdata => tx_tdata, s_axis_tvalid => tx_tvalid, s_axis_tready => tx_tready,
            s_axis_tlast => tx_tlast, s_axis_tuser => tx_tuser,
            m_axis_tdata => rx_tdata, m_axis_tvalid => rx_tvalid, m_axis_tready => rx_tready,
            m_axis_tlast => rx_tlast, m_axis_tuser => rx_tuser,
            irq => spw_irq,
            spw_di => spw_di, spw_si => spw_si, spw_do => spw_do, spw_so => spw_so);

    u_engine: entity work.spw_loopback_axi
        generic map (
            EXAMPLE_ID => x"5350574C", EXAMPLE_VER => x"00010048", -- low byte 'H' = VHDL build
            LINK_TXDIVCNT => std_logic_vector(to_unsigned(LINK_TXDIVCNT, 8)),
            SELFTEST_LEN => 16)
        port map (
            clk => clk, rst => rst,
            s_axi_awaddr => ax_awaddr, s_axi_awlen => ax_awlen, s_axi_awsize => ax_awsize,
            s_axi_awburst => ax_awburst, s_axi_awvalid => ax_awvalid, s_axi_awready => ax_awready,
            s_axi_wdata => ax_wdata, s_axi_wstrb => ax_wstrb, s_axi_wlast => ax_wlast,
            s_axi_wvalid => ax_wvalid, s_axi_wready => ax_wready,
            s_axi_bresp => ax_bresp, s_axi_bvalid => ax_bvalid, s_axi_bready => ax_bready,
            s_axi_araddr => ax_araddr, s_axi_arlen => ax_arlen, s_axi_arsize => ax_arsize,
            s_axi_arburst => ax_arburst, s_axi_arvalid => ax_arvalid, s_axi_arready => ax_arready,
            s_axi_rdata => ax_rdata, s_axi_rresp => ax_rresp, s_axi_rlast => ax_rlast,
            s_axi_rvalid => ax_rvalid, s_axi_rready => ax_rready,
            m_axil_awaddr => cs_awaddr, m_axil_awvalid => cs_awvalid, m_axil_awready => cs_awready,
            m_axil_wdata => cs_wdata, m_axil_wstrb => cs_wstrb, m_axil_wvalid => cs_wvalid, m_axil_wready => cs_wready,
            m_axil_bresp => cs_bresp, m_axil_bvalid => cs_bvalid, m_axil_bready => cs_bready,
            m_axil_araddr => cs_araddr, m_axil_arvalid => cs_arvalid, m_axil_arready => cs_arready,
            m_axil_rdata => cs_rdata, m_axil_rresp => cs_rresp, m_axil_rvalid => cs_rvalid, m_axil_rready => cs_rready,
            m_axis_tdata => tx_tdata, m_axis_tvalid => tx_tvalid, m_axis_tready => tx_tready,
            m_axis_tlast => tx_tlast, m_axis_tuser => tx_tuser,
            s_axis_tdata => rx_tdata, s_axis_tvalid => rx_tvalid, s_axis_tready => rx_tready,
            s_axis_tlast => rx_tlast, s_axis_tuser => rx_tuser,
            link_running => link_running, selftest_pass => selftest_pass,
            selftest_done => selftest_done, bringup_done => bringup_done,
            inj_freeze => inj_freeze, inj_invert => inj_invert);

    u_ejtagaxi: fcapz_ejtagaxi_xilinx7
        generic map (
            ADDR_W => 32, DATA_W => 32, FIFO_DEPTH => 16,
            CMD_FIFO_DEPTH => 16, RESP_FIFO_DEPTH => 16,
            CMD_FIFO_MEMORY_TYPE => "distributed", TIMEOUT => 4096, DEBUG_EN => 0)
        port map (
            axi_clk => clk, axi_rst => rst,
            m_axi_awaddr => ax_awaddr, m_axi_awlen => ax_awlen,
            m_axi_awsize => ax_awsize, m_axi_awburst => ax_awburst,
            m_axi_awvalid => ax_awvalid, m_axi_awready => ax_awready,
            m_axi_awprot => ax_awprot,
            m_axi_wdata => ax_wdata, m_axi_wstrb => ax_wstrb,
            m_axi_wvalid => ax_wvalid, m_axi_wready => ax_wready, m_axi_wlast => ax_wlast,
            m_axi_bresp => ax_bresp, m_axi_bvalid => ax_bvalid, m_axi_bready => ax_bready,
            m_axi_araddr => ax_araddr, m_axi_arlen => ax_arlen,
            m_axi_arsize => ax_arsize, m_axi_arburst => ax_arburst,
            m_axi_arvalid => ax_arvalid, m_axi_arready => ax_arready,
            m_axi_arprot => ax_arprot,
            m_axi_rdata => ax_rdata, m_axi_rresp => ax_rresp,
            m_axi_rvalid => ax_rvalid, m_axi_rready => ax_rready, m_axi_rlast => ax_rlast);

    ela0_probe <= spw_do & spw_so & spw_di & spw_si &
                  bringup_done & link_running & selftest_done & selftest_pass;
    ela1_probe <= rx_tdata;
    eio0_pin   <= '0' & link_running & selftest_done & selftest_pass &
                  "00" & bringup_done & (selftest_done or selftest_pass);
    eio1_pin   <= btn & eio0_pout(3 downto 0);
    ela_trig_in <= '0' & eio0_pout(4);

    u_debug: fcapz_debug_multi_xilinx7
        generic map (
            NUM_ELAS => 2, EIO_EN => 1, NUM_EIOS => 2,
            SAMPLE_W => 8, DEPTH => 1024, INPUT_PIPE => 1,
            DECIM_EN => 1, EXT_TRIG_EN => 1, TIMESTAMP_W => 32,
            NUM_SEGMENTS => 4, STARTUP_ARM => 1, DEFAULT_TRIG_EXT => 2,
            EIO_IN_W => 8, EIO_OUT_W => 8)
        port map (
            ela_sample_clk  => (clk, clk),
            ela_sample_rst  => (rst, rst),
            ela_probe_in    => ela1_probe & ela0_probe,
            ela_trigger_in  => ela_trig_in,
            ela_trigger_out => ela_trig_out,
            ela_armed_out   => ela_armed,
            eio_probe_in    => eio1_pin & eio0_pin,
            eio_probe_out   => eio_pout_all);

    eio0_pout <= eio_pout_all(7 downto 0);
    eio1_pout <= eio_pout_all(15 downto 8);

    led(0) <= bringup_done;
    led(1) <= link_running;
    led(2) <= selftest_done;
    led(3) <= selftest_pass;

end architecture rtl;
