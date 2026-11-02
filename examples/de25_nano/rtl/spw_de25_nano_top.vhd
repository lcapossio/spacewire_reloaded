--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- SpaceWire Reloaded - Terasic DE25-Nano (Intel Agilex 5 E-series) loopback
-- hardware-validation top-level (VHDL). Functional mirror of
-- rtl/spw_de25_nano_top.v: the VHDL spw_axi_top + spw_loopback_axi run in
-- internal loopback, self-test with no host, and show status on the LEDs; with
-- a host, the fpgacapZero JTAG cores give the same access as on the Arty board.
--
-- The vendor-specific pieces are declared here as components: the
-- configuration reset release (de25_reset_release) and the fcapz JTAG debug
-- cores (de25_debug). Quartus binds them to the Verilog wrappers in rtl/intel/
-- (mixed-language); simulation binds them to the behavioral stubs
-- tb/de25_reset_release_sim.vhd and tb/de25_debug_sim.vhd.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spwpkg.all;

entity spw_de25_nano_top is
    generic (
        -- Board oscillator frequency (Hz); DE25-Nano provides 50 MHz clocks.
        -- Keep in sync with de25_nano.sdc.
        SYS_CLOCK_HZ: integer := 50000000;
        -- RX/TX front-end: 0 = generic (single clock domain).
        RXIMPL:   integer := 0;
        TXIMPL:   integer := 0;
        RXCHUNK:  integer := 1;
        -- SpaceWire run-state TX divider: bit rate = clk/(LINK_TXDIVCNT+1).
        -- 4 -> 10 Mbit/s at 50 MHz.
        LINK_TXDIVCNT: integer := 4;
        -- DE25-Nano push-buttons (KEY) read 0 when pressed.
        RST_ACTIVE_LOW: integer := 1;
        -- DE25-Nano LEDs light when the pin is driven low.
        LED_ACTIVE_LOW: integer := 1
    );
    port (
        clk: in  std_logic;                     -- CLOCK1_50, 50 MHz
        btn: in  std_logic_vector(1 downto 0);  -- btn(0)=KEY0 reset, btn(1)=KEY1
        led: out std_logic_vector(3 downto 0)   -- LEDR[3:0]
    );
end entity spw_de25_nano_top;

architecture rtl of spw_de25_nano_top is

    component de25_reset_release is
        port ( ninit_done : out std_logic );
    end component;

    -- fcapz JTAG debug wrapper (ELA probe 16 bits, EIO 8 in / 8 out).
    component de25_debug is
        port (
            clk, rst       : in  std_logic;
            m_axi_awaddr   : out std_logic_vector(31 downto 0);
            m_axi_awlen    : out std_logic_vector(7 downto 0);
            m_axi_awsize   : out std_logic_vector(2 downto 0);
            m_axi_awburst  : out std_logic_vector(1 downto 0);
            m_axi_awvalid  : out std_logic;
            m_axi_awready  : in  std_logic;
            m_axi_wdata    : out std_logic_vector(31 downto 0);
            m_axi_wstrb    : out std_logic_vector(3 downto 0);
            m_axi_wlast    : out std_logic;
            m_axi_wvalid   : out std_logic;
            m_axi_wready   : in  std_logic;
            m_axi_bresp    : in  std_logic_vector(1 downto 0);
            m_axi_bvalid   : in  std_logic;
            m_axi_bready   : out std_logic;
            m_axi_araddr   : out std_logic_vector(31 downto 0);
            m_axi_arlen    : out std_logic_vector(7 downto 0);
            m_axi_arsize   : out std_logic_vector(2 downto 0);
            m_axi_arburst  : out std_logic_vector(1 downto 0);
            m_axi_arvalid  : out std_logic;
            m_axi_arready  : in  std_logic;
            m_axi_rdata    : in  std_logic_vector(31 downto 0);
            m_axi_rresp    : in  std_logic_vector(1 downto 0);
            m_axi_rlast    : in  std_logic;
            m_axi_rvalid   : in  std_logic;
            m_axi_rready   : out std_logic;
            ela_probe      : in  std_logic_vector(15 downto 0);
            ela_trigger_in : in  std_logic;
            eio_in         : in  std_logic_vector(7 downto 0);
            eio_out        : out std_logic_vector(7 downto 0));
    end component;

    function impl_of(n: integer) return spw_implementation_type is
    begin
        if n = 1 then return impl_fast; else return impl_generic; end if;
    end function;

    constant RX_IMPL_T : spw_implementation_type := impl_of(RXIMPL);
    constant TX_IMPL_T : spw_implementation_type := impl_of(TXIMPL);
    constant SYSFREQ   : real := real(SYS_CLOCK_HZ);

    -- reset
    signal ninit_done : std_logic;
    signal por_sr     : std_logic_vector(3 downto 0) := (others => '1');
    signal btn0_raw   : std_logic;
    signal btn0_meta  : std_logic := '1';
    signal btn0_sync  : std_logic := '1';
    signal init_meta  : std_logic := '1';
    signal init_sync  : std_logic := '1';
    signal rst        : std_logic;

    signal spw_do, spw_so, spw_di, spw_si : std_logic;
    signal spw_do_tx, spw_so_tx : std_logic;
    signal spw_irq : std_logic;

    -- JTAG bridge (de25_debug) <-> engine AXI4 host slave
    signal ax_awaddr, ax_wdata, ax_araddr, ax_rdata : std_logic_vector(31 downto 0);
    signal ax_awlen, ax_arlen : std_logic_vector(7 downto 0);
    signal ax_awsize, ax_arsize : std_logic_vector(2 downto 0);
    signal ax_awburst, ax_arburst, ax_bresp, ax_rresp : std_logic_vector(1 downto 0);
    signal ax_wstrb : std_logic_vector(3 downto 0);
    signal ax_awvalid, ax_awready, ax_wvalid, ax_wready, ax_wlast : std_logic;
    signal ax_bvalid, ax_bready : std_logic;
    signal ax_arvalid, ax_arready, ax_rvalid, ax_rready, ax_rlast : std_logic;

    -- debug probes
    signal key_pressed : std_logic_vector(1 downto 0);
    signal eio_in, eio_out : std_logic_vector(7 downto 0);
    signal ela_probe : std_logic_vector(15 downto 0);

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
    signal inj_freeze, inj_invert : std_logic;  -- from the engine ERRINJ register
    signal led_status : std_logic_vector(3 downto 0);

