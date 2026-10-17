# Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris
"""Laporan metrik (otp-metrics/1): Ukur satu program dan Periksa terhadap paket soal.

The figures that judge a program come from the toolchain, not from the machine:
steps, heap and call depth from a `odinpc build --count-steps` run
(rtl/COMPILER_INTERFACE.md §8) and the structure notes from `odinpc metrics`. So a
report is the same on macOS, Linux and Windows for the same source, input and
odinpc. This module turns those into one JSON report; it uses only the standard
library and imports nothing else from `odin`, so other front ends can carry a copy.

Problem package (paket soal), a folder:

    soal.md          the statement (Markdown)
    aturan.json      {"judul": str,
                      "pembanding": "trim" | "exact" | "tokens" | "real" (default trim),
                      "toleransi": float (real only, default 1e-6),
                      "batas": {"langkah": int, "heap": int, "kedalaman": int},
                      "syarat": ["tanpa_goto", "rekursi", "larik", "record", "pointer", "prosedur"],
                      "subtask": [{"nama": str, "poin": int, "kasus": [glob, ...]}, ...]}
    kasus/NAME.in    input of case NAME; kasus/NAME.out its expected output.
                     Cases whose name starts with "contoh" are shown to the
                     participant; the others are hidden.
    rujukan.pas      reference solution (optional)

Without "subtask" every case weighs the same and the points are 100 * passed / total.
A subtask scores its points only when all its cases pass.
"""
from __future__ import annotations

import difflib
import fnmatch
import hashlib
import json
import os
import subprocess
import threading
from dataclasses import dataclass, field
from pathlib import Path

REPORT_FORMAT = "otp-metrics"
REPORT_VERSION = 1
COMPARE_MODES = ("trim", "exact", "tokens", "real")
REQUIREMENTS = {
    "tanpa_goto": ("tanpa goto", lambda f: f.get("gotos", 0) == 0),
    "rekursi": ("memakai rekursi", lambda f: bool(f.get("recursive"))),
    "larik": ("memakai larik", lambda f: bool(f.get("arrays"))),
    "record": ("memakai record", lambda f: bool(f.get("records"))),
    "pointer": ("memakai pointer", lambda f: bool(f.get("pointers"))),
    "prosedur": ("memakai prosedur atau fungsi", lambda f: f.get("routines", 0) > 0),
}
# Runtime error codes of the step-counting RTL that are limits, not bugs.
LIMIT_ERRORS = {240: "batas_langkah", 203: "batas_heap", 202: "batas_kedalaman"}
VERDICTS = ("lulus", "salah", "runtime_error", "batas_langkah", "batas_heap", "batas_kedalaman",
            "batas_waktu", "batas_keluaran", "gagal_jalan")
STATS_KEYS = ("exit", "steps", "weight", "heap_peak", "heap_end", "depth_max", "points")
OUTPUT_LIMIT = 1 << 20


class PackageError(ValueError):
    """A problem package that cannot be used; the message says why, in Indonesian."""


# ---- reports of a --count-steps run ---------------------------------------------------------

def read_stats(text: str) -> dict:
    """Parses the RTL's $ODIN_STATS_FILE: the figures plus "counts" {statement id: steps}.
    Unknown keys are ignored, as the format allows."""
    lines = text.splitlines()
    if not lines or lines[0].split() != ["otp-stats", "1"]:
        raise ValueError("bukan laporan otp-stats 1")
    stats: dict = {"counts": {}}
    for line in lines[1:]:
        parts = line.split()
        try:
            if len(parts) == 3 and parts[0] == "p":
                stats["counts"][int(parts[1])] = int(parts[2])
            elif len(parts) == 2:
                stats[parts[0]] = int(parts[1])
        except ValueError:
            raise ValueError(f"baris laporan tidak sah: {line!r}") from None
    missing = [k for k in STATS_KEYS if k not in stats]
    if missing:
        raise ValueError("laporan tidak lengkap: " + ", ".join(missing))
    return stats


def line_steps(stats: dict, debug_info: dict) -> list[dict]:
    """Steps per source line: statement ids mapped through the `lines` table of the
    program's .odbg, summed per (file, line), in file and line order."""
    files = debug_info.get("files", [])
    table = debug_info.get("lines", [])
    totals: dict[tuple[str, int], int] = {}
    for point, count in stats["counts"].items():
        if 0 <= point < len(table):
            file_index, line = table[point][0], table[point][1]
            name = Path(files[file_index]).name if 0 <= file_index < len(files) else ""
            totals[(name, line)] = totals.get((name, line), 0) + count
    return [{"file": f, "line": l, "steps": n} for (f, l), n in sorted(totals.items())]


