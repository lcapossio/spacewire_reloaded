--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.spwpkg.all;

entity spw_axi_top_loop_tb is
    generic (
        SYS_CLOCK_HZ:     integer := 10000000;
        RX_CLOCK_HZ:      integer := 10000000;
        TX_CLOCK_HZ:      integer := 10000000;
        RXIMPL_SELECT:    integer := 0;
        TXIMPL_SELECT:    integer := 0;
        RXCHUNK_VALUE:    integer := 1;
        LOOPBACK_ENABLE:  integer := 1;
        RXFIFOSIZE_BITS:  integer := 6;
        TXFIFOSIZE_BITS:  integer := 4
    );
    port (
        clk:            in  std_logic;
        rxclk:          in  std_logic;
        txclk:          in  std_logic;
        rst:            in  std_logic;

        s_axi_awaddr:   in  std_logic_vector(7 downto 0);
        s_axi_awvalid:  in  std_logic;
        s_axi_awready:  out std_logic;
        s_axi_wdata:    in  std_logic_vector(31 downto 0);
        s_axi_wstrb:    in  std_logic_vector(3 downto 0);
        s_axi_wvalid:   in  std_logic;
        s_axi_wready:   out std_logic;
        s_axi_bresp:    out std_logic_vector(1 downto 0);
        s_axi_bvalid:   out std_logic;
        s_axi_bready:   in  std_logic;
        s_axi_araddr:   in  std_logic_vector(7 downto 0);
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

        spw_di_ext:     in  std_logic;
        spw_si_ext:     in  std_logic;
        spw_do:         out std_logic;
        spw_so:         out std_logic
    );
end entity spw_axi_top_loop_tb;

architecture tb of spw_axi_top_loop_tb is
    signal spw_di_in: std_logic;
    signal spw_si_in: std_logic;
    signal spw_do_int: std_logic;
    signal spw_so_int: std_logic;

    function to_impl(value: integer) return spw_implementation_type is
    begin
        if value = 0 then
            return impl_generic;
        end if;
        return impl_fast;
    end function;
begin
    spw_di_in <= spw_do_int when LOOPBACK_ENABLE /= 0 else spw_di_ext;
    spw_si_in <= spw_so_int when LOOPBACK_ENABLE /= 0 else spw_si_ext;
    spw_do <= spw_do_int;
    spw_so <= spw_so_int;

    dut_inst: entity work.spw_axi_top
        generic map (
            sysfreq          => real(SYS_CLOCK_HZ),
            txclkfreq        => real(TX_CLOCK_HZ),
            rximpl           => to_impl(RXIMPL_SELECT),
            rxchunk          => RXCHUNK_VALUE,
            tximpl           => to_impl(TXIMPL_SELECT),
            rxfifosize_bits  => RXFIFOSIZE_BITS,
            txfifosize_bits  => TXFIFOSIZE_BITS,
            AXI_ADDR_WIDTH   => 8 )
        port map (
            clk            => clk,
            rxclk          => rxclk,
            txclk          => txclk,
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
            s_axis_tdata   => s_axis_tdata,
            s_axis_tvalid  => s_axis_tvalid,
            s_axis_tready  => s_axis_tready,
            s_axis_tlast   => s_axis_tlast,
            s_axis_tuser   => s_axis_tuser,
            m_axis_tdata   => m_axis_tdata,
            m_axis_tvalid  => m_axis_tvalid,
            m_axis_tready  => m_axis_tready,
            m_axis_tlast   => m_axis_tlast,
            m_axis_tuser   => m_axis_tuser,
            irq            => irq,
            spw_di         => spw_di_in,
            spw_si         => spw_si_in,
            spw_do         => spw_do_int,
            spw_so         => spw_so_int );

end architecture tb;