begin

    -- ---- reset: configuration reset release + power-on pulse + KEY0 ----
    u_reset_release: de25_reset_release port map (ninit_done => ninit_done);

    btn0_raw <= not btn(0) when RST_ACTIVE_LOW /= 0 else btn(0);

    process (clk) is
    begin
        if rising_edge(clk) then
            por_sr    <= por_sr(2 downto 0) & '0';
            btn0_meta <= btn0_raw;
            btn0_sync <= btn0_meta;
            init_meta <= ninit_done;
            init_sync <= init_meta;
        end if;
    end process;

    rst <= por_sr(3) or btn0_sync or init_sync;

    -- ---- internal loopback, with transmit-side error injection ----
    --   inj_freeze -> hold D/S static; inj_invert -> invert the outgoing D.
    spw_do_tx <= '0' when inj_freeze = '1' else (spw_do xor inj_invert);
    spw_so_tx <= '0' when inj_freeze = '1' else spw_so;
    spw_di <= spw_do_tx;
    spw_si <= spw_so_tx;

    u_spw: entity work.spw_axi_top
        generic map (
            sysfreq => SYSFREQ, txclkfreq => SYSFREQ,
            rximpl => RX_IMPL_T, rxchunk => RXCHUNK, tximpl => TX_IMPL_T,
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
            EXAMPLE_ID => x"5350574C", EXAMPLE_VER => x"00010048", -- low byte 'H' = VHDL build
            LINK_TXDIVCNT => std_logic_vector(to_unsigned(LINK_TXDIVCNT, 8)),
            SELFTEST_LEN => 16)
        port map (
            clk => clk, rst => rst,
            s_axi_awaddr => ax_awaddr, s_axi_awlen => ax_awlen,
            s_axi_awsize => ax_awsize, s_axi_awburst => ax_awburst,
            s_axi_awvalid => ax_awvalid, s_axi_awready => ax_awready,
            s_axi_wdata => ax_wdata, s_axi_wstrb => ax_wstrb,
            s_axi_wlast => ax_wlast, s_axi_wvalid => ax_wvalid, s_axi_wready => ax_wready,
            s_axi_bresp => ax_bresp, s_axi_bvalid => ax_bvalid, s_axi_bready => ax_bready,
            s_axi_araddr => ax_araddr, s_axi_arlen => ax_arlen,
            s_axi_arsize => ax_arsize, s_axi_arburst => ax_arburst,
            s_axi_arvalid => ax_arvalid, s_axi_arready => ax_arready,
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

    -- ---- JTAG debug (same probe map as the Verilog top) ----
    key_pressed <= not btn when RST_ACTIVE_LOW /= 0 else btn;
    eio_in <= "00" & key_pressed & selftest_pass & selftest_done & bringup_done & link_running;
    ela_probe <= rx_tdata & spw_do_tx & spw_so_tx & spw_di & spw_si
                 & bringup_done & link_running & selftest_done & selftest_pass;

    u_debug: de25_debug
        port map (
            clk => clk, rst => rst,
            m_axi_awaddr => ax_awaddr, m_axi_awlen => ax_awlen, m_axi_awsize => ax_awsize,
            m_axi_awburst => ax_awburst, m_axi_awvalid => ax_awvalid, m_axi_awready => ax_awready,
            m_axi_wdata => ax_wdata, m_axi_wstrb => ax_wstrb, m_axi_wlast => ax_wlast,
            m_axi_wvalid => ax_wvalid, m_axi_wready => ax_wready,
            m_axi_bresp => ax_bresp, m_axi_bvalid => ax_bvalid, m_axi_bready => ax_bready,
            m_axi_araddr => ax_araddr, m_axi_arlen => ax_arlen, m_axi_arsize => ax_arsize,
            m_axi_arburst => ax_arburst, m_axi_arvalid => ax_arvalid, m_axi_arready => ax_arready,
            m_axi_rdata => ax_rdata, m_axi_rresp => ax_rresp, m_axi_rlast => ax_rlast,
            m_axi_rvalid => ax_rvalid, m_axi_rready => ax_rready,
            ela_probe => ela_probe, ela_trigger_in => eio_out(4),
            eio_in => eio_in, eio_out => eio_out);

    -- ---- LEDs: standalone status (DE25-Nano LEDs are active-low) ----
    led_status <= selftest_pass & selftest_done & link_running & bringup_done;
    led <= not led_status when LED_ACTIVE_LOW /= 0 else led_status;

end architecture rtl;
