# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

from cocotb.triggers import RisingEdge


def resolved_value(signal):
    try:
        return int(signal.value)
    except ValueError:
        return None


def resolved_payload(payload):
    values = []
    for signal in payload:
        value = resolved_value(signal)
        if value is None:
            return None
        values.append(value)
    return tuple(values)


class AxisStreamChecker:
    def __init__(
        self,
        *,
        clock,
        reset,
        tvalid,
        tready,
        tdata,
        tlast,
        tuser,
        name,
        max_packet_beats=4096,
        max_stall_cycles=256,
        reset_must_clear_valid=False,
        check_spw_nchar=True,
    ):
        self.clock = clock
        self.reset = reset
        self.tvalid = tvalid
        self.tready = tready
        self.tdata = tdata
        self.tlast = tlast
        self.tuser = tuser
        self.name = name
        self.max_packet_beats = max_packet_beats
        self.max_stall_cycles = max_stall_cycles
        self.reset_must_clear_valid = reset_must_clear_valid
        self.check_spw_nchar = check_spw_nchar

    async def run(self):
        previous_payload = None
        packet_beats = 0
        stall_cycles = 0

        while True:
            await RisingEdge(self.clock)

            reset_value = resolved_value(self.reset)
            if reset_value is None or reset_value:
                if self.reset_must_clear_valid:
                    valid_during_reset = resolved_value(self.tvalid)
                    assert valid_during_reset in (0, None), (
                        f"{self.name} TVALID asserted during reset"
                    )
                previous_payload = None
                packet_beats = 0
                stall_cycles = 0
                continue

            valid_value = resolved_value(self.tvalid)
            ready_value = resolved_value(self.tready)
            assert valid_value is not None, f"{self.name} TVALID unresolved outside reset"
            assert ready_value is not None, f"{self.name} TREADY unresolved outside reset"

            if valid_value == 0:
                previous_payload = None
                stall_cycles = 0
                continue

            payload = resolved_payload([self.tdata, self.tlast, self.tuser])
            assert payload is not None, f"{self.name} payload unresolved while TVALID is high"

            tdata_value, tlast_value, tuser_value = payload
            assert tlast_value in (0, 1), f"{self.name} TLAST is not one bit"
            assert tuser_value in (0, 1), f"{self.name} TUSER[0] is not one bit"

            if self.check_spw_nchar:
                self._check_spw_nchar_beat(tdata_value, tlast_value, tuser_value)

            if ready_value == 0:
                stall_cycles += 1
                if self.max_stall_cycles is not None:
                    assert stall_cycles <= self.max_stall_cycles, (
                        f"{self.name} stalled for more than {self.max_stall_cycles} cycles"
                    )
                if previous_payload is not None:
                    assert payload == previous_payload, (
                        f"{self.name} payload changed while TVALID=1 and TREADY=0"
                    )
                previous_payload = payload
                continue

            previous_payload = None
            stall_cycles = 0
            packet_beats += 1
            if self.max_packet_beats is not None:
                assert packet_beats <= self.max_packet_beats, (
                    f"{self.name} packet exceeded {self.max_packet_beats} beats without TLAST"
                )
            if tlast_value == 1:
                packet_beats = 0

    def _check_spw_nchar_beat(self, tdata_value, tlast_value, tuser_value):
        if tlast_value == 0:
            return

        assert tdata_value in (0, 1), (
            f"{self.name} terminal beat TDATA must encode EOP=0 or EEP=1"
        )
        assert (tdata_value & 1) == tuser_value, (
            f"{self.name} terminal beat TUSER[0] must match EEP code in TDATA[0]"
        )


