# Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris
"""odin/metrics.py: reading step reports, comparing output, similarity, problem packages,
scoring, and Ukur/Periksa end to end with odinpc."""
import json
import tempfile
import unittest
from pathlib import Path

from odin import core, metrics

ROOT = Path(__file__).resolve().parent.parent
HAVE_ODINPC = bool(core.locate_toolchain()) and core.odin_supported()
NEEDS_ODINPC = "Needs odinpc (cargo build in toolchain/) on a host it supports (core.ODIN_HOSTS)"

NAIVE_PRIMES = """program Prima;
var
  N, i, j, jumlah: longint;
  prima: boolean;
begin
  ReadLn(N);
  jumlah := 0;
  for i := 2 to N do
  begin
    prima := true;
    for j := 2 to i - 1 do
      if i mod j = 0 then
        prima := false;
    if prima then
      jumlah := jumlah + 1;
  end;
  WriteLn(jumlah);
end.
"""


def toolchain() -> metrics.Toolchain:
    return metrics.Toolchain(core.locate_toolchain(), core.PACKAGE_ROOT / "rtl")


def write_package(folder: Path, rules: dict, cases: dict[str, tuple[str, str]]) -> Path:
    (folder / "kasus").mkdir(parents=True)
    (folder / "aturan.json").write_text(json.dumps(rules), encoding="utf-8")
    (folder / "soal.md").write_text("Hitung bilangan prima sampai N.\n", encoding="utf-8")
    for name, (given, expected) in cases.items():
        (folder / "kasus" / f"{name}.in").write_text(given, encoding="utf-8")
        (folder / "kasus" / f"{name}.out").write_text(expected, encoding="utf-8")
    return folder


class StatsTests(unittest.TestCase):
    def test_reads_the_golden_report(self):
        stats = metrics.read_stats((ROOT / "tests/steps/PRIMA.stats").read_text(encoding="utf-8"))
        self.assertEqual(stats["steps"], 4013823)
        self.assertEqual(stats["points"], 9)
        self.assertEqual(stats["counts"][3], 1999000)
        self.assertEqual(sum(stats["counts"].values()) + stats["weight"], stats["steps"])

    def test_rejects_other_text_and_ignores_unknown_keys(self):
        with self.assertRaises(ValueError):
            metrics.read_stats("bukan laporan\n")
        with self.assertRaises(ValueError):
            metrics.read_stats("otp-stats 1\nexit 0\n")
        text = "otp-stats 1\n" + "".join(f"{k} 0\n" for k in metrics.STATS_KEYS) + "kunci_baru 7\n"
        self.assertEqual(metrics.read_stats(text)["kunci_baru"], 7)

    def test_line_steps_sums_ids_of_one_line(self):
        stats = {"counts": {0: 1, 1: 5, 2: 7}}
        info = {"files": ["/x/prima.pas"], "lines": [[0, 3], [0, 9], [0, 9]]}
        self.assertEqual(metrics.line_steps(stats, info),
                         [{"file": "prima.pas", "line": 3, "steps": 1}, {"file": "prima.pas", "line": 9, "steps": 12}])

    def test_error_location_uses_the_address_table(self):
        info = {"image_base": 1000, "files": ["/x/a.pas"], "addresses": [[1000, 0, 5], [1100, 0, 8], [1200, 0, 12]]}
        # Link-time address 5150 - 5000 + 1000 = 1150: the statement starting at 1100.
        self.assertEqual(metrics.error_location(info, "240 5150 5000"), {"code": 240, "file": "a.pas", "line": 8})
        self.assertEqual(metrics.error_location(info, "240 5250 5000")["line"], 12)
        self.assertEqual(metrics.error_location(info, "201 100 4000"), {"code": 201, "file": None, "line": None})
        self.assertIsNone(metrics.error_location(info, "rusak"))


class CompareTests(unittest.TestCase):
    def test_trim_ignores_line_ends_crlf_and_final_blank_lines(self):
        self.assertIsNone(metrics.compare("4\n25\n", "4  \r\n25\r\n\r\n"))
        diff = metrics.compare("4\n25\n", "4\n26\n")
        self.assertEqual((diff.line, diff.expected, diff.actual), (2, "25", "26"))

    def test_exact_sees_trailing_spaces(self):
        self.assertIsNone(metrics.compare("a b\n", "a b\r\n", "exact"))
        self.assertEqual(metrics.compare("a b\n", "a b \n", "exact").line, 1)

    def test_missing_and_extra_lines(self):
        self.assertEqual(metrics.compare("1\n2\n", "1\n").line, 2)
        self.assertEqual(metrics.compare("1\n", "1\nlagi\n").line, 2)

    def test_tokens_ignore_layout(self):
        self.assertIsNone(metrics.compare("1 2\n3\n", "1\n  2 3", "tokens"))
        self.assertEqual(metrics.compare("Jumlah 4\n", "Jumlah: 4\n", "tokens").line, 1)

    def test_real_uses_the_tolerance(self):
        self.assertIsNone(metrics.compare("3.14159\n", "3.141592\n", "real", 1e-5))
        self.assertIsNotNone(metrics.compare("3.14159\n", "3.15\n", "real", 1e-5))
        self.assertIsNone(metrics.compare("x = 1e-9\n", "x = 0\n", "real", 1e-6))

    def test_unknown_mode(self):
        with self.assertRaises(ValueError):
            metrics.compare("", "", "huruf")


