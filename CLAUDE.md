# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Odin Turbo Pascal: a Turbo Pascal–style IDE written in Python/Tk (stdlib only, no pip dependencies) that drives a real Free Pascal (`fpc`) compiler and runs the native binaries in a built-in 80×25 PTY terminal. It ships as a macOS `.app` bundle, but the bundle only wraps a local Python install. The project targets Python 3.10+ with Tk, FPC 3.2.2+, and Xcode Command Line Tools on macOS.

## Commands

Run everything from the repo root, because the tests import the `odin` package from the current directory.

```bash
python3 main.py                                   # launch the IDE from source
python3 -m unittest discover -s tests -v          # full suite
python3 -m unittest tests.test_core.CompilerTests.test_compile_every_example -v   # single test
ODIN_FPC=/path/to/fpc python3 -m unittest ...     # point tests at a specific compiler
python3 scripts/package_app.py                    # regenerate "Odin Turbo Pascal.app" from source
python3 scripts/check_mac.py "$(command -v fpc)"  # macOS installer gate: compile + run a native binary, verify CPU arch
```

- Every test module needs a Python built with Tk, because `odin/terminal.py` imports `tkinter`. On this Mac the default Homebrew `python3` (3.14) has no `_tkinter`; use `/usr/local/opt/python@3.13/bin/python3.13`. That is also the interpreter recorded in `~/Library/Application Support/OdinTurboPascal/python-path`.
- Tests that open a PTY (`Process`, interactive or CRT runs) fail with `OSError: out of pty devices` inside the Claude Code sandbox. Run them unsandboxed.
- `CompilerTests` (and the GUI compile test) are skipped when FPC isn't found.
- `GuiTests` run when `DISPLAY` is set or on darwin. On a Mac they open real Tk windows. On Linux they use Xvfb.
- There is no linter or formatter config.

## Architecture

There are three modules in `odin/`, layered so that only `app.py` and `TerminalView` depend on Tk:

- **`core.py`** (no Tk):
  - `Document` detects encoding (UTF-8, UTF-8 BOM, or CP437 fallback) and newline style (LF or CRLF), and keeps both so files round-trip byte-for-byte. It holds a SHA-256 hash of the file on disk, used to detect external changes.
  - `Settings` loads only keys present in `DEFAULTS` whose type matches, then clamps their values.
  - `build()` builds an `fpc` argv. Output goes to a cache dir keyed by a hash of the source path plus the build-relevant settings, so user folders never receive build artifacts. It deletes the old executable before compiling so a failed build can't run a stale binary. On darwin it adds `-Paarch64`/`-Px86_64` and `-XR<sdk>` from `xcrun`.
  - `build()` also appends FPC's Free Vision (Turbo Vision) unit dir, found by `free_vision_dir()`, after the user's unit paths. FPC searches `-Fu` paths in order. Without this, `uses App` fails on macOS because Apple's `univint/Menus.ppu` shadows Free Vision's `Menus`. `docs/COMPATIBILITY.txt` lists which TP7 units exist and which DOS-era features don't compile.
  - `parse_diagnostics()` turns FPC output into `Diagnostic`s. `syntax_spans()` is the regex highlighter.
- **`terminal.py`**:
  - `Screen` is a pure VT100/ANSI parser over a grid of `(char, fg, bg)` cells, with a 16-color CRT palette.
  - `Process` runs a child on a PTY in its own session, with a reader thread that reports through an `emit(kind, value)` callback. Ctrl-C and stop signal the whole process group.
  - `TerminalView` is the Tk widget that renders `Screen`.
- **`app.py`**: the `App` and `Editor` Tk classes (menus, MDI-style editor frames placed on a desktop frame, dialogs, find/replace, breakpoints gutter, session recovery).

### Threading model

Worker threads (the compile worker and the PTY reader) must never touch Tk. They push `("build" | "build_error" | "output" | "exit", value)` onto `App.messages`, and `App.poll()` drains that queue every 40 ms on the Tk thread. `compile()` takes a deep-copied `Settings` snapshot before starting its thread. Run and Debug are `compile(after="run" | "debug")`; the action is stored in `pending_action` and fired from `poll()` when the build succeeds.

