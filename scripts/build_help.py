#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
"""Build docs/help.html (Help > Contents in a browser) from scripts/help_shell.html, scripts/help_body.html and the
reference tables in docs/PASCAL.txt and docs/SHORTCUTS.txt, so there is one source for each fact.

    python3 scripts/build_help.py          # write docs/help.html
    python3 scripts/build_help.py --check  # exit 1 if docs/help.html is stale
"""
import base64
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from odin import __version__  # noqa: E402

OUT = ROOT / "docs" / "help.html"
CHAPTERS = {
    1: "Pengenalan", 2: "Struktur program", 3: "Tipe data", 4: "Masukan dan keluaran", 5: "Operator",
    6: "Percabangan", 7: "Pengulangan", 8: "Latihan logika", 9: "Prosedur dan fungsi", 10: "Rekursi",
    11: "Array", 12: "String", 13: "Record", 14: "Enumerasi, subrentang, dan set", 15: "Pencarian",
    16: "Pengurutan", 17: "Berkas", 18: "Pointer dan linked list", 19: "Unit", 20: "Proyek akhir",
}
APPENDIX = "ABCDEFGH"


def e(text):
    return html.escape(text, quote=False)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def blocks(lines):
    """Blank-line separated groups of lines."""
    group = []
    for line in lines:
        if line.strip():
            group.append(line)
        elif group:
            yield group
            group = []
    if group:
        yield group


def section(text, name):
    """Lines of the section that starts at a line equal to NAME, up to the next heading line."""
    lines = text.splitlines()
    start = lines.index(name) + 1
    body = []
    for line in lines[start:]:
        if re.fullmatch(r"[A-Z][A-Z0-9 ,/()-]{3,}", line):
            break
        body.append(line)
    return body


def entries(group, col):
    """Rows (name, description) when GROUP is a reference table whose descriptions start at column COL, else None."""
    rows = []
    for i, line in enumerate(group):
        if line.startswith(" " * col):
            if not rows:
                return None
            rows[-1][1].append(line.strip())
        elif len(line) > col and line[col - 2:col].isspace() and line[:col].strip() and not line[col].isspace():
            rows.append([line[:col].strip(), [line[col:].strip()]])
        elif len(line) < col and i + 1 < len(group) and group[i + 1].startswith(" " * col):
            rows.append([line.strip(), []])
        else:
            return None
    return [(name, " ".join(desc)) for name, desc in rows]


def rows_by_regex(group):
    """Shortcut tables: 'KEY   description' with at least two spaces between them."""
    rows = []
    for line in group:
        m = re.fullmatch(r"(\S.*?)\s{2,}(\S.*)", line)
        if not m:
            return None
        rows.append((m[1], m[2]))
    return rows


def table(rows, seen, kbd=False, head=("Nama", "Keterangan")):
    out = ['<div class="tw"><table class="ref"><tr><th>%s</th><th>%s</th></tr>' % head]
    for name, desc in rows:
        key = "k-" + slug(re.split(r"[(\s,]", name)[0])
        attr = ""
        if key != "k-" and key not in seen:
            seen.add(key)
            attr = ' id="%s"' % key
        cell = kbd_cell(name) if kbd else "<code>%s</code>" % e(name)
        if not kbd:
            # 'Cos(X), Sin(X)' and 'class, try, except' are findable by every name (F1 in the editor links to k-<name>).
            for alt in re.sub(r"\([^)]*\)", "", name).split(","):
                alt = "k-" + slug(alt)
                if re.fullmatch(r"k-[a-z0-9-]+", alt) and alt not in seen and alt != "k-":
                    seen.add(alt)
                    cell += '<span id="%s"></span>' % alt
        out.append("<tr%s><td>%s</td><td>%s</td></tr>" % (attr, cell, e(desc)))
    out.append("</table></div>")
    return "\n".join(out)


def kbd_cell(keys):
    parts = re.split(r"(\s/\s|\s)", keys)
    return "".join(e(p) if p.strip() in ("", "/") else "<kbd>%s</kbd>" % e(p) for p in parts)


def render(lines, col=None, shortcuts=False, seen=None):
    seen = seen if seen is not None else set()
    out = []
    for group in blocks(lines):
        rows = rows_by_regex(group) if shortcuts else entries(group, col)
        if rows:
            out.append(table(rows, seen, kbd=shortcuts, head=("Tombol", "Fungsi") if shortcuts else ("Nama", "Keterangan")))
        else:
            out.append("<p>%s</p>" % e(" ".join(l.strip() for l in group)))
    return "\n".join(out)


def pascal(name, seen):
    text = (ROOT / "docs" / "PASCAL.txt").read_text(encoding="utf-8")
    return render(section(text, name), col=30, seen=seen)


