# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""Board-level functional sim of the DE25-Nano SpaceWire loopback top.

Drives only the board pins (50 MHz clk, KEY push-buttons) and checks the four
status LEDs exactly as a person would read them on the board:

- LEDs stay off while the configuration reset release (ninit_done) is held;
- all four light (active-low pins go to 0) once bring-up, link, self-check done
  and self-check pass are reached, and stay lit;
- pressing KEY0 resets the design (all LEDs off) and releasing it brings the
  link back up and re-runs the self-check to a pass.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from cocotb.utils import get_sim_time

CLK_PERIOD_NS = 20            # 50 MHz, DE25-Nano CLOCK1_50
RESET_RELEASE_NS = 500        # de25_reset_release sim stub ninit_done window
PASS_TIMEOUT_US = 3000        # generous bound for bring-up + 4-packet self-check
HEARTBEAT_US = 100            # progress log period while waiting

LEDS_ALL_ON = "0000"          # active-low: every status bit true
LEDS_ALL_OFF = "1111"
BTN_RELEASED = 0b11           # KEY pins read 1 when not pressed
BTN_KEY0_PRESSED = 0b10


def leds(dut) -> str:
    return str(dut.led.value)


def describe(led_str: str) -> str:
    """Name the lit status LEDs (index 0 is the rightmost character)."""
    names = ["bringup_done", "link_running", "selftest_done", "selftest_pass"]
    if len(led_str) != 4 or any(c not in "01" for c in led_str):
        return f"unresolved ({led_str})"
    lit = [names[i] for i in range(4) if led_str[3 - i] == "0"]
    return ", ".join(lit) if lit else "none"


async def start(dut) -> None:
    dut.btn.value = BTN_RELEASED
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())


async def wait_all_on(dut, label: str) -> float:
    """Wait for all four LEDs lit; return the elapsed sim time in microseconds."""
    t0 = get_sim_time(unit="us")
    cycles_per_beat = HEARTBEAT_US * 1000 // CLK_PERIOD_NS
    beats = PASS_TIMEOUT_US // HEARTBEAT_US
    step = 50
    for beat in range(beats):
        for _ in range(cycles_per_beat // step):
            await ClockCycles(dut.clk, step)
            if leds(dut) == LEDS_ALL_ON:
                return get_sim_time(unit="us") - t0
        dut._log.info("[%s] heartbeat %d us: lit = %s",
                      label, (beat + 1) * HEARTBEAT_US, describe(leds(dut)))
    raise AssertionError(
        f"[{label}] LEDs never all lit within {PASS_TIMEOUT_US} us; "
        f"last lit = {describe(leds(dut))}")


@cocotb.test()
async def test_selftest_lights_all_leds(dut):
    """Reset release holds the design; then the self-check passes on the LEDs."""
    await start(dut)

    # Well past the power-on pulse but still inside the reset-release window:
    # only ninit_done can be holding the design in reset here.
    await Timer(RESET_RELEASE_NS - 100, unit="ns")
    assert str(dut.rst.value) == "1", "ninit_done must hold the design in reset"
    assert leds(dut) == LEDS_ALL_OFF, (
        f"LEDs must be off while ninit_done holds reset, got {leds(dut)}")

    # ninit_done falls at RESET_RELEASE_NS; after the 2-FF sync rst must drop.
    await Timer(200, unit="ns")
    assert str(dut.rst.value) == "0", "reset must release after ninit_done falls"

    elapsed = await wait_all_on(dut, "power-up")
    dut._log.info("all LEDs lit after ~%.1f us (bring-up + link + self-check pass)",
                  elapsed)

    # The pass is steady: no LED may drop while the design idles.
    for _ in range(20):
        await ClockCycles(dut.clk, 250)
        assert leds(dut) == LEDS_ALL_ON, f"LED dropped after pass: {leds(dut)}"


@cocotb.test()
async def test_key0_resets_and_recovers(dut):
    """KEY0 clears every status LED; on release the self-check passes again."""
    await start(dut)
    await wait_all_on(dut, "power-up")

    dut.btn.value = BTN_KEY0_PRESSED
    await ClockCycles(dut.clk, 20)
    assert leds(dut) == LEDS_ALL_OFF, f"KEY0 must reset all LEDs off, got {leds(dut)}"

    dut.btn.value = BTN_RELEASED
    elapsed = await wait_all_on(dut, "after KEY0")
    dut._log.info("recovered after KEY0 in ~%.1f us", elapsed)
