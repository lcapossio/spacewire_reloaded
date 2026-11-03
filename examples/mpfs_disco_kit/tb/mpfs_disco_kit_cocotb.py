# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""Board-level functional sim of the PolarFire SoC Discovery Kit loopback top.

Drives only the board pins (50 MHz clk, SWITCH push-buttons, idle JTAG pins)
and checks the four status LEDs exactly as a person would read them on the
board:

- LEDs stay off while the fabric power-on reset (the tb/mpfs_por_sim stub of
  the PolarFire INIT block) and the reset counter hold the design;
- all four light (active-high pins go to 1) once bring-up, link, self-check
  done and self-check pass are reached, and stay lit;
- pressing SWITCH1 resets the design (all LEDs off) and releasing it brings
  the link back up and re-runs the self-check to a pass.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotb.utils import get_sim_time

CLK_PERIOD_NS = 20            # 50 MHz, REF_CLK_50MHz
POR_LOW_CYCLES = 10           # tb/mpfs_por_sim: fabric_por_n low for 200 ns
POR_CYCLES = POR_LOW_CYCLES + 2 + 16  # + release synchronizer + por_cnt[4]
PASS_TIMEOUT_US = 3000        # generous bound for bring-up + 4-packet self-check
HEARTBEAT_US = 100            # progress log period while waiting

LEDS_ALL_ON = "1111"          # active-high: every status bit true
LEDS_ALL_OFF = "0000"
BTN_RELEASED = 0b11           # SWITCH pins read 1 when not pressed
BTN_SW1_PRESSED = 0b10


def leds(dut) -> str:
    return str(dut.led.value)


def describe(led_str: str) -> str:
    """Name the lit status LEDs (index 0 is the rightmost character)."""
    names = ["bringup_done", "link_running", "selftest_done", "selftest_pass"]
    if len(led_str) != 4 or any(c not in "01" for c in led_str):
        return f"unresolved ({led_str})"
    lit = [names[i] for i in range(4) if led_str[3 - i] == "1"]
    return ", ".join(lit) if lit else "none"


async def start(dut) -> None:
    dut.btn.value = BTN_RELEASED
    # No JTAG host: the dedicated JTAG pins sit idle.
    for pin in (dut.TCK, dut.TMS, dut.TDI, dut.TRSTB):
        pin.value = 0
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
    """The power-on reset holds the design; then the self-check passes on the LEDs."""
    await start(dut)

    # Inside the power-on window: only the power-on reset can be holding it.
    await ClockCycles(dut.clk, POR_CYCLES - 4)
    assert str(dut.rst.value) == "1", "the power-on reset must hold the design"
    assert leds(dut) == LEDS_ALL_OFF, (
        f"LEDs must be off during the power-on reset, got {leds(dut)}")

    # por_cnt[4] sets 16 clocks after the synchronized FABRIC_POR_N release.
    await ClockCycles(dut.clk, 8)
    assert str(dut.rst.value) == "0", "reset must release after the power-on count"

    # LED order: bring-up completes (first STATUS read) well before the link can
    # reach Run, so LED1 must light on its own first. Catches an LED1/LED2
    # swap between the Verilog and VHDL tops.
    while leds(dut) == LEDS_ALL_OFF:
        await ClockCycles(dut.clk, 10)
    assert leds(dut) == "0001", (
        f"first lit LED must be LED1 (bringup_done), got {describe(leds(dut))}")

    elapsed = await wait_all_on(dut, "power-up")
    dut._log.info("all LEDs lit after ~%.1f us (bring-up + link + self-check pass)",
                  elapsed)

    # The pass is steady: no LED may drop while the design idles.
    for _ in range(20):
        await ClockCycles(dut.clk, 250)
        assert leds(dut) == LEDS_ALL_ON, f"LED dropped after pass: {leds(dut)}"
    assert str(dut.TDO.value) == "0", "the debug stub drives TDO low"


@cocotb.test()
async def test_switch1_resets_and_recovers(dut):
    """SWITCH1 clears every status LED; on release the self-check passes again."""
    await start(dut)
    await wait_all_on(dut, "power-up")

    dut.btn.value = BTN_SW1_PRESSED
    await ClockCycles(dut.clk, 20)
    assert leds(dut) == LEDS_ALL_OFF, f"SWITCH1 must reset all LEDs off, got {leds(dut)}"

    dut.btn.value = BTN_RELEASED
    elapsed = await wait_all_on(dut, "after SWITCH1")
    dut._log.info("recovered after SWITCH1 in ~%.1f us", elapsed)
