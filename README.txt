ODIN TURBO PASCAL 2.4.0
Paket aplikasi desktop untuk Mac Intel dan Apple Silicon; berjalan dari source di Linux
Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

MULAI DI SINI

Cara termudah di Mac Intel, offline: buka OdinTurboPascal-VERSI-macos-x86_64.pkg (dari
halaman Releases). Aplikasi dipasang di ~/Applications tanpa kata sandi administrator dan
membawa Python dengan Tk sendiri. Paket belum ditandatangani Apple: klik kanan > Open.
Cara dari ZIP:

1. Ekstrak seluruh ZIP. Jangan menjalankan Install.command dari pratinjau ZIP.
2. Buka Install.command. Pemasang berjalan melalui Terminal.
3. Ikuti pemasangan dependensi apabila diminta. Satu-satunya dependensi
   adalah Python dengan Tk; pemasangan awal memerlukan internet bila belum
   tersedia. Compiler Pascal (odinpc) sudah ada di dalam aplikasi.
4. Pemasang mengompilasi dan menjalankan program kecil dengan odinpc untuk
   memeriksa bahwa hasilnya sesuai CPU Mac. Jika pemeriksaan gagal, pemasangan berhenti dengan
   pesan kesalahan, bukan melaporkan keberhasilan palsu.
5. Buka ~/Applications/Odin Turbo Pascal.app. Di Finder, pilih Go > Home,
   kemudian folder Applications. Aplikasi juga didaftarkan pada LaunchServices.
6. File > New, tulis program, F2 untuk menyimpan, Ctrl+F9 untuk menjalankan.
   Alternatif Mac: Command+S, Command+B, Command+R.

Jika macOS menahan pembukaan paket yang belum ditandatangani, ikuti prosedur
Apple melalui System Settings > Privacy & Security > Open Anyway. Jangan
menonaktifkan Gatekeeper secara global. Pemasang tidak menghapus quarantine.
Jika atribut executable hilang saat ZIP diekstrak, jalankan melalui Terminal:
  /bin/bash "/lokasi/paket/Install.command"

ISI PAKET

Odin Turbo Pascal.app  Bundel aplikasi macOS dengan launcher dan kode lengkap.
Install.command       Deteksi CPU, pemasangan Python/Tk, compile/run check,
                      pemasangan aplikasi, dan pencadangan versi terdahulu.
Uninstall.command     Memindahkan aplikasi ke Trash, mempertahankan data.
CHANGELOG.md          Riwayat perubahan per versi.
main.py, odin/        Source code aplikasi yang dapat dipelajari dan diubah.
examples/             Tutorial Pascal untuk pemula: 90 berkas dalam 20 bab,
                      yaitu 89 program dan unit matematika.pas (Bab 19).
rtl/                  Runtime library Odin dan Odin Vision (Pascal).
toolchain/            Source toolchain Odin: compiler, assembler, linker,
                      dan debugger (Rust).
docs/                 Panduan, referensi Pascal, pintasan, kompatibilitas,
                      laporan pengujian, serta pratinjau antarmuka.
assets/               Logo dan ikon: master PNG serta PNG/ICNS hasil render.
tests/                Pengujian fungsional dan GUI.
scripts/              Pemeriksaan macOS, pembentukan ulang bundel .app, dan
                      render logo (render_logo.py, butuh Pillow).

BENTUK DISTRIBUSI

Ini adalah aplikasi Python/Tk dengan bundel .app yang memakai runtime lokal.
Bundel membawa toolchain Odin (odinpc universal untuk Intel dan Apple
Silicon: compiler, assembler, linker, debugger) dan runtime library-nya,
sehingga tidak memerlukan Free Pascal, Xcode Command Line Tools, atau SDK
Apple. Python dengan Tk tidak disertakan. Karena itu, paket bukan installer
offline mandiri dan bukan DMG/PKG bertanda tangan Apple.
Setelah dependensi tersedia, penggunaan editor, kompilasi, dan menjalankan
program tidak memerlukan internet. Tidak ada API key, server, atau telemetri.

TARGET MAC

Intel x86_64 dan Apple Silicon arm64: compiler adalah toolchain Odin, yang
menghasilkan program native untuk CPU Mac, lengkap dengan debugger terpadu
dan Odin Vision. Linker Odin menulis tanda tangan kode ad-hoc yang diwajibkan
macOS di Apple Silicon, sehingga Xcode tidak diperlukan.
Di Apple Silicon pemasang memilih eksekusi arm64; Rosetta tidak diperlukan
bila Python native tersedia. Runtime Python universal2 juga didukung.
Apple Silicon diuji di runner GitHub Actions (macOS 15 arm64), belum di Mac
fisik milik pengembang.

LINUX

