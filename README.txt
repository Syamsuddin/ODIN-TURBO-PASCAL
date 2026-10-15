ODIN TURBO PASCAL 2.2.0-alpha.1
Paket aplikasi desktop untuk Mac Intel dan Apple Silicon; berjalan dari source di Linux
Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

MULAI DI SINI

1. Ekstrak seluruh ZIP. Jangan menjalankan Install.command dari pratinjau ZIP.
2. Buka Install.command. Pemasang berjalan melalui Terminal.
3. Ikuti pemasangan dependensi apabila diminta. Pemasangan awal memerlukan
   internet jika Python/Tk atau Free Pascal belum tersedia.
4. Pemasang mengompilasi dan menjalankan program kecil untuk memeriksa bahwa
   hasilnya sesuai CPU Mac. Jika pemeriksaan gagal, pemasangan berhenti dengan
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
Install.command       Deteksi CPU, pemasangan dependensi, compile/run check,
                      pemasangan aplikasi, dan pencadangan versi terdahulu.
Uninstall.command     Memindahkan aplikasi ke Trash, mempertahankan data.
CHANGELOG.md          Riwayat perubahan per versi.
main.py, odin/        Source code aplikasi yang dapat dipelajari dan diubah.
examples/             Sebelas berkas contoh Pascal, termasuk satu unit dan
                      demo Turbo Vision (VISION.PAS).
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
Silicon) dan runtime library-nya, tetapi tidak menyertakan Python, Free Pascal, atau SDK Apple. Karena itu,
paket bukan installer offline mandiri dan bukan DMG/PKG bertanda tangan Apple.
Setelah dependensi tersedia, penggunaan editor, kompilasi, dan menjalankan
program tidak memerlukan internet. Tidak ada API key, server, atau telemetri.

TARGET MAC

Intel x86_64 dan Apple Silicon arm64: backend bawaan adalah toolchain Odin,
yang menghasilkan program native untuk CPU Mac, lengkap dengan debugger
terpadu dan Odin Vision. Free Pascal bisa dipilih di Options > Compiler.
Di Apple Silicon pemasang memilih eksekusi arm64; Rosetta tidak diperlukan
bila dependensi native tersedia. Runtime Python universal2 juga didukung.
Apple Silicon diuji di runner GitHub Actions (macOS 15 arm64), belum di Mac
fisik milik pengembang.

LINUX

Odin berjalan dari source di Linux x86_64 dan arm64 dengan glibc 2.34 atau
lebih baru (Ubuntu 22.04+, Debian 12+, Fedora 35+); musl tidak didukung.
Pasang python3-tk dan Rust, lalu:
  cd toolchain && cargo build --release && cd .. && python3 main.py
Backend Odin, debugger, dan Odin Vision langsung tersedia. Diuji di VM
Ubuntu 24.04 dan di runner GitHub Actions (x86_64 dan arm64).

WINDOWS

Odin berjalan di Windows 10 versi 1809 atau lebih baru, 64-bit (x86_64).
Klik dua kali Install.cmd. Pemasang mencari Python 3.10+ dengan Tk dan Free
Pascal (menawarkan winget atau tautan unduhan resmi bila belum ada),
mengompilasi dan menjalankan program uji dengan Free Pascal dan dengan
toolchain Odin, lalu memasang aplikasi di
%LOCALAPPDATA%\Programs\OdinTurboPascal beserta pintasan di menu Start dan
Desktop. Hak administrator tidak diperlukan untuk Odin sendiri.
Uninstall.cmd menghapus aplikasi; pengaturan di %APPDATA%\OdinTurboPascal
tetap tersimpan. Windows diuji di runner GitHub Actions (Windows Server
2025); pemasang lengkap belum dijalankan di PC Windows sungguhan.

Target bundel macOS 11 atau lebih baru, Python 3.10 atau lebih baru dengan Tk,
Free Pascal 3.2.2 atau lebih baru, dan Xcode Command Line Tools. Target ini
adalah rancangan kompatibilitas, bukan hasil sertifikasi pada semua versi Mac.
Dukungan Homebrew tergantung versi macOS dan ketersediaan paket saat memasang.
Pada macOS atau Intel yang tidak didukung Homebrew, gunakan installer resmi
Python universal2 dan FPC Intel+ARM64, lalu jalankan Install.command kembali.

SUMBER DEPENDENSI RESMI

Python universal2: https://www.python.org/downloads/macos/
Tk pada Python: https://www.python.org/download/mac/tcltk/
Free Pascal: https://www.freepascal.org/down/i386/macosx.html
Homebrew: https://brew.sh/
Command Line Tools: jalankan xcode-select --install di Terminal.

Pemasang menawarkan Homebrew jika belum ada pengelola paket dan dependensi
belum lengkap. Pilihan manual tidak memasang Homebrew. Pemasangan Homebrew
mungkin meminta kata sandi administrator. Odin sendiri dipasang di akun
pengguna, bukan mengubah /Applications milik sistem.

