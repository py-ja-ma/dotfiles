# College

[Toolchain](../README.md) › [Profiles](README.md) › College

The tools for Computer Engineering coursework: circuits, digital design, maths, reports and microcontrollers.

| | |
|---|---|
| Code | `packages/roles/college.txt`, `packages/winget/college.txt`, `system/printing-setup.sh` |
| Runs on | cabin and lantern; the terminal tools in cabin-wsl and thermos-wsl; the GUIs natively on cabin-win |
| Needs | KiCad, Octave, Typst, TeX Live, CUPS |
| Decided in | the course-mandated waiver class of [decision 0013](../../../decisions/0013-software-rules-and-waivers.md) ([D6](../../../decisions/log.md#d6)) |

| Course work | Tools |
|---|---|
| Circuits, PCBs | KiCad with its libraries, ngspice (KiCad's simulator) |
| Digital design | Verilator, Icarus Verilog, GTKWave, Yosys, prjtrellis with openFPGALoader for the Lattice ECP5 |
| Maths, labs | Octave (MATLAB-compatible), uv for SciPy, NumPy and SymPy notebooks, gnuplot |
| Reports, notes | Typst by default, TeX Live with biber for IEEE and professors' templates, draw.io, Xournal++ for handwriting and PDF notes, Anki |
| Microcontrollers | arduino-cli, PlatformIO, avr-gcc, avr-libc, avrdude; OpenOCD and the logic analyzer are the re-lab role's |

On cabin-win, natively: KiCad with its libraries, Octave, Typst, draw.io, Xournal++, Anki and Arduino CLI.
The HDL tools, TeX Live, PlatformIO, gnuplot and ngspice on its own come from Arch, on cabin, lantern or a WSL clone ([D141](../../../decisions/log.md#d141)).
On Windows, a board whose USB serial chip is a CH340 or CH341 makes Windows Update install WCH's driver, from Nanjing.
cabin-win refuses that driver by device id ([D142](../../../decisions/log.md#d142)), so use boards with native USB, FTDI or CP210x serial there, or flash those from Arch, whose kernel driver is its own.

Later, vendored into `[dram]`: Zotero, Logisim-evolution (accepted) and nextpnr.
Qucs-S is not used: its donations go through Boosty.

## Printing

CUPS answers through its socket: `system/printing-setup.sh`, a `dram apply` hook, enables `cups.socket`.
Add the printer in system-config-printer or at `http://localhost:631`.
A network printer that speaks IPP Everywhere needs no driver.
A network multifunction scans driverless through `sane-airscan`, which waits for an Origin ruling and is not installed (2026-10-13).
A WSL clone has no CUPS: Windows prints for it.

## When a course requires closed software

For MATLAB, Multisim, LTspice, Quartus, Vivado, LabVIEW or Altium, in this order:

1. the FOSS substitute above, if the course accepts its files
2. the school's VDI or lab machines
3. cabin's Windows disk (`dram boot-to windows`)
4. a waiver on Linux per tool and per term, ending with the term ([D6](../../../decisions/log.md#d6))

Ask each professor early which file formats are graded.
