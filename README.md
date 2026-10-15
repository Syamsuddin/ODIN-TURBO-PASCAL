<div align="center">

<img src="assets/banner.svg" alt="Odin Turbo Pascal: IDE Pascal klasik dengan compiler, debugger, dan Turbo Vision native untuk macOS, Linux, dan Windows" width="100%">

# Odin Turbo Pascal

**Layar biru Turbo Pascal yang Anda kenal, dengan compiler dan debugger yang menghasilkan program native.**

[![Versi](https://img.shields.io/badge/rilis-2.2.0--alpha.1-0000aa?style=flat-square)](CHANGELOG.md)
[![Pengembangan](https://img.shields.io/badge/pengembangan-toolchain%20Odin-00aaaa?style=flat-square)](IMPLEMENTATION_PLAN.md)
[![Lisensi GPL v3](https://img.shields.io/badge/lisensi-GPL--3.0--or--later-ffff55?style=flat-square)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-11%2B%20Intel%20%7C%20Apple%20Silicon-000000?style=flat-square&logo=apple&logoColor=white)](#persyaratan-sistem)
[![Linux](https://img.shields.io/badge/Linux-x86__64%20%7C%20arm64-000000?style=flat-square&logo=linux&logoColor=white)](#linux)
[![Windows](https://img.shields.io/badge/Windows-10%201809%2B%20x86__64-000000?style=flat-square)](#windows)
[![CI](https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/actions/workflows/ci.yml/badge.svg)](https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/actions/workflows/ci.yml)
[![Python](https://img.shields.io/badge/Python-3.10%2B%20dengan%20Tk-3776ab?style=flat-square&logo=python&logoColor=white)](https://www.python.org/downloads/macos/)
[![Offline](https://img.shields.io/badge/offline-tanpa%20telemetri-55ff55?style=flat-square)](#privasi-dan-lokasi-data)

[Fitur](#fitur) · [Instalasi](#instalasi) · [Mulai Cepat](#mulai-cepat) · [Debugger](#debugger) · [Pintasan](#pintasan-keyboard) · [Pengembang](#untuk-pengembang) · [Changelog](CHANGELOG.md) · [Lisensi](#lisensi)

</div>

---

## Sekilas

<img src="assets/odin-logo.png" alt="Logo ODIN Turbo Pascal: Odin bertambal mata, petir, dan buku begin. end." width="200" align="right">

**Odin Turbo Pascal** adalah IDE Pascal yang menghadirkan kembali pengalaman Turbo Pascal era DOS: layar biru, teks kuning, menu abu-abu, jendela editor berbingkai, dan tombol fungsi klasik. Bedanya, kode Anda dikompilasi menjadi **program native untuk macOS, Linux, atau Windows**, tanpa emulator DOS. Setelah terpasang, Odin tidak memerlukan internet dan tidak mengirim telemetri.

Odin punya dua backend compiler:

- **Odin native.** Ini toolchain Odin sendiri: compiler Pascal, assembler, linker, runtime library, Odin Vision (Turbo Vision milik Odin), dan debugger, semuanya ditulis dari nol. Backend ini bawaan di macOS (Intel dan Apple Silicon), Linux (x86_64 dan arm64), dan Windows (x86_64).
- **Free Pascal.** Compiler yang dipakai rilis 1.0.0. Tetap bisa dipilih di **Options › Compiler**, dan dipakai otomatis di sistem yang belum didukung backend Odin.

> [!NOTE]
> **Rilis.**
>
> - **2.2.0-alpha.1** (rilis ini) membawa IDE, toolchain Odin, debugger terpadu, dan Odin Vision ke **Windows** (x86_64, Windows 10 1809 atau lebih baru), dengan pemasang `Install.cmd`. Windows diuji di runner GitHub Actions (Windows Server 2025), belum di PC Windows fisik.
> - **2.1.0-alpha.1** membawa toolchain Odin, debugger terpadu, dan Odin Vision ke **Apple Silicon** dan **Linux** (x86_64 dan arm64). Bundel macOS berisi `odinpc` universal (Intel dan Apple Silicon). Apple Silicon dan Linux diuji di runner GitHub Actions, belum di perangkat fisik pengembang.
> - **2.0.1** menampilkan tag versi di desktop, About, dan contoh `HELLO.PAS`.
> - **2.0.0** membawa toolchain Odin native, debugger terpadu, Odin Vision, dan logo baru untuk Mac Intel.
> - **2.0.0-alpha.1** dan **2.0.0-alpha.2** adalah rilis alfa yang memperkenalkan toolchain Odin native dan logo baru.
> - **1.0.0** mengompilasi dengan Free Pascal dan men-debug lewat LLDB.
>
> Rilis 2.1.0 dan 2.2.0 menyusul setelah pemasang diuji di Mac Apple Silicon dan PC Windows sungguhan. Kemajuan per tahap tercatat di [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md).

Cocok untuk siswa dan mahasiswa yang belajar algoritma dan pemrograman, guru yang mengajar Pascal di kelas, dan siapa saja yang rindu menekan `Ctrl+F9` lalu melihat programnya berjalan.

> **English summary.** Odin Turbo Pascal is a DOS-era, Turbo Pascal–style IDE for macOS, Linux and Windows. Programs compile into native binaries and run in a built-in 80×25 terminal with Crt and Turbo Vision support, including the mouse. Odin's own toolchain, written from scratch in Rust and Pascal (compiler with x86-64 and AArch64 code generators, assembler, Mach-O, ELF and PE linkers, runtime library, Odin Vision, and an integrated Turbo Pascal–style debugger with Watches, Locals and Call stack windows), is the default backend on Intel and Apple Silicon Macs and on x86_64 and arm64 Linux since release 2.1.0-alpha.1, and on x86_64 Windows since 2.2.0-alpha.1; Apple Silicon, Linux and Windows are verified on GitHub Actions runners. Free Pascal remains available as an alternative backend. Messages and documentation are in Indonesian. Licensed under the GNU GPL v3 or later.

<div align="center">

<img src="docs/UI_PREVIEW_LINUX.png" alt="Editor Odin Turbo Pascal menampilkan HELLO.PAS dengan menu klasik dan baris tombol fungsi" width="820">

<sub>Editor dengan contoh <code>HELLO.PAS</code>. Tangkapan layar dari lingkungan uji Linux; di macOS jendela memakai tampilan Tk native.</sub>

</div>

## Mengapa Odin?

- **Nostalgia yang benar-benar bekerja.** Alur kerja Turbo Pascal tetap utuh: `F2` simpan, `F9` make, `Ctrl+F9` jalankan, `Alt+F5` User screen, `F7`/`F8` menelusuri program baris demi baris.
- **Program native, bukan emulasi.** Hasil kompilasi adalah executable asli untuk CPU dan sistem operasi Anda, dan bisa diekspor untuk dijalankan di luar IDE.
- **Compiler dan debugger milik sendiri.** Di macOS, Linux, dan Windows, Odin mengompilasi dengan toolchain yang ditulis dari nol dan men-debug tanpa LLDB atau GDB, dengan jendela Watches dan Call stack seperti Turbo Pascal.
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
- Desktop menampilkan logo Odin, tag versi (misalnya `v2.0.0`), dan kredit penulis. Tag yang sama tampil di baris status, About, dan contoh `HELLO.PAS`.
- Encoding CP437 dan UTF-8 (termasuk BOM), serta akhir baris LF dan CRLF, dipertahankan apa adanya saat menyimpan.

### Kompilasi
- Pilihan backend di **Options › Compiler**:
  - **Odin native** *(bawaan di macOS, Linux, dan Windows)*. Bahasa Turbo Pascal 7, termasuk tipe `object`, dengan unit standar dan Turbo Vision (lihat [tabel unit](#unit-standar-turbo-pascal)). Tidak memerlukan Free Pascal, Xcode, maupun GCC. Menghasilkan program x86_64 dan arm64 untuk CPU Anda (di Windows: x86_64).
  - **Free Pascal** dengan mode **Turbo Pascal 7** (`-Mtp`), Object Pascal, atau Delphi.
- Compile, Make, dan Build. Tersedia *primary file* untuk proyek yang terdiri dari program dan unit.
- Unit path dan include path, range check, dan overflow check.
- Daftar diagnostik compiler: klik untuk melompat ke baris error, dan `Alt+F8` untuk pesan berikutnya. Pesan backend Odin berbahasa Indonesia dengan nomor galat gaya Turbo Pascal 7.
- Hasil build disimpan terpisah di cache. Build yang gagal tidak pernah menjalankan executable lama.
- Ekspor executable native.

### Menjalankan program
- User screen 80×25 berbasis pseudo-terminal (ConPTY di Windows): `ReadLn`, `ReadKey`, `KeyPressed`, 16 warna, `GotoXY`, `ClrScr`, dan `Window`.
- Tombol `F1`–`F12`, `Insert`, dan panah diteruskan ke program dengan kode scan Turbo Pascal, termasuk kombinasi Shift, Ctrl, dan Alt (Option di Mac).
- Program Turbo Vision menerima klik, seret, dan roda mouse. Setelah program selesai, isi layar sebelumnya kembali.
- Parameter program (Run › Parameters) diteruskan tanpa melewati shell.
- `Ctrl+C` menginterupsi program, `Ctrl+F2` menghentikannya, dan **Copy screen** menyalin isi layar.
- Runtime error (backend Odin): baris penyebabnya ditandai merah di editor, dan **Search › Find error** kembali ke baris itu.

### Turbo Vision (Odin Vision)

**Backend Odin (macOS, Linux, dan Windows).** Odin Vision adalah Turbo Vision milik Odin, ditulis ulang dari nol (*clean-room*) mengikuti API Turbo Vision di Turbo Pascal 7:

- Unit `App`, `Drivers`, `Views`, `Menus`, `Dialogs`, `MsgBox`, `StdDlg`, `Memory`, `HistList`, `Validate`, `Editors`, dan `Outline`.
- Jendela bertumpuk dengan bayangan, menu bar dan menu drop-down, serta status line.
- Dialog dengan tombol, input line (dengan validator dan riwayat), check box, radio button, dan list box, ditambah dialog berkas dan dialog ganti direktori.
- Editor teks dan outline.
- Keyboard dan mouse di User screen. Perilakunya dijelaskan di [`rtl/vision/SPEC.md`](rtl/vision/SPEC.md).
- Contoh siap pakai: **File › Examples › VISION.PAS**.

### Debugger

**Backend Odin (macOS, Linux, dan Windows).** Debugger terpadu bergaya Turbo Pascal, tanpa LLDB atau GDB:

- **Breakpoint** dari gutter atau `Ctrl+F8`. Breakpoint ikut bergeser saat baris disisipkan, tersimpan bersama pemulihan sesi, dan bisa diubah saat program berjalan.
- **Menelusuri program:**
  - **Trace into** (`F7`) dan **Step over** (`F8`);
  - **Go to cursor** (`F4`) dan Continue;
  - `Ctrl+C` di User screen untuk berhenti sementara.

  Baris yang akan dijalankan berikutnya ditandai hijau.
- **Jendela Watches, Local variables, dan Call stack.** Ketiganya ikut diatur Tile dan Cascade. Pilih frame di Call stack untuk melihat variabel pemanggil.
- **Evaluate/Modify** (`Ctrl+F7`) untuk ekspresi Pascal: variabel, field, indeks dengan cek batas, `^`, `@`, aritmetika, typecast, `Ord`/`Chr`/`Length`/`High`/`Low`/`SizeOf`. Nilai ditampilkan seperti di Turbo Pascal, misalnya `'abc'`, `(1, 2, 3)`, `(X:1; Y:2)`, `[1, 3..5]`, dan nama enumerasi.

Rilis 1.0.0 memakai konsol LLDB di User screen untuk breakpoint, step, variabel lokal, dan call stack. Sejak 2.0.0-alpha.1 debugger terpadu menggantikannya, dan sejak 2.1.0-alpha.1 debugger ini juga tersedia di Apple Silicon dan Linux, lalu di Windows sejak 2.2.0-alpha.1.

### Berkas dan sesi
- Contoh bawaan diperlakukan sebagai template: **Save** otomatis menjadi **Save as**, sehingga contoh asli tidak tertimpa.
- Daftar berkas terakhir, pengaturan yang tersimpan, dan hanya satu instance aplikasi yang berjalan.

## Unit Standar Turbo Pascal

Kolom Free Pascal diuji 13 Oktober 2026 melalui jalur kompilasi dan User screen Odin di Mac Intel dengan Free Pascal 3.2.2. Kolom backend Odin diuji dengan korpus tes yang keluarannya dibandingkan dengan Free Pascal 3.2.2: di Mac Intel, di VM Ubuntu 24.04 (x86_64, dan aarch64 lewat qemu), dan di runner GitHub Actions untuk macOS Apple Silicon, Linux x86_64, dan Linux arm64.

| Unit | Backend Odin | Free Pascal |
|---|---|---|
| `System` | ✅ String, matematika, `Str`/`Val`, berkas teks, bertipe, dan tanpa tipe, direktori, `ParamStr`, heap, `ExitProc`, runtime error | ✅ |
| `Crt` | ✅ `ClrScr`, `GotoXY`, `WhereX`/`WhereY`, warna, `Window`, `ClrEol`, `InsLine`/`DelLine`, `Delay`, `KeyPressed`, `ReadKey`. Layarnya dibandingkan sel demi sel dengan `Crt` milik FPC | ✅ |
| `Dos` | ✅ `GetDate`/`GetTime`, `GetEnv`, `FSplit`/`FExpand`/`FSearch`, `FindFirst`/`FindNext`, atribut dan waktu berkas, `DiskFree`, `Exec`/`DosExitCode` | ✅ |
| `Strings` | ✅ Rutin `PChar` | ✅ |
| `Printer` | ✅ `Lst` diteruskan ke `lpr` (di Windows: `notepad /p`). Pencetakan sungguhan belum diuji | ✅ `Lst` diteruskan ke printer default macOS melalui `lpr` |
| `Objects` | ✅ `TCollection`, `TSortedCollection`, `TStringCollection`, stream berkas/ber-buffer/memori, `RegisterType`, `Put`/`Get`. Format stream sama dengan FPC | ✅ `TCollection`, `TStringCollection`, stream |
| Turbo Vision | ✅ Odin Vision (`rtl/vision/`): `App`, `Drivers`, `Views`, `Menus`, `Dialogs`, `MsgBox`, `StdDlg`, `Memory`, `HistList`, `Validate`, `Editors`, `Outline`. Diuji dengan snapshot layar (karakter dan warna). Warna palet dirancang sendiri. Belum ada `ColorSel` dan `TextView` | ✅ Melalui Free Vision: `App`, `Drivers`, `Views`, `Menus`, `Dialogs`, `MsgBox`, `StdDlg`, `Memory`, `HistList`, `Validate`, `Editors`, `Outline` |
| `Graph`, `Graph3`, `Overlay`, `WinDos`, `Turbo3` | ❌ | ❌ Tidak tersedia di Free Pascal untuk macOS |

Program yang memakai unit yang belum tersedia di backend Odin mendapat pesan yang menyarankan backend Free Pascal. Rincian dan perbedaan perilaku ada di [`docs/COMPATIBILITY.txt`](docs/COMPATIBILITY.txt) dan [`tests/pascal/DEVIATIONS.md`](tests/pascal/DEVIATIONS.md).

## Persyaratan Sistem

| Komponen | Kebutuhan |
|---|---|
| macOS | 11 Big Sur atau lebih baru, Intel (x86_64) atau Apple Silicon (arm64) |
| Linux | x86_64 atau arm64 dengan glibc 2.34 atau lebih baru (Ubuntu 22.04+, Debian 12+, Fedora 35+). musl (Alpine) tidak didukung |
| Windows | Windows 10 versi 1809 atau lebih baru, 64-bit (x86_64). User screen memakai ConPTY. Windows on ARM belum didukung |
| Python | 3.10+ dengan Tk ([python.org universal2](https://www.python.org/downloads/macos/) atau Homebrew `python-tk@3.13` di macOS; paket `python3-tk` di Linux; [python.org](https://www.python.org/downloads/windows/) dengan pilihan tcl/tk di Windows) |
| Free Pascal | 3.2.2+ ([freepascal.org](https://www.freepascal.org/down/i386/macosx.html) atau Homebrew `fpc`). Diperiksa pemasang macOS dan Windows, dan dipakai bila backend Free Pascal dipilih |
| Xcode Command Line Tools | Untuk backend Free Pascal dan pemeriksaan pemasang: linker dan SDK (`xcode-select --install`) |
| Rust | 1.85+ ([rustup.rs](https://rustup.rs)), hanya untuk membangun toolchain Odin dari source |

Pemasang macOS dapat memasang dependensi yang belum ada melalui Homebrew, dan pemasang Windows melalui winget. Di Linux, Odin dijalankan dari source (lihat [Linux](#linux)).

## Instalasi

Pemasang ini memasang **rilis 2.2.0-alpha.1**: IDE, toolchain Odin universal untuk Mac Intel dan Apple Silicon, dan runtime library-nya. Free Pascal tetap dipasang, karena dipakai pemeriksaan pemasang dan bila backend Free Pascal dipilih.

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

### Linux

Odin dijalankan dari source. Contoh untuk Ubuntu atau Debian:

```bash
sudo apt install python3-tk git          # IDE (Python + Tk)
curl https://sh.rustup.rs -sSf | sh      # Rust, sekali saja, untuk membangun odinpc
git clone https://github.com/Syamsuddin/ODIN-TURBO-PASCAL.git
cd ODIN-TURBO-PASCAL/toolchain
cargo build --release                    # membangun odinpc; tanpa crate pihak ketiga
cd ..
python3 main.py                          # IDE menemukan toolchain/target/release/odinpc
```

Backend Odin langsung menjadi bawaan, termasuk debugger dan Odin Vision. Free Pascal (`sudo apt install fpc`) hanya diperlukan bila Anda memilih backend itu.

### Windows

Pemasang Windows memasang IDE beserta `odinpc.exe` dan runtime library-nya di `%LOCALAPPDATA%\Programs\OdinTurboPascal`, tanpa hak administrator.

1. **Unduh** repositori ini (**Code › Download ZIP**), lalu ekstrak seluruhnya.
2. **Klik dua kali `Install.cmd`.** Pemasang berjalan di jendela PowerShell dan akan:
   - memeriksa Windows 10 1809 atau lebih baru, 64-bit;
   - mencari Python dengan Tk dan Free Pascal, lalu menawarkan winget atau tautan unduhan resmi bila ada yang belum terpasang;
   - **mengompilasi dan menjalankan program uji kecil** dengan Free Pascal dan dengan toolchain Odin;
   - memasang aplikasi, mencadangkan versi sebelumnya bila ada, dan membuat pintasan di menu Start dan Desktop.
3. **Jalankan** Odin Turbo Pascal dari menu Start.

Untuk menghapus aplikasi, jalankan `Uninstall.cmd`. Program Pascal dan pengaturan Anda (`%APPDATA%\OdinTurboPascal`) tetap tersimpan.

> [!NOTE]
> Di runner GitHub Actions, pemeriksaan kompilasi dan penyalinan aplikasi oleh pemasang diuji pada setiap commit. Pemasang lengkap, termasuk winget dan pintasan, belum dijalankan di PC Windows sungguhan.

### Menjalankan dari source di macOS

Dengan Python (Tk) dan Rust: `cd toolchain && cargo build --release && cd .. && python3 main.py`. Untuk bundel `.app` yang berjalan di Intel maupun Apple Silicon, bangun `odinpc` universal dengan `python3 scripts/build_toolchain.py` sebelum `python3 scripts/package_app.py`.

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
4. *(Backend Odin)* Tekan `F8` untuk menjalankan program baris demi baris. Sorot `Nama`, lalu tekan `Ctrl+F7` untuk melihat isinya.
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
python3 main.py                                     # jalankan IDE dari source (macOS/Linux; di Windows: python main.py)
python3 -m unittest discover -s tests -v            # seluruh tes Python
python3 -m unittest tests.test_debugger -v          # sesi debugger tanpa Tk
python3 -m unittest tests.test_vision -v            # snapshot layar Odin Vision
ODIN_UPDATE_SNAPSHOTS=1 python3 -m unittest tests.test_vision   # tulis ulang snapshot (tinjau dulu)
ODIN_FPC=/path/ke/fpc python3 -m unittest discover -s tests -v   # pakai compiler tertentu
(cd toolchain && cargo build --release)             # bangun odinpc
(cd toolchain && cargo test --workspace)            # tes Rust, termasuk korpus diferensial
python3 scripts/build_toolchain.py                  # odinpc universal (x86_64 + arm64) untuk bundel macOS
ODIN_CORPUS_TARGET=aarch64-linux ODIN_CORPUS_RUNNER="qemu-aarch64-static -L /usr/aarch64-linux-gnu" \
  cargo test -p odinpc --test corpus                # korpus untuk target lain (lihat tests/corpus.rs)
python3 scripts/oracle.py                           # tulis ulang ekspektasi korpus dengan FPC
python3 scripts/render_logo.py                      # render logo, ikon, dan banner (butuh Pillow)
python3 scripts/package_app.py                      # bentuk ulang bundel .app dari source, termasuk tag versi di HELLO.PAS
python3 scripts/set_version.py 2.0.1                # naikkan nomor versi di semua berkas dan CHANGELOG
python3 scripts/update_checksums.py                 # buat ulang SHA256SUMS.json (terakhir, setelah package_app)
```

Penjelasan tes:

- Tes yang memakai Free Pascal dilewati bila FPC tidak ditemukan.
- Tes backend Odin dilewati bila `odinpc` belum dibangun atau sistemnya belum didukung (`core.ODIN_HOSTS`).
- GitHub Actions menjalankan semuanya di macOS Intel, macOS Apple Silicon, Linux x86_64, Linux arm64, dan Windows ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).
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
├── toolchain/              odinpc (Rust): lexer, parser, sema, codegen x86-64 dan AArch64,
│                           assembler, linker Mach-O/ELF/PE, info debug, debugger
├── rtl/                    Runtime library (Pascal): System, Crt, Dos, Strings, Printer, Objects
│   └── vision/             Odin Vision: unit Turbo Vision dan spesifikasinya (SPEC.md)
├── examples/               Sebelas contoh program Pascal, termasuk satu unit
├── docs/                   Panduan, referensi Pascal, pintasan, kompatibilitas
├── tests/                  Tes Python (fungsional, compiler, debugger, GUI, Odin Vision) dan
│   └── pascal/             korpus Pascal (keluaran FPC sebagai pembanding) serta snapshot Odin Vision
├── scripts/                Launcher, pemeriksaan Mac, oracle FPC, bundel .app, render logo
├── assets/                 Logo, ikon, dan banner (master PNG serta PNG/ICNS hasil render)
├── Odin Turbo Pascal.app   Bundel macOS (dibentuk dari source)
├── IMPLEMENTATION_PLAN.md  Rencana dan status toolchain Odin
└── Install.command · Uninstall.command · CHANGELOG.md · LICENSE · THIRD_PARTY.txt
```

Catatan arsitektur:

- **Threading.** `core.py` dan `debugger.py` tidak bergantung pada Tk. Thread kompilasi, pembaca terminal, dan pembaca debugger tidak pernah menyentuh Tk secara langsung. Hasilnya dikirim lewat antrean pesan yang dibaca UI setiap 40 ms.
- **Tanpa shell.** Kompilasi dan eksekusi program tidak pernah memakai shell.
- **Debugger berbasis instrumentasi.** Build debug menyisipkan pengait di setiap statement, dan `odinpc debug` berbicara dengan runtime library program lewat Unix socket (di Windows: TCP 127.0.0.1). Tidak ada ptrace, LLDB, maupun GDB, sehingga perilakunya sama di setiap sistem. Kontraknya ada di [`rtl/COMPILER_INTERFACE.md`](rtl/COMPILER_INTERFACE.md).
- **Clean-room.** Toolchain dan runtime library Odin ditulis tanpa membaca sumber Free Pascal, Free Vision, maupun Borland. Free Pascal hanya dipakai sebagai pembanding keluaran program di korpus `tests/pascal/`.

## Kompatibilitas dan Batasan

- Odin adalah **implementasi baru** yang mengikuti antarmuka dan alur Turbo Pascal klasik. Odin bukan salinan Borland dan tidak menyertakan binary, logo, font, maupun berkas bantuan Borland.
- Hasil kompilasi berupa program 64-bit untuk macOS, Linux, atau Windows, bukan EXE DOS 16-bit. Kode Graph/BGI, `Mem`/`Port`, interrupt DOS, assembler 16-bit, dan pointer berbasis segmen perlu di-porting.
- `Real` berukuran 8 byte (TP: 6 byte); gunakan `Real48` untuk membaca berkas biner lama. `Round` membulatkan ke bilangan genap untuk nilai `.5`.
- **Backend Odin:**
  - menghasilkan program untuk macOS dan Linux (x86_64 dan arm64) serta Windows (x86_64);
  - mendukung tipe `object` TP7, unit `Objects`, dan Turbo Vision lewat Odin Vision (tanpa `ColorSel` dan `TextView`). Record data dialog harus `packed record`, seperti di Free Vision;
  - `Extended` sama dengan `Double`;
  - fungsi seperti `Exp` dan `Sin` dihitung dalam `Double`.
- Debugger terpadu hanya tersedia di backend Odin. Rilis 1.0.0 memakai konsol LLDB.
- User screen tidak menyediakan scrollback maupun true color. Mouse diteruskan ke program yang memintanya. Option sebagai Alt di keyboard Mac sungguhan belum diuji.

## Status Pengujian

| Lingkungan | Hasil |
|---|---|
| Linux x86_64, Python 3.12, Tk 9.0, FPC 3.2.2, Xvfb (rilis 1.0.0) | Seluruh suite saat itu lulus. Lihat [`docs/TEST_REPORT.txt`](docs/TEST_REPORT.txt) |
| Mac Intel (macOS 15.7), Python 3.13, Tk 9.1, FPC 3.2.2, Rust 1.99 (rilis 2.2.0-alpha.1) | 92 tes Python lulus (6 tes khusus Windows dilewati), termasuk tes GUI dengan jendela Tk sungguhan, sesi debugger nyata, dan snapshot Odin Vision. 185 tes Rust juga lulus. Korpus diferensial 77 program (termasuk tipe `object` dan unit `Objects`) memberi keluaran dan kode keluar yang sama dengan FPC 3.2.2, baik dengan build biasa maupun build debug |
| VM Ubuntu 24.04 (Lima di Mac Intel), Python 3.12, Tk 8.6 (rilis 2.1.0-alpha.1) | Korpus diferensial lulus untuk x86_64 dan untuk aarch64 lewat qemu-user; 92 tes Python dengan backend Odin lulus di x86_64 |
| GitHub Actions: macOS 15 Apple Silicon, Ubuntu 24.04 x86_64 dan arm64, macOS 15 Intel (rilis 2.2.0-alpha.1) | Korpus diferensial berjalan native dan lulus; tes Python dengan backend Odin (GUI, debugger, Odin Vision) lulus. Lihat [CI](https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/actions/workflows/ci.yml) |
| GitHub Actions: Windows Server 2025 x86_64, Python 3.12, FPC 3.2.2 i386-win32 (rilis 2.2.0-alpha.1) | Korpus diferensial 77 program (biasa dan debug) identik dengan FPC untuk Windows; 92 tes Python lulus (2 tes khusus Unix dilewati), termasuk GUI, debugger, dan Odin Vision di ConPTY; pemeriksaan kompilasi dan penyalinan pemasang lulus |
| Belum diverifikasi langsung | Mac Apple Silicon dan PC Linux fisik (hanya runner CI dan VM), pemasangan lewat `Install.command` di Apple Silicon, peluncuran lewat Finder/LaunchServices, Gatekeeper, LLDB di paket rilis 1.0.0, dan pencetakan lewat `Printer`. PC Windows fisik, `Install.cmd` lengkap (winget, pintasan, menu Start), dan Windows on ARM |

## Privasi dan Lokasi Data

Odin tidak memakai akun, server, API key, maupun telemetri. Internet hanya diperlukan untuk memasang dependensi yang belum ada.

| Lokasi | Isi |
|---|---|
| Folder pilihan Anda | Source Pascal, melalui **Save as** |
| `~/Library/Application Support/OdinTurboPascal/` (macOS), `~/.local/share/OdinTurboPascal/` (Linux), `%APPDATA%\OdinTurboPascal\` (Windows) | `settings.json`, cache build (termasuk info debug `.odbg`), `recovery.json`, `runtime-error.txt`, `last-error.log`, `launch.log` |

Program dijalankan dengan working directory di folder source program utama. `Uninstall.command` dan `Uninstall.cmd` tidak menghapus program pribadi maupun folder pengaturan.

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

Logo dan ikon Odin adalah karya penulis, diambil dari proyek ODIN Turbo Pascal v2.0, dan berlisensi sama.

Python, Tcl/Tk, Free Pascal, Xcode Command Line Tools, dan Homebrew dipasang terpisah dengan lisensinya masing-masing. `odinpc` dibangun dengan pustaka standar Rust (lisensi MIT/Apache-2.0). Sebelum mendistribusikan program hasil kompilasi Free Pascal, baca juga ketentuan runtime Free Pascal. Lihat [`THIRD_PARTY.txt`](THIRD_PARTY.txt).

> Odin adalah aplikasi independen dan tidak berafiliasi dengan Borland maupun pemilik merek Turbo Pascal saat ini. "Turbo Pascal" dan "Borland" adalah merek dagang dari pemiliknya masing-masing. Nama tersebut dipakai hanya untuk menjelaskan kompatibilitas dan inspirasi.

## Penulis

**Syams Ideris** · [syamsuddin.ideris@gmail.com](mailto:syamsuddin.ideris@gmail.com)

<div align="center">

---

Bila Odin Turbo Pascal bermanfaat untuk belajar atau mengajar, beri ⭐ pada repositori ini dan bagikan ke teman sekelas.

<sub>Dibuat untuk generasi baru pembelajar Pascal.</sub>

</div>