FITUR YANG TERIMPLEMENTASI

Antarmuka biru, teks kuning, menu abu-abu, jendela editor, status bar, dan
pintasan fungsi klasik. File/Edit/Search/Run/Compile/Debug/Options/Window/Help.
Editor beberapa berkas dengan tile, cascade, zoom, undo/redo, clipboard,
find/replace, go-to-line, indentasi, mode insert/overwrite, warna sintaks opsional.
Toolchain Odin (macOS, Linux, Windows): compiler TP7 dengan tipe object, runtime library
dengan Crt, Dos, Strings, Printer, Objects, dan Odin Vision (Turbo Vision).
Free Pascal asli sebagai backend alternatif, mode TP/ObjFPC/Delphi, primary
file, unit/include paths, range/overflow checks, build ulang, pesan compiler
dan navigasi baris error.
Terminal PTY 80x25: ReadLn, ReadKey, warna CRT, GotoXY, ClrScr, input tombol,
dan mouse untuk program Turbo Vision.
Argumen program, penghentian proses, ekspor executable native.
Debugger terpadu (backend Odin): breakpoint, Trace into, Step over, Go to
cursor, jendela Watches, Local variables, dan Call stack, Evaluate/Modify,
serta Search > Find error untuk runtime error.
Penyimpanan atomik, deteksi perubahan dari luar, CP437/UTF-8, LF/CRLF,
daftar berkas terakhir, pengaturan, pemulihan sesi setiap 10 detik.

PERBEDAAN DARI BORLAND TURBO PASCAL

Odin merupakan implementasi baru yang mengikuti antarmuka dan alur klasik,
bukan salinan identik setiap piksel, dialog, font, compiler, debugger, atau
perilaku DOS. Tidak menyertakan perangkat lunak, logo, atau berkas Borland.
Free Pascal mode TP mendekatkan kompatibilitas sumber. Hasil kompilasi berupa
program native macOS, Linux, atau Windows, bukan EXE DOS 16-bit. Kode BGI/Graph, interrupt DOS,
Port/Mem, assembler x86 16-bit, serta pointer berbasis segment memerlukan
porting. Tidak ada emulator DOS di dalam paket ini.
Debugger terpadu hanya tersedia di backend Odin. Konsol LLDB dari rilis 1.0.0
tidak dipakai lagi.
Lihat docs/COMPATIBILITY.txt untuk rincian.

PENGUJIAN

Rilis 2.2.0-alpha.1 diuji di Mac Intel (macOS 15.7, Python 3.13, Tk 9.1,
Free Pascal 3.2.2): 92 tes Python (termasuk tes GUI dengan jendela Tk
sungguhan), 185 tes Rust, dan 77 program uji yang keluarannya sama dengan
Free Pascal. Korpus yang sama juga lulus di VM Ubuntu 24.04 (x86_64, dan
aarch64 lewat qemu) dan, bersama tes Python dengan backend Odin, di runner
GitHub Actions untuk macOS Apple Silicon, Linux x86_64, dan Linux arm64.
Sejak 2.2.0-alpha.1 korpus itu (dibandingkan dengan Free Pascal untuk
Windows), tes Python dengan backend Odin, dan pemeriksaan pemasang juga lulus
di runner GitHub Actions Windows Server 2025.
Rilis 1.0.0 diuji di Linux dengan Free Pascal 3.2.2 dan display virtual untuk
Tk; lihat docs/TEST_REPORT.txt.
Mac Apple Silicon, PC Linux, dan PC Windows fisik, Install.command di Apple
Silicon, Install.cmd lengkap, peluncuran lewat Finder/LaunchServices,
Gatekeeper, dan pemasang Homebrew belum diuji langsung.
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

Mac/Linux dengan Python/Tk dan Free Pascal:
  python3 main.py
Toolchain Odin (macOS, Linux, Windows; Rust 1.85 atau lebih baru):
  cd toolchain && cargo build --release
IDE memakai toolchain/target/release/odinpc bila ada. Untuk bundel macOS
universal: python3 scripts/build_toolchain.py lalu scripts/package_app.py.

Pengujian:
  python3 -m unittest discover -s tests -v
ODIN_FPC dapat diatur ke executable compiler bila tidak tersedia di PATH.
Pengujian GUI memerlukan desktop aktif. Tes compiler dilewati jika FPC tidak
ditemukan dan tes GUI dilewati jika tidak ada display.

Membentuk ulang bundel setelah source code diubah:
  python3 scripts/package_app.py
Jalankan dari folder paket. Perintah mengganti bundel build di folder ini,
bukan aplikasi yang sudah dipasang pada akun pengguna.

Lisensi source Odin: GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026
Syams Ideris. Program ini perangkat lunak bebas dan disediakan TANPA JAMINAN
APA PUN. Lihat LICENSE dan THIRD_PARTY.txt.
