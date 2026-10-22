# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Syams Ideris
import importlib.util
import io
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch
from pathlib import Path

from odin import __version__, __version_tag__
from odin import core
from odin.core import (Document, Settings, build, data_dir, executable_name, join_command, locate_toolchain, lock_instance,
                       odin_supported, split_arguments, syntax_spans, unlock_instance)
from odin.terminal import ALT_MASKS, KEYS, Process, Screen, color_256, modified_key, mouse_report

ROOT=Path(__file__).resolve().parent.parent
HAS_ODIN=bool(locate_toolchain() and odin_supported())
NEEDS_ODIN="Needs odinpc (cargo build in toolchain/) on a host it supports (core.ODIN_HOSTS)"
# The IDE's default page, which carries the release tag.
FIRST_EXAMPLE="bab01_01_halo_dunia.pas"

# Standard input and expected output for every tutorial program in examples/ except the Crt ones
# (bab19_02, bab19_03), which need a terminal. They run in name order in one folder, so
# bab17_02 reads the catatan.txt that bab17_01 wrote.
EXAMPLE_RUNS={
    "bab01_01_halo_dunia":("",["Halo, Dunia!"]),
    "bab01_02_cek_kompiler":("",["Integer  : 2 byte","Kompiler siap dipakai."]),
    "bab02_01_struktur_dasar":("",["Total bayar      : 100000"]),
    "bab02_02_komentar":("",["Luas = 40"]),
    "bab02_03_blok_begin_end":("",["Satu pernyataan: Lulus","  Blok dalam"]),
    "bab03_01_tipe_integer_real":("",["100 / 32     = 3.1250","Round(165.9)        : 166"]),
    "bab03_02_tipe_char_string":("",["Kode huruf A   : 65","Kota  : Kandangan (dipotong","Jum'at"]),
    "bab03_03_tipe_boolean":("",["Sudah dewasa? : TRUE","Boleh membuat SIM."]),
    "bab03_04_konstanta":("",["Bayar      : Rp 121500"]),
    "bab03_05_batas_tipe_data":("",["Integer     2        -32768         32767","MaxLongInt = 2147483647"]),
    "bab04_01_write_writeln":("",["Satu baris yang sama.","Hasil 7 x 6 = 42"]),
    "bab04_02_read_readln":("Syams\n40\n170.5\n3 4\n",["Tahun depan umur Anda 41 tahun.","Tinggi Anda 170.5 cm.","3 + 4 = 7"]),
    "bab04_03_format_keluaran":("",["[    42]","    3.1416"," 2  Buku tulis       5    6000.00"]),
    "bab04_04_biodata_sederhana":("Syams\nKandangan\n1986\n170\n65.5\nMembaca\n",["Umur   : 40 tahun","Berat  : 65.5 kg"]),
    "bab05_01_operator_aritmetika":("",["A / B = 3.40","Sqrt(81) = 9.0"]),
    "bab05_02_div_mod":("3725\n47\n",["3725 detik = 1 jam 2 menit 5 detik","Angka satuan = 7"]),
    "bab05_03_operator_relasional":("",["A <> B : TRUE","'Ani' < 'Budi' : TRUE"]),
    "bab05_04_operator_logika":("",[" TRUE  FALSE    FALSE    TRUE     TRUE","Boleh masuk (umur >= 13 dan punya tiket)? TRUE"]),
    "bab05_05_prioritas_operator":("",["2 + 3 * 4       = 14","(2 + 3) * 4     = 20"]),
    "bab05_06_luas_keliling":("8\n5\n7\n",["Keliling = 26.00 cm","Luas     = 153.94 cm2"]),
    "bab06_01_if_then":("38\n",["Anda demam.","Pemeriksaan selesai."]),
    "bab06_02_if_else":("7\n60\n",["7 adalah bilangan ganjil","Kurang 15 poin lagi."]),
    "bab06_03_if_bersarang":("17\ny\n",["Harga tiket: Rp 20000"]),
    "bab06_04_case_of":("7\nk\n",["Sabtu","Hari libur akhir pekan.","Huruf konsonan"]),
    "bab06_05_nilai_huruf":("72\n",["Nilai huruf: B"]),
    "bab06_06_tahun_kabisat":("1900\n",["1900 bukan tahun kabisat"]),
    "bab07_01_for_to":("7\n",["1 + 2 + ... + 7 = 28","  7 x 10 =   70"]),
    "bab07_02_for_downto":("",["10 9 8 7 6 5 4 3 2 1 Mulai!","ZYXWVUTSRQPONMLKJIHGFEDCBA"]),
    "bab07_03_while_do":("9875\n4\n6\n-2\n0\n",["Jumlah digit 9875 = 29","Banyak bilangan: 3, jumlahnya: 8"]),
    "bab07_04_repeat_until":("150\n80\ny\nt\n",["Nilai tidak sah","Nilai diterima: 80","Selesai setelah 2 putaran."]),
    "bab07_05_perulangan_bersarang":("",[" 9 |   9  18  27  36  45  54  63  72  81"]),
    "bab07_06_menu_berulang":("1\n100\n3\n42.195\n9\n0\n",["212.0 F","26.22 mil","Pilihan tidak tersedia.","Terima kasih!"]),
    "bab08_01_bilangan_prima":("97\n",["97 adalah bilangan prima.","Ada 25 bilangan prima."]),
    "bab08_02_fpb_kpk":("84\n36\n",["FPB(84, 36) = 12","KPK(84, 36) = 252"]),
    "bab08_03_deret_fibonacci":("50\n40\n",["Suku 40:  102334155"]),
    "bab08_04_segitiga_bintang":("4\n",["\n   *\n  ***\n *****\n*******"]),
    "bab08_05_bilangan_sempurna":("",["28 = 1 + 2 + 4 + 7 + 14","8128 = 1 + 2 + 4"]),
    "bab08_06_tebak_angka":("".join(f"{i}\n" for i in range(1,101)),["Benar! Angkanya"]),
    "bab09_01_prosedur_dasar":("",["DAFTAR MENU KANTIN SEKOLAH","Selamat makan!"]),
    "bab09_02_fungsi_dasar":("",["Kuadrat 3 + 4    = 25","Luas lingkaran r=7: 153.94"]),
    "bab09_03_parameter_nilai":("",["Di dalam prosedur, X = 10","Sesudah dipanggil, Angka = 5"]),
    "bab09_04_parameter_var":("",["Sesudah ditukar: X = 8, Y = 3","luas 24.0, keliling 20.0"]),
    "bab09_05_lokal_global":("",["Hitungan lokal = 100","Kembali di program utama, Hitungan = 2"]),
    "bab09_06_kalkulator_modular":("4\n12\n0\n4\n12\n4\n0\n",["Pembagi tidak boleh nol.","Hasil: 3.00","Sampai jumpa!"]),
    "bab10_01_faktorial_rekursif":("",["    masuk Faktorial(2)","Faktorial(4) = 24","12! =  479001600"]),
    "bab10_02_fibonacci_rekursif":("",["25         75025             150049"]),
    "bab10_03_pangkat_rekursif":("2\n10\n",["Cara biasa : 1024.00  (11 pemanggilan)","Cara cepat : 1024.00  (5 pemanggilan)"]),
    "bab10_04_menara_hanoi":("9\n3\n",["   4. Cakram 3: A -> C","Selesai dalam 7 langkah"]),
    "bab11_01_array_satu_dimensi":("70\n85\n90\n60\n75\n",["Urutan terbalik: 75 60 90 85 70"]),
    "bab11_02_maks_min_rata":("4\n12\n45\n7\n30\n",["Terbesar  : 45 (data ke-2)","Rata-rata : 23.50"]),
    "bab11_03_array_dua_dimensi":("",["  3      95   88   92   90  91.25"]),
    "bab11_04_penjumlahan_matriks":("",["A + B:\n   10   10   10"]),
    "bab11_05_perkalian_matriks":("",["    58    64\n   139   154"]),
    "bab12_01_fungsi_string":("",["Pos \"itu\" : 16","Kapital   : PASCAL ITU SANGAT MENYENANGKAN"]),
    "bab12_02_balik_kata":("saya  suka pascal\n",["Huruf dibalik : lacsap akus  ayas","Kata dibalik  : pascal suka saya"]),
    "bab12_03_palindrom":("Kasur ini rusak\nPascal\n\n",["\"Kasur ini rusak\" adalah palindrom.","\"Pascal\" bukan palindrom."]),
    "bab12_04_hitung_vokal":("Odin Turbo Pascal 2026!\n",["Vokal    : 6","Konsonan : 9","Angka    : 4"]),
    "bab12_05_konversi_angka_string":("12a50\n-5\n1250000\n",["salah di karakter ke-3","tidak boleh negatif","Harga      : Rp 1.250.000"]),
    "bab13_01_record_dasar":("",["harga diskon Rp 75000","Asli   : harga tetap Rp 85000"]),
    "bab13_02_array_of_record":("2\nAni\nX-A\n88\nBudi\nX-B\n92\n",[" 2  Budi                  X-B       92","Nilai tertinggi: Budi (92)"]),
    "bab13_03_record_bersarang":("",["Lahir     : 17-8-1995","            Kandangan 71211"]),
    "bab13_04_data_mahasiswa":("1\n2601004\nDewi\n3.91\n3\n2601002\n4\n0\n",["Bunga Lestari","IPK tertinggi : Dewi (3.91)"]),
    "bab14_01_tipe_enumerasi":("",["6. Minggu : libur","Besok       : Kamis"]),
    "bab14_02_tipe_subrange":("2\n150\n5\n",["Bulan 2 punya 28 hari","Nilai harus 0 sampai 100.","Inisial harus berupa huruf.","Hari kerja: 5 hari"]),
    "bab14_03_tipe_set":("",["Andi * Budi   : Rabu Jumat","Andi sekarang : Rabu Jumat Minggu"]),
    "bab14_04_validasi_huruf_set":("Rahasia#2026\n081234567890\n",["Kekuatan: KUAT (5/5)","Nomor HP sah."]),
    "bab15_01_sequential_search":("32\n",["32 ditemukan di posisi 4 setelah 4 perbandingan.","Semua posisi: 4 7"]),
    "bab15_02_binary_search":("68\n",["68 ditemukan di posisi 13.","Jumlah langkah: 4"]),
    "bab15_03_cari_data_record":("b001\npensil\n",["B001  Buku gambar","2 barang cocok."]),
    "bab16_01_bubble_sort":("",["Putaran 6 :","Hasil     :   5  10  13  14  21  29  37  42"]),
    "bab16_02_selection_sort":("",["Putaran 7 :","Hasil     :   5  10  13  14  21  29  37  42"]),
    "bab16_03_insertion_sort":("",["Sisip 21  :","Hasil     :   5  10  13  14  21  29  37  42"]),
    "bab16_04_urut_record":("",["    1      Citra             92","    3      Gita              88"]),
    "bab16_05_banding_jumlah_langkah":("",["Selection sort  190/  18  190/   0  190/  10"]),
    "bab17_01_tulis_file_teks":("Belajar\nPascal\nOdin\n",["Tersimpan ke file catatan.txt"]),
    "bab17_02_baca_file_teks":("",["  5 | 3. Odin","Jumlah baris: 5"]),
    "bab17_03_tambah_file_teks":("Tambahan\n",["  + Tambahan","catatan.txt kini berisi 6 baris."]),
    "bab17_04_file_bertipe":("",["Elemen nomor 4 berisi 25","1000 4 9 16 25 36 49 64 81 100"]),
    "bab17_05_simpan_baca_record":("Ani\nX-A\n88\n\n",["Data tersimpan saat ini: 0 siswa."," 1  Ani"]),
    "bab18_01_pointer_dasar":("",["Setelah Q^ := Q^ + 1, X = 100, P^ = 100"]),
    "bab18_02_new_dispose":("",["Isi memori baru: 2026","Sari: 81"]),
    "bab18_03_linked_list_tambah":("",["Awal -> 1 -> 5 -> 12 -> 8 -> nil"]),
    "bab18_04_linked_list_hapus":("",["Hapus 99: tidak ditemukan","Hapus 40:\n  nil"]),
    "bab19_01_pakai_unit_sendiri":("",["KPK(4, 6)       = 12","matematika.Kuadrat(12) = 144"]),
    "bab20_01_kasir_sederhana":("b01\n2\nx99\nb05\n3\n\n100\n200000\n",["Kode tidak dikenal.","Diskon 10%","Kembali                        Rp 50.150"]),
    "bab20_02_nilai_siswa":("2\nAni\n80\n85\n90\nBudi\n60\n70\n65\n",[" 1  Ani","Tuntas          : 1 dari 2 siswa"]),
    "bab20_03_buku_telepon":("2\nSiti\n08123456789\ns@x.id\n0\n",["1 kontak disimpan ke kontak.dat."]),
}


