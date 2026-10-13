<div align="center">

<img src="assets/banner.svg" alt="Odin Turbo Pascal: IDE Pascal klasik dengan Free Pascal native untuk macOS Intel dan Apple Silicon" width="100%">

# Odin Turbo Pascal

**Layar biru Turbo Pascal yang Anda kenal, compiler modern yang menghasilkan program native.**

[![Versi](https://img.shields.io/badge/versi-1.0.0-0000aa?style=flat-square)](#)
[![Lisensi GPL v3](https://img.shields.io/badge/lisensi-GPL--3.0--or--later-ffff55?style=flat-square)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-11%2B%20Intel%20%7C%20Apple%20Silicon-000000?style=flat-square&logo=apple&logoColor=white)](#persyaratan-sistem)
[![Python](https://img.shields.io/badge/Python-3.10%2B%20dengan%20Tk-3776ab?style=flat-square&logo=python&logoColor=white)](https://www.python.org/downloads/macos/)
[![Free Pascal](https://img.shields.io/badge/Free%20Pascal-3.2.2%2B-00aaaa?style=flat-square)](https://www.freepascal.org/)
[![Offline](https://img.shields.io/badge/offline-tanpa%20telemetri-55ff55?style=flat-square)](#privasi-dan-lokasi-data)

[Fitur](#fitur) · [Instalasi](#instalasi) · [Mulai Cepat](#mulai-cepat) · [Pintasan](#pintasan-keyboard) · [Pengembang](#untuk-pengembang) · [Changelog](CHANGELOG.md) · [Lisensi](#lisensi)

</div>

---

## Sekilas

**Odin Turbo Pascal** adalah IDE Pascal yang menghadirkan kembali pengalaman Turbo Pascal era DOS: layar biru, teks kuning, menu abu-abu, jendela editor berbingkai, dan tombol fungsi klasik. Bedanya, kode Anda dikompilasi oleh **Free Pascal** asli menjadi **program macOS native**, untuk Mac Intel (x86_64) maupun Apple Silicon (arm64). Tidak ada emulator DOS. Setelah terpasang, Odin tidak memerlukan internet dan tidak mengirim telemetri.

Cocok untuk siswa dan mahasiswa yang belajar algoritma dan pemrograman, guru yang mengajar Pascal di kelas, dan siapa saja yang rindu menekan `Ctrl+F9` lalu melihat programnya berjalan.

> **English summary.** Odin Turbo Pascal is a DOS-era, Turbo Pascal–style IDE for macOS (Intel and Apple Silicon). It compiles your code with the real Free Pascal compiler into native binaries and runs them in a built-in 80×25 terminal with Crt support. Messages and documentation are in Indonesian. Licensed under the GNU GPL v3 or later.

<div align="center">

<img src="docs/UI_PREVIEW_LINUX.png" alt="Editor Odin Turbo Pascal bergaya OTP v2.0 menampilkan HELLO.PAS dengan nomor baris, panel Program output, status line, dan baris tombol fungsi" width="820">

<sub>Editor dengan contoh <code>HELLO.PAS</code>. Tangkapan layar dari lingkungan uji Linux; di macOS jendela memakai tampilan Tk native.</sub>

</div>

## Mengapa Odin?

- **Nostalgia yang benar-benar bekerja.** Alur kerja Turbo Pascal tetap utuh: `F2` simpan, `F9` make, `Ctrl+F9` jalankan, `Alt+F5` User screen. Bedanya, di belakangnya bekerja compiler modern.
- **Program native, bukan emulasi.** Hasil kompilasi adalah executable macOS asli untuk CPU Anda, dan bisa diekspor untuk dijalankan di luar IDE.
- **Program interaktif sungguhan.** `ReadLn`, `ReadKey`, warna `Crt`, `GotoXY`, bahkan aplikasi Turbo Vision berjalan di User screen 80×25.
- **Siap untuk kelas.** Ada sepuluh contoh program berbahasa Indonesia, referensi Pascal ringkas, dan daftar pesan compiler yang langsung melompat ke baris yang salah.
- **Aman untuk berkas Anda.** Penyimpanan atomik, deteksi perubahan dari luar, dan pemulihan sesi otomatis setiap 10 detik.
- **Ringan, terbuka, dan privat.** Source Python yang mudah dipelajari dan diubah, berlisensi GNU GPL v3, tanpa akun, server, API key, atau telemetri.

## Fitur

### Antarmuka dan editor
- Desain antarmuka mengikuti **ODIN Turbo Pascal v2.0**: menu **ODIN · File · Edit · Search · Run · Compile · Debug · Options · Window · Help**, jendela editor berbingkai dengan judul `NAMA.PAS [1 / 2]`, nomor baris cyan, panel **Program output** abu-abu, status line cyan, dan baris tombol fungsi.
- Hasil kompilasi dan pesan error tampil di panel Program output; klik ganda pesan untuk melompat ke barisnya. `Shift+F5` menyembunyikan atau menampilkan panel.
- Beberapa jendela editor sekaligus: tile, cascade, zoom, dan daftar jendela.
- Undo/redo, clipboard, find/replace, go to line, hapus baris, indentasi otomatis, serta mode insert/overwrite.
- Warna sintaks aktif secara bawaan (kata kunci putih, string cyan, komentar abu-abu), bisa dimatikan untuk teks kuning klasik.
- Encoding CP437 dan UTF-8 (termasuk BOM), serta akhir baris LF dan CRLF, dipertahankan apa adanya saat menyimpan.

### Kompilasi
- Free Pascal asli dengan mode **Turbo Pascal 7** (`-Mtp`), Object Pascal, atau Delphi.
- Compile, Make, dan Build. Tersedia *primary file* untuk proyek yang terdiri dari program dan unit.
- Unit path dan include path, range check, dan overflow check.
- Daftar diagnostik compiler: klik untuk melompat ke baris error, dan `Alt+F8` untuk pesan berikutnya.
- Hasil build disimpan terpisah di cache. Build yang gagal tidak pernah menjalankan executable lama.
- Ekspor executable native.

### Menjalankan program
- User screen 80×25 berbasis pseudo-terminal: `ReadLn`, `ReadKey`, `KeyPressed`, 16 warna, `GotoXY`, `ClrScr`, dan `Window`.
- Tombol `F1`–`F12`, `Insert`, dan panah diteruskan ke program dengan kode scan Turbo Pascal.
- Parameter program (Run › Parameters) diteruskan tanpa melewati shell.
- `Ctrl+C` menginterupsi program, `Ctrl+F2` menghentikannya, dan **Copy screen** menyalin isi layar.

### Debugging dengan LLDB
- Breakpoint dari gutter atau `Ctrl+F8`, lalu step (`F7`), next (`F8`), dan continue.
- Variabel lokal, call stack, dan evaluasi ekspresi lewat konsol LLDB di User screen.

### Berkas dan sesi
- Contoh bawaan diperlakukan sebagai template: **Save** otomatis menjadi **Save as**, sehingga contoh asli tidak tertimpa.
- Daftar berkas terakhir, pengaturan yang tersimpan, dan hanya satu instance aplikasi yang berjalan.

## Unit Standar Turbo Pascal

Unit di bawah ini diuji melalui jalur kompilasi dan User screen Odin di Mac Intel dengan Free Pascal 3.2.2.

| Unit | Status |
|---|---|
| `System` | ✅ Otomatis tersedia: string, matematika, `Str`/`Val`, berkas teks dan bertipe, direktori, `ParamStr`, `New`/`Dispose`, `ExitProc` |
| `Crt` | ✅ `ClrScr`, `GotoXY`, `WhereX`/`WhereY`, warna, `Window`, `ClrEol`, `DelLine`, `Delay`, `Sound`, `KeyPressed`, `ReadKey` |
| `Dos` | ✅ `GetDate`/`GetTime`, `GetEnv`, `FSplit`, `FindFirst`/`FindNext`, `DiskFree`, `GetFTime`, `Exec`/`DosExitCode` |
| `Strings` | ✅ Rutin `PChar` |
| `Objects` | ✅ `TCollection`, `TStringCollection`, stream |
| `Printer` | ✅ `Lst` diteruskan ke printer default macOS melalui `lpr` |
| Turbo Vision | ✅ Melalui Free Vision: `App`, `Drivers`, `Views`, `Menus`, `Dialogs`, `MsgBox`, `StdDlg`, `Memory`, `HistList`, `Validate`, `Editors`, `Outline` |
| `Graph`, `Graph3`, `Overlay`, `WinDos`, `Turbo3` | ❌ Tidak tersedia di Free Pascal untuk macOS |

Rincian dan perbedaan perilaku ada di [`docs/COMPATIBILITY.txt`](docs/COMPATIBILITY.txt).

## Persyaratan Sistem

| Komponen | Kebutuhan |
|---|---|
| macOS | 11 Big Sur atau lebih baru, Intel (x86_64) atau Apple Silicon (arm64) |
| Python | 3.10+ dengan Tk ([python.org universal2](https://www.python.org/downloads/macos/) atau Homebrew `python-tk@3.13`) |
| Free Pascal | 3.2.2+ ([freepascal.org](https://www.freepascal.org/down/i386/macosx.html) atau Homebrew `fpc`) |
| Xcode Command Line Tools | Untuk linker dan LLDB (`xcode-select --install`) |

Pemasang dapat memasang dependensi yang belum ada melalui Homebrew. Di Linux, Odin dijalankan dari source (lihat [Untuk Pengembang](#untuk-pengembang)).

## Instalasi

1. **Unduh** repositori ini (**Code › Download ZIP**), lalu ekstrak seluruhnya. Jangan menjalankan pemasang dari pratinjau ZIP.
2. **Buka `Install.command`.** Pemasang berjalan di Terminal dan akan:
   - mendeteksi chip Intel atau Apple Silicon;
   - memeriksa Python dengan Tk, Free Pascal, dan Xcode Command Line Tools, lalu menawarkan Homebrew atau tautan unduhan resmi bila ada yang belum terpasang;
   - **mengompilasi dan menjalankan program uji kecil** untuk memastikan hasilnya cocok dengan CPU Mac Anda. Bila pemeriksaan ini gagal, pemasangan berhenti dengan pesan kesalahan;
   - memasang aplikasi di `~/Applications` dan mencadangkan versi sebelumnya bila ada.
3. **Jalankan** `~/Applications/Odin Turbo Pascal.app`.

> [!NOTE]
> Bundel ini belum ditandatangani maupun dinotarisasi Apple. Bila macOS menahan pembukaannya, buka **System Settings › Privacy & Security › Open Anyway**. Jangan menonaktifkan Gatekeeper secara global.
>
> Bila atribut executable hilang saat ZIP diekstrak, jalankan pemasang lewat Terminal: `/bin/bash "/lokasi/paket/Install.command"`

Untuk menghapus aplikasi, jalankan `Uninstall.command`. Aplikasi dipindahkan ke Trash, sedangkan program Pascal dan pengaturan Anda tetap tersimpan.

## Mulai Cepat

1. Pilih **File › New**, lalu ketik program berikut:

   ```pascal
   program Halo;
   uses Crt;
   var
     Nama: string;
   begin
     ClrScr;
     TextColor(Yellow);
     Write('Siapa nama Anda? ');
     ReadLn(Nama);
     TextColor(LightCyan);
     WriteLn('Halo, ', Nama, '! Selamat datang di Odin Turbo Pascal.');
     ReadKey;
   end.
   ```

2. Tekan `F2` untuk menyimpan (di Mac juga bisa `Command+S`).
3. Tekan `Ctrl+F9` untuk mengompilasi dan menjalankan (di Mac juga bisa `Command+R`). Program tampil di **User screen**; `Alt+F5` menampilkan atau menyembunyikannya.
4. Buka **File › Examples** untuk mencoba sepuluh contoh siap pakai: `HELLO`, `INPUT`, `KALKULATOR`, `PARAMETER`, `REKURSI`, `ARRAY`, `BERKAS`, `CRTDEMO`, serta `UNITDEMO` bersama unit `UMATH`.

## Pintasan Keyboard

| Tombol | Fungsi | Tombol | Fungsi |
|---|---|---|---|
| `F1` | Help | `Ctrl+F9` | Compile dan run |
| `F2` | Save | `Alt+F9` / `F9` | Compile / Make |
| `F3` | Open | `Ctrl+F2` | Hentikan program atau debugger |
| `F5` | Zoom editor | `Alt+F5` | User screen |
| `Shift+F5` | Panel Program output | | |
| `F6` | Editor berikutnya | `Ctrl+F8` | Toggle breakpoint |
| `F7` / `F8` | LLDB step / next | `Alt+F8` | Diagnostik berikutnya |
| `F10` | Menu File | `Alt+X` | Keluar |

Alternatif Mac: `Command+N/O/S` (New/Open/Save), `Command+B` (Compile), `Command+R` (Run), `Command+F` (Find), `Command+W` (Close), `Command+Q` (Quit). Pada Mac laptop, tekan `Fn` bersama `F1`–`F12`. Daftar lengkap ada di [`docs/SHORTCUTS.txt`](docs/SHORTCUTS.txt).

## Untuk Pengembang

Odin adalah aplikasi Python/Tk tanpa dependensi pip. Semua perintah dijalankan dari root repositori, dengan Python yang mendukung Tk:

```bash
python3 main.py                                     # jalankan IDE dari source (macOS/Linux)
python3 -m unittest discover -s tests -v            # seluruh tes
python3 -m unittest tests.test_core.CompilerTests -v
ODIN_FPC=/path/ke/fpc python3 -m unittest discover -s tests -v   # pakai compiler tertentu
python3 scripts/package_app.py                      # bentuk ulang bundel .app dari source
```

Tes compiler dilewati bila Free Pascal tidak ditemukan, dan tes GUI dilewati bila tidak ada display.

```text
Odin_Turbo_Pascal/
├── main.py                 Titik masuk aplikasi
├── odin/
│   ├── app.py              Antarmuka Tk: menu, editor, dialog, User screen, LLDB
│   ├── core.py             Dokumen, pengaturan, build Free Pascal, diagnostik
│   └── terminal.py         Emulator VT100 80×25 dan proses pseudo-terminal
├── examples/               Sepuluh contoh program Pascal, termasuk satu unit
├── docs/                   Panduan, referensi Pascal, pintasan, kompatibilitas
├── tests/                  Tes fungsional, compiler, terminal, dan GUI
├── scripts/                Launcher, pemeriksaan Mac, pembentuk bundel .app, render logo
├── assets/                 Logo, ikon, dan banner (sumber SVG serta PNG/ICNS)
├── Odin Turbo Pascal.app   Bundel macOS (dibentuk dari source)
└── Install.command · Uninstall.command · CHANGELOG.md · LICENSE · THIRD_PARTY.txt
```

`core.py` tidak bergantung pada Tk. Thread kompilasi dan pembaca terminal tidak pernah menyentuh Tk secara langsung: hasilnya dikirim lewat antrean pesan yang dibaca UI setiap 40 ms. Kompilasi dan eksekusi program tidak pernah memakai shell.

## Kompatibilitas dan Batasan

- Odin adalah **implementasi baru** yang mengikuti antarmuka dan alur Turbo Pascal klasik. Odin bukan salinan Borland dan tidak menyertakan binary, logo, font, maupun berkas bantuan Borland.
- Hasil kompilasi berupa program macOS 64-bit, bukan EXE DOS 16-bit. Kode Graph/BGI, `Mem`/`Port`, interrupt DOS, assembler 16-bit, dan pointer berbasis segmen perlu di-porting.
- `Real` berukuran 8 byte (TP: 6 byte); gunakan `Real48` untuk membaca berkas biner lama. `Round` membulatkan ke bilangan genap untuk nilai `.5`.
- Debugger memakai perintah LLDB di User screen, tanpa watch window seperti debugger Borland.
- User screen tidak menyediakan scrollback, mouse reporting, maupun true color.

## Status Pengujian

| Lingkungan | Hasil |
|---|---|
| Linux x86_64, Python 3.12, Tk 9.0, FPC 3.2.2, Xvfb | Seluruh suite saat itu lulus. Lihat [`docs/TEST_REPORT.txt`](docs/TEST_REPORT.txt) |
| Mac Intel (macOS 15.7), Python 3.13, Tk 9.1, FPC 3.2.2 | Seluruh 24 tes lulus, termasuk kompilasi semua contoh, unit standar, Turbo Vision, input `ReadKey`, dan 6 tes GUI dengan jendela Tk sungguhan |
| Belum diverifikasi langsung | Pemasangan di Apple Silicon, peluncuran lewat Finder/LaunchServices, Gatekeeper, dan LLDB di macOS |

## Privasi dan Lokasi Data

Odin tidak memakai akun, server, API key, maupun telemetri. Internet hanya diperlukan untuk memasang dependensi yang belum ada.

| Lokasi | Isi |
|---|---|
| Folder pilihan Anda | Source Pascal, melalui **Save as** |
| `~/Library/Application Support/OdinTurboPascal/` | `settings.json`, cache build, `recovery.json`, `last-error.log`, `launch.log` |

Program dijalankan dengan working directory di folder source program utama. `Uninstall.command` tidak menghapus program pribadi maupun folder pengaturan.

## Kontribusi

Laporan bug, saran, dan pull request dipersilakan. Sebelum mengirim perubahan:

1. Jalankan `python3 -m unittest discover -s tests -v`, dan tambahkan tes untuk perilaku baru.
2. Tulis pesan untuk pengguna dalam bahasa Indonesia. Label menu tetap berbahasa Inggris, sesuai gaya Turbo Pascal.
3. Awali berkas source baru dengan header lisensi `SPDX-License-Identifier: GPL-3.0-or-later`.
4. Setelah mengubah source, jalankan `python3 scripts/package_app.py` agar bundel `.app` ikut diperbarui.

## Lisensi

Odin Turbo Pascal adalah perangkat lunak bebas di bawah **[GNU General Public License v3.0 atau yang lebih baru](LICENSE)**. Anda boleh memakai, mempelajari, mengubah, dan menyebarkannya. Bila Anda menyebarkan versi asli atau versi ubahan, sertakan source code-nya dengan lisensi yang sama. Program ini disediakan tanpa jaminan apa pun.

**Copyright © 2026 Syams Ideris** · [syamsuddin.ideris@gmail.com](mailto:syamsuddin.ideris@gmail.com)

Python, Tcl/Tk, Free Pascal, LLDB, dan Homebrew dipasang terpisah dengan lisensinya masing-masing. Sebelum mendistribusikan program hasil kompilasi, baca juga ketentuan runtime Free Pascal. Lihat [`THIRD_PARTY.txt`](THIRD_PARTY.txt).

> Odin adalah aplikasi independen dan tidak berafiliasi dengan Borland maupun pemilik merek Turbo Pascal saat ini. "Turbo Pascal" dan "Borland" adalah merek dagang dari pemiliknya masing-masing. Nama tersebut dipakai hanya untuk menjelaskan kompatibilitas dan inspirasi.

## Penulis

**Syams Ideris** · [syamsuddin.ideris@gmail.com](mailto:syamsuddin.ideris@gmail.com)

<div align="center">

---

Bila Odin Turbo Pascal bermanfaat untuk belajar atau mengajar, beri ⭐ pada repositori ini dan bagikan ke teman sekelas.

<sub>Dibuat untuk generasi baru pembelajar Pascal.</sub>

</div>
