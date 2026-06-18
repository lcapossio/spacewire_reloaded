--
-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Leonardo Capossio - bard0 design
-- Author: Leonardo Capossio - bard0 design - hello@bard0.com
--
-- SpaceWire loopback example engine (VHDL) for the Arty A7-100T fpgacapZero
-- design. Functional mirror of rtl/spw_loopback_axi.v; see that file for the
-- register map and behaviour description.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spw_loopback_axi is
    generic (
        EXAMPLE_ID:    std_logic_vector(31 downto 0) := x"5350574C"; -- "SPWL"
        EXAMPLE_VER:   std_logic_vector(31 downto 0) := x"00010000";
        LINK_TXDIVCNT: std_logic_vector(7 downto 0)  := x"09";
        SELFTEST_LEN:  integer := 16;
        SELFTEST_PKTS: integer := 4
    );
    port (
        clk: in std_logic;
        rst: in std_logic;

        -- AXI4 slave (from fpgacapZero EJTAG-AXI bridge)
        s_axi_awaddr:  in  std_logic_vector(31 downto 0);
        s_axi_awlen:   in  std_logic_vector(7 downto 0);
        s_axi_awsize:  in  std_logic_vector(2 downto 0);
        s_axi_awburst: in  std_logic_vector(1 downto 0);
        s_axi_awvalid: in  std_logic;
        s_axi_awready: out std_logic;
        s_axi_wdata:   in  std_logic_vector(31 downto 0);
        s_axi_wstrb:   in  std_logic_vector(3 downto 0);
        s_axi_wlast:   in  std_logic;
        s_axi_wvalid:  in  std_logic;
        s_axi_wready:  out std_logic;
        s_axi_bresp:   out std_logic_vector(1 downto 0);
        s_axi_bvalid:  out std_logic;
        s_axi_bready:  in  std_logic;
        s_axi_araddr:  in  std_logic_vector(31 downto 0);
        s_axi_arlen:   in  std_logic_vector(7 downto 0);
        s_axi_arsize:  in  std_logic_vector(2 downto 0);
        s_axi_arburst: in  std_logic_vector(1 downto 0);
        s_axi_arvalid: in  std_logic;
        s_axi_arready: out std_logic;
        s_axi_rdata:   out std_logic_vector(31 downto 0);
        s_axi_rresp:   out std_logic_vector(1 downto 0);
        s_axi_rlast:   out std_logic;
        s_axi_rvalid:  out std_logic;
        s_axi_rready:  in  std_logic;

        -- AXI4-Lite master (to spw_axi_top CSRs)
        m_axil_awaddr:  out std_logic_vector(7 downto 0);
        m_axil_awvalid: out std_logic;
        m_axil_awready: in  std_logic;
        m_axil_wdata:   out std_logic_vector(31 downto 0);
        m_axil_wstrb:   out std_logic_vector(3 downto 0);
        m_axil_wvalid:  out std_logic;
        m_axil_wready:  in  std_logic;
        m_axil_bresp:   in  std_logic_vector(1 downto 0);
        m_axil_bvalid:  in  std_logic;
        m_axil_bready:  out std_logic;
        m_axil_araddr:  out std_logic_vector(7 downto 0);
        m_axil_arvalid: out std_logic;
        m_axil_arready: in  std_logic;
        m_axil_rdata:   in  std_logic_vector(31 downto 0);
        m_axil_rresp:   in  std_logic_vector(1 downto 0);
        m_axil_rvalid:  in  std_logic;
        m_axil_rready:  out std_logic;

        -- AXI-Stream master: SpaceWire N-Char TX
        m_axis_tdata:  out std_logic_vector(7 downto 0);
        m_axis_tvalid: out std_logic;
        m_axis_tready: in  std_logic;
        m_axis_tlast:  out std_logic;
        m_axis_tuser:  out std_logic_vector(0 downto 0);

        -- AXI-Stream slave: SpaceWire N-Char RX
        s_axis_tdata:  in  std_logic_vector(7 downto 0);
        s_axis_tvalid: in  std_logic;
        s_axis_tready: out std_logic;
        s_axis_tlast:  in  std_logic;
        s_axis_tuser:  in  std_logic_vector(0 downto 0);

        -- Status sideband
        link_running:  out std_logic;
        selftest_pass: out std_logic;
        selftest_done: out std_logic;
        bringup_done:  out std_logic;

        -- Internal-loopback error injection (to the top's loopback mux)
        inj_freeze:    out std_logic;   -- hold looped-back D/S static -> disconnect
        inj_invert:    out std_logic    -- invert looped-back D -> parity/char error
    );
end entity spw_loopback_axi;

architecture rtl of spw_loopback_axi is

    constant SPW_REG_CORE_ID:     std_logic_vector(7 downto 0) := x"00";
    constant SPW_REG_CONTROL:     std_logic_vector(7 downto 0) := x"08";
    constant SPW_REG_STATUS:      std_logic_vector(7 downto 0) := x"0C";
    constant SPW_REG_TXDIVCNT:    std_logic_vector(7 downto 0) := x"10";
    constant SPW_REG_TIMECODE_TX: std_logic_vector(7 downto 0) := x"14";
    constant SPW_REG_TIMECODE_RX: std_logic_vector(7 downto 0) := x"18";
    constant SPW_REG_ERROR:       std_logic_vector(7 downto 0) := x"1C";

    type m_state_t is (M_RST, M_CRST_AW, M_CRST_B, M_CTRL_AW, M_CTRL_B,
                       M_DIV_AW, M_DIV_B, M_ID_AR, M_ID_R, M_STAT_AR, M_STAT_R,
                       M_CLR_AW, M_CLR_B,
                       M_TC_CLR_AW, M_TC_CLR_B, M_TC_TX_AW, M_TC_TX_B, M_TCRX_R);
    type t_state_t is (T_IDLE, T_DATA, T_EOP, T_DONE);
    type w_state_t is (W_IDLE, W_DATA, W_RESP);
    type r_state_t is (R_IDLE, R_DATA);

    signal mstate: m_state_t;
    signal tstate: t_state_t;
    signal wstate: w_state_t;
    signal rstate: r_state_t;

    -- AXI-Lite master regs
    signal awaddr_m:  std_logic_vector(7 downto 0);
    signal awvalid_m: std_logic;
    signal wdata_m:   std_logic_vector(31 downto 0);
    signal wvalid_m:  std_logic;
    signal bready_m:  std_logic;
    signal araddr_m:  std_logic_vector(7 downto 0);
    signal arvalid_m: std_logic;
    signal rready_m:  std_logic;
    signal spw_coreid_r: std_logic_vector(31 downto 0);
    signal spw_status_r: std_logic_vector(31 downto 0);
    signal bringup_done_r: std_logic;
    signal errclr_pending: std_logic;   -- clear sticky spw errors once link is up
    signal spw_tc_rx_r:    std_logic_vector(31 downto 0); -- mirror of TIMECODE_RX
    signal tc_send_value:  std_logic_vector(7 downto 0);  -- time-code to send
    signal tc_send_push:   std_logic;   -- 1-cycle pulse: host requested a send
    signal tc_send_pending: std_logic;  -- owned by master FSM: a send is queued

    -- example register file
    signal scratch_r:       std_logic_vector(31 downto 0);
    signal selftest_en_r:   std_logic;
    signal selftest_loop_r: std_logic;   -- continuous (free-running) self-check
    signal errinj_r: std_logic_vector(1 downto 0);  -- [0]=freeze [1]=invert D
    signal selftest_start_pulse: std_logic;
    signal soft_reset_pulse: std_logic;
    signal txcount_r:  unsigned(31 downto 0);
    signal rxcount_r:  unsigned(31 downto 0);
    signal errcount_r: unsigned(31 downto 0);
    signal selftest_busy_r: std_logic;
    signal selftest_done_r: std_logic;
    signal selftest_pass_r: std_logic;

    -- TX path / self-check
    signal tx_idx:  integer range 0 to 255;  -- PRBS byte index in current TX packet
    signal exp_idx: integer range 0 to 255;  -- PRBS byte index in current RX packet
    signal check_active: std_logic;
    signal tx_lfsr: std_logic_vector(7 downto 0);  -- PRBS generator (TX)
    signal rx_lfsr: std_logic_vector(7 downto 0);  -- PRBS checker (RX)
    signal tx_pkt:  natural;      -- packets transmitted this run (free-running in loop mode)
    signal rx_pkt:  natural;      -- packets received this run
    constant PRBS_SEED: std_logic_vector(7 downto 0) := x"FF";
    constant PRBS_POLY: std_logic_vector(7 downto 0) := x"B8"; -- maximal 8-bit LFSR

    function prbs_next(s: std_logic_vector(7 downto 0)) return std_logic_vector is
    begin
        if s(0) = '1' then
            return ('0' & s(7 downto 1)) xor PRBS_POLY;
        else
            return '0' & s(7 downto 1);
        end if;
    end function;
    signal m_axis_tdata_r:  std_logic_vector(7 downto 0);
    signal m_axis_tvalid_r: std_logic;
    signal m_axis_tlast_r:  std_logic;
    signal m_axis_tuser_r:  std_logic;
    signal s_axis_tready_r: std_logic;

    -- data-mover
    signal dm_tx_beat:    std_logic_vector(9 downto 0);
    signal dm_tx_pending: std_logic;
    signal dm_tx_push:    std_logic;

    -- RX FIFO
    constant RXFIFO_AW: integer := 6;
    type rxfifo_t is array(0 to (2**RXFIFO_AW)-1) of std_logic_vector(9 downto 0);
    signal rxfifo_mem:  rxfifo_t;
    signal rxfifo_wptr: unsigned(RXFIFO_AW downto 0);
    signal rxfifo_rptr: unsigned(RXFIFO_AW downto 0);
    signal rxfifo_push: std_logic;
    signal rxfifo_pop:  std_logic;
    signal rxfifo_wdata: std_logic_vector(9 downto 0);

    signal rxfifo_empty: std_logic;
    signal rxfifo_full:  std_logic;
    signal rxfifo_dout:  std_logic_vector(9 downto 0);

    -- AXI4 slave regs
    signal awready_s: std_logic;
    signal wready_s:  std_logic;
    signal bvalid_s:  std_logic;
    signal arready_s: std_logic;
    signal rdata_s:   std_logic_vector(31 downto 0);
    signal rlast_s:   std_logic;
    signal rvalid_s:  std_logic;
    signal w_addr:    std_logic_vector(31 downto 0);
    signal w_len:     unsigned(7 downto 0);
    signal r_addr:    std_logic_vector(31 downto 0);
    signal r_len:     unsigned(7 downto 0);

    signal link_running_i: std_logic;

    function status_word(
        spw_status: std_logic_vector(31 downto 0);
        bringup:    std_logic;
        rxne:       std_logic;
        txrdy:      std_logic;
        st_pass:    std_logic;
        st_done:    std_logic;
        st_busy:    std_logic;
        running:    std_logic) return std_logic_vector is
        variable v: std_logic_vector(31 downto 0);
    begin
        v := (others => '0');
        v(0) := running;
        v(1) := st_busy;
        v(2) := st_done;
        v(3) := st_pass;
        v(4) := txrdy;
        v(5) := rxne;
        v(6) := bringup;
        v(11 downto 8) := spw_status(11 downto 8);
        return v;
    end function;

    -- Decode a host read. Returns 0 for any address outside the low 256 bytes
    -- so the register map does not alias every 0x100 bytes.
    impure function reg_read(addr: std_logic_vector(31 downto 0))
        return std_logic_vector is
        variable rd: std_logic_vector(31 downto 0);
    begin
        rd := (others => '0');
        if unsigned(addr(31 downto 8)) = 0 then
            case addr(7 downto 0) is
                when x"00" => rd := EXAMPLE_ID;
                when x"04" => rd := EXAMPLE_VER;
                when x"08" => rd := scratch_r;
                when x"0C" => rd := (0 => selftest_en_r, 3 => selftest_loop_r, others => '0');
                when x"10" => rd := status_word(spw_status_r, bringup_done_r,
                                    not rxfifo_empty, not dm_tx_pending,
                                    selftest_pass_r, selftest_done_r,
                                    selftest_busy_r, link_running_i);
                when x"14" => rd := spw_coreid_r;
                when x"18" => rd := spw_status_r;
                when x"20" =>
                    if rxfifo_empty = '0' then
                        rd := (31 => '1', 9 => rxfifo_dout(9),
                               8 => rxfifo_dout(8), others => '0');
                        rd(7 downto 0) := rxfifo_dout(7 downto 0);
                    end if;
                when x"24" => rd := std_logic_vector(txcount_r);
                when x"28" => rd := std_logic_vector(rxcount_r);
                when x"2C" => rd := std_logic_vector(errcount_r);
                when x"30" => rd := std_logic_vector(to_unsigned(rx_pkt, 32));
                when x"34" => rd(1 downto 0) := errinj_r;
                when x"38" => rd := spw_tc_rx_r;  -- received time-code mirror
                when others => null;
            end case;
        end if;
        return rd;
    end function;

begin

    -- output assignments
    s_axi_awready <= awready_s;
    s_axi_wready  <= wready_s;
    s_axi_bresp   <= "00";
    s_axi_bvalid  <= bvalid_s;
    s_axi_arready <= arready_s;
    s_axi_rdata   <= rdata_s;
    s_axi_rresp   <= "00";
    s_axi_rlast   <= rlast_s;
    s_axi_rvalid  <= rvalid_s;

    m_axil_awaddr  <= awaddr_m;
    m_axil_awvalid <= awvalid_m;
    m_axil_wdata   <= wdata_m;
    m_axil_wstrb   <= "1111";
    m_axil_wvalid  <= wvalid_m;
    m_axil_bready  <= bready_m;
    m_axil_araddr  <= araddr_m;
    m_axil_arvalid <= arvalid_m;
    m_axil_rready  <= rready_m;

    m_axis_tdata  <= m_axis_tdata_r;
    m_axis_tvalid <= m_axis_tvalid_r;
    m_axis_tlast  <= m_axis_tlast_r;
    m_axis_tuser(0) <= m_axis_tuser_r;
    s_axis_tready <= s_axis_tready_r;

    link_running_i <= spw_status_r(2);
    link_running  <= link_running_i;
    selftest_pass <= selftest_pass_r;
    selftest_done <= selftest_done_r;
    bringup_done  <= bringup_done_r;
    inj_freeze    <= errinj_r(0);
    inj_invert    <= errinj_r(1);

    rxfifo_empty <= '1' when rxfifo_wptr = rxfifo_rptr else '0';
    rxfifo_full  <= '1' when (rxfifo_wptr(RXFIFO_AW-1 downto 0) = rxfifo_rptr(RXFIFO_AW-1 downto 0))
                          and (rxfifo_wptr(RXFIFO_AW) /= rxfifo_rptr(RXFIFO_AW)) else '0';
    rxfifo_dout  <= rxfifo_mem(to_integer(rxfifo_rptr(RXFIFO_AW-1 downto 0)));

    -- ================= AXI-Lite master bring-up + status poll =================
    process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                mstate <= M_RST;
                awaddr_m <= (others => '0'); awvalid_m <= '0';
                wdata_m <= (others => '0'); wvalid_m <= '0'; bready_m <= '0';
                araddr_m <= (others => '0'); arvalid_m <= '0'; rready_m <= '0';
                spw_coreid_r <= (others => '0'); spw_status_r <= (others => '0');
                bringup_done_r <= '0';
                errclr_pending <= '0';
                spw_tc_rx_r <= (others => '0');
                tc_send_pending <= '0';
            else
                case mstate is
                    when M_RST =>
                        errclr_pending <= '1';  -- clear sticky errors once link is up
                        -- assert spw core reset first: flushes the core RX FIFO
                        -- and AXIS bridges so a recovery after a mid-stream error
                        -- starts from a clean datapath (no stale N-Chars).
                        awaddr_m  <= SPW_REG_CONTROL;
                        wdata_m   <= x"00000001"; -- core_rst=1
                        awvalid_m <= '1';
                        wvalid_m  <= '1';
                        mstate    <= M_CRST_AW;
                    when M_CRST_AW =>
                        if m_axil_awready = '1' then awvalid_m <= '0'; end if;
                        if m_axil_wready  = '1' then wvalid_m  <= '0'; end if;
                        if (awvalid_m = '0') and (wvalid_m = '0') then
                            bready_m <= '1';
                            mstate   <= M_CRST_B;
                        end if;
                    when M_CRST_B =>
                        if m_axil_bvalid = '1' then
                            bready_m  <= '0';
                            awaddr_m  <= SPW_REG_CONTROL;
                            wdata_m   <= x"00000006"; -- core_rst=0, autostart|linkstart
                            awvalid_m <= '1';
                            wvalid_m  <= '1';
                            mstate    <= M_CTRL_AW;
                        end if;
                    when M_CLR_AW =>
                        if m_axil_awready = '1' then awvalid_m <= '0'; end if;
                        if m_axil_wready  = '1' then wvalid_m  <= '0'; end if;
                        if (awvalid_m = '0') and (wvalid_m = '0') then
                            bready_m <= '1';
                            mstate   <= M_CLR_B;
                        end if;
                    when M_CLR_B =>
                        if m_axil_bvalid = '1' then
                            bready_m <= '0';
                            mstate   <= M_STAT_AR;  -- resume polling
                        end if;
                    when M_CTRL_AW =>
                        if m_axil_awready = '1' then awvalid_m <= '0'; end if;
                        if m_axil_wready  = '1' then wvalid_m  <= '0'; end if;
                        if (awvalid_m = '0') and (wvalid_m = '0') then
                            bready_m <= '1';
                            mstate   <= M_CTRL_B;
                        end if;
                    when M_CTRL_B =>
                        if m_axil_bvalid = '1' then
                            bready_m  <= '0';
                            awaddr_m  <= SPW_REG_TXDIVCNT;
                            wdata_m   <= x"000000" & LINK_TXDIVCNT;
                            awvalid_m <= '1';
                            wvalid_m  <= '1';
                            mstate    <= M_DIV_AW;
                        end if;
                    when M_DIV_AW =>
                        if m_axil_awready = '1' then awvalid_m <= '0'; end if;
                        if m_axil_wready  = '1' then wvalid_m  <= '0'; end if;
                        if (awvalid_m = '0') and (wvalid_m = '0') then
                            bready_m <= '1';
                            mstate   <= M_DIV_B;
                        end if;
                    when M_DIV_B =>
                        if m_axil_bvalid = '1' then
                            bready_m  <= '0';
                            araddr_m  <= SPW_REG_CORE_ID;
                            arvalid_m <= '1';
                            rready_m  <= '1';
                            mstate    <= M_ID_AR;
                        end if;
                    when M_ID_AR =>
                        if m_axil_arready = '1' then arvalid_m <= '0'; end if;
                        mstate <= M_ID_R;
                    when M_ID_R =>
                        if m_axil_rvalid = '1' then
                            spw_coreid_r <= m_axil_rdata;
                            rready_m     <= '0';
                            mstate       <= M_STAT_AR;
                        end if;
                    when M_STAT_AR =>
                        araddr_m  <= SPW_REG_STATUS;
                        arvalid_m <= '1';
                        rready_m  <= '1';
                        mstate    <= M_STAT_R;
                    when M_STAT_R =>
                        if m_axil_arready = '1' then arvalid_m <= '0'; end if;
                        if m_axil_rvalid = '1' then
                            spw_status_r   <= m_axil_rdata;
                            rready_m       <= '0';
                            bringup_done_r <= '1';
                            if (m_axil_rdata(2) = '1') and (errclr_pending = '1') then
                                -- link up after (re)bring-up: W1C-clear sticky errors once
                                errclr_pending <= '0';
                                awaddr_m  <= SPW_REG_ERROR;
                                wdata_m   <= x"0000000F";
                                awvalid_m <= '1';
                                wvalid_m  <= '1';
                                mstate    <= M_CLR_AW;
                            elsif tc_send_pending = '1' then
                                -- host requested a time-code send: first W1C the
                                -- received-timecode valid so a stale one can't pass.
                                tc_send_pending <= '0';
                                awaddr_m  <= SPW_REG_TIMECODE_RX;
                                wdata_m   <= x"80000000";
                                awvalid_m <= '1';
                                wvalid_m  <= '1';
                                mstate    <= M_TC_CLR_AW;
                            else
                                -- mirror the received time-code every poll cycle
                                araddr_m  <= SPW_REG_TIMECODE_RX;
                                arvalid_m <= '1';
                                rready_m  <= '1';
                                mstate    <= M_TCRX_R;
                            end if;
                        end if;
                    when M_TC_CLR_AW =>
                        if m_axil_awready = '1' then awvalid_m <= '0'; end if;
                        if m_axil_wready  = '1' then wvalid_m  <= '0'; end if;
                        if (awvalid_m = '0') and (wvalid_m = '0') then
                            bready_m <= '1';
                            mstate   <= M_TC_CLR_B;
                        end if;
                    when M_TC_CLR_B =>
                        if m_axil_bvalid = '1' then
                            bready_m  <= '0';
                            -- now send the requested time-code (tick + ctrl/time)
                            awaddr_m  <= SPW_REG_TIMECODE_TX;
                            wdata_m(31)          <= '1';  -- tick trigger
                            wdata_m(30 downto 8) <= (others => '0');
                            wdata_m(7 downto 0)  <= tc_send_value;
                            awvalid_m <= '1';
                            wvalid_m  <= '1';
                            mstate    <= M_TC_TX_AW;
                        end if;
                    when M_TC_TX_AW =>
                        if m_axil_awready = '1' then awvalid_m <= '0'; end if;
                        if m_axil_wready  = '1' then wvalid_m  <= '0'; end if;
                        if (awvalid_m = '0') and (wvalid_m = '0') then
                            bready_m <= '1';
                            mstate   <= M_TC_TX_B;
                        end if;
                    when M_TC_TX_B =>
                        if m_axil_bvalid = '1' then
                            bready_m <= '0';
                            mstate   <= M_STAT_AR;
                        end if;
                    when M_TCRX_R =>
                        if m_axil_arready = '1' then arvalid_m <= '0'; end if;
                        if m_axil_rvalid = '1' then
                            spw_tc_rx_r <= m_axil_rdata;
                            rready_m    <= '0';
                            mstate      <= M_STAT_AR;
                        end if;
                    when others =>
                        mstate <= M_RST;
                end case;
                -- Latch a host time-code send request (pulse from the W FSM).
                if tc_send_push = '1' then
                    tc_send_pending <= '1';
                end if;
                -- soft_reset must override the case's mstate assignment, so it
                -- comes after the case (last signal assignment wins).
                if soft_reset_pulse = '1' then
                    mstate <= M_RST;
                    bringup_done_r <= '0';
                end if;
            end if;
        end if;
    end process;

    -- ================= TX path: self-check vs data-mover =================
    process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tstate <= T_IDLE; tx_idx <= 0; exp_idx <= 0; check_active <= '0';
                tx_lfsr <= PRBS_SEED; rx_lfsr <= PRBS_SEED; tx_pkt <= 0; rx_pkt <= 0;
                selftest_busy_r <= '0'; selftest_done_r <= '0'; selftest_pass_r <= '0';
                txcount_r <= (others => '0'); rxcount_r <= (others => '0');
                errcount_r <= (others => '0');
                m_axis_tdata_r <= (others => '0'); m_axis_tvalid_r <= '0';
                m_axis_tlast_r <= '0'; m_axis_tuser_r <= '0';
                s_axis_tready_r <= '0'; rxfifo_push <= '0'; rxfifo_wdata <= (others => '0');
                dm_tx_pending <= '0';
            else
                rxfifo_push <= '0';
                if selftest_en_r = '1' then
                    dm_tx_pending  <= '0';
                    s_axis_tready_r <= '1';
                    case tstate is
                        when T_IDLE =>
                            m_axis_tvalid_r <= '0';
                            if (bringup_done_r = '1') and (link_running_i = '1') and
                               ((selftest_start_pulse = '1') or (selftest_done_r = '0')) then
                                tx_idx <= 0; exp_idx <= 0;
                                tx_pkt <= 0; rx_pkt <= 0;
                                tx_lfsr <= PRBS_SEED; rx_lfsr <= PRBS_SEED;
                                errcount_r <= (others => '0');
                                txcount_r <= (others => '0');
                                rxcount_r <= (others => '0');
                                selftest_busy_r <= '1';
                                selftest_done_r <= '0';
                                selftest_pass_r <= '0';
                                check_active <= '1';
                                tstate <= T_DATA;
                            end if;
                        when T_DATA =>
                            -- Present the current PRBS byte; hold until accepted.
                            m_axis_tdata_r  <= tx_lfsr;
                            m_axis_tlast_r  <= '0';
                            m_axis_tuser_r  <= '0';
                            m_axis_tvalid_r <= '1';
                            if (m_axis_tvalid_r = '1') and (m_axis_tready = '1') then
                                txcount_r <= txcount_r + 1;
                                tx_lfsr   <= prbs_next(tx_lfsr);
                                if tx_idx = (SELFTEST_LEN - 1) then
                                    m_axis_tdata_r  <= (others => '0');
                                    m_axis_tlast_r  <= '1';
                                    m_axis_tuser_r  <= '0';
                                    m_axis_tvalid_r <= '1';
                                    tstate <= T_EOP;
                                else
                                    tx_idx <= tx_idx + 1;
                                    m_axis_tdata_r <= prbs_next(tx_lfsr);
                                end if;
                            end if;
                        when T_EOP =>
                            -- On accept, start next packet back-to-back (PRBS
                            -- continues) or finish.
                            if (m_axis_tvalid_r = '1') and (m_axis_tready = '1') then
                                txcount_r <= txcount_r + 1;
                                if (selftest_loop_r = '0') and (tx_pkt = (SELFTEST_PKTS - 1)) then
                                    m_axis_tvalid_r <= '0';
                                    m_axis_tlast_r  <= '0';
                                    tstate <= T_DONE;
                                else
                                    tx_pkt <= tx_pkt + 1;
                                    tx_idx <= 0;
                                    m_axis_tdata_r  <= tx_lfsr;
                                    m_axis_tlast_r  <= '0';
                                    m_axis_tuser_r  <= '0';
                                    m_axis_tvalid_r <= '1';
                                    tstate <= T_DATA;
                                end if;
                            end if;
                        when others =>
                            m_axis_tvalid_r <= '0';
                    end case;

                    -- self-check comparator (PRBS, multi-packet)
                    if (check_active = '1') and (s_axis_tvalid = '1') and (s_axis_tready_r = '1') then
                        rxcount_r <= rxcount_r + 1;
                        if s_axis_tlast = '1' then
                            if (s_axis_tuser(0) = '1') or (exp_idx /= SELFTEST_LEN) or
                               (s_axis_tdata /= x"00") then
                                errcount_r <= errcount_r + 1;
                            end if;
                            exp_idx <= 0;
                            rx_pkt  <= rx_pkt + 1;
                            if (selftest_loop_r = '0') and (rx_pkt = (SELFTEST_PKTS - 1)) then
                                check_active    <= '0';
                                selftest_busy_r <= '0';
                                selftest_done_r <= '1';
                                if (errcount_r = 0) and (s_axis_tuser(0) = '0') and
                                   (exp_idx = SELFTEST_LEN) and
                                   (s_axis_tdata = x"00") then
                                    selftest_pass_r <= '1';
                                else
                                    selftest_pass_r <= '0';
                                end if;
                            end if;
                        else
                            if s_axis_tdata /= rx_lfsr then
                                errcount_r <= errcount_r + 1;
                            end if;
                            rx_lfsr <= prbs_next(rx_lfsr);
                            exp_idx <= exp_idx + 1;
                        end if;
                    end if;

                    if selftest_start_pulse = '1' then
                        selftest_done_r <= '0';
                        tstate <= T_IDLE;
                    end if;
                else
                    -- data-mover
                    selftest_busy_r <= '0';
                    if (dm_tx_pending = '1') and (m_axis_tvalid_r = '0') then
                        m_axis_tdata_r  <= dm_tx_beat(7 downto 0);
                        m_axis_tlast_r  <= dm_tx_beat(8);
                        m_axis_tuser_r  <= dm_tx_beat(9);
                        m_axis_tvalid_r <= '1';
                    end if;
                    if (m_axis_tvalid_r = '1') and (m_axis_tready = '1') then
                        m_axis_tvalid_r <= '0';
                        txcount_r <= txcount_r + 1;
                        dm_tx_pending <= '0';
                    end if;
                    if rxfifo_full = '0' then s_axis_tready_r <= '1';
                    else s_axis_tready_r <= '0'; end if;
                    if (s_axis_tvalid = '1') and (s_axis_tready_r = '1') then
                        rxfifo_push  <= '1';
                        rxfifo_wdata <= s_axis_tuser(0) & s_axis_tlast & s_axis_tdata;
                        rxcount_r    <= rxcount_r + 1;
                    end if;
                    if dm_tx_push = '1' then dm_tx_pending <= '1'; end if;
                end if;
            end if;
        end if;
    end process;

    -- ================= RX FIFO pointers =================
    process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rxfifo_wptr <= (others => '0');
                rxfifo_rptr <= (others => '0');
            else
                if (rxfifo_push = '1') and (rxfifo_full = '0') then
                    rxfifo_mem(to_integer(rxfifo_wptr(RXFIFO_AW-1 downto 0))) <= rxfifo_wdata;
                    rxfifo_wptr <= rxfifo_wptr + 1;
                end if;
                if (rxfifo_pop = '1') and (rxfifo_empty = '0') then
                    rxfifo_rptr <= rxfifo_rptr + 1;
                end if;
            end if;
        end if;
    end process;

    -- ================= AXI4 slave write FSM =================
    process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                wstate <= W_IDLE; awready_s <= '1'; wready_s <= '0'; bvalid_s <= '0';
                w_addr <= (others => '0'); w_len <= (others => '0');
                scratch_r <= (others => '0'); selftest_en_r <= '1';
                selftest_loop_r <= '0';
                errinj_r <= "00";
                selftest_start_pulse <= '0'; soft_reset_pulse <= '0';
                dm_tx_push <= '0'; dm_tx_beat <= (others => '0');
                tc_send_push <= '0'; tc_send_value <= (others => '0');
            else
                selftest_start_pulse <= '0';
                soft_reset_pulse     <= '0';
                dm_tx_push           <= '0';
                tc_send_push         <= '0';
                case wstate is
                    when W_IDLE =>
                        bvalid_s <= '0';
                        if (s_axi_awvalid = '1') and (awready_s = '1') then
                            w_addr    <= s_axi_awaddr;
                            w_len     <= unsigned(s_axi_awlen);
                            awready_s <= '0';
                            wready_s  <= '1';
                            wstate    <= W_DATA;
                        end if;
                    when W_DATA =>
                        if (s_axi_wvalid = '1') and (wready_s = '1') then
                            if unsigned(w_addr(31 downto 8)) = 0 then
                            case w_addr(7 downto 0) is
                                when x"08" =>
                                    if s_axi_wstrb(0) = '1' then scratch_r(7 downto 0)   <= s_axi_wdata(7 downto 0); end if;
                                    if s_axi_wstrb(1) = '1' then scratch_r(15 downto 8)  <= s_axi_wdata(15 downto 8); end if;
                                    if s_axi_wstrb(2) = '1' then scratch_r(23 downto 16) <= s_axi_wdata(23 downto 16); end if;
                                    if s_axi_wstrb(3) = '1' then scratch_r(31 downto 24) <= s_axi_wdata(31 downto 24); end if;
                                when x"0C" =>
                                    if s_axi_wstrb(0) = '1' then
                                        selftest_en_r        <= s_axi_wdata(0);
                                        selftest_start_pulse <= s_axi_wdata(1);
                                        selftest_loop_r      <= s_axi_wdata(3);
                                        soft_reset_pulse     <= s_axi_wdata(2);
                                    end if;
                                when x"1C" =>
                                    dm_tx_beat <= s_axi_wdata(9 downto 0);
                                    dm_tx_push <= '1';
                                when x"34" =>
                                    if s_axi_wstrb(0) = '1' then
                                        errinj_r <= s_axi_wdata(1 downto 0);
                                    end if;
                                when x"38" =>  -- TIMECODE: send the requested time-code
                                    if s_axi_wstrb(0) = '1' then
                                        tc_send_value <= s_axi_wdata(7 downto 0);
                                    end if;
                                    tc_send_push <= '1';
                                when others =>
                                    null;
                            end case;
                            end if;
                            w_addr <= std_logic_vector(unsigned(w_addr) + 4);
                            if (s_axi_wlast = '1') or (w_len = 0) then
                                wready_s <= '0';
                                bvalid_s <= '1';
                                wstate   <= W_RESP;
                            else
                                w_len <= w_len - 1;
                            end if;
                        end if;
                    when W_RESP =>
                        if (bvalid_s = '1') and (s_axi_bready = '1') then
                            bvalid_s  <= '0';
                            awready_s <= '1';
                            wstate    <= W_IDLE;
                        end if;
                    when others =>
                        wstate <= W_IDLE;
                end case;
            end if;
        end if;
    end process;

    -- ================= AXI4 slave read FSM =================
    process (clk) is
        variable naddr: std_logic_vector(31 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rstate <= R_IDLE; arready_s <= '1'; rvalid_s <= '0';
                rdata_s <= (others => '0'); rlast_s <= '0';
                r_addr <= (others => '0'); r_len <= (others => '0');
                rxfifo_pop <= '0';
            else
                rxfifo_pop <= '0';
                case rstate is
                    when R_IDLE =>
                        rvalid_s <= '0';
                        rlast_s  <= '0';
                        if (s_axi_arvalid = '1') and (arready_s = '1') then
                            r_addr    <= s_axi_araddr;
                            r_len     <= unsigned(s_axi_arlen);
                            arready_s <= '0';
                            rdata_s   <= reg_read(s_axi_araddr);
                            rvalid_s  <= '1';
                            if s_axi_arlen = x"00" then rlast_s <= '1'; else rlast_s <= '0'; end if;
                            if (unsigned(s_axi_araddr(31 downto 8)) = 0) and
                               (s_axi_araddr(7 downto 0) = x"20") and (rxfifo_empty = '0') then
                                rxfifo_pop <= '1';
                            end if;
                            rstate <= R_DATA;
                        end if;
                    when R_DATA =>
                        if (rvalid_s = '1') and (s_axi_rready = '1') then
                            if r_len = 0 then
                                rvalid_s  <= '0';
                                rlast_s   <= '0';
                                arready_s <= '1';
                                rstate    <= R_IDLE;
                            else
                                naddr  := std_logic_vector(unsigned(r_addr) + 4);
                                r_addr <= naddr;
                                r_len  <= r_len - 1;
                                rdata_s <= reg_read(naddr);
                                if r_len = 1 then rlast_s <= '1'; else rlast_s <= '0'; end if;
                                if (unsigned(naddr(31 downto 8)) = 0) and
                                   (naddr(7 downto 0) = x"20") and (rxfifo_empty = '0') then
                                    rxfifo_pop <= '1';
                                end if;
                            end if;
                        end if;
                    when others =>
                        rstate <= R_IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