def error_location(debug_info: dict, report: str) -> dict | None:
    """The RTL's $ODIN_ERROR_FILE report ("code address header") as {"code", "file", "line"}
    through the `addresses` table of the .odbg; file and line are None outside the program."""
    try:
        code, address, header = (int(v) for v in report.split()[:3])
        link = address - header + int(debug_info["image_base"])
        rows = debug_info["addresses"]
    except (ValueError, KeyError, TypeError):
        return None
    best = None
    for row in rows:
        if row[0] <= link and (best is None or row[0] >= best[0]):
            best = row
    if best is None:
        return {"code": code, "file": None, "line": None}
    files = debug_info.get("files", [])
    name = Path(files[best[1]]).name if 0 <= best[1] < len(files) else None
    return {"code": code, "file": name, "line": best[2]}


# ---- comparing output ----------------------------------------------------------------------

@dataclass
class Difference:
    """Where the output first differs from the expectation (1-based line) and both lines."""
    line: int
    expected: str
    actual: str

    def as_dict(self) -> dict:
        return {"line": self.line, "expected": self.expected, "actual": self.actual}


def _lines(text: str, trim: bool) -> list[str]:
    lines = text.replace("\r\n", "\n").split("\n")
    if trim:
        lines = [l.rstrip() for l in lines]
        while lines and lines[-1] == "":
            lines.pop()
    elif lines and lines[-1] == "":
        lines.pop()
    return lines


def _tokens(text: str) -> list[tuple[int, str]]:
    return [(n, t) for n, line in enumerate(_lines(text, False), 1) for t in line.split()]


def _same_number(a: str, b: str, tolerance: float) -> bool:
    try:
        x, y = float(a), float(b)
    except ValueError:
        return a == b
    return abs(x - y) <= tolerance * max(1.0, abs(x), abs(y))


def compare(expected: str, actual: str, mode: str = "trim", tolerance: float = 1e-6) -> Difference | None:
    """None when `actual` matches `expected` under `mode`, else the first difference.
    Every mode reads CR LF as LF (WriteLn ends lines with CR LF on Windows).
    trim ignores spaces at line ends and empty lines at the end; exact does not;
    tokens compares the words between any white space; real does too, numbers
    within `tolerance` (relative, absolute below 1) counting as equal."""
    if mode not in COMPARE_MODES:
        raise ValueError(f"pembanding tidak dikenal: {mode}")
    if mode in ("trim", "exact"):
        want, got = _lines(expected, mode == "trim"), _lines(actual, mode == "trim")
        for i in range(max(len(want), len(got))):
            w = want[i] if i < len(want) else ""
            g = got[i] if i < len(got) else ""
            if w != g or (i >= len(want)) != (i >= len(got)):
                return Difference(i + 1, w, g)
        return None
    want, got = _tokens(expected), _tokens(actual)
    want_lines, got_lines = _lines(expected, False), _lines(actual, False)
    for i in range(max(len(want), len(got))):
        w = want[i] if i < len(want) else None
        g = got[i] if i < len(got) else None
        same = w is not None and g is not None and (
            _same_number(w[1], g[1], tolerance) if mode == "real" else w[1] == g[1])
        if not same:
            line = (g or w)[0]
            return Difference(line, want_lines[line - 1] if line <= len(want_lines) else "",
                              got_lines[line - 1] if line <= len(got_lines) else "")
    return None


# ---- similarity ----------------------------------------------------------------------------

def similarity(shape_a: list, shape_b: list, min_block: int = 8) -> dict:
    """How alike two programs are, from their `odinpc metrics` shapes ([line, token] pairs;
    names, values, spacing and comments are not part of a shape). ratio is 0..1; blocks are
    the matching runs of at least `min_block` tokens as line ranges in both programs."""
    a = [t for _, t in shape_a]
    b = [t for _, t in shape_b]
    if not a and not b:
        return {"ratio": 1.0, "blocks": []}
    matcher = difflib.SequenceMatcher(None, a, b, autojunk=False)
    blocks = []
    for m in matcher.get_matching_blocks():
        if m.size >= min_block:
            blocks.append({"a": [shape_a[m.a][0], shape_a[m.a + m.size - 1][0]],
                           "b": [shape_b[m.b][0], shape_b[m.b + m.size - 1][0]], "size": m.size})
    return {"ratio": round(matcher.ratio(), 4), "blocks": blocks}