Pemasang satu berkas, offline (tanpa root): sh OdinTurboPascal-VERSI-linux-ARCH.run
Berkas ini membawa IDE, odinpc, dan Python dengan Tk sendiri; hanya pustaka X11 sistem
yang dipakai. Opsi: --prefix DIR, --no-menu, --check, --uninstall. Diuji di VM Ubuntu
24.04 x86_64 tanpa jaringan; arm64 dan distro lain belum diuji di mesin sungguhan.

Odin berjalan dari source di Linux x86_64 dan arm64 dengan glibc 2.34 atau
lebih baru (Ubuntu 22.04+, Debian 12+, Fedora 35+); musl tidak didukung.
Pasang python3-tk dan Rust, lalu:
  cd toolchain && cargo build --release && cd .. && python3 main.py
Compiler, debugger, dan Odin Vision langsung tersedia. Diuji di VM
Ubuntu 24.04 dan di runner GitHub Actions (x86_64 dan arm64).

WINDOWS

Odin berjalan di Windows 10 versi 1809 atau lebih baru, 64-bit (x86_64).
Cara termudah dan offline: jalankan OdinTurboPascal-VERSI-Setup-x64.exe
(dari halaman Releases); berkas ini sudah membawa Python dengan Tk dan
odinpc.exe, tanpa unduhan dan tanpa hak administrator. Hapus lewat
Settings > Apps. Setup belum ditandatangani kode, jadi SmartScreen dapat
memberi peringatan (More info > Run anyway).
Dari paket ZIP: klik dua kali Install.cmd. Pemasang mencari Python 3.10+ dengan Tk
(menawarkan winget atau tautan unduhan resmi bila belum ada), mengompilasi
dan menjalankan program uji dengan odinpc.exe, lalu memasang aplikasi di
%LOCALAPPDATA%\Programs\OdinTurboPascal beserta pintasan di menu Start dan
Desktop. Hak administrator tidak diperlukan untuk Odin sendiri.
Uninstall.cmd menghapus aplikasi; pengaturan di %APPDATA%\OdinTurboPascal
tetap tersimpan. Windows diuji di runner GitHub Actions (Windows Server
2025); pemasang lengkap (Install.cmd dan setup Inno) belum dijalankan di PC Windows
sungguhan.

Target bundel macOS 11 atau lebih baru dan Python 3.10 atau lebih baru dengan
Tk. Target ini adalah rancangan kompatibilitas, bukan hasil sertifikasi pada
semua versi Mac. Dukungan Homebrew tergantung versi macOS dan ketersediaan
paket saat memasang. Pada macOS atau Intel yang tidak didukung Homebrew,
gunakan installer resmi Python universal2, lalu jalankan Install.command
kembali.

SUMBER DEPENDENSI RESMI

Python universal2: https://www.python.org/downloads/macos/
Tk pada Python: https://www.python.org/download/mac/tcltk/
Homebrew: https://brew.sh/

Pemasang menawarkan Homebrew jika belum ada pengelola paket dan Python dengan
Tk belum tersedia. Pilihan manual tidak memasang Homebrew. Pemasangan Homebrew
mungkin meminta kata sandi administrator, dan Homebrew sendiri memasang Xcode
Command Line Tools; Odin tidak memerlukannya. Odin sendiri dipasang di akun
pengguna, bukan mengubah /Applications milik sistem.

FITUR YANG TERIMPLEMENTASI

Antarmuka biru, teks kuning, menu abu-abu, jendela editor, status bar, dan
pintasan fungsi klasik. File/Edit/Search/Run/Compile/Debug/Options/Window/Help.
Editor beberapa berkas dengan tile, cascade, zoom, undo/redo, clipboard,
find/replace, go-to-line, indentasi, mode insert/overwrite, dan warna sintaks
Turbo Biru Lembut yang bisa dimatikan.
Toolchain Odin (macOS, Linux, Windows): compiler TP7 dengan tipe object, runtime library
dengan Crt, Dos, Strings, Printer, Objects, dan Odin Vision (Turbo Vision
lengkap, termasuk ColorSel dan TextView). Primary file, unit/include paths, range/overflow checks, build ulang, pesan compiler
dan navigasi baris error.
Terminal PTY 80x25: ReadLn, ReadKey, warna CRT, GotoXY, ClrScr, input tombol,
dan mouse untuk program Turbo Vision.
Argumen program, penghentian proses, ekspor executable native.
Debugger terpadu: breakpoint, Trace into, Step over, Go to
cursor, jendela Watches, Local variables, dan Call stack, Evaluate/Modify,
serta Search > Find error untuk runtime error.
Metrik (backend Odin): Run > Ukur (Shift+F9) mengukur langkah, puncak heap,
memori global, dan kedalaman panggilan dengan angka yang sama di semua
platform, beserta peta langkah dan catatan struktur kode; Run > Periksa
menilai program dengan paket soal (kasus uji, subtask, syarat).
Penyimpanan atomik, deteksi perubahan dari luar, CP437/UTF-8, LF/CRLF,
daftar berkas terakhir, pengaturan, pemulihan sesi setiap 10 detik.