class VersionTests(unittest.TestCase):
    def test_help_html_is_current(self):
        # docs/help.html is generated from docs/*.txt and the version; a stale copy fails here.
        result=subprocess.run([sys.executable,str(ROOT/"scripts"/"build_help.py"),"--check"],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+"\nJalankan python3 scripts/build_help.py")

    def test_first_example_carries_release_tag(self):
        # scripts/package_app.py restamps this comment on every build; a stale tag fails here.
        self.assertEqual(__version_tag__,f"v{__version__}")
        self.assertIn(f"{{ Odin Turbo Pascal {__version_tag__} - program pertama }}",(ROOT/"examples"/FIRST_EXAMPLE).read_text(encoding="utf-8"))

    def test_set_version_rewrites_every_copy(self):
        # Runs the real bump on copies of the real files, so a reworded README or doc fails here, not at release time.
        spec=importlib.util.spec_from_file_location("set_version",ROOT/"scripts"/"set_version.py")
        set_version=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(set_version)
        with tempfile.TemporaryDirectory() as temp:
            temp=Path(temp)
            for name in set_version.FILES:
                (temp/name).parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(ROOT/name,temp/name)
            changelog=temp/"CHANGELOG.md"
            changelog.write_bytes(changelog.read_bytes().replace(b"## [Unreleased]\n",b"## [Unreleased]\n\n### Diubah\n\n- Uji.\n",1))
            new="9.8.7-rc.1"
            with redirect_stdout(io.StringIO()),redirect_stderr(io.StringIO()):
                self.assertEqual(set_version.main([new,"--root",str(temp),"--date","2030-01-02"]),0)
                # The same version again is refused and writes nothing.
                self.assertEqual(set_version.main([new,"--root",str(temp)]),1)
            read=lambda name:(temp/name).read_text(encoding="utf-8")
            self.assertIn(f'__version__ = "{new}"',read("odin/__init__.py"))
            self.assertIn(f'version = "{new}"',read("toolchain/Cargo.toml"))
            self.assertNotIn(f'version = "{__version__}"',read("toolchain/Cargo.lock"))
            self.assertIn(f"ODIN TURBO PASCAL {new}\\n",read("Install.command"))
            self.assertTrue(read("README.txt").startswith(f"ODIN TURBO PASCAL {new}\n"))
            self.assertIn(f"Panduan penggunaan {new}\n",read("docs/HELP.txt"))
            self.assertIn(f"KOMPATIBILITAS DAN CAKUPAN VERSI {new}\n",read("docs/COMPATIBILITY.txt"))
            self.assertIn("badge/rilis-9.8.7--rc.1-",read("README.md"))
            self.assertIn(f"Pemasang ini memasang **rilis {new}**",read("README.md"))
            self.assertIn(f"{{ Odin Turbo Pascal v{new} - program pertama }}",read(f"examples/{FIRST_EXAMPLE}"))
            self.assertIn(f"## [Unreleased]\n\n## [{new}] - 2030-01-02\n\n### Diubah\n\n- Uji.\n",read("CHANGELOG.md"))
            self.assertIn(f"compare/v{__version__}...v{new}",read("CHANGELOG.md"))


