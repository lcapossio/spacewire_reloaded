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
use work.spwpkg.all;

entity spw_arty_a7100t_top is
    generic (
        LOOPBACK_INTERNAL: integer := 1
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

    -- debug
    signal ela_trig_in  : std_logic_vector(1 downto 0);
    signal ela_trig_out : std_logic_vector(1 downto 0);
    signal ela_armed    : std_logic_vector(1 downto 0);
    signal eio0_pin, eio0_pout, eio1_pin, eio1_pout : std_logic_vector(7 downto 0);
    signal eio_pout_all : std_logic_vector(15 downto 0);
    signal ela0_probe, ela1_probe : std_logic_vector(7 downto 0);

begin

    -- ---- reset ----
    process (clk) is
    begin
        if rising_edge(clk) then
            por_sr    <= por_sr(2 downto 0) & '0';
            btn0_meta <= btn(0);
            btn0_sync <= btn0_meta;
        end if;
    end process;
    rst <= por_sr(3) or btn0_sync;

    -- ---- loopback select ----
    spw_di     <= spw_do when LOOPBACK_INTERNAL /= 0 else spw_di_pin;
    spw_si     <= spw_so when LOOPBACK_INTERNAL /= 0 else spw_si_pin;
    spw_do_pin <= spw_do;
    spw_so_pin <= spw_so;

    u_spw: entity work.spw_axi_top
        generic map (
            sysfreq => 100.0e6, txclkfreq => 0.0,
            rximpl => impl_generic, rxchunk => 1, tximpl => impl_generic,
            rxfifosize_bits => 11, txfifosize_bits => 11,
            AXI_ADDR_WIDTH => 8, CORE_ID => x"53505752", VERSION => x"00010000")
        port map (
            clk => clk, rxclk => clk, txclk => clk, rst => rst,
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
            EXAMPLE_ID => x"5350574C", EXAMPLE_VER => x"00010000",
            LINK_TXDIVCNT => x"09", SELFTEST_LEN => 16)
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
            selftest_done => selftest_done, bringup_done => bringup_done);

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