class SimilarityTests(unittest.TestCase):
    def test_identical_and_different_shapes(self):
        a = [[i + 1, t] for i, t in enumerate("for name int name assign name + name int".split() * 3)]
        same = metrics.similarity(a, [[l + 10, t] for l, t in a])
        self.assertEqual(same["ratio"], 1.0)
        self.assertEqual(same["blocks"][0]["b"][0], 11)
        other = metrics.similarity(a, [[1, "while"], [2, "name"]])
        self.assertLess(other["ratio"], 0.3)
        self.assertEqual(other["blocks"], [])

    @unittest.skipUnless(HAVE_ODINPC, NEEDS_ODINPC)
    def test_renamed_program_is_identical(self):
        tc = toolchain()
        shapes = {n: tc.structure(ROOT / "tests/metrics" / f"ANTRE_{n}.PAS")[0]["shape"] for n in "ABC"}
        self.assertEqual(metrics.similarity(shapes["A"], shapes["B"])["ratio"], 1.0)
        self.assertLess(metrics.similarity(shapes["A"], shapes["C"])["ratio"], 0.8)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_loads_cases_subtasks_and_hides_non_examples(self):
        p = metrics.load_package(write_package(self.dir / "p", {
            "judul": "Prima", "batas": {"langkah": 1000},
            "subtask": [{"nama": "S1", "poin": 40, "kasus": ["contoh*", "a*"]}, {"nama": "S2", "poin": 60, "kasus": ["b*"]}],
            "syarat": ["tanpa_goto"]}, {"contoh1": ("10", "4"), "a1": ("2", "1"), "b1": ("100", "25")}))
        self.assertEqual(p.title, "Prima")
        self.assertEqual([(c.name, c.hidden) for c in p.cases], [("a1", True), ("b1", True), ("contoh1", False)])
        self.assertEqual([(s.name, s.cases) for s in p.subtasks], [("S1", ["a1", "contoh1"]), ("S2", ["b1"])])
        self.assertEqual(len(p.sha256), 64)

    def test_refuses_bad_packages(self):
        cases = {"contoh1": ("1", "0")}
        for i, (rules, message) in enumerate([
                ({"pembanding": "huruf"}, "pembanding"),
                ({"syarat": ["terbang"]}, "syarat"),
                ({"batas": {"waktu": 5}}, "batas"),
                ({"subtask": [{"nama": "S1", "poin": 10, "kasus": ["tidak_ada"]}]}, "subtask")]):
            with self.assertRaisesRegex(metrics.PackageError, message):
                metrics.load_package(write_package(self.dir / f"p{i}", rules, cases))
        folder = write_package(self.dir / "tanpa_out", {}, cases)
        (folder / "kasus" / "contoh1.out").unlink()
        with self.assertRaisesRegex(metrics.PackageError, ".out"):
            metrics.load_package(folder)

    def test_scores_subtasks_and_best_of(self):
        p = metrics.load_package(write_package(self.dir / "p", {
            "subtask": [{"nama": "S1", "poin": 40, "kasus": ["a*"]}, {"nama": "S2", "poin": 60, "kasus": ["b*"]}]},
            {"a1": ("", ""), "a2": ("", ""), "b1": ("", "")}))
        first = metrics.score(p, {"a1": "lulus", "a2": "lulus", "b1": "salah"})
        second = metrics.score(p, {"a1": "salah", "a2": "lulus", "b1": "lulus"})
        self.assertEqual((first["points"], second["points"]), (40, 60))
        self.assertEqual(metrics.best_of([first, second])["points"], 100)
        plain = metrics.load_package(write_package(self.dir / "q", {}, {"x1": ("", ""), "x2": ("", ""), "x3": ("", "")}))
        self.assertEqual(metrics.score(plain, {"x1": "lulus", "x2": "lulus"})["points"], 66)