class AxiLiteSlaveChecker:
    def __init__(
        self,
        *,
        clock,
        reset,
        prefix,
        signals,
        max_response_cycles=64,
        max_stall_cycles=256,
    ):
        self.clock = clock
        self.reset = reset
        self.prefix = prefix
        self.signals = signals
        self.max_response_cycles = max_response_cycles
        self.max_stall_cycles = max_stall_cycles

    async def run(self):
        previous_payload = {}
        stall_cycles = {}
        aw_pending = False
        w_pending = False
        write_outstanding = False
        write_wait = 0
        read_outstanding = False
        read_wait = 0
        reset_seen = False

        while True:
            await RisingEdge(self.clock)

            reset_value = resolved_value(self.reset)
            if reset_value is None or reset_value:
                if reset_seen:
                    self._assert_reset_outputs()
                previous_payload.clear()
                stall_cycles.clear()
                aw_pending = False
                w_pending = False
                write_outstanding = False
                write_wait = 0
                read_outstanding = False
                read_wait = 0
                reset_seen = True
                continue
            reset_seen = False

            channel_values = {}
            for channel, payload in {
                "aw": ["awaddr"],
                "w": ["wdata", "wstrb"],
                "ar": ["araddr"],
                "b": ["bresp"],
                "r": ["rdata", "rresp"],
            }.items():
                channel_values[channel] = self._check_channel(
                    channel,
                    payload,
                    previous_payload,
                    stall_cycles,
                )

            aw_fire = channel_values["aw"]["fire"]
            w_fire = channel_values["w"]["fire"]
            ar_fire = channel_values["ar"]["fire"]
            b_fire = channel_values["b"]["fire"]
            r_fire = channel_values["r"]["fire"]
            bvalid = channel_values["b"]["valid"]
            rvalid = channel_values["r"]["valid"]

            if bvalid:
                assert resolved_value(self.signals["bresp"]) == 0, (
                    f"{self.prefix}_b BRESP must be OKAY"
                )
                assert write_outstanding, f"{self.prefix}_b response without write"

            if rvalid:
                assert resolved_value(self.signals["rresp"]) == 0, (
                    f"{self.prefix}_r RRESP must be OKAY"
                )
                assert read_outstanding, f"{self.prefix}_r response without read"

            if aw_fire:
                assert not aw_pending, f"{self.prefix}_aw accepted duplicate address"
                assert not write_outstanding, f"{self.prefix}_aw accepted while write response pending"
                aw_pending = True

            if w_fire:
                assert not w_pending, f"{self.prefix}_w accepted duplicate data"
                assert not write_outstanding, f"{self.prefix}_w accepted while write response pending"
                w_pending = True

            if aw_pending and w_pending and not write_outstanding:
                write_outstanding = True
                write_wait = 0
                aw_pending = False
                w_pending = False

            if write_outstanding:
                if bvalid:
                    write_wait = 0
                else:
                    write_wait += 1
                    assert write_wait <= self.max_response_cycles, (
                        f"{self.prefix}_b response latency exceeded {self.max_response_cycles} cycles"
                    )
                if b_fire:
                    write_outstanding = False

            if ar_fire:
                assert not read_outstanding, f"{self.prefix}_ar accepted while read response pending"
                read_outstanding = True
                read_wait = 0

            if read_outstanding:
                if rvalid:
                    read_wait = 0
                else:
                    read_wait += 1
                    assert read_wait <= self.max_response_cycles, (
                        f"{self.prefix}_r response latency exceeded {self.max_response_cycles} cycles"
                    )
                if r_fire:
                    read_outstanding = False

    def _assert_reset_outputs(self):
        for name in ("bvalid", "rvalid"):
            value = resolved_value(self.signals[name])
            assert value in (0, None), f"{self.prefix}_{name} asserted during reset"

    def _check_channel(self, channel, payload_names, previous_payload, stall_cycles):
        valid = self.signals[f"{channel}valid"]
        ready = self.signals[f"{channel}ready"]
        valid_value = resolved_value(valid)
        ready_value = resolved_value(ready)
        assert valid_value is not None, f"{self.prefix}_{channel}valid unresolved outside reset"
        assert ready_value is not None, f"{self.prefix}_{channel}ready unresolved outside reset"

        if valid_value == 0:
            previous_payload.pop(channel, None)
            stall_cycles[channel] = 0
            return {"valid": False, "ready": bool(ready_value), "fire": False}

        payload = resolved_payload([self.signals[name] for name in payload_names])
        assert payload is not None, f"{self.prefix}_{channel} payload unresolved while valid"

        if ready_value == 0:
            stall_cycles[channel] = stall_cycles.get(channel, 0) + 1
            assert stall_cycles[channel] <= self.max_stall_cycles, (
                f"{self.prefix}_{channel} stalled for more than {self.max_stall_cycles} cycles"
            )
            if channel in previous_payload:
                assert payload == previous_payload[channel], (
                    f"{self.prefix}_{channel} payload changed while valid and not ready"
                )
            previous_payload[channel] = payload
            return {"valid": True, "ready": False, "fire": False}

        previous_payload.pop(channel, None)
        stall_cycles[channel] = 0
        return {"valid": True, "ready": True, "fire": True}


async def assert_stable_when_stalled(clock, reset, valid, ready, payload, name):
    previous = None
    while True:
        await RisingEdge(clock)
        reset_value = resolved_value(reset)
        if reset_value is None or reset_value:
            previous = None
            continue

        valid_value = resolved_value(valid)
        ready_value = resolved_value(ready)
        if valid_value != 1 or ready_value is None:
            previous = None
            continue

        stalled = ready_value == 0
        current = resolved_payload(payload)
        assert current is not None, f"{name} payload unresolved while valid"

        if stalled and previous is not None:
            assert current == previous, f"{name} payload changed while valid and not ready"

        previous = current if stalled else None


def start_axis_assertions(
    cocotb,
    dut,
    prefix,
    *,
    max_packet_beats=4096,
    max_stall_cycles=256,
    reset_must_clear_valid=False,
    check_spw_nchar=True,
):
    cocotb.start_soon(
        AxisStreamChecker(
            clock=dut.clk,
            reset=dut.rst,
            tvalid=getattr(dut, f"{prefix}_tvalid"),
            tready=getattr(dut, f"{prefix}_tready"),
            tdata=getattr(dut, f"{prefix}_tdata"),
            tlast=getattr(dut, f"{prefix}_tlast"),
            tuser=getattr(dut, f"{prefix}_tuser"),
            name=prefix,
            max_packet_beats=max_packet_beats,
            max_stall_cycles=max_stall_cycles,
            reset_must_clear_valid=reset_must_clear_valid,
            check_spw_nchar=check_spw_nchar,
        )
        .run()
    )


def start_axil_assertions(cocotb, dut, prefix="s_axi", max_response_cycles=64, max_stall_cycles=256):
    signals = {}
    for channel in ("aw", "w", "b", "ar", "r"):
        signals[f"{channel}valid"] = getattr(dut, f"{prefix}_{channel}valid")
        signals[f"{channel}ready"] = getattr(dut, f"{prefix}_{channel}ready")
    for name in ("awaddr", "wdata", "wstrb", "bresp", "araddr", "rdata", "rresp"):
        signals[name] = getattr(dut, f"{prefix}_{name}")

    cocotb.start_soon(
        AxiLiteSlaveChecker(
            clock=dut.clk,
            reset=dut.rst,
            prefix=prefix,
            signals=signals,
            max_response_cycles=max_response_cycles,
            max_stall_cycles=max_stall_cycles,
        ).run()
    )