class DocumentTests(unittest.TestCase):
    def test_cp437_crlf_round_trip_and_conflict(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"old.pas"
            raw="{ café }\r\nbegin\r\nend.\r\n".encode("cp437")
            p.write_bytes(raw)
            doc=Document.read(p)
            self.assertEqual(doc.encoding,"cp437")
            self.assertEqual(doc.newline,"\r\n")
            doc.save()
            self.assertEqual(p.read_bytes(),raw)
            p.write_bytes(b"changed")
            self.assertTrue(doc.externally_changed())

    def test_utf8_bom_and_atomic_failure(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"unicode.pas"
            raw=b"\xef\xbb\xbf"+"{ Halo 世界 }\n".encode()
            p.write_bytes(raw)
            doc=Document.read(p)
            self.assertEqual(doc.encoding,"utf-8-sig")
            doc.save()
            self.assertEqual(p.read_bytes(),raw)
            doc.encoding="ascii"
            with self.assertRaises(UnicodeEncodeError):doc.save()
            self.assertEqual(p.read_bytes(),raw)

    def test_settings_invalid_input_is_recoverable(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"settings.json"
            p.write_text('{"font_size":999,"tab_width":0,"syntax":false,"syntax_colors":"wrong","mode":"objfpc","backend":"fpc","compiler":"/usr/local/bin/fpc"}')
            s=Settings(p)
            # Settings of the removed Free Pascal backend are ignored.
            for key in ("mode","backend","compiler"):self.assertNotIn(key,s.values)
            self.assertEqual(s["font_size"],30)
            self.assertEqual(s["tab_width"],1)
            self.assertTrue(s["syntax_colors"])   # the old "syntax" key no longer turns colors off

    def test_lexer_comments_and_escaped_quote(self):
        text="begin { end } WriteLn('it''s a string'); end."
        spans=[(kind,text[a:b]) for kind,a,b in syntax_spans(text)]
        self.assertEqual(spans,[("reserved","begin"),("comment","{ end }"),("builtin","WriteLn"),("operator","("),
                                ("string","'it''s a string'"),("operator",")"),("operator",";"),("reserved","end"),
                                ("operator",".")])

    def test_lexer_kinds(self):
        text=("{$R+} (* catatan *) // baris\n"
              "function Luas(P: Real): Real; forward;\n"
              "const N = $0E; S = #13#10'ok'; X = 1.5e3;\n"
              "begin Luas(N); ClrScr; if Ada = nil then Ok := True; for I := 1 to 10 do; end.\n"
              "Teks := 'belum ditutup\n"
              "BEGIN")
        spans=[(kind,text[a:b]) for kind,a,b in syntax_spans(text)]
        for expected in [("directive","{$R+}"),("comment","(* catatan *)"),("comment","// baris"),
                         ("reserved","function"),("routine","Luas"),("type","Real"),("number","$0E"),
                         ("string","#13"),("string","#10"),("string","'ok'"),("number","1.5e3"),
                         ("builtin","ClrScr"),("identifier","Ada"),("constant","nil"),("constant","True"),
                         ("operator",":="),("operator","="),("number","1"),("number","10"),
                         ("string","'belum ditutup"),("reserved","BEGIN")]:
            self.assertIn(expected,spans)
        self.assertEqual(spans.count(("routine","Luas")),2)   # the declaration and the call
        self.assertEqual([s for s in spans if s[0]=="string" and "\n" in s[1]],[])
        self.assertIn(("operator",".."),[(kind,"1..9"[a:b]) for kind,a,b in syntax_spans("1..9")])


class TerminalTests(unittest.TestCase):
    def test_clear_position_color_and_fragmented_escape(self):
        s=Screen(20,5)
        s.feed("old\x1b[")
        s.feed("2J\x1b[3;4H\x1b[1;33;44mOdin")
        self.assertEqual(s.grid[2][3],("O",11,4))
        self.assertEqual("".join(c[0] for c in s.grid[0])," "*20)

    def test_status_and_cursor_reports(self):
        s=Screen()
        s.feed("\x1b[3;5Hab\x1b[6n\x1b[5n\x1b[?6n")
        self.assertEqual(s.replies,[b"\x1b[3;7R",b"\x1b[0n"])

    def test_wrap_crlf_and_scroll(self):
        s=Screen(4,2)
        s.feed("1234\r\n5678")
        self.assertEqual(s.text(),"1234\n5678")
        s.feed("9")
        self.assertEqual(s.text(),"5678\n9   ")

    def test_backspace_delete_and_cursor_visibility(self):
        s=Screen(10,2)
        s.feed("abc\bX\x1b[?25l")
        self.assertTrue(s.text().startswith("abX"))
        self.assertFalse(s.visible)
        s.feed("\x1b[1;2H\x1b[P")
        self.assertTrue(s.text().startswith("aX"))

    def test_g1_charset_shift_and_line_drawing(self):
        # Turbo Vision programs: G1 = DEC graphics, SO/SI switch; ESC ) 0 alone must not alter text.
        s=Screen(12,2)
        s.feed("\x1b%@\x1b(B\x1b)0File \x0elqk\x0f x\r\n\x1b(0aq\x1b(Bq")
        self.assertEqual(s.text(),"File ┌─┐ x  \n▒─q         ")

    def test_mouse_modes_and_alternate_screen(self):
        # Odin Vision: SGR mouse tracking on the alternate screen; leaving it restores the text.
        s=Screen(10,2)
        s.feed("main\x1b[?1049h\x1b[?1000h\x1b[?1002h\x1b[?1006hTV")
        self.assertEqual((s.mouse,s.sgr_mouse),({1000,1002},True))
        # Like xterm, the cursor stays where it was.
        self.assertEqual(s.text().split("\n")[0],"    TV    ")
        s.feed("\x1b[?1006l\x1b[?1002l\x1b[?1000l\x1b[?1049l")
        self.assertEqual((s.mouse,s.sgr_mouse),(set(),False))
        self.assertTrue(s.text().startswith("main"))

    def test_key_modifiers_and_mouse_reports(self):
        self.assertEqual(modified_key(b"\x1b[D",2),b"\x1b[1;2D")
        self.assertEqual(modified_key(b"\x1b[3~",5),b"\x1b[3;5~")
        self.assertEqual(modified_key(b"\x1bOR",3),b"\x1b[1;3R")
        self.assertEqual(modified_key(b"\x1b[15~",1),b"\x1b[15~")
        self.assertEqual(mouse_report(0,4,2,False,True),b"\x1b[<0;5;3M")
        self.assertEqual(mouse_report(2,4,2,True,True),b"\x1b[<2;5;3m")
        self.assertEqual(mouse_report(0,4,2,True,False),b"\x1b[M#%#")

    def test_extended_colors(self):
        # 256-color and RGB SGR (ConPTY and modern programs) map to the CRT palette and do not
        # leak their parameters as other attributes (the 1 of 38;5;1 is not bold).
        s=Screen(10,1)
        s.feed("\x1b[38;5;1mA\x1b[48;5;12mB\x1b[38;2;255;255;85;48;2;0;0;170mC\x1b[0;38;5;226mD\x1b[38;5;240mE")
        self.assertEqual(s.grid[0][0],("A",1,0))
        self.assertEqual(s.grid[0][1],("B",1,12))
        self.assertEqual(s.grid[0][2],("C",11,4))
        self.assertEqual(s.grid[0][3],("D",11,0))
        self.assertEqual(s.grid[0][4][1],8)
        self.assertFalse(s.bold)
        self.assertEqual([color_256(n) for n in (0,15,16,231,232,255)],[0,15,0,15,0,15])

    def test_alt_masks(self):
        # Alt is Option (Mod2) on macOS, Mod1 on X11 and Tk's ALT_MASK on Windows, where Mod1 is Num Lock.
        self.assertEqual(ALT_MASKS,{"aqua":0x10,"win32":0x20000,"x11":0x08})

    @unittest.skipUnless(os.name=="posix","pass_fds and /bin/sh are POSIX; on Windows the debugger channel will be TCP (Tahap 8d)")
    def test_extra_descriptors_reach_grandchildren(self):
        # Spike S4: the debug channel is a pipe passed through the debugger
        # process to the program, while the program's output stays on the PTY.
        r,w=os.pipe()
        q=queue.Queue()
        p=Process(["/bin/sh","-c",f"/bin/sh -c 'printf hook >&{w}; printf screen'"],"/",lambda k,v:q.put((k,v)),
                  pass_fds=(w,),env={"ODIN_DEBUG_FDS":f"{r},{w}"})
        os.close(w)
        output=""
        while True:
            k,v=q.get(timeout=10)
            if k=="output":output+=v
            else:
                self.assertEqual(v,0)
                break
        self.assertEqual(os.read(r,100),b"hook")
        os.close(r)
        self.assertIn("screen",output)

    def test_process_stop(self):
        import sys
        q=queue.Queue()
        p=Process([sys.executable,"-c","import time; print('ready',flush=True); time.sleep(30)"],ROOT,lambda k,v:q.put((k,v)))
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            k,v=q.get(timeout=5)
            if k=="output" and "ready" in v:break
        p.stop()
        while time.monotonic()<deadline:
            k,v=q.get(timeout=5)
            if k=="exit":
                self.assertNotEqual(v,0)
                break
        else:self.fail("Process did not stop")


class PlatformTests(unittest.TestCase):
    """Platform paths and helpers; Windows behaviour is checked here by patching sys.platform."""

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="odin platform ")
        self.root=Path(self.temp.name)

    def tearDown(self):self.temp.cleanup()

    def test_data_dir_per_platform(self):
        home=self.root/"home"
        with patch.object(core.Path,"home",return_value=home):
            with patch.object(core.sys,"platform","darwin"):
                self.assertEqual(data_dir(),home/"Library"/"Application Support"/"OdinTurboPascal")
            with patch.object(core.sys,"platform","linux"):
                self.assertEqual(data_dir(),home/".local"/"share"/"OdinTurboPascal")
            with patch.object(core.sys,"platform","win32"):
                with patch.dict(os.environ,{"APPDATA":str(self.root/"Roaming")}):
                    self.assertEqual(data_dir(),self.root/"Roaming"/"OdinTurboPascal")
                with patch.dict(os.environ):
                    os.environ.pop("APPDATA",None)
                    self.assertEqual(data_dir(),home/"AppData"/"Roaming"/"OdinTurboPascal")
        self.assertTrue((self.root/"Roaming"/"OdinTurboPascal").is_dir())

    def test_executable_names_and_arguments(self):
        with patch.object(core.sys,"platform","win32"):
            self.assertEqual(executable_name("HELLO"),"HELLO.exe")
            # Backslashes are path separators on Windows; quotes still group words.
            self.assertEqual(split_arguments(r'C:\Pascal\data.txt "two words" 3'),[r"C:\Pascal\data.txt","two words","3"])
            self.assertEqual(join_command([r"C:\Odin\odinpc.exe",r"C:\my dir\a.pas"]),r'C:\Odin\odinpc.exe "C:\my dir\a.pas"')
        with patch.object(core.sys,"platform","darwin"):
            self.assertEqual(executable_name("HELLO"),"HELLO")
            self.assertEqual(split_arguments("\"hello world\" '$(no shell)' a\\ b"),["hello world","$(no shell)","a b"])
            self.assertEqual(join_command(["odinpc","my file.pas"]),"odinpc 'my file.pas'")

    def test_single_instance_lock(self):
        path=self.root/"instance.lock"
        first=lock_instance(path)
        self.assertIsNotNone(first)
        try:
            # Another open of the same file, as a second IDE would do, is refused.
            self.assertIsNone(lock_instance(path))
        finally:
            unlock_instance(first)
        again=lock_instance(path)
        self.assertIsNotNone(again)
        unlock_instance(again)

    def fake_file(self,path,content=""):
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(content)
        path.chmod(0o755)
        return path

    def test_windows_build_command(self):
        source=self.root/"hello.pas"
        source.write_text("program Hello;\nbegin\nend.\n")
        settings=Settings(self.root/"settings.json")
        toolchain=self.fake_file(self.root/"toolchain"/"odinpc.exe")
        commands=[]
        def run(command,**options):
            commands.append((command,options))
            return subprocess.CompletedProcess(command,0,stdout=b"",stderr=b"")
        with patch.object(core.sys,"platform","win32"),patch("odin.core.locate_toolchain",return_value=str(toolchain)),\
             patch("odin.core.odin_supported",return_value=True),patch("odin.core.subprocess.run",side_effect=run):
            r=build(source,settings,cache=self.root/"build")
        command=r.command
        self.assertEqual(command[:3],[str(toolchain),"build",str(source.resolve())])
        self.assertTrue(command[command.index("--out")+1].endswith("hello.exe"))
        self.assertEqual(commands[-1][0],command)
        self.assertEqual(commands[-1][1].get("creationflags"),0x08000000 if os.name=="nt" else None)
        with patch.object(core.sys,"platform","win32"),patch("odin.core.locate_toolchain",return_value=None):
            r=build(source,settings,cache=self.root/"build")
        self.assertFalse(r.success)
        self.assertIn("Install.ps1",r.output)

    def test_unsupported_host_is_reported(self):
        source=self.root/"hello.pas"
        source.write_text("program Hello;\nbegin\nend.\n")
        toolchain=self.fake_file(self.root/"toolchain"/"odinpc")
        with patch("odin.core.locate_toolchain",return_value=str(toolchain)),patch("odin.core.odin_supported",return_value=False),\
             patch("odin.core.subprocess.run") as run:
            r=build(source,Settings(self.root/"settings.json"),cache=self.root/"build")
        run.assert_not_called()
        self.assertFalse(r.success)
        self.assertIn("belum bisa membuat program",r.output)


@unittest.skipUnless(HAS_ODIN,NEEDS_ODIN)
class OdinBackendTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="odin backend ")
        self.root=Path(self.temp.name)
        self.settings=Settings(self.root/"settings.json")

    def tearDown(self):self.temp.cleanup()

    def test_diagnostics_come_back_as_objects(self):
        r=build(ROOT/"tests"/"pascal"/"errors"/"SEMI_STMT.PAS",self.settings,cache=self.root/"build")
        self.assertFalse(r.success)
        self.assertIsNone(r.executable)
        self.assertEqual(r.command[1],"build")
        d=r.diagnostics[0]
        self.assertEqual((d.line,d.column,d.kind),(5,3,"Error"))
        self.assertIn("diharapkan",d.message)
        self.assertIn("SEMI_STMT.PAS(5,3) Error 85",r.output)


@unittest.skipUnless(HAS_ODIN,NEEDS_ODIN)
class CompilerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="odin tests ")
        self.root=Path(self.temp.name)
        self.settings=Settings(self.root/"settings.json")

    def tearDown(self):self.temp.cleanup()

    def compile_example(self,name):
        r=build(ROOT/"examples"/name,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        return r

    def run_example(self,name,input_data=""):
        """Runs an example in self.root, where its data files land (the IDE runs a program in its source folder)."""
        r=self.compile_example(name)
        result=subprocess.run([str(r.executable)],input=input_data,capture_output=True,text=True,timeout=20,cwd=self.root)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        return result.stdout

    def test_otp_ai_units_are_found_by_uses(self):
        units=sorted(p.stem for p in (ROOT/"otp-AI"/"UNITS").glob("*.PAS"))
        self.assertEqual(len(units),19)
        source=self.root/"AIUSES.pas"
        source.write_text("program AIUses;\nuses Crt, "+", ".join(units)+";\nbegin WriteLn('uses OK') end.\n",encoding="utf-8")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        result=subprocess.run([str(r.executable)],capture_output=True,text=True,timeout=20,cwd=self.root)
        self.assertIn("uses OK",result.stdout)

    def test_every_example_compiles_and_runs(self):
        # The tutorial: 89 programs bab01_01..bab20_03 and the unit matematika.pas (Bab 19).
        paths=sorted(p for p in (ROOT/"examples").iterdir() if p.suffix.lower()==".pas")
        self.assertEqual(len(paths),90)
        self.assertLessEqual(set(EXAMPLE_RUNS),{p.stem for p in paths})
        for path in paths:
            with self.subTest(path=path.name):
                r=self.compile_example(path.name)
                # A unit builds no executable.
                self.assertEqual(r.executable is None,path.stem=="matematika")
                if path.stem in EXAMPLE_RUNS:
                    input_data,expected=EXAMPLE_RUNS[path.stem]
                    output=self.run_example(path.name,input_data)
                    for text in expected:self.assertIn(text,output)

    def test_program_parameters_without_shell(self):
        source=self.root/"params.pas"
        source.write_text("program Params;\nvar I: Integer;\nbegin\n  WriteLn('Jumlah argumen: ', ParamCount);\n"
                          "  for I := 1 to ParamCount do\n    WriteLn(I, ': ', ParamStr(I));\nend.\n")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        result=subprocess.run([str(r.executable),"hello world","$(no shell)"],capture_output=True,text=True,timeout=5,cwd=self.root)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn("1: hello world",result.stdout)
        self.assertIn("2: $(no shell)",result.stdout)

    def test_no_stale_executable_after_failed_build(self):
        source=self.root/"program with spaces.pas"
        source.write_text("program p; begin WriteLn('ok'); end.")
        first=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(first.success,first.output)
        source.write_text("program p; begin not_valid_token; end.")
        second=build(source,self.settings,cache=self.root/"build")
        self.assertFalse(second.success)
        self.assertIsNone(second.executable)
        self.assertFalse(first.executable.exists())
        self.assertTrue(any(d.kind=="Error" for d in second.diagnostics))


    def test_file_examples_keep_their_data(self):
        self.assertIn("belum ada",self.run_example("bab17_02_baca_file_teks.pas"))
        self.run_example("bab17_01_tulis_file_teks.pas","satu\ndua\ntiga\n")
        self.assertEqual((self.root/"catatan.txt").read_text().splitlines()[2:],["1. satu","2. dua","3. tiga"])
        self.assertIn("Jumlah baris: 5",self.run_example("bab17_02_baca_file_teks.pas"))
        self.assertIn("kini berisi 6 baris",self.run_example("bab17_03_tambah_file_teks.pas","empat\n"))
        # Rewrite starts the file over.
        self.run_example("bab17_01_tulis_file_teks.pas","a\nb\nc\n")
        self.assertEqual(len((self.root/"catatan.txt").read_text().splitlines()),5)
        # Typed files keep their records from one run to the next.
        self.run_example("bab17_05_simpan_baca_record.pas","Ani\nX-A\n88\n\n")
        output=self.run_example("bab17_05_simpan_baca_record.pas","Budi\nX-B\n75\n\n")
        self.assertIn("Data tersimpan saat ini: 1 siswa.",output)
        self.assertIn(" 2  Budi",output)
        self.run_example("bab20_03_buku_telepon.pas","2\nSiti\n08123456789\ns@x.id\n2\nAndi\n0811111111\n\n0\n")
        output=self.run_example("bab20_03_buku_telepon.pas","1\n0\n")
        self.assertIn("2 kontak dimuat",output)
        self.assertLess(output.index("Andi"),output.index("Siti"))
        self.assertIn("Tidak ada perubahan.",output)

    def pty_session(self,name,steps):
        """Runs an example on a PTY. steps: (text to wait for, keys to send then).
        Returns the output, the final screen, and a copy of the screen grid at each step."""
        r=self.compile_example(name)
        q=queue.Queue()
        p=Process([str(r.executable)],self.root,lambda k,v:q.put((k,v)))
        output=""
        # ConPTY (Windows) may repaint with cursor moves between words: also check the rendered screen.
        screen=Screen()
        steps,grids=list(steps),[]
        deadline=time.monotonic()+20
        while time.monotonic()<deadline:
            k,v=q.get(timeout=20)
            if k=="output":
                output+=v
                screen.feed(v)
                # Answer cursor-position requests as TerminalView does (Crt asks for WhereX).
                while screen.replies:p.write(screen.replies.pop(0))
                if steps and steps[0][0] in output+screen.text():
                    grids.append([row[:] for row in screen.grid])
                    for key in steps.pop(0)[1]:
                        p.write(key)
                        time.sleep(.05)
            elif k=="exit":
                self.assertEqual(v,0)
                break
        else:
            p.stop()
            self.fail(f"{name} hung waiting for {steps[0][0] if steps else 'exit'}")
        self.assertFalse(steps,f"{name} never showed {steps[0][0] if steps else ''}")
        return output+screen.text(),screen,grids

    def test_interactive_pty_readln(self):
        output,_,_=self.pty_session("bab04_02_read_readln.pas",[("Nama Anda",[b"Syams\r40\r170.5\r3 4\r"])])
        self.assertIn("41 tahun",output)

    def test_crt_cursor_and_readkey(self):
        output,screen,grids=self.pty_session("bab19_02_unit_crt.pas",[("Tekan sembarang",[b"x"])])
        # GotoXY(32, 2): column 32 of row 2, in Yellow on Blue (ANSI colours 11 and 4 in Screen).
        self.assertEqual("".join(cell[0] for cell in grids[0][1][31:47]),"BELAJAR UNIT CRT")
        self.assertEqual(grids[0][1][31][1:],(11,4))
        self.assertIn("Kursor ada di kolom 5, baris 16",output)
        self.assertIn('Anda menekan tombol "x"',screen.text())
        self.assertIn("Program selesai",screen.text())

    def test_crt_menu_with_arrow_keys(self):
        down,up=KEYS["Down"],KEYS["Up"]
        # Down twice to Pengumuman, Up to Jadwal, then Up twice wraps round to Keluar.
        output,screen,grids=self.pty_session("bab19_03_menu_berwarna.pas",[
            ("MENU UTAMA SEKOLAH",[down,down,b"\r"]),
            ("Ujian semester",[up,b"\r"]),
            ("Senin-Jumat",[up,up,b"\r"])])
        # The active item (row 13, Pengumuman) has a Cyan background (ANSI colour 6 in Screen).
        self.assertEqual(grids[1][12][30][0],"P")
        self.assertEqual(grids[1][12][30][2],6)
        self.assertIn("Terima kasih telah memakai menu.",screen.text())

    def test_crt_function_keys(self):
        names=["F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12","Insert","Up"]
        source=self.root/"keys.pas"
        source.write_text("program Keys;\nuses Crt;\nvar I: Integer; C: Char;\nbegin\n  WriteLn('READY');\n"
                          f"  for I := 1 to {len(names)} do\n  begin\n    C := ReadKey;\n"
                          "    if C = #0 then Write(Ord(ReadKey), ' ') else Write('?', Ord(C), ' ');\n  end;\n  WriteLn('DONE');\nend.\n")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        q=queue.Queue()
        p=Process([str(r.executable)],self.root,lambda k,v:q.put((k,v)))
        screen=Screen()
        sent=False
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            k,v=q.get(timeout=10)
            if k=="output":
                screen.feed(v)
                if "READY" in screen.text() and not sent:
                    for name in names:
                        p.write(KEYS[name])
                        time.sleep(.05)
                    sent=True
            elif k=="exit":
                self.assertEqual(v,0)
                break
        else:
            p.stop()
            self.fail("ReadKey hung")
        # Turbo Pascal scan codes: F1..F10 = 59..68, F11/F12 = 133/134, Insert = 82, Up = 72.
        self.assertIn("59 60 61 62 63 64 65 66 67 68 133 134 82 72 DONE",screen.text())


    def test_standard_units_and_turbo_vision(self):
        source=self.root/"units.pas"
        source.write_text("program Units;\nuses Crt, Dos, Strings, Printer, Objects;\nvar C: TStringCollection;\n"
                          "begin\n  C.Init(2, 2);\n  C.Insert(NewStr('b'));\n  C.Insert(NewStr('a'));\n"
                          "  WriteLn(StrLen('abc'), ' ', PString(C.At(0))^, C.Count);\n  C.Done;\nend.\n")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        result=subprocess.run([str(r.executable)],capture_output=True,text=True,timeout=5,cwd=self.root)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn("3 a2",result.stdout)
        # Odin Vision: the 1.0 Turbo Vision program builds and runs (without a terminal too).
        source=self.root/"tv.pas"
        source.write_text("program TV;\nuses Objects, Drivers, Views, Menus, Dialogs, App, MsgBox, StdDlg;\n"
                          "var A: TApplication;\nbegin\n  A.Init;\n  A.Done;\n  WriteLn('TV ok');\nend.\n")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        result=subprocess.run([str(r.executable)],capture_output=True,text=True,timeout=5,cwd=self.root)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn("TV ok",result.stdout)
        # ColorSel and TextView, the last Turbo Vision units, are Odin's own too.
        source.write_text("program TV;\nuses Objects, Views, Dialogs, App, ColorSel, TextView;\nbegin\n  WriteLn('TV2 ok');\nend.\n")
        r=build(source,self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        result=subprocess.run([str(r.executable)],capture_output=True,text=True,timeout=5,cwd=self.root)
        self.assertIn("TV2 ok",result.stdout)

    def screen_after_run(self,executable):
        """Runs a Crt program on a PTY until it waits in ReadKey, presses a key, returns the screen."""
        q=queue.Queue()
        p=Process([str(executable)],self.root,lambda k,v:q.put((k,v)))
        screen=Screen()
        sent=False
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            try:k,v=q.get(timeout=1)
            except queue.Empty:
                if not sent:
                    p.write(b"x")
                    sent=True
                continue
            if k=="output":
                screen.feed(v)
                # Answer cursor-position requests as TerminalView does (Crt asks for WhereX).
                while screen.replies:p.write(screen.replies.pop(0))
            elif k=="exit":
                self.assertEqual(v,0)
                return screen
        p.stop()
        self.fail("Crt program did not finish")

    def test_crt_screen_matches_snapshot(self):
        # CRT_WINDOW.snap: Window, scrolling, InsLine/DelLine and colors cell by cell (text rows, then fg/bg
        # hex digits per cell). It was checked against Free Pascal 3.2.2 before that backend was removed;
        # ODIN_BLESS=1 rewrites it after a reviewed change.
        r=build(ROOT/"tests"/"pascal"/"crt"/"CRT_WINDOW.PAS",self.settings,cache=self.root/"build")
        self.assertTrue(r.success,r.output)
        screen=self.screen_after_run(r.executable)
        lines=["|"+"".join(c[0] for c in row)+"|" for row in screen.grid]
        lines+=["".join(f"{c[1]:x}{c[2]:x}" for c in row) for row in screen.grid]
        lines.append(f"cursor {screen.x} {screen.y}")
        path=ROOT/"tests"/"pascal"/"crt"/"CRT_WINDOW.snap"
        if os.environ.get("ODIN_BLESS")=="1":
            path.write_text("\n".join(lines)+"\n",encoding="utf-8")
        want=path.read_text(encoding="utf-8").splitlines()
        self.assertIn("full width",screen.text())
        rows=screen.rows
        for y in range(rows):
            for x in range(screen.cols):
                a=(want[y][x+1],want[rows+y][2*x],want[rows+y][2*x+1])
                b=(lines[y][x+1],lines[rows+y][2*x],lines[rows+y][2*x+1])
                # The foreground of a blank cell cannot be seen.
                same=a[0]==b[0] and a[2]==b[2] and (a[0]==" " or a[1]==b[1])
                self.assertTrue(same,f"cell {x+1},{y+1}: snapshot {a} Odin {b}")
        self.assertEqual(lines[-1],want[-1])


if __name__=="__main__":unittest.main()
