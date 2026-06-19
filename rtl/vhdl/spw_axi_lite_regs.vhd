--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- AXI4-Lite control and status registers for SpaceWire Reloaded.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spw_axi_lite_regs is
    generic (
        ADDR_WIDTH: integer := 8;
        CORE_ID:    std_logic_vector(31 downto 0) := x"53505752";
        VERSION:    std_logic_vector(31 downto 0) := x"00010000"
    );
    port (
        clk:            in  std_logic;
        rst:            in  std_logic;

        s_axi_awaddr:   in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        s_axi_awvalid:  in  std_logic;
        s_axi_awready:  out std_logic;
        s_axi_wdata:    in  std_logic_vector(31 downto 0);
        s_axi_wstrb:    in  std_logic_vector(3 downto 0);
        s_axi_wvalid:   in  std_logic;
        s_axi_wready:   out std_logic;
        s_axi_bresp:    out std_logic_vector(1 downto 0);
        s_axi_bvalid:   out std_logic;
        s_axi_bready:   in  std_logic;
        s_axi_araddr:   in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        s_axi_arvalid:  in  std_logic;
        s_axi_arready:  out std_logic;
        s_axi_rdata:    out std_logic_vector(31 downto 0);
        s_axi_rresp:    out std_logic_vector(1 downto 0);
        s_axi_rvalid:   out std_logic;
        s_axi_rready:   in  std_logic;

        core_rst:       out std_logic;
        autostart:      out std_logic;
        linkstart:      out std_logic;
        linkdis:        out std_logic;
        txdivcnt:       out std_logic_vector(7 downto 0);

        tick_in:        out std_logic;
        ctrl_in:        out std_logic_vector(1 downto 0);
        time_in:        out std_logic_vector(5 downto 0);

        tick_out:       in  std_logic;
        ctrl_out:       in  std_logic_vector(1 downto 0);
        time_out:       in  std_logic_vector(5 downto 0);

        txrdy:          in  std_logic;
        txhalff:        in  std_logic;
        rxvalid:        in  std_logic;
        rxhalff:        in  std_logic;
        started:        in  std_logic;
        connecting:     in  std_logic;
        running:        in  std_logic;
        errdisc:        in  std_logic;
        errpar:         in  std_logic;
        erresc:         in  std_logic;
        errcred:        in  std_logic;

        irq:            out std_logic
    );
end entity spw_axi_lite_regs;

