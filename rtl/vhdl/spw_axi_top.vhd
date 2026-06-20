--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- SpaceWire Reloaded AXI top-level wrapper.
--

library ieee;
use ieee.std_logic_1164.all;
use work.spwpkg.all;

entity spw_axi_top is
    generic (
        sysfreq:          real;
        txclkfreq:        real := 0.0;
        rximpl:           spw_implementation_type := impl_generic;
        rxchunk:          integer range 1 to 4 := 1;
        tximpl:           spw_implementation_type := impl_generic;
        rxfifosize_bits:  integer range 6 to 14 := 11;
        txfifosize_bits:  integer range 2 to 14 := 11;
        strict_timecodes: integer range 0 to 1 := 0;
        AXI_ADDR_WIDTH:   integer := 8;
        CORE_ID:          std_logic_vector(31 downto 0) := x"53505752";
        VERSION:          std_logic_vector(31 downto 0) := x"00010000"
    );
    port (
        clk:            in  std_logic;
        rxclk:          in  std_logic;
        txclk:          in  std_logic;
        rst:            in  std_logic;

        s_axi_awaddr:   in  std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
        s_axi_awvalid:  in  std_logic;
        s_axi_awready:  out std_logic;
        s_axi_wdata:    in  std_logic_vector(31 downto 0);
        s_axi_wstrb:    in  std_logic_vector(3 downto 0);
        s_axi_wvalid:   in  std_logic;
        s_axi_wready:   out std_logic;
        s_axi_bresp:    out std_logic_vector(1 downto 0);
        s_axi_bvalid:   out std_logic;
        s_axi_bready:   in  std_logic;
        s_axi_araddr:   in  std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
        s_axi_arvalid:  in  std_logic;
        s_axi_arready:  out std_logic;
        s_axi_rdata:    out std_logic_vector(31 downto 0);
        s_axi_rresp:    out std_logic_vector(1 downto 0);
        s_axi_rvalid:   out std_logic;
        s_axi_rready:   in  std_logic;

        s_axis_tdata:   in  std_logic_vector(7 downto 0);
        s_axis_tvalid:  in  std_logic;
        s_axis_tready:  out std_logic;
        s_axis_tlast:   in  std_logic;
        s_axis_tuser:   in  std_logic_vector(0 downto 0);

        m_axis_tdata:   out std_logic_vector(7 downto 0);
        m_axis_tvalid:  out std_logic;
        m_axis_tready:  in  std_logic;
        m_axis_tlast:   out std_logic;
        m_axis_tuser:   out std_logic_vector(0 downto 0);

        irq:            out std_logic;

        spw_di:         in  std_logic;
        spw_si:         in  std_logic;
        spw_do:         out std_logic;
        spw_so:         out std_logic
    );
end entity spw_axi_top;

architecture rtl of spw_axi_top is
    signal soft_rst:    std_logic;
    signal core_rst:    std_logic;
    signal autostart:   std_logic;
    signal linkstart:   std_logic;
    signal linkdis:     std_logic;
    signal txdivcnt:    std_logic_vector(7 downto 0);
    signal tick_in:     std_logic;
    signal ctrl_in:     std_logic_vector(1 downto 0);
    signal time_in:     std_logic_vector(5 downto 0);
    signal txwrite:     std_logic;
    signal txflag:      std_logic;
    signal txdata:      std_logic_vector(7 downto 0);
    signal txrdy:       std_logic;
    signal txhalff:     std_logic;
    signal tick_out:    std_logic;
    signal ctrl_out:    std_logic_vector(1 downto 0);
    signal time_out:    std_logic_vector(5 downto 0);
    signal rxvalid:     std_logic;
    signal rxhalff:     std_logic;
    signal rxflag:      std_logic;
    signal rxdata:      std_logic_vector(7 downto 0);
    signal rxread:      std_logic;
    signal started:     std_logic;
    signal connecting:  std_logic;
    signal running:     std_logic;
    signal errdisc:     std_logic;
    signal errpar:      std_logic;
    signal erresc:      std_logic;
    signal errcred:     std_logic;
