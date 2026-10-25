<div align="center">

<img src="assets/banner.svg" alt="Odin Turbo Pascal: IDE Pascal klasik dengan compiler, debugger, dan Turbo Vision native untuk macOS, Linux, dan Windows" width="100%">

# Odin Turbo Pascal

**Cara kerja Turbo Pascal yang Anda kenal, dalam IDE berjendela modern, dengan compiler dan debugger yang menghasilkan program native.**

[![Versi](https://img.shields.io/badge/rilis-3.0.0--beta.1-0000aa?style=flat-square)](CHANGELOG.md)
[![CI](https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/actions/workflows/ci.yml/badge.svg)](https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/actions/workflows/ci.yml)
[![Lisensi GPL v3](https://img.shields.io/badge/lisensi-GPL--3.0--or--later-ffff55?style=flat-square)](LICENSE)
[![Offline](https://img.shields.io/badge/offline-tanpa%20telemetri-55ff55?style=flat-square)](#privasi-dan-lokasi-data)
<br>
[![macOS](https://img.shields.io/badge/macOS-11%2B%20Intel%20%7C%20Apple%20Silicon-000000?style=flat-square&logo=apple&logoColor=white)](#macos)
[![Linux](https://img.shields.io/badge/Linux-x86__64%20%7C%20arm64-000000?style=flat-square&logo=linux&logoColor=white)](#linux)
[![Windows](https://img.shields.io/badge/Windows-10%201809%2B%20x86__64-000000?style=flat-square)](#windows)
[![Python](https://img.shields.io/badge/Python-3.10%2B%20dengan%20Tk-3776ab?style=flat-square&logo=python&logoColor=white)](#persyaratan-sistem)
[![Rust](https://img.shields.io/badge/toolchain-Rust%20tanpa%20crate%20pihak%20ketiga-b7410e?style=flat-square&logo=rust&logoColor=white)](#pengembangan)

[Instalasi](#instalasi) · [Mulai Cepat](#mulai-cepat) · [Fitur](#fitur) · [Dokumentasi](#dokumentasi) · [Changelog](CHANGELOG.md) · [Kontribusi](#kontribusi)

</div>

> [!IMPORTANT]
> **Pra-rilis 3.0.0-beta.1** mengganti tampilan DOS dengan **antarmuka berjendela modern**: menu teks dengan dropdown, toolbar berikon, serta jendela editor, Output, dan Messages yang bisa digeser, diubah ukurannya, di-minimize, dan di-maximize di dalam jendela utama. Beta ini hanya diuji di Mac Intel. Rilis stabil terbaru tetap 2.9.0.
>
> **Rilis 2.9.0** memperluas bahasa Turbo Pascal 7 dengan **OOP berbasis `class`** seperti Delphi dan Free Pascal (pewarisan, `virtual`/`override`/`abstract`, `property`, `is`/`as`, `class of`, overload method), tanpa mode khusus sehingga program TP7 tetap dikompilasi apa adanya. Rilis ini juga membawa unit **Classes** dan **Contnrs** serta menu **File › Examples - OOP...** dengan 9 contoh. Rilis 2.8.0 menambahkan jendela grafik sungguhan untuk unit Graph. IDE, toolchain Odin, debugger terpadu, dan Odin Vision berjalan di macOS (Intel dan Apple Silicon), Linux (x86_64 dan arm64), dan **Windows** (x86_64). Windows, Apple Silicon, dan Linux diuji di runner GitHub Actions, belum di perangkat fisik pengembang. Lihat [Riwayat Rilis](#riwayat-rilis) dan [Status Pengujian](#status-pengujian).

## Daftar Isi

- [Tentang](#tentang)
- [Fitur](#fitur)
- [Platform yang Didukung](#platform-yang-didukung)
- [Persyaratan Sistem](#persyaratan-sistem)
- [Instalasi](#instalasi)
- [Mulai Cepat](#mulai-cepat)
- [Tutorial Pascal](#tutorial-pascal)
- [Pintasan Keyboard](#pintasan-keyboard)
- [Kompatibilitas](#kompatibilitas)
- [Status Pengujian](#status-pengujian)
- [Privasi dan Lokasi Data](#privasi-dan-lokasi-data)
- [Dokumentasi](#dokumentasi)
- [Pengembangan](#pengembangan)
- [Riwayat Rilis](#riwayat-rilis)
- [Kontribusi](#kontribusi)
- [Lisensi](#lisensi)
- [Penulis](#penulis)

## Tentang

<img src="assets/odin-logo.png" alt="Logo ODIN Turbo Pascal: Odin bertambal mata, petir, dan buku begin. end." width="200" align="right">

**Odin Turbo Pascal** adalah IDE Pascal yang menghadirkan kembali cara kerja Turbo Pascal (tombol fungsi klasik, beberapa jendela sekaligus, debugger terpadu) dalam antarmuka berjendela modern: menu teks dengan dropdown, toolbar berikon, dan jendela editor, Output, serta Messages yang bisa digeser, diubah ukurannya, di-minimize, dan di-maximize di dalam jendela utama. Kode Anda dikompilasi menjadi **program native untuk macOS, Linux, atau Windows**, tanpa emulator DOS. Setelah terpasang, Odin tidak memerlukan internet dan tidak mengirim telemetri.

Bahasanya **Turbo Pascal 7 secara bawaan, diperluas dengan OOP berbasis `class`** seperti Delphi dan Free Pascal: program TP7 tetap dikompilasi apa adanya, dan siswa bisa melanjutkan ke pewarisan, polimorfisme, dan property tanpa pindah alat.

Compiler-nya adalah **toolchain Odin sendiri**: compiler Pascal, assembler, linker, runtime library, Odin Vision (Turbo Vision milik Odin), dan debugger, semuanya ditulis dari nol, untuk macOS (Intel dan Apple Silicon), Linux (x86_64 dan arm64), dan Windows (x86_64). Odin tidak memerlukan Free Pascal, Xcode, LLDB, atau GCC; satu-satunya dependensi adalah Python dengan Tk untuk IDE-nya. Free Pascal, yang dipakai rilis 1.0.0 dan menjadi backend alternatif sampai 2.3.0, sudah dicabut.

Odin cocok untuk siswa dan mahasiswa yang belajar algoritma dan pemrograman, guru yang mengajar Pascal di kelas, dan siapa saja yang rindu menekan `Ctrl+F9` lalu melihat programnya berjalan.

<div align="center">

<img src="docs/UI_PREVIEW_LINUX.png" alt="Editor Odin Turbo Pascal menampilkan HELLO.PAS dengan menu klasik dan baris tombol fungsi" width="820">

<sub>Tampilan klasik rilis 2.2.0 dengan contoh <code>HELLO.PAS</code>, dari lingkungan uji Linux. Tampilan berjendela 3.0.0 belum punya tangkapan layar.</sub>

</div>

### Mengapa Odin?

- **Nostalgia yang benar-benar bekerja.** Alur kerja Turbo Pascal tetap utuh: `F2` simpan, `F9` make, `Ctrl+F9` jalankan, `Alt+F5` jendela Output, `F5` zoom, `F7`/`F8` menelusuri program baris demi baris.
- **Program native, bukan emulasi.** Hasil kompilasi adalah executable asli untuk CPU dan sistem operasi Anda, dan bisa diekspor untuk dijalankan di luar IDE.
- **Compiler dan debugger milik sendiri.** Di macOS, Linux, dan Windows, Odin mengompilasi dengan toolchain yang ditulis dari nol dan men-debug tanpa LLDB atau GDB, dengan jendela Watches dan Call stack seperti Turbo Pascal.
- **Program interaktif sungguhan.** `ReadLn`, `ReadKey`, warna `Crt`, dan `GotoXY` berjalan di jendela Output 80×25 di dalam IDE. Aplikasi Turbo Vision (Odin Vision) juga berjalan di sana, lengkap dengan mouse.
- **Siap untuk kelas.** Ada tutorial 20 bab, contoh OOP, contoh grafik, dan contoh AI berbahasa Indonesia, referensi Pascal ringkas, dan daftar pesan compiler yang langsung melompat ke baris yang salah.
- **Dari TP7 ke OOP.** Tipe `object` Turbo Pascal tetap ada, dan `class` gaya Delphi/Free Pascal tersedia tanpa mode khusus: `virtual`/`override`/`abstract`, `property`, `is`/`as`, `class of`, dan overload method.
- **Aman untuk berkas Anda.** Penyimpanan atomik, deteksi perubahan dari luar, dan pemulihan sesi otomatis setiap 10 detik.
- **Ringan, terbuka, dan privat.** Source yang mudah dipelajari dan diubah, berlisensi GNU GPL v3, tanpa akun, server, API key, atau telemetri.

<details>
<summary><strong>English summary</strong></summary>

Odin Turbo Pascal is a Turbo Pascal–style IDE for macOS, Linux and Windows, with a modern windowed interface (text menu bar, icon toolbar, movable and resizable editor, Output and Messages windows inside the main window). The language is Turbo Pascal 7 by default, extended with Delphi/Free Pascal–style classes (no mode switch, no new reserved words). Programs compile into native binaries and run in the built-in 80×25 Output window with Crt and Turbo Vision support, including the mouse. Odin's own toolchain, written from scratch in Rust and Pascal (compiler with x86-64 and AArch64 code generators, assembler, Mach-O, ELF and PE linkers, runtime library, Odin Vision, and an integrated Turbo Pascal–style debugger with Watches, Locals and Call stack windows), is the only compiler, on Intel and Apple Silicon Macs, x86_64 and arm64 Linux, and x86_64 Windows; Apple Silicon, Linux and Windows are verified on GitHub Actions runners. Free Pascal, Xcode and LLDB are not needed; the IDE itself needs Python with Tk. The Free Pascal backend of releases up to 2.3.0 has been removed. Messages and documentation are in Indonesian. Licensed under the GNU GPL v3 or later.

</details>

## Fitur

### Antarmuka dan editor

- Menu teks di dalam jendela utama, sama di macOS, Linux, dan Windows: **File · Edit · Search · Run · Compile · Debug · Options · Window · Help**, masing-masing dengan dropdown dan submenu (Examples, Open recent). `Alt`+huruf dan `F10` membuka menu.
- Toolbar berikon dengan tooltip, dan status bar dengan baris/kolom, mode INS/OVR, serta encoding.
- Jendela editor, Output, Messages, Watches, Local variables, dan Call stack di dalam jendela utama: masing-masing punya bilah judul dengan tombol minimize, maximize, dan close, bisa digeser dan diubah ukurannya. Menu **Window**: Tile, Cascade, Arrange icons, Zoom (`F5`), dan daftar jendela.
- Tata letak jendela dan berkas yang terbuka (dengan posisi kursor dan breakpoint) disimpan saat keluar dan dipulihkan saat dibuka lagi.
- Satu dialog **Options** bertab: Compiler, Directories, Editor, Environment.
- Undo/redo, clipboard, find/replace, go to line, hapus baris, indentasi otomatis, serta mode insert/overwrite.
- Nomor baris, breakpoint, dan panah eksekusi di gutter; tema editor **Terang** (bawaan) dan **Gelap**, dengan warna sintaks yang membedakan kata tercadang, variabel, prosedur/fungsi, tipe bawaan, konstanta, angka, string, operator, komentar, dan direktif kompiler.
- Area kerja menampilkan logo Odin dengan tag versi (misalnya `v2.2.0`), kredit penulis, hak cipta, dan lisensi. Tag yang sama tampil di baris status, About, dan halaman bawaan `bab01_01_halo_dunia.pas`.
- Encoding CP437 dan UTF-8 (termasuk BOM), serta akhir baris LF dan CRLF, dipertahankan apa adanya saat menyimpan.

### Kompilasi

- Compiler Odin (`odinpc`): bahasa Turbo Pascal 7 secara bawaan, termasuk tipe `object`, dengan unit standar dan Turbo Vision (lihat [Unit standar](#unit-standar-turbo-pascal)), diperluas dengan OOP berbasis `class` (lihat [OOP dengan class](#oop-dengan-class)). Tidak memerlukan Free Pascal, Xcode, maupun GCC. Menghasilkan program x86_64 dan arm64 untuk CPU Anda (di Windows: x86_64); di Apple Silicon, linker Odin menulis tanda tangan kode ad-hoc yang diwajibkan macOS.
- Compile, Make, dan Build. Tersedia *primary file* untuk proyek yang terdiri dari program dan unit.
- Unit path dan include path, range check, dan overflow check.
- Jendela Messages berisi diagnostik compiler serta perintah dan keluaran `odinpc`: kursor langsung menuju error pertama, klik dua kali untuk melompat ke baris error lain, dan `Alt+F8` untuk pesan berikutnya. Pesan compiler berbahasa Indonesia dengan nomor galat gaya Turbo Pascal 7.
- Hasil build disimpan terpisah di cache. Build yang gagal tidak pernah menjalankan executable lama.
- Ekspor executable native.

### Menjalankan program

- Jendela Output 80×25 di dalam IDE, berbasis pseudo-terminal (ConPTY di Windows): `ReadLn`, `ReadKey`, `KeyPressed`, 16 warna, `GotoXY`, `ClrScr`, dan `Window`.
- Tombol `F1`–`F12`, `Insert`, dan panah diteruskan ke program dengan kode scan Turbo Pascal, termasuk kombinasi Shift, Ctrl, dan Alt (Option di Mac).
- Program Turbo Vision menerima klik, seret, dan roda mouse. Setelah program selesai, isi layar sebelumnya kembali.
- Parameter program (**Run › Parameters**) diteruskan tanpa melewati shell.
- `Ctrl+C` menginterupsi program, `Ctrl+F2` atau tombol Stop di toolbar menghentikannya, dan **Copy screen** (klik kanan) menyalin isi layar.
- Runtime error: baris penyebabnya ditandai merah di editor, dan **Search › Find error** kembali ke baris itu.

### Turbo Vision (Odin Vision)

Odin Vision adalah Turbo Vision milik Odin (macOS, Linux, dan Windows), ditulis ulang dari nol (*clean-room*) mengikuti API Turbo Vision di Turbo Pascal 7:

- Unit `App`, `Drivers`, `Views`, `Menus`, `Dialogs`, `MsgBox`, `StdDlg`, `Memory`, `HistList`, `Validate`, `Editors`, `Outline`, `ColorSel`, dan `TextView`: seluruh unit Turbo Vision TP7.
- Jendela bertumpuk dengan bayangan, menu bar dan menu drop-down, serta status line.
- Dialog dengan tombol, input line (dengan validator dan riwayat), check box, radio button, dan list box, ditambah dialog berkas dan dialog ganti direktori.
- Editor teks, outline, dialog warna (`TColorDialog`), dan terminal teks (`TTerminal`, ditulis lewat `WriteLn` dengan `AssignDevice`).
- Keyboard dan mouse di jendela Output. Perilakunya dijelaskan di [`rtl/vision/SPEC.md`](rtl/vision/SPEC.md).
- Program demo (menu, jendela editor, dialog, MessageBox) ada di repositori source: [`tests/pascal/vision/VISION.PAS`](tests/pascal/vision/VISION.PAS). Buka dengan **File › Open**, lalu tekan `Ctrl+F9`.

### Debugger

Debugger terpadu bergaya Turbo Pascal (macOS, Linux, dan Windows), tanpa LLDB atau GDB:

- **Breakpoint** dari gutter atau `Ctrl+F8`. Breakpoint ikut bergeser saat baris disisipkan, tersimpan bersama pemulihan sesi, dan bisa diubah saat program berjalan.
- **Menelusuri program:** **Trace into** (`F7`), **Step over** (`F8`), **Go to cursor** (`F4`), dan Continue. `Ctrl+C` di jendela Output menghentikan program sementara. Baris yang akan dijalankan berikutnya ditandai hijau.
- **Jendela Watches, Local variables, dan Call stack.** Ketiganya terbuka di kanan area editor dan ikut diatur Tile dan Cascade. Pilih frame di Call stack untuk melihat variabel pemanggil.
- **Evaluate/Modify** (`Ctrl+F7`) untuk ekspresi Pascal: variabel, field, indeks dengan cek batas, `^`, `@`, aritmetika, typecast, `Ord`/`Chr`/`Length`/`High`/`Low`/`SizeOf`. Nilai ditampilkan seperti di Turbo Pascal, misalnya `'abc'`, `(1, 2, 3)`, `(X:1; Y:2)`, `[1, 3..5]`, dan nama enumerasi.

> [!NOTE]
> Rilis 1.0.0 memakai konsol LLDB di User screen. Sejak 2.0.0-alpha.1 debugger terpadu menggantikannya, sejak 2.1.0-alpha.1 debugger ini juga tersedia di Apple Silicon dan Linux, dan sejak 2.2.0 di Windows.

### OTP-AI: unit machine learning

Folder [`otp-AI/`](otp-AI/) berisi pustaka **AI dan machine learning murni Pascal** untuk Odin Turbo Pascal, tanpa dependensi luar. Pustakanya terdiri dari 19 unit yang dikelompokkan menurut fungsi seperti modul Python, sehingga cukup beberapa `uses` untuk satu program:

| Kelompok | Unit |
|---|---|
| Fondasi | `AITYPES`, `AIMATH` (vektor, jarak, matriks), `AISTATS` (statistik dan metrik), `AIDATA` (dataset dan preprocessing), `AISPLIT` (train/test, k-fold) |
| Model | `AILINEAR` (regresi linear, regresi logistik, perceptron), `AIKNN`, `AIKMEANS`, `AINNET`, `AIBAYES`, `AITREE`, `AIRULE`, `AIFUZZY`, `AITEXT` |
| Pelatihan dan pendukung | `AIOPTIM`, `AIREWARD` (Q-learning), `AISEARCH` (A*, BFS, DFS), `AIMODEL` (simpan dan muat model), `AIPLOT` (grafik SVG) |

- 20 program contoh di `otp-AI/EXAMPLES/` (regresi, KNN, K-Means, cross-validation, jaringan saraf, Naive Bayes, pohon keputusan, logika fuzzy, Q-learning, dan lainnya), serta tes `TESTALL` dan `TESTADV`.
- Validasi input dilakukan di setiap unit: parameter tidak valid mengembalikan kode galat tanpa merusak data.
- Buku tutorial berwarna penuh [`otp-AI/PANDUAN_OTP_AI.pdf`](otp-AI/PANDUAN_OTP_AI.pdf) (60 halaman, ditulis Syams Ideris, GPL v3) membahas tiap unit dan contoh: peran unit, tujuan, parameter, hasil yang diharapkan, dan posisinya dalam pembelajaran machine learning.
- Menu **File › Examples - Graph...** membuka daftar 14 contoh unit Graph (garis, bentuk, palet, grafik batang dan pai, grafik fungsi, animasi, sprite, Mandelbrot, jam analog, menggambar dengan panah), yang dijalankan di jendela grafik sungguhan.
- Menu **File › Examples - AI...** membuka daftar 20 contoh OTP-AI beserta topiknya, seperti **File › Examples** untuk tutorial Pascal.
- Cara memakai: 19 unit sudah terpasang di IDE dan langsung dipanggil seperti `Crt`, tanpa pengaturan unit path: tulis `uses AIMATH, AIDATA, AILINEAR;` lalu `Ctrl+F9`. Panduan lengkap ada di [`otp-AI/README.TXT`](otp-AI/README.TXT).

Seluruh contoh dikompilasi dan dijalankan dengan `odinpc` 2.5.0 di macOS x86_64 (`TESTALL` 139 pernyataan uji, `TESTADV` 148). Platform lain belum diuji untuk pustaka ini.

### Metrik: Ukur dan Periksa

Bahan analisis dan penilaian kode, misalnya untuk lomba pemrograman (backend Odin; lihat **Help › Metrik: Ukur dan Periksa**):

- **Run › Ukur** (`Shift+F9`) membangun program dengan build juri (`odinpc build --count-steps --range-checks --overflow-checks`), menjalankannya di jendela Output, lalu membuka jendela **Metrik**: jumlah langkah, puncak heap, memori global, dan kedalaman panggilan. Angka-angka ini sama di macOS, Linux, dan Windows, x86-64 maupun arm64, karena yang dihitung adalah langkah, bukan waktu.
- **Peta langkah** menunjukkan baris mana yang paling banyak dijalankan. **Catatan struktur** dari `odinpc metrics` (variabel tidak dipakai, nesting dalam, kompleksitas tinggi, angka ajaib, `goto`, efek samping global) bisa diklik ke barisnya.
- **Run › Periksa...** menjalankan program dengan setiap kasus dalam paket soal (`aturan.json`, `kasus/*.in`/`.out`). Hasilnya: vonis per kasus (benar, salah, melewati batas langkah atau memori, runtime error), skor subtask gaya OSN/IOI, dan pemeriksaan syarat soal.
- Laporan bisa disimpan sebagai JSON `otp-metrics/1` (`odin/metrics.py`, hanya pustaka standar Python). Kontrak build hitung langkah ada di [`rtl/COMPILER_INTERFACE.md`](rtl/COMPILER_INTERFACE.md) §8.

### Berkas dan sesi

- Contoh bawaan diperlakukan sebagai template: **Save** otomatis menjadi **Save as**, sehingga contoh asli tidak tertimpa.
- Daftar berkas terakhir, pengaturan yang tersimpan, dan hanya satu instance aplikasi yang berjalan.

## Platform yang Didukung

| Platform | Compiler Odin | Debugger terpadu | Cara memasang | Diverifikasi di |
|---|:---:|:---:|---|---|
| macOS Intel (x86_64) | ✅ | ✅ | [`Install.command`](#macos) | Mac pengembang dan runner CI |
| macOS Apple Silicon (arm64) | ✅ | ✅ | [`Install.command`](#macos), bundel berisi `odinpc` universal | Runner GitHub Actions macOS 15 arm64 |
| Linux x86_64 | ✅ | ✅ | [Dari source](#linux) | VM Ubuntu 24.04 dan runner CI |
| Linux arm64 | ✅ | ✅ | [Dari source](#linux) | qemu-user dan runner CI Ubuntu arm64 |
| Windows 10 1809+ (x86_64) | ✅ | ✅ | [`Install.cmd`](#windows), paket berisi `toolchain/odinpc.exe` | Runner GitHub Actions Windows Server 2025 |
| Windows on ARM, Linux musl (Alpine) | ❌ | ❌ | — | — |

## Persyaratan Sistem

| Komponen | Kebutuhan |
|---|---|
| macOS | 11 Big Sur atau lebih baru, Intel (x86_64) atau Apple Silicon (arm64) |
| Linux | x86_64 atau arm64 dengan glibc 2.34 atau lebih baru (Ubuntu 22.04+, Debian 12+, Fedora 35+). musl (Alpine) tidak didukung |
| Windows | Windows 10 versi 1809 atau lebih baru, 64-bit (x86_64). Jendela Output memakai ConPTY. Windows on ARM belum didukung |
| Python | 3.10+ dengan Tk ([python.org universal2](https://www.python.org/downloads/macos/) atau Homebrew `python-tk@3.13` di macOS; paket `python3-tk` di Linux; [python.org](https://www.python.org/downloads/windows/) dengan pilihan tcl/tk di Windows) |
| Compiler | Sudah disertakan (`odinpc`). Free Pascal, Xcode Command Line Tools, LLDB, dan GCC tidak diperlukan |
| Rust | 1.85+ ([rustup.rs](https://rustup.rs)), hanya untuk membangun toolchain Odin dari source |

Pemasang macOS dapat memasang Python dengan Tk melalui Homebrew, dan pemasang Windows melalui winget. Di Linux, Odin dijalankan dari source.

## Instalasi

### macOS

**Pemasang satu berkas (offline).** Unduh `OdinTurboPascal-VERSI-macos-x86_64.pkg` (Mac Intel) dari halaman Releases, lalu buka. Paket memasang aplikasi di `~/Applications` tanpa kata sandi administrator dan membawa Python dengan Tk sendiri, jadi tidak ada yang diunduh dan tidak perlu Homebrew atau Xcode. Paket belum ditandatangani Apple: bila macOS menahannya, klik kanan paketnya, pilih **Open**, atau gunakan **System Settings › Privacy & Security › Open Anyway**. Dibangun oleh `python3 scripts/build_setup_mac.py` dan oleh CI. Diuji di Mac Intel pengembang (pasang, pemeriksaan kompilasi dengan jaringan diblokir, buka lewat LaunchServices); versi `arm64` hanya dibangun di CI, dan Mac bersih tanpa Python belum diuji.

**Dari repositori (`Install.command`).** Pemasang ini memasang **rilis 3.0.0-beta.1**: IDE, toolchain Odin universal untuk Mac Intel dan Apple Silicon, dan runtime library-nya. Satu-satunya dependensi adalah Python dengan Tk.

1. **Unduh** repositori ini (**Code › Download ZIP**), lalu ekstrak seluruhnya. Jangan menjalankan pemasang dari pratinjau ZIP.
2. **Buka `Install.command`.** Pemasang berjalan di Terminal dan akan:
   - mendeteksi chip Intel atau Apple Silicon;
   - memeriksa Python dengan Tk, lalu menawarkan Homebrew atau tautan unduhan resmi bila belum terpasang;
   - **mengompilasi dan menjalankan program uji kecil** dengan `odinpc` dari bundel untuk memastikan hasilnya cocok dengan CPU Mac Anda. Bila pemeriksaan ini gagal, pemasangan berhenti dengan pesan kesalahan;
   - memasang aplikasi di `~/Applications` dan mencadangkan versi sebelumnya bila ada.
3. **Jalankan** `~/Applications/Odin Turbo Pascal.app`.

> [!WARNING]
> Bundel ini belum ditandatangani maupun dinotarisasi Apple. Bila macOS menahan pembukaannya, buka **System Settings › Privacy & Security › Open Anyway**. Jangan menonaktifkan Gatekeeper secara global.

> [!TIP]
> Bila atribut executable hilang saat ZIP diekstrak, jalankan pemasang lewat Terminal: `/bin/bash "/lokasi/paket/Install.command"`

### Windows

Pemasang Windows memasang IDE beserta `odinpc.exe` dan runtime library-nya di `%LOCALAPPDATA%\Programs\OdinTurboPascal`, tanpa hak administrator.

**Setup satu berkas (offline).** Pilihan termudah: unduh `OdinTurboPascal-VERSI-Setup-x64.exe` dari halaman Releases, lalu klik dua kali. Berkas ini membawa Python dengan Tk khusus untuk Odin, jadi tidak ada yang diunduh saat memasang dan tidak ada Python lain yang perlu dipasang. Pemasangan senyap untuk banyak PC: `Setup.exe /VERYSILENT /SUPPRESSMSGBOXES`. Hapus lewat **Settings › Apps**. Setup belum ditandatangani kode, sehingga Windows SmartScreen dapat menampilkan peringatan (**More info › Run anyway**). Setup dibangun oleh `python scripts/build_setup_windows.py` (Windows, Inno Setup 6.3+) dan oleh job Windows di CI.

**Dari repositori (`Install.cmd`).** Jalur ini memerlukan Python dengan Tk yang sudah terpasang atau internet untuk memasangnya:

1. **Unduh** repositori ini (**Code › Download ZIP**), lalu ekstrak seluruhnya.
2. **Klik dua kali `Install.cmd`.** Pemasang berjalan di jendela PowerShell dan akan:
   - memeriksa Windows 10 1809 atau lebih baru, 64-bit;
   - mencari Python dengan Tk, lalu menawarkan winget atau tautan unduhan resmi bila belum terpasang;
   - **mengompilasi dan menjalankan program uji kecil** dengan `odinpc.exe`;
   - memasang aplikasi, mencadangkan versi sebelumnya bila ada, dan membuat pintasan di menu Start dan Desktop.
3. **Jalankan** Odin Turbo Pascal dari menu Start.

> [!NOTE]
> Di runner GitHub Actions, pemeriksaan kompilasi dan penyalinan aplikasi oleh pemasang diuji pada setiap commit, dan setup Inno dipasang serta dihapus secara senyap. Pemasang lengkap (`Install.cmd` dengan winget, setup Inno dengan wizard, pintasan, SmartScreen) belum dijalankan di PC Windows sungguhan.

### Linux

**Pemasang satu berkas (offline).** Unduh `OdinTurboPascal-VERSI-linux-x86_64.run` (atau `-aarch64.run`) dari halaman Releases, lalu jalankan `sh OdinTurboPascal-VERSI-linux-x86_64.run`. Berkas ini membawa IDE, `odinpc`, dan Python dengan Tk sendiri, jadi tidak ada yang diunduh dan tidak perlu hak root: pemasangan masuk ke `~/.local/share/OdinTurboPascal-app` (`--prefix DIR` untuk folder lain), dengan perintah `odin-turbo-pascal` di `~/.local/bin` dan entri menu aplikasi. Dari sistem hanya dibutuhkan pustaka X11 (ada di setiap desktop Linux). Hapus dengan `sh BERKAS.run --uninstall`; program Pascal dan pengaturan tetap tersimpan. Pemasang dibangun oleh `python3 scripts/build_setup_linux.py` setelah `cargo build --release`, dan oleh CI.

> Pemasang ini diuji di VM Ubuntu 24.04 x86_64 dengan jaringan diputus, dan versi arm64 hanya dibangun di CI. Distro lain, glibc 2.34 (build dibuat di glibc 2.39, simbol baru hanya referensi lemah), dan desktop sungguhan belum diuji.

**Dari source.** Contoh untuk Ubuntu atau Debian:

```bash
sudo apt install python3-tk git          # IDE (Python + Tk)
curl https://sh.rustup.rs -sSf | sh      # Rust, sekali saja, untuk membangun odinpc
git clone https://github.com/Syamsuddin/ODIN-TURBO-PASCAL.git
cd ODIN-TURBO-PASCAL/toolchain
cargo build --release                    # membangun odinpc; tanpa crate pihak ketiga
cd ..
python3 main.py                          # IDE menemukan toolchain/target/release/odinpc
```

Compiler, debugger, dan Odin Vision langsung tersedia. Free Pascal tidak diperlukan.

### Dari source (macOS dan Windows)

Dengan Python (Tk) dan Rust:

```bash
cd toolchain && cargo build --release && cd ..
python3 main.py                          # di Windows: python main.py
```

Untuk bundel `.app` yang berjalan di Intel maupun Apple Silicon, bangun `odinpc` universal dengan `python3 scripts/build_toolchain.py` sebelum `python3 scripts/package_app.py`.

### Menghapus aplikasi

| Sistem | Cara | Yang tetap tersimpan |
|---|---|---|
| macOS | Jalankan `Uninstall.command`; aplikasi dipindahkan ke Trash | Program Pascal dan folder pengaturan |
| Windows | Settings › Apps (setup Inno), atau `Uninstall.cmd` (pemasangan `Install.cmd`) | Program Pascal dan `%APPDATA%\OdinTurboPascal` |
| Linux | Hapus folder hasil `git clone` | Program Pascal dan `~/.local/share/OdinTurboPascal/` |

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
3. Tekan `Ctrl+F9` untuk mengompilasi dan menjalankan (di Mac juga bisa `Command+R`). Program tampil di jendela **Output**; `F5` memaksimalkannya, dan `Alt+F5` berpindah antara Output dan editor.
4. Tekan `F8` untuk menjalankan program baris demi baris. Sorot `Nama`, lalu tekan `Ctrl+F7` untuk melihat isinya.
5. Buka **File › Examples** untuk belajar Pascal dari awal lewat [tutorial](#tutorial-pascal) 20 bab, lalu **File › Examples - OOP** untuk pemrograman berorientasi objek dengan `class`.

## Tutorial Pascal

**File › Examples** berisi tutorial Pascal untuk pemula: 90 berkas dalam 20 bab, yaitu 89 program dan satu unit. Setiap kode penting diberi komentar penjelasan singkat dalam bahasa Indonesia. Tes otomatis menjalankan setiap program dan memeriksa keluarannya.

| Bagian | Bab |
|---|---|
| 1. Fondasi | 1 Pengenalan pemrograman dan Pascal · 2 Struktur program · 3 Tipe data, variabel, dan konstanta · 4 Input dan output · 5 Operator dan ekspresi |
| 2. Alur kendali | 6 Percabangan · 7 Perulangan · 8 Latihan logika |
| 3. Modularisasi | 9 Prosedur dan fungsi · 10 Rekursi |
| 4. Struktur data | 11 Array · 12 String lanjutan · 13 Record · 14 Tipe bentukan |
| 5. Algoritma dasar | 15 Pencarian · 16 Pengurutan |
| 6. Lanjutan ringan | 17 File · 18 Pointer dan alokasi dinamis · 19 Unit dan modul · 20 Proyek akhir |

- Nama berkas mengikuti pola `babNN_MM_topik.pas`, misalnya `bab06_04_case_of.pas`, sehingga berkas urut sendiri di folder. Nama `program` di dalamnya sama dengan nama berkas.
- Unit Bab 19 bernama `matematika.pas` tanpa awalan bab, karena nama berkas unit harus sama dengan nama di baris `unit matematika;`.
- Program Bab 17 dan proyek Bab 20 membuat berkas data (`catatan.txt`, `angka.dat`, `siswa.dat`, `struk.txt`, `rekap_nilai.txt`, `kontak.dat`). Nama berkasnya ditulis sebagai konstanta di awal program, dan program menampilkan folder tempat berkas itu dibuat, yaitu folder berkas `.pas`-nya.
- Contoh bawaan adalah templat: **Save** selalu menjadi **Save As**. Simpan salinannya ke folder sendiri sebelum mengubah atau menjalankan program yang membuat berkas data, supaya berkas itu tidak tersimpan di dalam folder aplikasi. Untuk Bab 19, salin juga `matematika.pas` ke folder yang sama.

**File › Examples - OOP** melanjutkan tutorial dengan sembilan program berorientasi objek di [`examples-oop/`](examples-oop/): class pertama, constructor dan destructor, enkapsulasi dan property, pewarisan, polimorfisme (`virtual`, `override`, `abstract`), class var dan `class of`, daftar objek dengan `is`/`as`, overload, dan proyek kasir toko. Tes otomatis juga menjalankan dan memeriksa keluarannya. Buku tutorial PDF membahas kesembilan program ini di Bab 21 dan keempat belas contoh **File › Examples - Graph** di Bab 22.

## Pintasan Keyboard

| Tombol | Fungsi | Tombol | Fungsi |
|---|---|---|---|
| `F1` | Help | `Ctrl+F9` | Compile dan run; lanjut di debugger |
| `F2` | Save | `Alt+F9` / `F9` | Compile / Make |
| `F3` | Open | `Ctrl+F2` | Hentikan program atau debugger |
| `F4` | Go to cursor (debugger) | `Alt+F5` | Jendela Output |
| `F5` | Zoom jendela | `Ctrl+F8` | Toggle breakpoint |
| `F6` | Jendela berikutnya | `Ctrl+F7` | Evaluate/Modify (debugger) |
| `F7` / `F8` | Trace into / Step over | `Alt+F8` | Diagnostik berikutnya |
| `F10` | Menu File | `Alt+X` | Keluar |

Alternatif Mac: `Command+N/O/S` (New/Open/Save), `Command+B` (Compile), `Command+R` (Run), `Command+F` (Find), `Command+W` (Close), `Command+Q` (Quit). Pada Mac laptop, tekan `Fn` bersama `F1`–`F12`. Daftar lengkap ada di [`docs/SHORTCUTS.txt`](docs/SHORTCUTS.txt).

## Kompatibilitas

### OOP dengan class

Bahasa bawaannya Turbo Pascal 7. Di atasnya, `odinpc` memahami OOP berbasis `class` seperti Delphi dan Free Pascal, tanpa direktif atau mode dan tanpa kata tercadang baru (program TP7 yang memakai `class`, `property`, `is`, atau `as` sebagai nama tetap dikompilasi):

```pascal
type
  THewan = class
  private
    FNama: String;
  public
    constructor Create(const ANama: String);
    function Suara: String; virtual; abstract;
    property Nama: String read FNama;
  end;
  TKucing = class(THewan)
    function Suara: String; override;
  end;
```

- Didukung: `class(Induk)` dengan akar `TObject`, deklarasi forward, `private`/`protected`/`public`/`published` (dan `strict`), constructor dan destructor, `virtual`/`override`/`abstract`/`reintroduce`, `inherited` dengan atau tanpa nama, `property` (termasuk property larik dan `default`), `class var`, class method (juga virtual), `class of` dengan constructor virtual, overload method, `is`/`as`, dan `with` pada objek.
- Unit `Classes` (`TList`, `TStringList`) dan `Contnrs` (`TObjectList`) ditulis dengan class.
- Belum termasuk: exception, interface, generic, `procedure of object`, dan `Result`. Tanpa exception, salah pakai menjadi runtime error (211 method abstract, 219 `as` gagal, 216 rujukan `nil`).
- Debugger menampilkan isi field objek, dan `Obj.Field` bisa dievaluasi.
- Diuji di Mac Intel dan di runner GitHub Actions untuk macOS Intel, macOS Apple Silicon, Linux x86_64, Linux arm64, dan Windows. Perangkat fisik Apple Silicon dan Windows belum diuji langsung. Rinciannya ada di [`docs/COMPATIBILITY.txt`](docs/COMPATIBILITY.txt) dan [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) (Tahap 10).

### Unit standar Turbo Pascal

Diuji dengan korpus tes di Mac Intel, di VM Ubuntu 24.04 (x86_64, dan aarch64 lewat qemu), dan di runner GitHub Actions untuk macOS Apple Silicon, Linux x86_64, Linux arm64, dan Windows x86_64. Sampai 2.3.0, ekspektasi korpus dibuat dengan Free Pascal 3.2.2 sebagai pembanding.

| Unit | Status |
|---|---|
| `System` | ✅ String, matematika, `Str`/`Val`, berkas teks, bertipe, dan tanpa tipe, direktori, `ParamStr`, heap, `ExitProc`, runtime error |
| `Crt` | ✅ `ClrScr`, `GotoXY`, `WhereX`/`WhereY`, warna, `Window`, `ClrEol`, `InsLine`/`DelLine`, `Delay`, `KeyPressed`, `ReadKey`. Layarnya dibandingkan sel demi sel dengan snapshot yang dulu dicocokkan dengan `Crt` milik FPC |
| `Dos` | ✅ `GetDate`/`GetTime`, `GetEnv`, `FSplit`/`FExpand`/`FSearch`, `FindFirst`/`FindNext`, atribut dan waktu berkas, `DiskFree`, `Exec`/`DosExitCode` |
| `Strings` | ✅ Rutin `PChar` |
| `Printer` | ✅ `Lst` diteruskan ke `lpr` (di Windows: `notepad /p`). Pencetakan sungguhan belum diuji |
| `Objects` | ✅ `TCollection`, `TSortedCollection`, `TStringCollection`, stream berkas/ber-buffer/memori, `RegisterType`, `Put`/`Get` |
| Turbo Vision | ✅ Odin Vision (`rtl/vision/`): `App`, `Drivers`, `Views`, `Menus`, `Dialogs`, `MsgBox`, `StdDlg`, `Memory`, `HistList`, `Validate`, `Editors`, `Outline`, `ColorSel`, `TextView`. Diuji dengan snapshot layar (karakter dan warna). Warna palet dirancang sendiri |
| `WinDos` | ✅ `Dos` dengan `PChar` (`FindFirst`, `FileSplit`, `GetCurDir`, `GetEnvVar`, ...), diteruskan ke `Dos`. Tanpa `Intr`/`MsDos`/`TRegisters` |
| `Graph` | ✅ Antarmuka BGI TP7 lengkap (garis, lingkaran, busur, isian, `FloodFill`, teks, `GetImage`/`PutImage`, palet, halaman, semua mode driver). Gambar disimpan di memori per piksel dan diuji piksel demi piksel; di IDE tampil di jendela grafik dengan piksel sebenarnya, di terminal biasa hanya pratinjau kasar dengan karakter setengah blok. Tanpa berkas `.BGI`/`.CHR` (font stroke diganti font bitmap 8 x 8) |
| `Overlay` | ✅ Antarmuka saja: `OvrInit` selalu berhasil karena seluruh kode ada di memori |
| `Math`, `SysUtils` | ✅ Tambahan Odin (bukan unit TP7): subset unit Free Pascal/Delphi tanpa exception, `Format`, parameter bawaan, dan overload rutin biasa |
| `Classes`, `Contnrs` | ✅ Tambahan Odin (bukan unit TP7), ditulis dengan class: `TList`, `TStringList`, `TObjectList`. Diuji di Mac Intel dan runner CI kelima platform |
| `Graph3`, `Turbo3` | ❌ |

Rincian dan perbedaan perilaku ada di [`docs/COMPATIBILITY.txt`](docs/COMPATIBILITY.txt) dan [`tests/pascal/DEVIATIONS.md`](tests/pascal/DEVIATIONS.md).

### Batasan

- Odin adalah **implementasi baru** yang mengikuti antarmuka dan alur Turbo Pascal klasik. Odin bukan salinan Borland dan tidak menyertakan binary, logo, font, maupun berkas bantuan Borland.
- Hasil kompilasi berupa program 64-bit untuk macOS, Linux, atau Windows, bukan EXE DOS 16-bit. Kode `Mem`/`Port`, interrupt DOS, assembler 16-bit, dan pointer berbasis segmen perlu di-porting.
- `Real` berukuran 8 byte (TP: 6 byte), dan `Real48` tidak tersedia; berkas biner lama perlu dikonversi. `Round` membulatkan ke bilangan genap untuk nilai `.5`.
- Compiler Odin:
  - menghasilkan program untuk macOS dan Linux (x86_64 dan arm64) serta Windows (x86_64); di sistem lain IDE bisa mengedit tetapi tidak mengompilasi;
  - mengikuti bahasa Turbo Pascal 7 secara bawaan, termasuk tipe `object`, dan diperluas dengan `class` (lihat [OOP dengan class](#oop-dengan-class)); mode ObjFPC/Delphi dari backend Free Pascal lama tidak ada lagi sebagai mode, exception dan interface belum didukung, begitu pula blok `asm`;
  - mendukung unit `Objects` dan seluruh Turbo Vision lewat Odin Vision. Record data dialog harus `packed record`;
  - `Extended` sama dengan `Double`, dan fungsi seperti `Exp` dan `Sin` dihitung dalam `Double`.
- Rilis 1.0.0 memakai konsol LLDB; sejak 2.0.0-alpha.1 debugger terpadu menggantikannya.
- Jendela Output tidak menyediakan scrollback maupun true color. Mouse diteruskan ke program yang memintanya. Option sebagai Alt di keyboard Mac sungguhan belum diuji.

## Status Pengujian

| Lingkungan | Hasil |
|---|---|
| Mac Intel (macOS 15.7), Python 3.13, Tk 9.1, Rust 1.99 (pra-rilis 3.0.0-beta.1) | 160 tes Python lulus (10 dilewati), termasuk 38 tes antarmuka berjendela, dan seluruh tes Rust (191) termasuk korpus. Pemeriksaan pemasang `.pkg` lulus; pemasangan di Mac bersih, Apple Silicon, Linux, dan Windows belum diuji untuk tampilan ini |
| Mac Intel (macOS 15.7), Python 3.13, Tk 9.1, Rust 1.99 (rilis 2.9.0) | 147 tes Python lulus (10 dilewati) dan seluruh tes Rust (191), termasuk korpus 97 program (11 di antaranya class) dalam tiga mode build, galat semantik class, debugger dengan objek class, dan kesembilan contoh OOP. Korpus juga lulus di VM Ubuntu 24.04 (x86_64, dan aarch64 lewat qemu) |
| GitHub Actions: macOS 15 Intel dan Apple Silicon, Ubuntu 24.04 x86_64 dan arm64, Windows Server 2025 (rilis 2.9.0) | Tes Rust (termasuk korpus) dan tes Python lulus di kelima runner; di Windows juga pemeriksaan pemasang dan setup Inno Setup. Perangkat fisik Apple Silicon dan Windows belum diuji |
| Mac Intel (macOS 15.7), Python 3.13, Tk 9.1, Rust 1.99 (rilis 2.8.0) | 144 tes Python lulus (10 dilewati), termasuk tes jendela grafik dengan piksel sebenarnya, tes soket Graph, tampilan Graph lewat PTY, dan seluruh tes Rust (korpus diferensial dalam tiga mode build). Korpus Math, SysUtils, WinDos, dan Overlay serta keenam program Graph juga lulus di VM Ubuntu 24.04 (x86_64, dan aarch64 lewat qemu) dengan keluaran sama. Hasil CI rilis ini dicatat di halaman Releases |
| Mac Intel (macOS 15.7), Python 3.13, Tk 9.1, FPC 3.2.2, Rust 1.99 (rilis 2.4.0) | 119 tes Python lulus (6 dilewati), termasuk tes GUI dengan jendela Tk sungguhan, sesi debugger nyata, snapshot Odin Vision, dan **Run › Ukur**/**Periksa...**. 189 tes Rust juga lulus. Korpus diferensial 77 program (termasuk tipe `object` dan unit `Objects`) memberi keluaran dan kode keluar yang sama dengan FPC 3.2.2, dengan build biasa, build debug, dan build hitung langkah |
| GitHub Actions: macOS 15 Apple Silicon, Ubuntu 24.04 x86_64 dan arm64, macOS 15 Intel (rilis 2.4.0) | Korpus diferensial berjalan native dan lulus; laporan langkah `tests/steps/` sama di semua target; tes Python dengan backend Odin (GUI, debugger, Odin Vision) lulus. Lihat [CI](https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/actions/workflows/ci.yml) |
| GitHub Actions: Windows Server 2025 x86_64, Python 3.12, FPC 3.2.2 i386-win32 (rilis 2.4.0) | Korpus diferensial 77 program (biasa, debug, dan hitung langkah) identik dengan FPC untuk Windows; laporan langkah sama dengan target lain; 119 tes Python lulus (2 tes khusus Unix dilewati), termasuk GUI, debugger, dan Odin Vision di ConPTY; pemeriksaan kompilasi dan penyalinan pemasang lulus |
| VM Ubuntu 24.04 (Lima di Mac Intel) (rilis 2.4.0) | Laporan langkah `tests/steps/` sama dengan Mac Intel untuk x86_64 dan untuk aarch64 lewat qemu-user |
| VM Ubuntu 24.04 (Lima di Mac Intel), Python 3.12, Tk 8.6 (rilis 2.1.0-alpha.1) | Korpus diferensial lulus untuk x86_64 dan untuk aarch64 lewat qemu-user; 92 tes Python dengan backend Odin lulus di x86_64 |
| Linux x86_64, Python 3.12, Tk 9.0, FPC 3.2.2, Xvfb (rilis 1.0.0) | Seluruh suite saat itu lulus. Lihat [`docs/TEST_REPORT.txt`](docs/TEST_REPORT.txt) |

> [!CAUTION]
> **Belum diverifikasi langsung:** Mac Apple Silicon, PC Linux, dan PC Windows fisik (hanya runner CI dan VM); pemasangan lewat `Install.command` di Apple Silicon; `Install.cmd` lengkap (winget, pintasan, menu Start); Windows on ARM; peluncuran lewat Finder/LaunchServices; Gatekeeper; Mac bersih tanpa Free Pascal maupun Xcode Command Line Tools; LLDB di paket rilis 1.0.0; dan pencetakan lewat `Printer`.

## Privasi dan Lokasi Data

Odin tidak memakai akun, server, API key, maupun telemetri. Internet hanya diperlukan untuk memasang dependensi yang belum ada.

| Lokasi | Isi |
|---|---|
| Folder pilihan Anda | Source Pascal, melalui **Save as** |
| `~/Library/Application Support/OdinTurboPascal/` (macOS)<br>`~/.local/share/OdinTurboPascal/` (Linux)<br>`%APPDATA%\OdinTurboPascal\` (Windows) | `settings.json`, cache build (termasuk info debug `.odbg`), `recovery.json`, `runtime-error.txt`, `last-error.log`, `launch.log` |

Program dijalankan dengan working directory di folder source program utama. `Uninstall.command` dan `Uninstall.cmd` tidak menghapus program pribadi maupun folder pengaturan.

## Buku

**Help › Buku** membuka buku tutorial *Belajar Pemrograman Bahasa Pascal dengan ODIN Turbo Pascal* ([`docs/Belajar_Pemrograman_Bahasa_Pascal.pdf`](docs/Belajar_Pemrograman_Bahasa_Pascal.pdf)) di aplikasi PDF bawaan sistem. Buku berwarna penuh ini ditulis oleh Syams Ideris dan mengikuti tutorial di **File › Examples**, lalu contoh **File › Examples - OOP** (Bab 21), **File › Examples - Graph** (Bab 22), dan **File › Examples - AI** (Bab 23–24): kata pengantar, daftar isi, 24 bab dalam delapan bagian, penutup, dan enam lampiran (pemasangan, pintasan keyboard, kata tercadang, arti pesan kesalahan, daftar program, glosarium). Setiap bab dilengkapi infografik, gambar layar IDE, rangkuman, dan latihan bertingkat.

Semua listing di buku dicetak langsung dari `examples/`, dan semua keluaran program adalah hasil mengompilasi lalu menjalankan program itu dengan `odinpc`. Gambar layar IDE digambar dari menu, warna editor, dan kode aslinya. PDF dibangun ulang dengan `python3 scripts/build_book.py` (perlu Google Chrome dan PyMuPDF; sumbernya di `book/`).

## Dokumentasi

| Dokumen | Isi |
|---|---|
| [`docs/Belajar_Pemrograman_Bahasa_Pascal.pdf`](docs/Belajar_Pemrograman_Bahasa_Pascal.pdf) | Buku tutorial Pascal berwarna penuh (menu **Help › Buku**) |
| [`otp-AI/PANDUAN_OTP_AI.pdf`](otp-AI/PANDUAN_OTP_AI.pdf) | Buku panduan unit AI/machine learning OTP-AI |
| [`docs/HELP.txt`](docs/HELP.txt) | Panduan penggunaan IDE (juga di menu **Help**) |
| [`docs/PASCAL.txt`](docs/PASCAL.txt) | Referensi Pascal ringkas |
| [`docs/SHORTCUTS.txt`](docs/SHORTCUTS.txt) | Daftar lengkap pintasan keyboard |
| [`docs/COMPATIBILITY.txt`](docs/COMPATIBILITY.txt) | Kompatibilitas, cakupan versi, dan perbedaan dari Turbo Pascal |
| [`README.txt`](README.txt) | Panduan teks yang ikut terpasang |
| [`CHANGELOG.md`](CHANGELOG.md) | Riwayat perubahan per rilis |
| [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) | Rencana dan status toolchain Odin per tahap |
| [`rtl/COMPILER_INTERFACE.md`](rtl/COMPILER_INTERFACE.md) | Kontrak compiler, runtime library, dan debugger |
| [`rtl/vision/SPEC.md`](rtl/vision/SPEC.md) | Spesifikasi perilaku Odin Vision |

## Pengembangan

IDE-nya aplikasi Python/Tk tanpa dependensi pip. Toolchain Odin ditulis dalam Rust tanpa crate pihak ketiga, dan runtime library-nya dalam Pascal.

### Build dan tes

Semua perintah dijalankan dari root repositori, dengan Python yang mendukung Tk:

```bash
python3 main.py                                     # jalankan IDE dari source (di Windows: python main.py)
python3 -m unittest discover -s tests -v            # seluruh tes Python
python3 -m unittest tests.test_debugger -v          # sesi debugger tanpa Tk
python3 -m unittest tests.test_vision -v            # snapshot layar Odin Vision
ODIN_UPDATE_SNAPSHOTS=1 python3 -m unittest tests.test_vision   # tulis ulang snapshot (tinjau dulu)
(cd toolchain && cargo build --release)             # bangun odinpc
(cd toolchain && cargo test --workspace)            # tes Rust, termasuk korpus diferensial
ODIN_CORPUS_TARGET=aarch64-linux ODIN_CORPUS_RUNNER="qemu-aarch64-static -L /usr/aarch64-linux-gnu" \
  cargo test -p odinpc --test corpus                # korpus untuk target lain (lihat tests/corpus.rs)
python3 scripts/bless_corpus.py NAMA                # ekspektasi korpus untuk program baru (tinjau dulu)
ODIN_BLESS=1 python3 -m unittest tests.test_core.CompilerTests.test_crt_screen_matches_snapshot   # snapshot layar Crt
python3 scripts/check_mac.py                        # gerbang pemasang macOS: odinpc compile + run native
python3 scripts/build_book.py                       # bangun ulang buku PDF (Chrome + PyMuPDF; di luar sandbox, perlu PTY)
```

Catatan tes:

- Tes compiler dilewati bila `odinpc` belum dibangun atau sistemnya belum didukung (`core.ODIN_HOSTS`). Tidak ada tes yang memerlukan Free Pascal.
- Tes GUI dilewati bila tidak ada display. Tes yang membuka pseudo-terminal memerlukan izin membuat PTY.
- GitHub Actions menjalankan semuanya di macOS Intel, macOS Apple Silicon, Linux x86_64, Linux arm64, dan Windows ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)). Job Windows juga mengunggah `odinpc.exe` sebagai artefak.

### Rilis

```bash
python3 scripts/set_version.py X.Y.Z                # naikkan nomor versi di semua berkas dan CHANGELOG
python3 scripts/build_toolchain.py                  # odinpc universal (x86_64 + arm64) untuk bundel macOS
python3 scripts/package_app.py                      # bentuk ulang bundel .app, termasuk tag versi di halaman bawaan
rm toolchain/odinpc.exe; gh run download <run> -n odinpc-windows-x86_64 -D toolchain   # odinpc.exe dari CI Windows
python3 scripts/update_checksums.py                 # buat ulang SHA256SUMS.json (terakhir)
python3 scripts/render_logo.py                      # bila logo berubah: render logo, ikon, dan banner (butuh Pillow)
```

### Struktur proyek

```text
ODIN-TURBO-PASCAL/
├── main.py                  Titik masuk aplikasi
├── odin/
│   ├── app.py               Antarmuka Tk: menu bar, toolbar, area kerja, dialog, sesi debug
│   ├── windows.py           Jendela child: editor, Output, Messages, Watches, Locals, Call stack
│   ├── icons.py             Ikon toolbar yang digambar dari bentuk sederhana (PNG, tanpa Tk)
│   ├── core.py              Dokumen, pengaturan, build dengan odinpc, diagnostik
│   ├── debugger.py          Sesi debug: odinpc debug di jendela Output, perintah JSON
│   ├── console.py           Emulator VT100 80×25 dan proses pseudo-terminal (tanpa Tk)
│   ├── terminal.py          Widget Tk untuk konsol jendela Output
│   └── conpty.py            Konsol Output di Windows (ConPTY lewat ctypes)
├── toolchain/               odinpc (Rust): lexer, parser, sema, codegen x86-64 dan AArch64,
│                            assembler, linker Mach-O/ELF/PE, info debug, debugger;
│                            odinpc.exe untuk paket Windows
├── rtl/                     Runtime library (Pascal): System, Crt, Dos, Strings, Printer, Objects,
│                            Classes, Contnrs, Math, SysUtils, Graph, ...
│   └── vision/              Odin Vision: semua unit Turbo Vision TP7 dan spesifikasinya (SPEC.md)
├── examples/                Tutorial Pascal pemula: 89 program dan satu unit dalam 20 bab
├── examples-graph/          Contoh unit Graph (File › Examples - Graph)
├── examples-oop/            Contoh OOP dengan class (File › Examples - OOP)
├── otp-AI/                  Pustaka AI/machine learning Pascal: 19 unit, 20 contoh, tes, buku PDF
├── docs/                    Panduan, referensi Pascal, pintasan, kompatibilitas
├── tests/                   Tes Python (fungsional, compiler, debugger, GUI, Odin Vision) dan
│   └── pascal/              korpus Pascal dengan ekspektasi tersimpan serta snapshot Crt dan Odin Vision
├── book/                    Sumber buku tutorial (HTML per bab dan buku.css); dibangun scripts/build_book.py
├── scripts/                 Launcher, pemeriksaan pemasang, ekspektasi korpus, bundel .app, versi, logo, buku
├── assets/                  Logo, ikon, dan banner (master PNG serta PNG/ICNS hasil render)
├── .github/workflows/       CI lima platform
├── Odin Turbo Pascal.app    Bundel macOS (dibentuk dari source)
├── Install.command · Uninstall.command          Pemasang macOS
├── Install.cmd · Install.ps1 · Uninstall.cmd   Pemasang Windows
└── CHANGELOG.md · IMPLEMENTATION_PLAN.md · LICENSE · THIRD_PARTY.txt · SHA256SUMS.json
```

### Arsitektur

- **Threading.** `core.py` dan `debugger.py` tidak bergantung pada Tk. Thread kompilasi, pembaca terminal, dan pembaca debugger tidak pernah menyentuh Tk secara langsung. Hasilnya dikirim lewat antrean pesan yang dibaca UI setiap 40 ms.
- **Tanpa shell.** Kompilasi dan eksekusi program tidak pernah memakai shell.
- **Debugger berbasis instrumentasi.** Build debug menyisipkan pengait di setiap statement, dan `odinpc debug` berbicara dengan runtime library program lewat Unix socket (di Windows: TCP 127.0.0.1). Tidak ada ptrace, LLDB, maupun GDB, sehingga perilakunya sama di setiap sistem. Kontraknya ada di [`rtl/COMPILER_INTERFACE.md`](rtl/COMPILER_INTERFACE.md).
- **Clean-room.** Toolchain dan runtime library Odin ditulis tanpa membaca sumber Free Pascal, Free Vision, maupun Borland. Sampai 2.3.0, Free Pascal hanya dipakai sebagai pembanding keluaran program di korpus `tests/pascal/`; kini proyek ini tidak memakainya sama sekali.

## Riwayat Rilis

| Versi | Ringkasan |
|---|---|
| **3.0.0-beta.1** (pra-rilis) | Antarmuka berjendela modern: menu teks dan dropdown, toolbar berikon, jendela child dengan minimize/maximize, jendela Output dan Messages, dialog Options bertab, desktop tersimpan; buku Bab 21–22 |
| **2.9.0** (terbaru) | **OOP berbasis `class`** di atas TP7, unit **Classes** dan **Contnrs**, debugger menampilkan isi objek, dan **File › Examples - OOP...** dengan 9 contoh |
| 2.8.0 | Jendela grafik sungguhan untuk program yang memakai Graph (piksel sebenarnya, tombol diteruskan ke program) dan **File › Examples - Graph...** dengan 14 contoh |
| 2.7.0 | Unit **Graph** (BGI TP7 lengkap: framebuffer di memori dengan pratinjau terminal), **WinDos**, **Overlay**, **Math**, dan **SysUtils** |
| 2.6.0 | Komentar penjelasan di 20 contoh OTP-AI |
| 2.5.0 | Bantuan HTML (`docs/help.html`, F1), referensi Pascal lengkap, unit Odin Vision `ColorSel` dan `TextView`, Setup Windows satu berkas, dan pustaka OTP-AI |
| 2.4.0 | Metrik untuk analisis dan lomba: `odinpc build --count-steps`, `odinpc metrics`, menu **Run › Ukur** (Shift+F9) dan **Run › Periksa...** dengan paket soal, serta laporan JSON `otp-metrics/1` |
| 2.3.0 | Buku tutorial PDF berwarna penuh (403 halaman, 20 bab) di menu **Help › Buku**, tutorial 90 contoh di **File › Examples**, dan warna sintaks **Turbo Biru Lembut**. Toolchain Odin tidak berubah |
| 2.2.0 | IDE, toolchain Odin, debugger terpadu, dan Odin Vision di **Windows** (x86_64, Windows 10 1809 atau lebih baru), dengan pemasang `Install.cmd`. Mencakup dukungan Apple Silicon dan Linux dari 2.1.0-alpha.1; tidak ada rilis 2.1.0 terpisah |
| 2.1.0-alpha.1 | Toolchain Odin, debugger terpadu, dan Odin Vision di **Apple Silicon** dan **Linux** (x86_64 dan arm64). Bundel macOS berisi `odinpc` universal |
| 2.0.1 | Tag versi di desktop, About, dan contoh `HELLO.PAS` |
| 2.0.0 | Toolchain Odin native, debugger terpadu, Odin Vision, dan logo baru untuk Mac Intel |
| 2.0.0-alpha.1, 2.0.0-alpha.2 | Rilis alfa yang memperkenalkan toolchain Odin native dan logo baru |
| 1.0.0 | Kompilasi dengan Free Pascal dan debug lewat LLDB |

Rincian setiap rilis ada di [`CHANGELOG.md`](CHANGELOG.md) dan di halaman [Releases](https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/releases).

## Kontribusi

Laporan bug, saran, dan pull request dipersilakan melalui [Issues](https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/issues) dan [Pull requests](https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/pulls). Sebelum mengirim perubahan:

1. Jalankan `python3 -m unittest discover -s tests -v` dan, bila mengubah `toolchain/` atau `rtl/`, `cargo test --workspace` di `toolchain/`. Tambahkan tes untuk perilaku baru.
2. Untuk perilaku Pascal baru, tambahkan program ke `tests/pascal/`, buat ekspektasinya dengan `scripts/bless_corpus.py`, lalu periksa ekspektasi itu terhadap perilaku Turbo Pascal 7 sebelum commit. Jangan membaca atau menyalin sumber Free Pascal, Free Vision, maupun Borland.
3. Tulis pesan untuk pengguna dalam bahasa Indonesia. Label menu tetap berbahasa Inggris, sesuai gaya Turbo Pascal.
4. Awali berkas source baru dengan header lisensi `SPDX-License-Identifier: GPL-3.0-or-later`.
5. Setelah mengubah source, jalankan `python3 scripts/package_app.py` agar bundel `.app` ikut diperbarui.

## Lisensi

Odin Turbo Pascal adalah perangkat lunak bebas di bawah **[GNU General Public License v3.0 atau yang lebih baru](LICENSE)**. Anda boleh memakai, mempelajari, mengubah, dan menyebarkannya. Bila Anda menyebarkan versi asli atau versi ubahan, sertakan source code-nya dengan lisensi yang sama. Program ini disediakan tanpa jaminan apa pun.

**Copyright © 2026 Syams Ideris**

- Program yang dikompilasi dengan Odin memuat runtime library Odin, yang juga berlisensi GNU GPL v3 atau yang lebih baru tanpa pengecualian runtime. Bila Anda membagikan program tersebut, ketentuan GPL berlaku untuk program itu.
- Logo dan ikon Odin adalah karya penulis, diambil dari proyek ODIN Turbo Pascal v2.0, dan berlisensi sama.
- Python, Tcl/Tk, Homebrew, dan winget dipasang terpisah dengan lisensinya masing-masing. `odinpc` dibangun dengan pustaka standar Rust (lisensi MIT/Apache-2.0). Lihat [`THIRD_PARTY.txt`](THIRD_PARTY.txt).

> [!NOTE]
> Odin adalah aplikasi independen dan tidak berafiliasi dengan Borland maupun pemilik merek Turbo Pascal saat ini. "Turbo Pascal" dan "Borland" adalah merek dagang dari pemiliknya masing-masing. Nama tersebut dipakai hanya untuk menjelaskan kompatibilitas dan inspirasi.

## Penulis

**Syams Ideris** · [syamsuddin.ideris@gmail.com](mailto:syamsuddin.ideris@gmail.com)

<div align="center">

---

Bila Odin Turbo Pascal bermanfaat untuk belajar atau mengajar, beri ⭐ pada repositori ini dan bagikan ke teman sekelas.

<sub>Dibuat untuk generasi baru pembelajar Pascal.</sub>

</div>