class VerdictTests(unittest.TestCase):
    def test_limits_errors_and_answers(self):
        v = lambda **k: metrics.verdict(**{"error_code": None, "exit_code": 0, "timed_out": False,
                                           "truncated": False, "difference": None, **k})
        self.assertEqual(v(), "lulus")
        self.assertEqual(v(difference=metrics.Difference(1, "4", "5")), "salah")
        self.assertEqual(v(error_code=240), "batas_langkah")
        self.assertEqual(v(error_code=203), "batas_heap")
        self.assertEqual(v(error_code=202), "batas_kedalaman")
        self.assertEqual(v(error_code=201), "runtime_error")
        self.assertEqual(v(exit_code=1), "runtime_error")
        self.assertEqual(v(timed_out=True, error_code=240), "batas_waktu")
        self.assertEqual(v(truncated=True), "batas_keluaran")

    def test_public_view_keeps_only_the_verdict_of_hidden_cases(self):
        report = {"cases": [{"name": "contoh1", "hidden": False, "verdict": "lulus", "steps": 9, "output": "4"},
                            {"name": "r1", "hidden": True, "verdict": "salah", "steps": 99, "difference": {"line": 1},
                             "subtask": "S1"}],
                  "lines": [{"line": 3, "steps": 9}]}
        view = metrics.public_view(report)
        self.assertEqual(view["cases"][1], {"name": "r1", "hidden": True, "verdict": "salah", "subtask": "S1"})
        self.assertEqual(view["cases"][0]["steps"], 9)
        self.assertEqual(view["lines"], [])
        self.assertEqual(report["cases"][1]["steps"], 99)


@unittest.skipUnless(HAVE_ODINPC, NEEDS_ODINPC)
class EndToEndTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_measure_reports_steps_lines_and_notes(self):
        report = metrics.measure(ROOT / "tests/steps/PRIMA.PAS", toolchain(), self.dir / "w")
        self.assertEqual((report["format"], report["version"]), ("otp-metrics", 1))
        case = report["cases"][0]
        self.assertEqual((case["verdict"], case["steps"], case["exit"]), ("selesai", 4013823, 0))
        self.assertEqual(case["output"].strip(), "303")
        by_line = {e["line"]: e["steps"] for e in report["lines"]}
        self.assertEqual(by_line[13], 1999000)
        self.assertEqual(by_line[14], 1997001)
        self.assertEqual([n["code"] for n in report["structure"]["notes"]], ["unused-var"])
        self.assertEqual(len(report["source"]["sha256"]), 64)

    def test_check_scores_cases_limits_and_requirements(self):
        source = self.dir / "prima.pas"
        source.write_text(NAIVE_PRIMES, encoding="utf-8")
        package = metrics.load_package(write_package(self.dir / "paket", {
            "judul": "Bilangan prima", "batas": {"langkah": 50000000}, "syarat": ["tanpa_goto", "rekursi"]},
            {"contoh1": ("10\n", "4\n"), "contoh2": ("100\n", "25\n"), "r1": ("1000\n", "168\n"),
             "r2": ("30000\n", "3245\n"), "r3": ("2\n", "2\n")}))
        report = metrics.check(source, package, toolchain(), self.dir / "w")
        verdicts = {c["name"]: c["verdict"] for c in report["cases"]}
        self.assertEqual(verdicts, {"contoh1": "lulus", "contoh2": "lulus", "r1": "lulus",
                                    "r2": "batas_langkah", "r3": "salah"})
        self.assertEqual(report["score"]["passed"], 3)
        self.assertEqual(report["score"]["points"], 60)
        self.assertEqual([(r["name"], r["met"]) for r in report["requirements"]],
                         [("tanpa_goto", True), ("rekursi", False)])
        limited = next(c for c in report["cases"] if c["name"] == "r2")
        self.assertEqual(limited["error"]["code"], 240)
        self.assertEqual(limited["steps"], 50000001)
        wrong = next(c for c in report["cases"] if c["name"] == "r3")
        self.assertEqual(wrong["difference"], {"line": 1, "expected": "2", "actual": "1"})
        # Steps per line from the larger example (N = 100): the inner for once per outer
        # iteration plus once per iteration, its if once per iteration.
        by_line = {e["line"]: e["steps"] for e in report["lines"]}
        self.assertEqual((by_line[11], by_line[12]), (99 + 4851, 4851))
        view = metrics.public_view(report)
        self.assertEqual(set(next(c for c in view["cases"] if c["name"] == "r3")), {"name", "hidden", "verdict"})

    def test_compile_error_is_reported(self):
        source = self.dir / "rusak.pas"
        source.write_text("program Rusak;\nbegin\n  x := 1;\nend.\n", encoding="utf-8")
        report = metrics.measure(source, toolchain(), self.dir / "w")
        self.assertFalse(report["compile"]["success"])
        self.assertEqual(report["compile"]["diagnostics"][0]["line"], 3)
        self.assertEqual(report["cases"], [])


if __name__ == "__main__":
    unittest.main()