# ---- problem packages ----------------------------------------------------------------------

@dataclass
class Case:
    name: str
    input: bytes
    expected: str
    hidden: bool


@dataclass
class Subtask:
    name: str
    points: int
    cases: list[str]


@dataclass
class Package:
    folder: Path
    title: str
    statement: str
    compare: str
    tolerance: float
    limits: dict
    requirements: list[str]
    cases: list[Case]
    subtasks: list[Subtask]
    reference: Path | None
    sha256: str = ""


def _hash_folder(folder: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(p for p in folder.rglob("*") if p.is_file()):
        digest.update(path.relative_to(folder).as_posix().encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def load_package(folder: Path) -> Package:
    """Reads and checks a problem package (see the module docstring)."""
    folder = Path(folder)
    try:
        rules = json.loads((folder / "aturan.json").read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise PackageError("aturan.json tidak ada") from None
    except ValueError as error:
        raise PackageError(f"aturan.json bukan JSON yang sah: {error}") from None
    if not isinstance(rules, dict):
        raise PackageError("aturan.json harus berisi objek")
    mode = rules.get("pembanding", "trim")
    if mode not in COMPARE_MODES:
        raise PackageError(f"pembanding tidak dikenal: {mode}")
    limits = rules.get("batas", {})
    if not isinstance(limits, dict) or any(k not in ("langkah", "heap", "kedalaman") or not isinstance(v, int) or v <= 0
                                           for k, v in limits.items()):
        raise PackageError("batas hanya boleh berisi langkah, heap, dan kedalaman berupa bilangan bulat positif")
    requirements = rules.get("syarat", [])
    unknown = [r for r in requirements if r not in REQUIREMENTS]
    if unknown:
        raise PackageError("syarat tidak dikenal: " + ", ".join(unknown))
    cases = []
    for given in sorted((folder / "kasus").glob("*.in")) if (folder / "kasus").is_dir() else []:
        expected = given.with_suffix(".out")
        if not expected.is_file():
            raise PackageError(f"kasus {given.stem} tidak punya berkas .out")
        cases.append(Case(given.stem, given.read_bytes(), expected.read_text(encoding="utf-8", errors="replace"),
                          not given.stem.lower().startswith("contoh")))
    if not cases:
        raise PackageError("paket tidak punya kasus uji di kasus/*.in")
    subtasks = []
    names = [c.name for c in cases]
    for item in rules.get("subtask", []):
        if not isinstance(item, dict) or not isinstance(item.get("poin"), int) or not item.get("kasus"):
            raise PackageError("setiap subtask perlu nama, poin, dan kasus")
        matched = sorted({n for pattern in item["kasus"] for n in fnmatch.filter(names, pattern)})
        if not matched:
            raise PackageError(f"subtask {item.get('nama', '?')} tidak cocok dengan kasus mana pun")
        subtasks.append(Subtask(str(item.get("nama", f"S{len(subtasks) + 1}")), item["poin"], matched))
    statement = folder / "soal.md"
    reference = folder / "rujukan.pas"
    return Package(folder, str(rules.get("judul", folder.name)),
                   statement.read_text(encoding="utf-8") if statement.is_file() else "",
                   mode, float(rules.get("toleransi", 1e-6)), limits, list(requirements), cases, subtasks,
                   reference if reference.is_file() else None, _hash_folder(folder))


def score(package: Package, verdicts: dict[str, str]) -> dict:
    """Points of one submission: per subtask (all its cases must pass), or 100 * passed / total
    without subtasks."""
    passed = sum(1 for c in package.cases if verdicts.get(c.name) == "lulus")
    total = len(package.cases)
    subtasks = []
    for s in package.subtasks:
        ok = all(verdicts.get(n) == "lulus" for n in s.cases)
        subtasks.append({"name": s.name, "points": s.points if ok else 0, "max": s.points, "passed": ok})
    points = sum(s["points"] for s in subtasks) if subtasks else (100 * passed // total if total else 0)
    return {"passed": passed, "total": total, "points": points, "subtasks": subtasks}


def best_of(scores: list[dict]) -> dict:
    """OSN/IOI scoring across a participant's submissions to one problem: each subtask's best."""
    best: dict[str, dict] = {}
    for s in scores:
        for sub in s["subtasks"]:
            if sub["name"] not in best or sub["points"] > best[sub["name"]]["points"]:
                best[sub["name"]] = sub
    if not best:
        return {"points": max((s["points"] for s in scores), default=0), "subtasks": []}
    return {"points": sum(s["points"] for s in best.values()), "subtasks": list(best.values())}


def requirements(facts: dict, names: list[str]) -> list[dict]:
    """Whether the program meets each requirement of the package, from `odinpc metrics` facts."""
    return [{"name": n, "label": REQUIREMENTS[n][0], "met": bool(REQUIREMENTS[n][1](facts))} for n in names]


def verdict(*, error_code: int | None, exit_code: int, timed_out: bool, truncated: bool,
            difference: Difference | None) -> str:
    """The outcome of one case. A limit of the step-counting RTL (steps, heap, depth) is its
    own verdict; any other runtime error or a non-zero exit is runtime_error."""
    if timed_out:
        return "batas_waktu"
    if truncated:
        return "batas_keluaran"
    if error_code is not None:
        return LIMIT_ERRORS.get(error_code, "runtime_error")
    if exit_code != 0:
        return "runtime_error"
    return "lulus" if difference is None else "salah"


def public_view(report: dict) -> dict:
    """The report as a participant may see it: hidden cases keep only their verdict."""
    view = json.loads(json.dumps(report))
    for case in view.get("cases", []):
        if case.get("hidden"):
            for key in list(case):
                if key not in ("name", "hidden", "verdict", "subtask"):
                    del case[key]
    if any(c.get("hidden") for c in view.get("cases", [])):
        view["lines"] = []
    return view


# ---- building and running ------------------------------------------------------------------

@dataclass
class Run:
    """What running a program once gave back."""
    returncode: int
    output: bytes
    timed_out: bool = False
    truncated: bool = False
    wall_ms: int = 0


def run_local(argv: list[str], stdin: bytes, env: dict, cwd: Path, timeout: float,
              output_limit: int = OUTPUT_LIMIT) -> Run:
    """Runs a program here, without a sandbox: the desktop IDE's runner. A front end that
    runs programs elsewhere passes its own function with the same signature."""
    import time
    started = time.monotonic()
    # ODIN_* left in the IDE's own environment (a seed, a limit) must not change a run.
    inherited = {k: v for k, v in os.environ.items() if not k.upper().startswith("ODIN_")}
    process = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               cwd=cwd, env={**inherited, **env})
    chunks: list[bytes] = []
    state = {"size": 0, "truncated": False}

    def read():
        while True:
            data = process.stdout.read1(65536) if hasattr(process.stdout, "read1") else process.stdout.read(65536)
            if not data:
                return
            chunks.append(data)
            state["size"] += len(data)
            if state["size"] > output_limit:
                state["truncated"] = True
                process.kill()
                return

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    try:
        process.stdin.write(stdin)
        process.stdin.close()
    except OSError:
        pass
    timed_out = False
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()
        process.wait()
    reader.join(timeout=5)
    process.stdout.close()
    return Run(process.returncode, b"".join(chunks)[:output_limit], timed_out, state["truncated"],
               int((time.monotonic() - started) * 1000))


def _sha256(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _json_lines(text: str) -> list[dict]:
    items = []
    for line in text.splitlines():
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if isinstance(item, dict):
            items.append(item)
    return items


@dataclass
class Toolchain:
    """odinpc and the RTL it compiles with."""
    odinpc: str
    rtl: Path
    unit_paths: list[Path] = field(default_factory=list)

    def version(self) -> dict:
        out = subprocess.run([self.odinpc, "version"], stdout=subprocess.PIPE, text=True).stdout.split()
        return {"version": out[1] if len(out) > 1 else "", "target": out[2].strip("()") if len(out) > 2 else "",
                "sha256": _sha256(Path(self.odinpc))}

    def _common(self) -> list[str]:
        args = ["--rtl", str(self.rtl), "--diag-format", "json"]
        for p in self.unit_paths:
            args += ["--unit-path", str(p)]
        return args

    def structure(self, source: Path) -> tuple[dict | None, list[dict]]:
        """`odinpc metrics`: (figures, diagnostics); figures is None when the program does not compile."""
        out = subprocess.run([self.odinpc, "metrics", str(source), *self._common()], cwd=source.parent,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout
        items = _json_lines(out)
        figures = next((i for i in items if i.get("type") == "metrics"), None)
        diagnostics = [i for i in items if i.get("type") == "diagnostic"]
        if figures:
            for key in ("routines", "notes"):
                for entry in figures.get(key, []):
                    entry["file"] = Path(entry.get("file", "")).name
            figures = {k: figures[k] for k in ("routines", "notes", "facts", "shape") if k in figures}
        return figures, diagnostics

    def build(self, source: Path, folder: Path) -> tuple[Path | None, dict | None, list[dict]]:
        """A judge build (--count-steps with range and overflow checks): (executable, .odbg
        contents, diagnostics). The executable is None when the build fails."""
        folder.mkdir(parents=True, exist_ok=True)
        exe = folder / (source.stem + (".exe" if os.name == "nt" else ""))
        exe.unlink(missing_ok=True)
        out = subprocess.run([self.odinpc, "build", str(source), "--out", str(exe), "--cache", str(folder / "units"),
                              "--count-steps", "--range-checks", "--overflow-checks", *self._common()],
                             cwd=source.parent, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout
        items = _json_lines(out)
        result = next((i for i in items if i.get("type") == "result"), {})
        diagnostics = [i for i in items if i.get("type") == "diagnostic"]
        if not result.get("success") or not exe.is_file():
            return None, None, diagnostics
        odbg = Path(result.get("debug_info", str(exe) + ".odbg"))
        info = json.loads(odbg.read_text(encoding="utf-8")) if odbg.is_file() else {}
        return exe, info, diagnostics


def _run_case(exe: Path, debug_info: dict, name: str, stdin: bytes, limits: dict, workdir: Path,
              runner, timeout: float) -> tuple[Run, dict | None, dict | None]:
    folder = workdir / f"kasus-{name}"
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.iterdir():
        if old.is_file():
            old.unlink()
    stats_file, error_file = workdir / f"{name}.stats", workdir / f"{name}.error"
    stats_file.unlink(missing_ok=True)
    error_file.unlink(missing_ok=True)
    env = {"ODIN_STATS_FILE": str(stats_file), "ODIN_ERROR_FILE": str(error_file)}
    for key, var in (("langkah", "ODIN_STEP_LIMIT"), ("heap", "ODIN_HEAP_LIMIT"), ("kedalaman", "ODIN_DEPTH_LIMIT")):
        if limits.get(key):
            env[var] = str(limits[key])
    run = runner([str(exe)], stdin, env, folder, timeout)
    stats = None
    if stats_file.is_file():
        try:
            stats = read_stats(stats_file.read_text(encoding="utf-8"))
        except ValueError:
            stats = None
    error = error_location(debug_info, error_file.read_text(encoding="utf-8")) if error_file.is_file() else None
    return run, stats, error


def _case_entry(name: str, hidden: bool, run: Run, stats: dict | None, error: dict | None,
                difference: Difference | None, decided: str) -> dict:
    entry = {"name": name, "hidden": hidden, "verdict": decided,
             "exit": stats["exit"] if stats else run.returncode,
             "steps": stats["steps"] if stats else None, "weight": stats["weight"] if stats else None,
             "heap_peak": stats["heap_peak"] if stats else None, "depth_max": stats["depth_max"] if stats else None,
             "error": error, "difference": difference.as_dict() if difference else None,
             "machine": {"wall_ms": run.wall_ms}}
    if not hidden:
        entry["output"] = run.output.decode("utf-8", errors="replace")
    return entry


def _base_report(source: Path, toolchain: Toolchain, structure: dict | None, diagnostics: list[dict]) -> dict:
    return {"format": REPORT_FORMAT, "version": REPORT_VERSION,
            "source": {"name": source.name, "sha256": _sha256(source)},
            "odinpc": toolchain.version(), "package": None,
            "compile": {"success": structure is not None, "diagnostics": diagnostics},
            "cases": [], "score": None, "requirements": [], "structure": structure, "lines": []}


def measured(source: Path, toolchain: Toolchain, structure: dict | None, debug_info: dict, run: Run,
             stats_text: str | None, error_text: str | None) -> dict:
    """The Ukur report of a judge build that already ran (in the IDE's terminal, with its
    $ODIN_STATS_FILE and $ODIN_ERROR_FILE), from what those files hold."""
    source = Path(source).resolve()
    report = _base_report(source, toolchain, structure, [])
    try:
        stats = read_stats(stats_text) if stats_text else None
    except ValueError:
        stats = None
    error = error_location(debug_info, error_text) if error_text else None
    decided = verdict(error_code=error["code"] if error else None, exit_code=stats["exit"] if stats else run.returncode,
                      timed_out=run.timed_out, truncated=run.truncated, difference=None)
    if decided == "lulus":
        decided = "selesai"
    report["cases"].append(_case_entry("ukur", False, run, stats, error, None, decided))
    report["lines"] = line_steps(stats, debug_info) if stats else []
    return report


def measure(source: Path, toolchain: Toolchain, workdir: Path, stdin: bytes = b"", runner=run_local,
            timeout: float = 10.0, limits: dict | None = None) -> dict:
    """Ukur: builds the program for judging, runs it once with `stdin`, and reports its
    figures, steps per line and structure notes."""
    source, workdir = Path(source).resolve(), Path(workdir)
    structure, diagnostics = toolchain.structure(source)
    if structure is None:
        return _base_report(source, toolchain, structure, diagnostics)
    exe, info, diagnostics = toolchain.build(source, workdir / "build")
    if exe is None:
        report = _base_report(source, toolchain, structure, diagnostics)
        report["compile"] = {"success": False, "diagnostics": diagnostics}
        return report
    run, _, _ = _run_case(exe, info, "ukur", stdin, limits or {}, workdir, runner, timeout)
    read = lambda p: p.read_text(encoding="utf-8") if p.is_file() else None
    return measured(source, toolchain, structure, info, run, read(workdir / "ukur.stats"), read(workdir / "ukur.error"))


def check(source: Path, package: Package, toolchain: Toolchain, workdir: Path, runner=run_local,
          timeout: float = 10.0) -> dict:
    """Periksa: every case of `package`, scored, with the requirements and structure notes.
    The steps per line come from the largest visible case."""
    source, workdir = Path(source).resolve(), Path(workdir)
    structure, diagnostics = toolchain.structure(source)
    report = _base_report(source, toolchain, structure, diagnostics)
    report["package"] = {"title": package.title, "sha256": package.sha256}
    verdicts: dict[str, str] = {}
    exe = info = None
    if structure is not None:
        exe, info, diagnostics = toolchain.build(source, workdir / "build")
        if exe is None:
            report["compile"] = {"success": False, "diagnostics": diagnostics}
    subtask_of = {n: s.name for s in package.subtasks for n in s.cases}
    best_visible = None
    for case in package.cases:
        if exe is None:
            verdicts[case.name] = "gagal_jalan"
            report["cases"].append({"name": case.name, "hidden": case.hidden, "verdict": "gagal_jalan"})
            continue
        run, stats, error = _run_case(exe, info, case.name, case.input, package.limits, workdir, runner, timeout)
        actual = run.output.decode("utf-8", errors="replace")
        difference = compare(case.expected, actual, package.compare, package.tolerance)
        decided = verdict(error_code=error["code"] if error else None,
                          exit_code=stats["exit"] if stats else run.returncode,
                          timed_out=run.timed_out, truncated=run.truncated, difference=difference)
        verdicts[case.name] = decided
        entry = _case_entry(case.name, case.hidden, run, stats, error, difference, decided)
        if case.name in subtask_of:
            entry["subtask"] = subtask_of[case.name]
        report["cases"].append(entry)
        if not case.hidden and stats and (best_visible is None or stats["steps"] > best_visible["steps"]):
            best_visible = stats
    report["score"] = score(package, verdicts)
    if structure is not None:
        report["requirements"] = requirements(structure.get("facts", {}), package.requirements)
    if best_visible and info:
        report["lines"] = line_steps(best_visible, info)
    return report


# ---- the report for people -----------------------------------------------------------------

VERDICT_LABELS = {"lulus": "Lulus", "selesai": "Selesai", "salah": "Keluaran salah", "runtime_error": "Runtime error",
                  "batas_langkah": "Batas langkah", "batas_heap": "Batas heap", "batas_kedalaman": "Batas kedalaman",
                  "batas_waktu": "Batas waktu", "batas_keluaran": "Keluaran terlalu panjang",
                  "gagal_jalan": "Tidak dijalankan"}


def number(n: int | None) -> str:
    """1234567 as 1.234.567; None as a dash."""
    return "-" if n is None else f"{n:,}".replace(",", ".")


def size(n: int | None) -> str:
    """Bytes as B, KB or MB with a decimal comma."""
    if n is None:
        return "-"
    if n < 1024:
        return f"{n} B"
    for unit, scale in (("KB", 1024), ("MB", 1024 ** 2)):
        if n < scale * 1024 or unit == "MB":
            return f"{n / scale:.1f} {unit}".replace(".", ",")
    return f"{n} B"


def summary(report: dict) -> list[tuple[str, int | None]]:
    """The report as lines of text for the IDE's Metrik window: (text, source line to jump
    to or None). Sections follow docs/HELP.txt: official figures (the same everywhere), this
    machine's figures, cases, requirements, steps per line, structure notes."""
    out: list[tuple[str, int | None]] = []
    add = lambda text="", line=None: out.append((text, line))
    tc = report.get("odinpc", {})
    title = f"Periksa {report['source']['name']} \u00b7 {report['package']['title']}" if report.get("package") \
        else f"Ukur {report['source']['name']}"
    add(title)
    add(f"odinpc {tc.get('version', '')} \u00b7 {tc.get('target', '')} \u00b7 laporan {report['format']}/{report['version']}")
    add()
    if not report["compile"]["success"]:
        add(f"Gagal compile ({len(report['compile']['diagnostics'])} pesan). Lihat Compile > Compiler messages.")
        return out
    facts = (report.get("structure") or {}).get("facts", {})
    cases = report.get("cases", [])
    if report.get("score"):
        s = report["score"]
        add(f"SKOR {s['points']}   ({s['passed']} dari {s['total']} kasus lulus)")
        for sub in s["subtasks"]:
            add(f"  {sub['name']}: {sub['points']}/{sub['max']}" + ("" if sub["passed"] else "  (belum lulus)"))
        add()
        add("KASUS")
        for c in cases:
            label = VERDICT_LABELS.get(c["verdict"], c["verdict"])
            hidden = " (tersembunyi)" if c.get("hidden") else ""
            add(f"  {c['name']}{hidden}: {label}   langkah {number(c.get('steps'))}, heap {size(c.get('heap_peak'))}")
            d = c.get("difference")
            if d and not c.get("hidden"):
                add(f"      baris {d['line']}: diharapkan {d['expected']!r}, keluaran {d['actual']!r}")
            e = c.get("error")
            if e and e.get("line"):
                add(f"      runtime error {e['code']} di baris {e['line']}", e["line"])
        for r in report.get("requirements", []):
            add(f"  Syarat {r['label']}: " + ("terpenuhi" if r["met"] else "TIDAK terpenuhi"))
        add()
    elif cases:
        c = cases[0]
        add(f"{VERDICT_LABELS.get(c['verdict'], c['verdict'])}, kode keluar {c.get('exit')}")
        e = c.get("error")
        if e and e.get("line"):
            add(f"Runtime error {e['code']} di baris {e['line']}", e["line"])
        add()
        add("ANGKA RESMI (sama di macOS, Linux, dan Windows)")
        add(f"  Langkah eksekusi      {number(c.get('steps'))}" +
            (f"  (termasuk {number(c['weight'])} untuk menyalin data)" if c.get("weight") else ""))
        add(f"  Puncak heap           {size(c.get('heap_peak'))}")
        add(f"  Memori global         {size(facts.get('global_bytes'))}")
        add(f"  Kedalaman panggilan   {number(c.get('depth_max'))}")
        add()
        add("INFO MESIN INI (tidak dinilai, berbeda antar-mesin)")
        add(f"  Waktu nyata           {number((c.get('machine') or {}).get('wall_ms'))} ms")
        add()
    lines = report.get("lines", [])
    if lines:
        total = sum(e["steps"] for e in lines) or 1
        add("PETA LANGKAH (baris dengan langkah terbanyak)")
        for e in sorted(lines, key=lambda e: -e["steps"])[:5]:
            share = f"{100 * e['steps'] / total:.1f}".replace(".", ",")
            add(f"  baris {e['line']:>4}   {number(e['steps']):>14}   {share} %", e["line"])
        add()
    notes = (report.get("structure") or {}).get("notes", [])
    add(f"CATATAN STRUKTUR ({len(notes)})")
    for n in notes:
        level = "Saran" if n["level"] == "saran" else "Info"
        add(f"  [{level}] {n['message']} (baris {n['line']})", n["line"])
    if not notes:
        add("  Tidak ada catatan.")
    return out
