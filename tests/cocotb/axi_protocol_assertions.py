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


def start_axis_assertions(cocotb, dut, prefix):
    cocotb.start_soon(
        assert_stable_when_stalled(
            dut.clk,
            dut.rst,
            getattr(dut, f"{prefix}_tvalid"),
            getattr(dut, f"{prefix}_tready"),
            [
                getattr(dut, f"{prefix}_tdata"),
                getattr(dut, f"{prefix}_tlast"),
                getattr(dut, f"{prefix}_tuser"),
            ],
            prefix,
        )
    )


def start_axil_assertions(cocotb, dut, prefix="s_axi"):
    for channel, payload_names in {
        "aw": ["awaddr"],
        "w": ["wdata", "wstrb"],
        "ar": ["araddr"],
        "b": ["bresp"],
        "r": ["rdata", "rresp"],
    }.items():
        valid = getattr(dut, f"{prefix}_{channel}valid")
        ready = getattr(dut, f"{prefix}_{channel}ready")
        payload = [getattr(dut, f"{prefix}_{name}") for name in payload_names]
        cocotb.start_soon(
            assert_stable_when_stalled(
                dut.clk,
                dut.rst,
                valid,
                ready,
                payload,
                f"{prefix}_{channel}",
            )
        )