begin

    core_rst <= rst or soft_rst;

    regs_inst: entity work.spw_axi_lite_regs
        generic map (
            ADDR_WIDTH => AXI_ADDR_WIDTH,
            CORE_ID    => CORE_ID,
            VERSION    => VERSION )
        port map (
            clk            => clk,
            rst            => rst,
            s_axi_awaddr   => s_axi_awaddr,
            s_axi_awvalid  => s_axi_awvalid,
            s_axi_awready  => s_axi_awready,
            s_axi_wdata    => s_axi_wdata,
            s_axi_wstrb    => s_axi_wstrb,
            s_axi_wvalid   => s_axi_wvalid,
            s_axi_wready   => s_axi_wready,
            s_axi_bresp    => s_axi_bresp,
            s_axi_bvalid   => s_axi_bvalid,
            s_axi_bready   => s_axi_bready,
            s_axi_araddr   => s_axi_araddr,
            s_axi_arvalid  => s_axi_arvalid,
            s_axi_arready  => s_axi_arready,
            s_axi_rdata    => s_axi_rdata,
            s_axi_rresp    => s_axi_rresp,
            s_axi_rvalid   => s_axi_rvalid,
            s_axi_rready   => s_axi_rready,
            core_rst       => soft_rst,
            autostart      => autostart,
            linkstart      => linkstart,
            linkdis        => linkdis,
            txdivcnt       => txdivcnt,
            tick_in        => tick_in,
            ctrl_in        => ctrl_in,
            time_in        => time_in,
            tick_out       => tick_out,
            ctrl_out       => ctrl_out,
            time_out       => time_out,
            txrdy          => txrdy,
            txhalff        => txhalff,
            rxvalid        => rxvalid,
            rxhalff        => rxhalff,
            started        => started,
            connecting     => connecting,
            running        => running,
            errdisc        => errdisc,
            errpar         => errpar,
            erresc         => erresc,
            errcred        => errcred,
            irq            => irq );

    axis_tx_inst: entity work.spw_axis_tx
        port map (
            clk            => clk,
            rst            => core_rst,
            s_axis_tdata   => s_axis_tdata,
            s_axis_tvalid  => s_axis_tvalid,
            s_axis_tready  => s_axis_tready,
            s_axis_tlast   => s_axis_tlast,
            s_axis_tuser   => s_axis_tuser,
            txwrite        => txwrite,
            txflag         => txflag,
            txdata         => txdata,
            txrdy          => txrdy );

    axis_rx_inst: entity work.spw_axis_rx
        port map (
            clk            => clk,
            rst            => core_rst,
            m_axis_tdata   => m_axis_tdata,
            m_axis_tvalid  => m_axis_tvalid,
            m_axis_tready  => m_axis_tready,
            m_axis_tlast   => m_axis_tlast,
            m_axis_tuser   => m_axis_tuser,
            rxvalid        => rxvalid,
            rxflag         => rxflag,
            rxdata         => rxdata,
            rxread         => rxread );

    core_inst: entity work.spwstream
        generic map (
            sysfreq          => sysfreq,
            txclkfreq        => txclkfreq,
            rximpl           => rximpl,
            rxchunk          => rxchunk,
            tximpl           => tximpl,
            rxfifosize_bits  => rxfifosize_bits,
            txfifosize_bits  => txfifosize_bits,
            strict_timecodes => strict_timecodes )
        port map (
            clk        => clk,
            rxclk      => rxclk,
            txclk      => txclk,
            rst        => core_rst,
            autostart  => autostart,
            linkstart  => linkstart,
            linkdis    => linkdis,
            txdivcnt   => txdivcnt,
            tick_in    => tick_in,
            ctrl_in    => ctrl_in,
            time_in    => time_in,
            txwrite    => txwrite,
            txflag     => txflag,
            txdata     => txdata,
            txrdy      => txrdy,
            txhalff    => txhalff,
            tick_out   => tick_out,
            ctrl_out   => ctrl_out,
            time_out   => time_out,
            rxvalid    => rxvalid,
            rxhalff    => rxhalff,
            rxflag     => rxflag,
            rxdata     => rxdata,
            rxread     => rxread,
            started    => started,
            connecting => connecting,
            running    => running,
            errdisc    => errdisc,
            errpar     => errpar,
            erresc     => erresc,
            errcred    => errcred,
            spw_di     => spw_di,
            spw_si     => spw_si,
            spw_do     => spw_do,
            spw_so     => spw_so );

end architecture rtl;