PERBEDAAN DARI BORLAND TURBO PASCAL

Odin merupakan implementasi baru yang mengikuti antarmuka dan alur klasik,
bukan salinan identik setiap piksel, dialog, font, compiler, debugger, atau
perilaku DOS. Tidak menyertakan perangkat lunak, logo, atau berkas Borland.
Compiler Odin mengikuti bahasa Turbo Pascal 7. Hasil kompilasi berupa
program native macOS, Linux, atau Windows, bukan EXE DOS 16-bit. Kode BGI/Graph, interrupt DOS,
Port/Mem, assembler x86 16-bit, serta pointer berbasis segment memerlukan
porting. Tidak ada emulator DOS di dalam paket ini.
Free Pascal (backend alternatif sampai 2.3.0, beserta mode ObjFPC/Delphi)
dan konsol LLDB dari rilis 1.0.0 tidak dipakai lagi.
Lihat docs/COMPATIBILITY.txt untuk rincian.

PENGUJIAN

Rilis 2.4.0 diuji di Mac Intel (macOS 15.7, Python 3.13, Tk 9.1,
Free Pascal 3.2.2): 119 tes Python (termasuk tes GUI dengan jendela Tk
sungguhan) dan 189 tes Rust. Laporan langkah build hitung langkah sama di
Mac Intel, VM Ubuntu 24.04 (x86_64, dan aarch64 lewat qemu), dan kelima
runner GitHub Actions. Rilis 2.2.0 diuji di Mac Intel dengan 92 tes
Python, 185 tes Rust, dan 77 program uji yang keluarannya sama dengan
Free Pascal. Korpus yang sama juga lulus di VM Ubuntu 24.04 (x86_64, dan
aarch64 lewat qemu) dan, bersama tes Python dengan backend Odin, di runner
GitHub Actions untuk macOS Apple Silicon, Linux x86_64, dan Linux arm64.
Sejak 2.2.0 korpus itu (dibandingkan dengan Free Pascal untuk
Windows), tes Python dengan backend Odin, dan pemeriksaan pemasang juga lulus
di runner GitHub Actions Windows Server 2025.
Rilis 1.0.0 diuji di Linux dengan Free Pascal 3.2.2 dan display virtual untuk
Tk; lihat docs/TEST_REPORT.txt.
Mac Apple Silicon, PC Linux, dan PC Windows fisik, Install.command di Apple
Silicon, Install.cmd lengkap, peluncuran lewat Finder/LaunchServices,
Gatekeeper, pemasang Homebrew, dan Mac bersih tanpa Free Pascal maupun Xcode
Command Line Tools belum diuji langsung.
Tidak ada klaim bahwa bundel telah ditandatangani atau dinotarisasi Apple.

PENYIMPANAN

Sumber Pascal tersimpan pada lokasi yang Anda pilih melalui Save as.
Pengaturan, build cache, recovery, dan log:
  ~/Library/Application Support/OdinTurboPascal/ (macOS)
  ~/.local/share/OdinTurboPascal/ (Linux)
  %APPDATA%\OdinTurboPascal\ (Windows)
Program berjalan dengan working directory folder sumber program utama.
Untuk contoh baca-tulis berkas, simpan dahulu salinan ke folder kerja sendiri.
File bawaan aplikasi diperlakukan sebagai template saat disimpan dari editor.
Uninstall tidak menghapus program pribadi atau folder pengaturan tersebut.

MENJALANKAN SOURCE CODE

Toolchain Odin dulu (macOS, Linux, Windows; Rust 1.85 atau lebih baru):
  cd toolchain && cargo build --release
lalu IDE dengan Python/Tk:
  python3 main.py
IDE memakai toolchain/target/release/odinpc. Untuk bundel macOS
universal: python3 scripts/build_toolchain.py lalu scripts/package_app.py.

Pengujian:
  python3 -m unittest discover -s tests -v
Pengujian GUI memerlukan desktop aktif. Tes compiler dilewati jika odinpc
belum dibangun dan tes GUI dilewati jika tidak ada display.

Membentuk ulang bundel setelah source code diubah:
  python3 scripts/package_app.py
Jalankan dari folder paket. Perintah mengganti bundel build di folder ini,
bukan aplikasi yang sudah dipasang pada akun pengguna.

Lisensi source Odin: GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026
Syams Ideris. Program ini perangkat lunak bebas dan disediakan TANPA JAMINAN
APA PUN. Lihat LICENSE dan THIRD_PARTY.txt.
