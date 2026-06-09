# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

from cocotb.triggers import RisingEdge


def value(signal):
    return int(signal.value)


async def assert_stable_when_stalled(clock, reset, valid, ready, payload, name):
    previous = None
    while True:
        await RisingEdge(clock)
        if value(reset):
            previous = None
            continue

        stalled = value(valid) and not value(ready)
        current = tuple(value(signal) for signal in payload)

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