### Debugging

Debugging runs `lldb --no-lldbinit` in the same PTY User screen, with breakpoints passed as `-o "breakpoint set ..."`. If there are no breakpoints it breaks on `PASCALMAIN`. F7, F8 and Evaluate just type LLDB commands into the PTY. There is no structured debugger protocol.

### Paths and data

- `ASSETS` (in `app.py`) is the parent of the `odin` package. That works both from the repo and from inside `.app/Contents/Resources/`, because `package_app.py` copies `odin/`, `examples/`, `docs/` and `main.py` there. Help menu items read `docs/*.txt` at runtime, so renaming those files breaks Help.
- Files under `ASSETS` (the bundled examples) are treated as templates: Save always becomes Save As.
- Per-user state lives in `data_dir()`:
  - Location: `~/Library/Application Support/OdinTurboPascal/` on macOS, `~/.local/share/OdinTurboPascal/` elsewhere.
  - Files written by the app: `settings.json`, `build/`, `recovery.json` (autosaved every 10 s, deleted on clean quit), `last-error.log`, and `instance.lock` (`flock` single-instance guard).
  - Files written by the installer and launcher: `python-path` (written by `Install.command`) and `launch.log`.
- Any write of user files or settings should go through `atomic_write()`.
- Compile and run never use a shell. Program arguments are parsed with `shlex.split` and passed as an argv list.

### Packaging

- `Odin Turbo Pascal.app/` is a **generated copy**. Edit `odin/`, `docs/` and `examples/` at the repo root, then rerun `scripts/package_app.py`, which deletes and rebuilds the bundle.
- `scripts/launcher.sh` becomes `Contents/MacOS/OdinTurboPascal`. It reads `python-path` and re-execs as arm64 on Apple Silicon.
- `SHA256SUMS.json` covers the source tree and the bundle, but no script regenerates it. It goes stale after any edit.
- The version `1.0.0` is hard-coded in several places: `odin/__init__.py`, `package_app.py` (Info.plist), strings in `app.py`, `Install.command`, `README.txt` and `docs/`.

## Conventions

- User-facing messages, dialogs and all docs (`README.txt`, `docs/*.txt`) are in Indonesian. Menu labels and status-bar text stay in English, Turbo Pascal style. Keep that split.
- The docs strictly separate what was verified (Linux, FPC 3.2.2, Xvfb) from what was not verified on real Mac hardware (installer, LaunchServices, Gatekeeper, LLDB). Don't upgrade those claims in `README.md` (the GitHub page, which embeds `assets/banner.svg`), `README.txt`, `docs/TEST_REPORT.txt` or `docs/COMPATIBILITY.txt` without actually running the check.
- License: GNU GPL v3 or later (`GPL-3.0-or-later`), copyright holder Syams Ideris. `LICENSE` is the verbatim GPLv3 text. New source files, scripts and bundled examples start with the notice (`# SPDX-License-Identifier: GPL-3.0-or-later` + `# Copyright (c) 2026 Syams Ideris` after any shebang; `<!-- SPDX-License-Identifier: GPL-3.0-or-later -->` in SVG; `{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }` in `.PAS`), and docs carry `Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.` under the title. The About window must keep the GPL "Appropriate Legal Notices": copyright, no warranty, redistribution under the GPL, and where to read `LICENSE`. The About window and the desktop caption read `__copyright__` from `odin/__init__.py`, and the author credit ("Created by Syams Ideris", from `__author__`) appears on the desktop under the logo, in the startup/idle status bar, in About (also wired to the macOS app menu via `tkAboutDialog`) and in the `Install.command` banner. The File > New template stays without a notice, because user programs belong to the user.
- The project must not include Borland assets or claim to be Borland's product. See the About text and `docs/COMPATIBILITY.txt`.