architecture rtl of spw_axi_lite_regs is

    constant REG_CORE_ID:     integer := 0;
    constant REG_VERSION:     integer := 1;
    constant REG_CONTROL:     integer := 2;
    constant REG_STATUS:      integer := 3;
    constant REG_TXDIVCNT:    integer := 4;
    constant REG_TIMECODE_TX: integer := 5;
    constant REG_TIMECODE_RX: integer := 6;
    constant REG_ERROR:       integer := 7;
    constant REG_IRQ_ENABLE:  integer := 8;
    constant REG_IRQ_STATUS:  integer := 9;

    signal awaddr_r:      std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal aw_holding_r:  std_logic := '0';
    signal wdata_r:       std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb_r:       std_logic_vector(3 downto 0) := (others => '0');
    signal w_holding_r:   std_logic := '0';
    signal bvalid_r:      std_logic := '0';
    signal rdata_r:       std_logic_vector(31 downto 0) := (others => '0');
    signal rvalid_r:      std_logic := '0';
    signal awready_s:     std_logic;
    signal wready_s:      std_logic;
    signal arready_s:     std_logic;

    signal control_r:     std_logic_vector(31 downto 0) := (others => '0');
    signal txdivcnt_r:    std_logic_vector(7 downto 0) := (others => '0');
    signal tick_pulse_r:  std_logic := '0';
    signal tick_ctrl_r:   std_logic_vector(1 downto 0) := (others => '0');
    signal tick_time_r:   std_logic_vector(5 downto 0) := (others => '0');
    signal rx_tick_valid_r: std_logic := '0';
    signal rx_tick_ctrl_r:  std_logic_vector(1 downto 0) := (others => '0');
    signal rx_tick_time_r:  std_logic_vector(5 downto 0) := (others => '0');
    signal error_r:       std_logic_vector(3 downto 0) := (others => '0');
    signal irq_enable_r:  std_logic_vector(31 downto 0) := (others => '0');
    signal irq_status_s:  std_logic_vector(31 downto 0);

    function apply_wstrb(
        old_value: std_logic_vector(31 downto 0);
        new_value: std_logic_vector(31 downto 0);
        wstrb:     std_logic_vector(3 downto 0))
        return std_logic_vector is
        variable merged: std_logic_vector(31 downto 0);
    begin
        merged := old_value;
        for i in 0 to 3 loop
            if wstrb(i) = '1' then
                merged((8*i)+7 downto 8*i) := new_value((8*i)+7 downto 8*i);
            end if;
        end loop;
        return merged;
    end function;

    function any_set(value: std_logic_vector) return std_logic is
        variable result: std_logic := '0';
    begin
        for i in value'range loop
            result := result or value(i);
        end loop;
        return result;
    end function;

    function reg_index(addr: std_logic_vector) return integer is
    begin
        return to_integer(unsigned(addr(5 downto 2)));
    end function;

    -- The register file occupies the low 64-byte (16-word) aperture. Any access
    -- with an address bit above [5] set is unmapped: it must read as zero and
    -- ignore writes, not alias the low bank. The upper bits are tested directly
    -- (not via to_integer, which would overflow the 32-bit VHDL integer range for
    -- wide AXI address widths when software probes a high address).
    function addr_in_range(addr: std_logic_vector) return boolean is
    begin
        if addr'length <= 6 then
            return true;
        else
            return unsigned(addr(addr'high downto 6)) = 0;
        end if;
    end function;

    function status_word(
        txrdy_i:      std_logic;
        txhalff_i:    std_logic;
        rxvalid_i:    std_logic;
        rxhalff_i:    std_logic;
        started_i:    std_logic;
        connecting_i: std_logic;
        running_i:    std_logic;
        errors_i:     std_logic_vector(3 downto 0);
        tick_valid_i: std_logic)
        return std_logic_vector is
        variable value: std_logic_vector(31 downto 0);
    begin
        value := (others => '0');
        value(0) := started_i;
        value(1) := connecting_i;
        value(2) := running_i;
        value(3) := txrdy_i;
        value(4) := txhalff_i;
        value(5) := rxvalid_i;
        value(6) := rxhalff_i;
        value(7) := tick_valid_i;
        value(11 downto 8) := errors_i;
        return value;
    end function;

    function rx_timecode_word(
        valid_i: std_logic;
        ctrl_i:  std_logic_vector(1 downto 0);
        time_i:  std_logic_vector(5 downto 0))
        return std_logic_vector is
        variable value: std_logic_vector(31 downto 0);
    begin
        value := (others => '0');
        value(31) := valid_i;
        value(7 downto 6) := ctrl_i;
        value(5 downto 0) := time_i;
        return value;
    end function;

begin

    -- The 64-byte register aperture needs at least address bits [5:0].
    assert ADDR_WIDTH >= 6
        report "spw_axi_lite_regs: ADDR_WIDTH must be >= 6 for the 64-byte register aperture"
        severity failure;

    awready_s <= (not aw_holding_r) and (not bvalid_r);
    wready_s  <= (not w_holding_r) and (not bvalid_r);
    arready_s <= not rvalid_r;

    s_axi_awready <= awready_s;
    s_axi_wready  <= wready_s;
    s_axi_bresp   <= "00";
    s_axi_bvalid  <= bvalid_r;

    s_axi_arready <= arready_s;
    s_axi_rdata   <= rdata_r;
    s_axi_rresp   <= "00";
    s_axi_rvalid  <= rvalid_r;

    core_rst  <= control_r(0);
    autostart <= control_r(1);
    linkstart <= control_r(2);
    linkdis   <= control_r(3);
    txdivcnt  <= txdivcnt_r;

    tick_in <= tick_pulse_r;
    ctrl_in <= tick_ctrl_r;
    time_in <= tick_time_r;

    irq_status_s(0) <= any_set(error_r);
    irq_status_s(1) <= rx_tick_valid_r;
    irq_status_s(2) <= rxvalid;
    irq_status_s(3) <= txrdy;
    irq_status_s(4) <= started or connecting or running;
    irq_status_s(31 downto 5) <= (others => '0');
    irq <= any_set(irq_status_s and irq_enable_r);

    process (clk) is
        variable write_addr: std_logic_vector(ADDR_WIDTH-1 downto 0);
        variable write_data: std_logic_vector(31 downto 0);
        variable write_strb: std_logic_vector(3 downto 0);
        variable read_data:  std_logic_vector(31 downto 0);
        variable write_fire: std_logic;
        variable error_inputs: std_logic_vector(3 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                awaddr_r        <= (others => '0');
                aw_holding_r    <= '0';
                wdata_r         <= (others => '0');
                wstrb_r         <= (others => '0');
                w_holding_r     <= '0';
                bvalid_r        <= '0';
                rdata_r         <= (others => '0');
                rvalid_r        <= '0';
                control_r       <= (others => '0');
                txdivcnt_r      <= (others => '0');
                tick_pulse_r    <= '0';
                tick_ctrl_r     <= (others => '0');
                tick_time_r     <= (others => '0');
                rx_tick_valid_r <= '0';
                rx_tick_ctrl_r  <= (others => '0');
                rx_tick_time_r  <= (others => '0');
                error_r         <= (others => '0');
                irq_enable_r    <= (others => '0');
            else
                tick_pulse_r <= '0';
                error_inputs := errcred & erresc & errpar & errdisc;

                error_r <= error_r or error_inputs;

                if tick_out = '1' then
                    rx_tick_valid_r <= '1';
                    rx_tick_ctrl_r  <= ctrl_out;
                    rx_tick_time_r  <= time_out;
                end if;

                if bvalid_r = '1' and s_axi_bready = '1' then
                    bvalid_r <= '0';
                end if;

                if awready_s = '1' and s_axi_awvalid = '1' then
                    awaddr_r     <= s_axi_awaddr;
                    aw_holding_r <= '1';
                end if;

                if wready_s = '1' and s_axi_wvalid = '1' then
                    wdata_r     <= s_axi_wdata;
                    wstrb_r     <= s_axi_wstrb;
                    w_holding_r <= '1';
                end if;

                write_fire := '0';
                if bvalid_r = '0' then
                    if ((aw_holding_r = '1') or ((awready_s = '1') and (s_axi_awvalid = '1'))) and
                       ((w_holding_r = '1') or ((wready_s = '1') and (s_axi_wvalid = '1'))) then
                        write_fire := '1';
                    end if;
                end if;

                if write_fire = '1' then
                    if aw_holding_r = '1' then
                        write_addr := awaddr_r;
                    else
                        write_addr := s_axi_awaddr;
                    end if;

                    if w_holding_r = '1' then
                        write_data := wdata_r;
                        write_strb := wstrb_r;
                    else
                        write_data := s_axi_wdata;
                        write_strb := s_axi_wstrb;
                    end if;

                    if addr_in_range(write_addr) then
                    case reg_index(write_addr) is
                        when REG_CONTROL =>
                            control_r <= apply_wstrb(control_r, write_data, write_strb);
                        when REG_TXDIVCNT =>
                            if write_strb(0) = '1' then
                                txdivcnt_r <= write_data(7 downto 0);
                            end if;
                        when REG_TIMECODE_TX =>
                            if write_strb(0) = '1' then
                                tick_time_r <= write_data(5 downto 0);
                                tick_ctrl_r <= write_data(7 downto 6);
                            end if;
                            if write_strb(3) = '1' and write_data(31) = '1' then
                                tick_pulse_r <= '1';
                            end if;
                        when REG_TIMECODE_RX =>
                            if write_strb(3) = '1' and write_data(31) = '1' then
                                rx_tick_valid_r <= tick_out;
                            end if;
                        when REG_ERROR =>
                            if write_strb(0) = '1' then
                                error_r <= (error_r and not write_data(3 downto 0)) or error_inputs;
                            end if;
                        when REG_IRQ_ENABLE =>
                            irq_enable_r <= apply_wstrb(irq_enable_r, write_data, write_strb);
                        when REG_IRQ_STATUS =>
                            if write_strb(0) = '1' and write_data(0) = '1' then
                                error_r <= error_inputs;
                            end if;
                            if write_strb(0) = '1' and write_data(1) = '1' then
                                rx_tick_valid_r <= tick_out;
                            end if;
                        when others =>
                            null;
                    end case;
                    end if;

                    aw_holding_r <= '0';
                    w_holding_r  <= '0';
                    bvalid_r     <= '1';
                end if;

                if rvalid_r = '1' and s_axi_rready = '1' then
                    rvalid_r <= '0';
                end if;

                if arready_s = '1' and s_axi_arvalid = '1' then
                    read_data := (others => '0');
                    if addr_in_range(s_axi_araddr) then
                    case reg_index(s_axi_araddr) is
                        when REG_CORE_ID =>
                            read_data := CORE_ID;
                        when REG_VERSION =>
                            read_data := VERSION;
                        when REG_CONTROL =>
                            read_data := control_r;
                        when REG_STATUS =>
                            read_data := status_word(txrdy, txhalff, rxvalid, rxhalff, started, connecting, running, error_r, rx_tick_valid_r);
                        when REG_TXDIVCNT =>
                            read_data(7 downto 0) := txdivcnt_r;
                        when REG_TIMECODE_RX =>
                            read_data := rx_timecode_word(rx_tick_valid_r, rx_tick_ctrl_r, rx_tick_time_r);
                        when REG_ERROR =>
                            read_data(3 downto 0) := error_r;
                        when REG_IRQ_ENABLE =>
                            read_data := irq_enable_r;
                        when REG_IRQ_STATUS =>
                            read_data := irq_status_s;
                        when others =>
                            read_data := (others => '0');
                    end case;
                    end if;

                    rdata_r  <= read_data;
                    rvalid_r <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
