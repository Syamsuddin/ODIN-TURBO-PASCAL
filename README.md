<div align="center">

<img src="assets/banner.svg" alt="Odin Turbo Pascal: IDE Pascal klasik dengan Free Pascal native untuk macOS Intel dan Apple Silicon" width="100%">

# Odin Turbo Pascal

**Layar biru Turbo Pascal yang Anda kenal, dengan compiler dan debugger yang menghasilkan program native.**

[![Versi](https://img.shields.io/badge/rilis-2.0.0--alpha.1-0000aa?style=flat-square)](CHANGELOG.md)
[![Pengembangan](https://img.shields.io/badge/pengembangan-toolchain%20Odin-00aaaa?style=flat-square)](IMPLEMENTATION_PLAN.md)
[![Lisensi GPL v3](https://img.shields.io/badge/lisensi-GPL--3.0--or--later-ffff55?style=flat-square)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-11%2B%20Intel%20%7C%20Apple%20Silicon-000000?style=flat-square&logo=apple&logoColor=white)](#persyaratan-sistem)
[![Python](https://img.shields.io/badge/Python-3.10%2B%20dengan%20Tk-3776ab?style=flat-square&logo=python&logoColor=white)](https://www.python.org/downloads/macos/)
[![Offline](https://img.shields.io/badge/offline-tanpa%20telemetri-55ff55?style=flat-square)](#privasi-dan-lokasi-data)

[Fitur](#fitur) · [Instalasi](#instalasi) · [Mulai Cepat](#mulai-cepat) · [Debugger](#debugger) · [Pintasan](#pintasan-keyboard) · [Pengembang](#untuk-pengembang) · [Changelog](CHANGELOG.md) · [Lisensi](#lisensi)

</div>

---

## Sekilas

**Odin Turbo Pascal** adalah IDE Pascal yang menghadirkan kembali pengalaman Turbo Pascal era DOS: layar biru, teks kuning, menu abu-abu, jendela editor berbingkai, dan tombol fungsi klasik. Bedanya, kode Anda dikompilasi menjadi **program macOS native**, tanpa emulator DOS. Setelah terpasang, Odin tidak memerlukan internet dan tidak mengirim telemetri.

Odin punya dua backend compiler:

- **Odin native.** Ini toolchain Odin sendiri: compiler Pascal, assembler, linker, runtime library, dan debugger, ditulis dari nol. Statusnya alfa (rilis 2.0.0-alpha.1), dan baru berjalan di Mac Intel. Di sana backend ini menjadi bawaan.
- **Free Pascal.** Compiler yang dipakai rilis 1.0.0, tersedia untuk Mac Intel dan Apple Silicon. Di Apple Silicon, Odin otomatis memakainya.

> [!NOTE]
> **Rilis.**
>
> - **2.0.0-alpha.1** (rilis ini), yang dipasang lewat `Install.command`, sudah membawa toolchain Odin native, debugger terpadu, dan Odin Vision. Bagian yang ditandai *versi pengembangan* termasuk di dalamnya, tetapi baru berjalan di Mac Intel. Di Apple Silicon, Odin memakai Free Pascal dan belum punya debugger.
> - **1.0.0** mengompilasi dengan Free Pascal dan men-debug lewat LLDB.
>
> Kemajuan per tahap tercatat di [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md).

Cocok untuk siswa dan mahasiswa yang belajar algoritma dan pemrograman, guru yang mengajar Pascal di kelas, dan siapa saja yang rindu menekan `Ctrl+F9` lalu melihat programnya berjalan.

> **English summary.** Odin Turbo Pascal is a DOS-era, Turbo Pascal–style IDE for macOS. Release 1.0.0 compiled with the real Free Pascal compiler into native binaries and ran them in a built-in 80×25 terminal with Crt support. Release 2.0.0-alpha.1 adds Odin's own toolchain as the default backend on Intel Macs (Free Pascal remains available, and is used on Apple Silicon), written from scratch in Rust and Pascal: compiler, assembler, Mach-O linker, runtime library, Odin Vision (a Turbo Vision–compatible library), and an integrated Turbo Pascal–style debugger with Watches, Locals and Call stack windows. It currently targets Intel Macs. Messages and documentation are in Indonesian. Licensed under the GNU GPL v3 or later.

<div align="center">

<img src="docs/UI_PREVIEW_LINUX.png" alt="Editor Odin Turbo Pascal menampilkan HELLO.PAS dengan menu klasik dan baris tombol fungsi" width="820">

<sub>Editor dengan contoh <code>HELLO.PAS</code>. Tangkapan layar dari lingkungan uji Linux; di macOS jendela memakai tampilan Tk native.</sub>

</div>

## Mengapa Odin?

- **Nostalgia yang benar-benar bekerja.** Alur kerja Turbo Pascal tetap utuh: `F2` simpan, `F9` make, `Ctrl+F9` jalankan, `Alt+F5` User screen, `F7`/`F8` menelusuri program baris demi baris.
- **Program native, bukan emulasi.** Hasil kompilasi adalah executable macOS asli untuk CPU Anda, dan bisa diekspor untuk dijalankan di luar IDE.
- **Program interaktif sungguhan.** `ReadLn`, `ReadKey`, warna `Crt`, dan `GotoXY` berjalan di User screen 80×25. Aplikasi Turbo Vision juga berjalan di sana, lengkap dengan mouse, baik dengan Odin Vision milik Odin maupun dengan Free Vision.
- **Siap untuk kelas.** Ada sebelas contoh program berbahasa Indonesia, referensi Pascal ringkas, dan daftar pesan compiler yang langsung melompat ke baris yang salah.
- **Aman untuk berkas Anda.** Penyimpanan atomik, deteksi perubahan dari luar, dan pemulihan sesi otomatis setiap 10 detik.
- **Ringan, terbuka, dan privat.** Source yang mudah dipelajari dan diubah, berlisensi GNU GPL v3, tanpa akun, server, API key, atau telemetri.

## Fitur

### Antarmuka dan editor
- Layar biru klasik dengan menu **File · Edit · Search · Run · Compile · Debug · Options · Window · Help**, status bar, dan baris tombol fungsi.
- Beberapa jendela sekaligus: tile, cascade, zoom, dan daftar jendela.
- Undo/redo, clipboard, find/replace, go to line, hapus baris, indentasi otomatis, serta mode insert/overwrite.
- Warna sintaks opsional. Bawaannya teks kuning klasik.
- Encoding CP437 dan UTF-8 (termasuk BOM), serta akhir baris LF dan CRLF, dipertahankan apa adanya saat menyimpan.

### Kompilasi
- Pilihan backend di **Options › Compiler**:
  - **Odin native** *(versi pengembangan, bawaan)*. Tidak memerlukan Free Pascal maupun Xcode. Saat ini menghasilkan program x86_64; di Apple Silicon, Odin otomatis memakai Free Pascal.
  - **Free Pascal** dengan mode **Turbo Pascal 7** (`-Mtp`), Object Pascal, atau Delphi.
- Compile, Make, dan Build. Tersedia *primary file* untuk proyek yang terdiri dari program dan unit.
- Unit path dan include path, range check, dan overflow check.
- Daftar diagnostik compiler: klik untuk melompat ke baris error, dan `Alt+F8` untuk pesan berikutnya. Pesan backend Odin berbahasa Indonesia dengan nomor galat gaya Turbo Pascal 7.
- Hasil build disimpan terpisah di cache. Build yang gagal tidak pernah menjalankan executable lama.
- Ekspor executable native.

### Menjalankan program
- User screen 80×25 berbasis pseudo-terminal: `ReadLn`, `ReadKey`, `KeyPressed`, 16 warna, `GotoXY`, `ClrScr`, dan `Window`.
- Tombol `F1`–`F12`, `Insert`, dan panah diteruskan ke program dengan kode scan Turbo Pascal.
- Parameter program (Run › Parameters) diteruskan tanpa melewati shell.
- `Ctrl+C` menginterupsi program, `Ctrl+F2` menghentikannya, dan **Copy screen** menyalin isi layar.
- Runtime error (backend Odin): baris penyebabnya ditandai merah di editor, dan **Search › Find error** kembali ke baris itu.

### Debugger

**Versi pengembangan, backend Odin.** Debugger terpadu bergaya Turbo Pascal, tanpa LLDB:

- **Breakpoint** dari gutter atau `Ctrl+F8`. Breakpoint ikut bergeser saat baris disisipkan, tersimpan bersama pemulihan sesi, dan bisa diubah saat program berjalan.
- **Menelusuri program:**
  - **Trace into** (`F7`) dan **Step over** (`F8`);
  - **Go to cursor** (`F4`) dan Continue;
  - `Ctrl+C` di User screen untuk berhenti sementara.

  Baris yang akan dijalankan berikutnya ditandai hijau.
- **Jendela Watches, Local variables, dan Call stack.** Ketiganya ikut diatur Tile dan Cascade. Pilih frame di Call stack untuk melihat variabel pemanggil.
- **Evaluate/Modify** (`Ctrl+F7`) untuk ekspresi Pascal: variabel, field, indeks dengan cek batas, `^`, `@`, aritmetika, typecast, `Ord`/`Chr`/`Length`/`High`/`Low`/`SizeOf`. Nilai ditampilkan seperti di Turbo Pascal, misalnya `'abc'`, `(1, 2, 3)`, `(X:1; Y:2)`, `[1, 3..5]`, dan nama enumerasi.

Rilis 1.0.0 memakai konsol LLDB di User screen untuk breakpoint, step, variabel lokal, dan call stack. Sejak 2.0.0-alpha.1 debugger terpadu menggantikannya, sehingga di Apple Silicon (backend Free Pascal) belum ada debugger.

### Berkas dan sesi
- Contoh bawaan diperlakukan sebagai template: **Save** otomatis menjadi **Save as**, sehingga contoh asli tidak tertimpa.
- Daftar berkas terakhir, pengaturan yang tersimpan, dan hanya satu instance aplikasi yang berjalan.

## Unit Standar Turbo Pascal

Kolom Free Pascal diuji 13 Oktober 2026 melalui jalur kompilasi dan User screen Odin di Mac Intel dengan Free Pascal 3.2.2. Kolom backend Odin diuji dengan korpus tes yang keluarannya dibandingkan dengan Free Pascal 3.2.2, juga di Mac Intel.

| Unit | Backend Odin | Free Pascal |
|---|---|---|
| `System` | ✅ String, matematika, `Str`/`Val`, berkas teks, bertipe, dan tanpa tipe, direktori, `ParamStr`, heap, `ExitProc`, runtime error | ✅ |
| `Crt` | ✅ `ClrScr`, `GotoXY`, `WhereX`/`WhereY`, warna, `Window`, `ClrEol`, `InsLine`/`DelLine`, `Delay`, `KeyPressed`, `ReadKey`. Layarnya dibandingkan sel demi sel dengan `Crt` milik FPC | ✅ |
| `Dos` | ✅ `GetDate`/`GetTime`, `GetEnv`, `FSplit`/`FExpand`/`FSearch`, `FindFirst`/`FindNext`, atribut dan waktu berkas, `DiskFree`, `Exec`/`DosExitCode` | ✅ |
| `Strings` | ✅ Rutin `PChar` | ✅ |
| `Printer` | ✅ `Lst` diteruskan ke `lpr`. Pencetakan sungguhan belum diuji | ✅ `Lst` diteruskan ke printer default macOS melalui `lpr` |
| `Objects` | ✅ `TCollection`, `TSortedCollection`, `TStringCollection`, stream berkas/ber-buffer/memori, `RegisterType`, `Put`/`Get`. Format stream sama dengan FPC | ✅ `TCollection`, `TStringCollection`, stream |
| Turbo Vision | ✅ Odin Vision (`rtl/vision/`): `App`, `Drivers`, `Views`, `Menus`, `Dialogs`, `MsgBox`, `StdDlg`, `Memory`, `HistList`, `Validate`, `Editors`, `Outline`. Diuji dengan snapshot layar (karakter dan warna). Warna palet dirancang sendiri. Belum ada `ColorSel` dan `TextView` | ✅ Melalui Free Vision: `App`, `Drivers`, `Views`, `Menus`, `Dialogs`, `MsgBox`, `StdDlg`, `Memory`, `HistList`, `Validate`, `Editors`, `Outline` |
| `Graph`, `Graph3`, `Overlay`, `WinDos`, `Turbo3` | ❌ | ❌ Tidak tersedia di Free Pascal untuk macOS |

Program yang memakai unit yang belum tersedia di backend Odin mendapat pesan yang menyarankan backend Free Pascal. Rincian dan perbedaan perilaku ada di [`docs/COMPATIBILITY.txt`](docs/COMPATIBILITY.txt) dan [`tests/pascal/DEVIATIONS.md`](tests/pascal/DEVIATIONS.md).

## Persyaratan Sistem

| Komponen | Kebutuhan |
|---|---|
| macOS | 11 Big Sur atau lebih baru, Intel (x86_64) atau Apple Silicon (arm64) |
| Python | 3.10+ dengan Tk ([python.org universal2](https://www.python.org/downloads/macos/) atau Homebrew `python-tk@3.13`) |
| Free Pascal | 3.2.2+ ([freepascal.org](https://www.freepascal.org/down/i386/macosx.html) atau Homebrew `fpc`). Wajib untuk paket rilis dan Apple Silicon |
| Xcode Command Line Tools | Untuk backend Free Pascal: linker, SDK, dan LLDB (`xcode-select --install`) |
| Rust | 1.85+ ([rustup.rs](https://rustup.rs)), hanya untuk membangun toolchain Odin dari source |

Pemasang dapat memasang dependensi yang belum ada melalui Homebrew. Di Linux, Odin dijalankan dari source dengan backend Free Pascal (lihat [Untuk Pengembang](#untuk-pengembang)).

## Instalasi

Pemasang ini memasang **rilis 2.0.0-alpha.1**: IDE, toolchain Odin untuk Mac Intel, dan runtime library-nya. Free Pascal tetap dipasang, karena dipakai pemeriksaan pemasang, di Apple Silicon, dan bila backend Free Pascal dipilih.

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

### Mencoba versi pengembangan

Di Mac Intel dengan Python (Tk) dan Rust:

```bash
cd Odin_Turbo_Pascal/toolchain
cargo build --release        # membangun odinpc; tanpa crate pihak ketiga
cd ..
python3 main.py              # IDE menemukan toolchain/target/release/odinpc
```

Backend Odin langsung menjadi bawaan. Free Pascal tetap bisa dipilih di **Options › Compiler**.

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
4. *(Versi pengembangan)* Tekan `F8` untuk menjalankan program baris demi baris. Sorot `Nama`, lalu tekan `Ctrl+F7` untuk melihat isinya.
5. Buka **File › Examples** untuk mencoba sebelas contoh siap pakai: `HELLO`, `INPUT`, `KALKULATOR`, `PARAMETER`, `REKURSI`, `ARRAY`, `BERKAS`, `CRTDEMO`, `VISION` (Turbo Vision), serta `UNITDEMO` bersama unit `UMATH`.

## Pintasan Keyboard

| Tombol | Fungsi | Tombol | Fungsi |
|---|---|---|---|
| `F1` | Help | `Ctrl+F9` | Compile dan run; lanjut di debugger |
| `F2` | Save | `Alt+F9` / `F9` | Compile / Make |
| `F3` | Open | `Ctrl+F2` | Hentikan program atau debugger |
| `F4` | Go to cursor (debugger) | `Alt+F5` | User screen |
| `F5` | Zoom jendela | `Ctrl+F8` | Toggle breakpoint |
| `F6` | Jendela berikutnya | `Ctrl+F7` | Evaluate/Modify (debugger) |
| `F7` / `F8` | Trace into / Step over | `Alt+F8` | Diagnostik berikutnya |
| `F10` | Menu File | `Alt+X` | Keluar |

Alternatif Mac: `Command+N/O/S` (New/Open/Save), `Command+B` (Compile), `Command+R` (Run), `Command+F` (Find), `Command+W` (Close), `Command+Q` (Quit). Pada Mac laptop, tekan `Fn` bersama `F1`–`F12`. Daftar lengkap ada di [`docs/SHORTCUTS.txt`](docs/SHORTCUTS.txt).

## Untuk Pengembang

IDE-nya aplikasi Python/Tk tanpa dependensi pip. Toolchain Odin ditulis dalam Rust tanpa crate pihak ketiga, dan runtime library-nya dalam Pascal. Semua perintah dijalankan dari root repositori, dengan Python yang mendukung Tk:

```bash
python3 main.py                                     # jalankan IDE dari source (macOS/Linux)
python3 -m unittest discover -s tests -v            # seluruh tes Python
python3 -m unittest tests.test_debugger -v          # sesi debugger tanpa Tk
ODIN_FPC=/path/ke/fpc python3 -m unittest discover -s tests -v   # pakai compiler tertentu
(cd toolchain && cargo build --release)             # bangun odinpc
(cd toolchain && cargo test --workspace)            # tes Rust, termasuk korpus diferensial
python3 scripts/oracle.py                           # tulis ulang ekspektasi korpus dengan FPC
python3 scripts/package_app.py                      # bentuk ulang bundel .app dari source
```

Penjelasan tes:

- Tes yang memakai Free Pascal dilewati bila FPC tidak ditemukan.
- Tes backend Odin dilewati bila `odinpc` belum dibangun atau Mac-nya bukan Intel.
- Tes GUI dilewati bila tidak ada display.
- Tes yang membuka pseudo-terminal memerlukan izin membuat PTY.

```text
Odin_Turbo_Pascal/
├── main.py                 Titik masuk aplikasi
├── odin/
│   ├── app.py              Antarmuka Tk: menu, dialog, User screen, sesi debug
│   ├── windows.py          Jendela desktop: editor, Watches, Local variables, Call stack
│   ├── core.py             Dokumen, pengaturan, build (Odin dan Free Pascal), diagnostik
│   ├── debugger.py         Sesi debug: odinpc debug di User screen, perintah JSON
│   └── terminal.py         Emulator VT100 80×25 dan proses pseudo-terminal
├── toolchain/              odinpc (Rust): lexer, parser, sema, codegen x86-64,
│                           assembler, linker Mach-O, info debug, debugger
├── rtl/                    Runtime library (Pascal): System, Crt, Dos, Strings, Printer
├── examples/               Sebelas contoh program Pascal, termasuk satu unit
├── docs/                   Panduan, referensi Pascal, pintasan, kompatibilitas
├── tests/                  Tes Python (fungsional, compiler, debugger, GUI) dan
│   └── pascal/             korpus Pascal dengan keluaran FPC sebagai pembanding
├── scripts/                Launcher, pemeriksaan Mac, oracle FPC, bundel .app, render logo
├── assets/                 Logo, ikon, dan banner (sumber SVG serta PNG/ICNS)
├── Odin Turbo Pascal.app   Bundel macOS (dibentuk dari source)
├── IMPLEMENTATION_PLAN.md  Rencana dan status toolchain Odin
└── Install.command · Uninstall.command · CHANGELOG.md · LICENSE · THIRD_PARTY.txt
```

Catatan arsitektur:

- **Threading.** `core.py` dan `debugger.py` tidak bergantung pada Tk. Thread kompilasi, pembaca terminal, dan pembaca debugger tidak pernah menyentuh Tk secara langsung. Hasilnya dikirim lewat antrean pesan yang dibaca UI setiap 40 ms.
- **Tanpa shell.** Kompilasi dan eksekusi program tidak pernah memakai shell.
- **Debugger berbasis instrumentasi.** Build debug menyisipkan pengait di setiap statement, dan `odinpc debug` berbicara dengan runtime library program lewat Unix socket. Tidak ada ptrace maupun LLDB. Kontraknya ada di [`rtl/COMPILER_INTERFACE.md`](rtl/COMPILER_INTERFACE.md).
- **Clean-room.** Toolchain dan runtime library Odin ditulis tanpa membaca sumber Free Pascal, Free Vision, maupun Borland. Free Pascal hanya dipakai sebagai pembanding keluaran program di korpus `tests/pascal/`.

## Kompatibilitas dan Batasan

- Odin adalah **implementasi baru** yang mengikuti antarmuka dan alur Turbo Pascal klasik. Odin bukan salinan Borland dan tidak menyertakan binary, logo, font, maupun berkas bantuan Borland.
- Hasil kompilasi berupa program macOS 64-bit, bukan EXE DOS 16-bit. Kode Graph/BGI, `Mem`/`Port`, interrupt DOS, assembler 16-bit, dan pointer berbasis segmen perlu di-porting.
- `Real` berukuran 8 byte (TP: 6 byte); gunakan `Real48` untuk membaca berkas biner lama. `Round` membulatkan ke bilangan genap untuk nilai `.5`.
- **Backend Odin (versi pengembangan):**
  - baru menghasilkan program untuk Mac Intel;
  - mendukung tipe `object` TP7, unit `Objects`, dan Turbo Vision lewat Odin Vision (tanpa `ColorSel` dan `TextView`). Record data dialog harus `packed record`, seperti di Free Vision;
  - `Extended` sama dengan `Double`;
  - fungsi seperti `Exp` dan `Sin` dihitung dalam `Double`.
- Debugger terpadu hanya tersedia di backend Odin (Mac Intel). Rilis 1.0.0 memakai konsol LLDB.
- User screen tidak menyediakan scrollback maupun true color. Mouse diteruskan ke program yang memintanya. Option sebagai Alt di keyboard Mac sungguhan belum diuji.

## Status Pengujian

| Lingkungan | Hasil |
|---|---|
| Linux x86_64, Python 3.12, Tk 9.0, FPC 3.2.2, Xvfb (rilis 1.0.0) | Seluruh suite saat itu lulus. Lihat [`docs/TEST_REPORT.txt`](docs/TEST_REPORT.txt) |
| Mac Intel (macOS 15.7), Python 3.13, Tk 9.1, FPC 3.2.2, Rust 1.99 | 56 tes Python lulus, termasuk 17 tes GUI dengan jendela Tk sungguhan dan sesi debugger nyata, serta 4 tes Odin Vision (snapshot layar dan dialog berkas). 110 tes Rust juga lulus. Korpus diferensial 77 program (termasuk tipe `object` dan unit `Objects`) memberi keluaran dan kode keluar yang sama dengan FPC 3.2.2, baik dengan build biasa maupun build debug |
| Belum diverifikasi langsung | Pemasangan di Apple Silicon, peluncuran lewat Finder/LaunchServices, Gatekeeper, LLDB di paket rilis 1.0.0, dan pencetakan lewat `Printer`. Backend Odin belum mendukung Apple Silicon |

## Privasi dan Lokasi Data

Odin tidak memakai akun, server, API key, maupun telemetri. Internet hanya diperlukan untuk memasang dependensi yang belum ada.

| Lokasi | Isi |
|---|---|
| Folder pilihan Anda | Source Pascal, melalui **Save as** |
| `~/Library/Application Support/OdinTurboPascal/` | `settings.json`, cache build (termasuk info debug `.odbg`), `recovery.json`, `runtime-error.txt`, `last-error.log`, `launch.log` |

Program dijalankan dengan working directory di folder source program utama. `Uninstall.command` tidak menghapus program pribadi maupun folder pengaturan.

## Kontribusi

Laporan bug, saran, dan pull request dipersilakan. Sebelum mengirim perubahan:

1. Jalankan `python3 -m unittest discover -s tests -v` dan, bila mengubah `toolchain/` atau `rtl/`, `cargo test --workspace` di `toolchain/`. Tambahkan tes untuk perilaku baru.
2. Untuk perilaku Pascal baru, tambahkan program ke `tests/pascal/` dan buat ekspektasinya dengan `scripts/oracle.py`. Jangan membaca atau menyalin sumber Free Pascal, Free Vision, maupun Borland.
3. Tulis pesan untuk pengguna dalam bahasa Indonesia. Label menu tetap berbahasa Inggris, sesuai gaya Turbo Pascal.
4. Awali berkas source baru dengan header lisensi `SPDX-License-Identifier: GPL-3.0-or-later`.
5. Setelah mengubah source, jalankan `python3 scripts/package_app.py` agar bundel `.app` ikut diperbarui.

## Lisensi

Odin Turbo Pascal adalah perangkat lunak bebas di bawah **[GNU General Public License v3.0 atau yang lebih baru](LICENSE)**. Anda boleh memakai, mempelajari, mengubah, dan menyebarkannya. Bila Anda menyebarkan versi asli atau versi ubahan, sertakan source code-nya dengan lisensi yang sama. Program ini disediakan tanpa jaminan apa pun.

**Copyright © 2026 Syams Ideris** · [syamsuddin.ideris@gmail.com](mailto:syamsuddin.ideris@gmail.com)

Program yang dikompilasi dengan backend Odin memuat runtime library Odin, yang juga berlisensi GNU GPL v3 atau yang lebih baru tanpa pengecualian runtime. Bila Anda membagikan program tersebut, ketentuan GPL berlaku untuk program itu.

Python, Tcl/Tk, Free Pascal, Xcode Command Line Tools (termasuk LLDB), dan Homebrew dipasang terpisah dengan lisensinya masing-masing. `odinpc` dibangun dengan pustaka standar Rust (lisensi MIT/Apache-2.0). Sebelum mendistribusikan program hasil kompilasi Free Pascal, baca juga ketentuan runtime Free Pascal. Lihat [`THIRD_PARTY.txt`](THIRD_PARTY.txt).

> Odin adalah aplikasi independen dan tidak berafiliasi dengan Borland maupun pemilik merek Turbo Pascal saat ini. "Turbo Pascal" dan "Borland" adalah merek dagang dari pemiliknya masing-masing. Nama tersebut dipakai hanya untuk menjelaskan kompatibilitas dan inspirasi.

## Penulis

**Syams Ideris** · [syamsuddin.ideris@gmail.com](mailto:syamsuddin.ideris@gmail.com)

<div align="center">

---

Bila Odin Turbo Pascal bermanfaat untuk belajar atau mengajar, beri ⭐ pada repositori ini dan bagikan ke teman sekelas.

<sub>Dibuat untuk generasi baru pembelajar Pascal.</sub>

</div>