def shortcuts(part, seen):
    text = (ROOT / "docs" / "SHORTCUTS.txt").read_text(encoding="utf-8")
    parts = {"": [], "MAC ALTERNATIVES": [], "USER SCREEN": []}
    key = ""
    for line in text.splitlines():
        if line and line in parts:
            key = line
        else:
            parts[key].append(line)
    if part in ("fn", "general"):
        tables = [g for g in blocks(parts[""]) if rows_by_regex(g)]
        return render(tables[0 if part == "fn" else 1], shortcuts=True, seen=seen)
    return render(parts["MAC ALTERNATIVES" if part == "mac" else "USER SCREEN"], shortcuts=True, seen=seen)


def tutorial():
    groups = {}
    for path in sorted((ROOT / "examples").glob("bab*.pas")):
        m = re.fullmatch(r"bab(\d\d)_(\d\d)_(.+)\.pas", path.name)
        groups.setdefault(int(m[1]), []).append((path.name, m[3].replace("_", " ")))
    rows = ['<div class="tw"><table class="wrap"><tr><th>Bab</th><th>Topik</th><th>Program</th></tr>']
    for chapter, files in sorted(groups.items()):
        items = ", ".join("<code title=\"%s\">%s</code>" % (e(n), e(t)) for n, t in files)
        rows.append("<tr><td>%d</td><td>%s</td><td>%s</td></tr>" % (chapter, e(CHAPTERS[chapter]), items))
    rows.append("</table></div>")
    count = sum(len(f) for f in groups.values())
    return ("<p>%d program dalam %d bab, ditambah unit <code>matematika.pas</code> untuk Bab 19. Arahkan penunjuk ke nama "
            "program untuk melihat nama berkasnya.</p>\n" % (count, len(groups))) + "\n".join(rows)


def number(body):
    """Number the h2/h3 headings (appendices get letters), add anchors, and return (body, toc)."""
    toc, state = [], {"h2": 0, "h3": 0, "app": 0}

    def heading(m):
        tag, attrs, title = m[1], m[2], m[3]
        hid = re.search(r'id="([^"]+)"', attrs)[1]
        if tag == "h2":
            state["h3"] = 0
            if "appendix" in attrs:
                label = APPENDIX[state["app"]]
                state["app"] += 1
            else:
                state["h2"] += 1
                label = str(state["h2"])
            toc.append([label, hid, title, [], "appendix" in attrs])
            state["label"] = label
        else:
            state["h3"] += 1
            label = "%s.%d" % (state["label"], state["h3"])
            toc[-1][3].append((label, hid, title))
        return '<%s%s><span class="n">%s</span>%s <a class="anchor" href="#%s" aria-label="Tautan">#</a></%s>' % (
            tag, attrs, label, title, hid, tag)

    body = re.sub(r"<(h2|h3)([^>]*)>(.*?)</\1>", heading, body)
    out = ["    <ul>"]
    appendix_started = False
    for label, hid, title, subs, appendix in toc:
        if appendix and not appendix_started:
            out.append('    </ul>\n    <div class="sep">Lampiran</div>\n    <ul>')
            appendix_started = True
        out.append('      <li><a href="#%s"><span class="n">%s</span>%s</a>' % (hid, label, title))
        if subs:
            out.append("        <ul>" + "".join('<li><a href="#%s">%s</a></li>' % (i, t) for _, i, t in subs) + "</ul>")
        out.append("      </li>")
    out.append("    </ul>")
    return body, "\n".join(out)


def build():
    body = (ROOT / "scripts" / "help_body.html").read_text(encoding="utf-8")
    seen = set()

    def marker(m):
        kind, _, arg = m[1].partition(":")
        if kind == "pascal":
            return pascal(arg, seen)
        if kind == "shortcuts":
            return shortcuts(arg, seen)
        if kind == "tutorial":
            return tutorial()
        raise SystemExit("unknown marker " + m[0])

    body = re.sub(r"<!--@(.+?)-->", marker, body)
    body, toc = number(body)
    logo = base64.b64encode((ROOT / "assets" / "odin-logo-small.png").read_bytes()).decode()
    page = (ROOT / "scripts" / "help_shell.html").read_text(encoding="utf-8")
    for key, value in (("{{LOGO}}", logo), ("{{TOC}}", toc), ("{{BODY}}", body)):
        page = page.replace(key, value)
    return page.replace("{{VERSION}}", __version__)


def main():
    page = build()
    if "--check" in sys.argv:
        if not OUT.is_file() or OUT.read_text(encoding="utf-8") != page:
            print("docs/help.html is out of date: run scripts/build_help.py")
            return 1
        return 0
    OUT.write_text(page, encoding="utf-8")
    print("wrote %s (%d KB)" % (OUT.relative_to(ROOT), len(page) // 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
