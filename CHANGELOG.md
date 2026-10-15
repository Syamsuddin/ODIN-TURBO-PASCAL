# Changelog

Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

Semua perubahan penting pada Odin Turbo Pascal dicatat di berkas ini. Formatnya mengikuti [Keep a Changelog](https://keepachangelog.com/id-ID/1.1.0/), dan nomor versinya mengikuti [Semantic Versioning](https://semver.org/lang/id/).

## [Unreleased]

### Diperbaiki

- Windows: program tidak lagi sesekali berhenti dengan runtime error 216 saat `Exec` menjalankan program lewat PATH. Handler pengecualian hanya menangani pelanggaran akses di kode program sendiri; pelanggaran akses di DLL sistem (yang bisa ditangani DLL itu sendiri) diteruskan, dan yang tidak tertangani tetap menjadi runtime error lewat filter terakhir.

## [2.2.0] - 2026-10-15

Rilis 2.2.0. IDE, toolchain Odin, debugger terpadu, dan Odin Vision kini juga berjalan di Windows 10 1809 atau lebih baru (x86_64). Rilis ini juga membawa dukungan Apple Silicon dan Linux (x86_64 dan arm64) dari 2.1.0-alpha.1 (rinciannya di entri itu); tidak ada rilis 2.1.0 terpisah.

### Ditambahkan

- Target `x86_64-windows` di `odinpc`: konvensi panggil Win64 (shadow space, register argumen Windows, probe stack untuk frame besar) dan linker PE32+ yang mengimpor `kernel32.dll` dan `ucrtbase.dll`. `odinpc.exe` sendiri dibangun di runner CI Windows, dan paket rilis membawanya di `toolchain/odinpc.exe`.
- RTL Windows:
  - `System`: berkas lewat UCRT dalam mode biner, `WriteLn` menulis CRLF seperti FPC, runtime error dari vectored exception handler;
  - `Crt`: konsol dengan pemrosesan VT dan UTF-8, `KeyPressed`/`ReadKey` dari event konsol;
  - `Dos`: `FindFirst`/`FindNext` lewat `FindFirstFileA`, atribut dan waktu berkas, `DiskFree`, `Exec` lewat `_spawnvpe`, `FExpand` dan `FSplit` dengan huruf drive dan `\`, kode `DosError` seperti FPC untuk Windows;
  - `Printer` mencetak lewat `notepad /p`;
  - Odin Vision: lapisan konsol Windows di `Drivers`, dan dialog berkas `StdDlg` yang memakai `\` dan akar `C:\`.
- Debugger terpadu di Windows: program dan `odinpc debug` berbicara lewat TCP 127.0.0.1 dengan memori bersama berbasis berkas; IDE berbicara dengan `odinpc debug` lewat TCP juga.
- User screen ConPTY (`odin/conpty.py`, lewat `ctypes`): job object agar Stop menghentikan seluruh pohon proses, dan `Ctrl+C` yang sampai ke program lewat helper yang menempel ke pseudoconsole.
- Pemasang Windows `Install.cmd`/`Install.ps1` dan `Uninstall.cmd`: mencari Python dengan Tk dan Free Pascal (menawarkan winget), memeriksa kompilasi dengan Free Pascal dan dengan `odinpc.exe`, lalu memasang di `%LOCALAPPDATA%\Programs\OdinTurboPascal` dengan pintasan Start dan Desktop.
- Ekspektasi korpus per sistem operasi (`NAME.windows.out`) dari Free Pascal untuk Windows, dibuat oleh workflow `oracle.yml`.

### Diubah

- Teks di bawah logo desktop kini berupa plakat bergaya dialog Turbo Vision (abu-abu, bingkai ganda putih, bayangan hitam): `NATIVE PASCAL IDE` dengan tag versi, `Created by Syams Ideris`, hak cipta, dan lisensi. Ukurannya tetap, tidak ikut ukuran font editor, sehingga baris-barisnya tidak lagi berimpitan atau melebar jauh melampaui logo.
- CI: job Windows kini wajib lulus, menjalankan pemeriksaan pemasang, dan mengunggah `odinpc.exe` sebagai artefak.
- Tes snapshot Odin Vision mengabaikan warna depan sel kosong (tidak terlihat, dan ConPTY tidak mempertahankannya), lalu menyebutkan sel mana yang berbeda bila warna tidak cocok.

### Pengujian

- **Mac Intel** (macOS 15.7, Python 3.13, Tk 9.1, FPC 3.2.2, Rust 1.99): 92 tes Python (6 tes khusus Windows dilewati) dan 185 tes Rust lulus. Korpus diferensial 77 program (build biasa dan debug) identik dengan FPC 3.2.2.
- **GitHub Actions:** di Windows Server 2025, korpus 77 program (biasa dan debug) identik dengan FPC 3.2.2 untuk Windows, 92 tes Python lulus (2 tes khusus Unix dilewati), termasuk GUI, debugger, dan Odin Vision,, dan pemeriksaan pemasang lulus. macOS 15 Intel dan Apple Silicon serta Ubuntu 24.04 x86_64 dan arm64 tetap lulus.
- **Belum diverifikasi langsung:** PC Windows fisik, `Install.cmd` lengkap (winget, pintasan, peluncuran dari menu Start), Windows on ARM, serta yang belum diverifikasi di 2.1.0-alpha.1.

## [2.1.0-alpha.1] - 2026-10-15

Rilis alfa pertama menuju 2.1.0. Toolchain Odin, debugger terpadu, dan Odin Vision kini juga berjalan di Apple Silicon dan Linux (x86_64 dan arm64). Windows sedang dikerjakan dan belum didukung.

### Ditambahkan

- Target baru di `odinpc`: `aarch64-darwin` (Apple Silicon), `x86_64-linux`, dan `aarch64-linux`. IDE memakai backend Odin secara bawaan di macOS dan Linux, baik x86_64 maupun arm64 (`core.ODIN_HOSTS`).
- Codegen AArch64 (`odin-codegen/src/aarch64.rs`), beserta encoder AArch64 dan assembler teks arm64 di `odin-asm` yang diuji terhadap 575 encoding instruksi dari clang. Prosesor arm64 tidak menghentikan program saat operasi real gagal, jadi bendera FPSR diperiksa sesudah operasi real. Runtime error 207/200/205 dihasilkan lewat `ODIN_FPERROR`, seperti di x86-64.
- Linker ELF: executable PIE dinamis untuk glibc (x86_64 dan aarch64), dengan GOT, relokasi RELATIVE, `.symtab` untuk gdb, dan `__ehdr_start`. Butuh glibc 2.34 atau yang lebih baru; musl tidak didukung.
- RTL per sistem operasi: layout `stat`, `dirent`, `statfs`, `termios`, `sigaction`, dan konteks sinyal untuk macOS dan Linux, x86-64 dan arm64, serta shim assembly per target.
- Bundel macOS membawa `odinpc` universal (x86_64 + arm64). `scripts/build_toolchain.py` membangunnya, dan `scripts/package_app.py` memakainya.
- CI GitHub Actions (`.github/workflows/ci.yml`) menjalankan build `odinpc`, tes Rust (termasuk korpus diferensial yang berjalan native), dan tes Python di macOS Intel, macOS Apple Silicon, Linux x86_64, Linux arm64, dan Windows.
- Korpus diferensial bisa dijalankan untuk target lain (`ODIN_CORPUS_TARGET`, `ODIN_CORPUS_RUNNER`), misalnya lewat VM atau qemu.
- Pekerjaan Windows yang sudah masuk, tetapi belum didukung:
  - konvensi panggil Win64 di codegen x86-64;
  - linker PE32+;
  - RTL Windows: UCRT, Win32, konsol VT, dan vectored exception handler;
  - IDE dengan User screen ConPTY lewat `ctypes`;
  - pemasang `Install.ps1`.

  Statusnya tercatat di `IMPLEMENTATION_PLAN.md` (Tahap 8d).

### Diubah

- User screen menjawab permintaan status dan posisi kursor (`ESC [5n`, `ESC [6n`). Crt milik Free Pascal di Linux menunggu jawaban ini sebelum menggambar apa pun.
- Di macOS, keluaran program yang sangat cepat tidak lagi hilang dari User screen: slave pty tetap terbuka sampai program keluar.
- Parser layar menerima warna 256 dan RGB (`38;5;n`, `38;2;r;g;b`) dan memetakannya ke 16 warna CRT; parameternya tidak lagi terbaca sebagai atribut lain.
- `.gitattributes` mematikan konversi CRLF Git, sehingga checkout di Windows sama byte demi byte dengan repo.

### Pengujian

- **Mac Intel** (macOS 15.7, Python 3.13, Tk 9.1, FPC 3.2.2, Rust 1.99): 92 tes Python dan 185 tes Rust lulus. Korpus diferensial 77 program (build biasa dan debug) identik dengan FPC 3.2.2.
- **VM Ubuntu 24.04 (Lima):** korpus lulus untuk x86_64 dan aarch64 (lewat qemu-user), dan 92 tes Python dengan backend Odin lulus di x86_64.
- **GitHub Actions:** korpus yang berjalan native dan tes Python dengan backend Odin (GUI, debugger, Odin Vision) lulus di macOS 15 Apple Silicon, Ubuntu 24.04 x86_64, dan Ubuntu 24.04 arm64. macOS 15 Intel juga lulus.
- **Belum diverifikasi langsung:** Mac Apple Silicon dan PC Linux fisik, `Install.command` di Apple Silicon, Gatekeeper, serta seluruh dukungan Windows.

## [2.0.1] - 2026-10-15

Rilis perbaikan kecil: tag versi yang selalu terbaru di IDE dan alat bantu rilis. Compiler, runtime library, dan debugger sama dengan 2.0.0, jadi backend Odin tetap hanya untuk Mac Intel.

### Ditambahkan

- Tag versi rilis (misalnya `v2.0.0`) tampil di desktop IDE, baris status saat startup, jendela About, Environment, dan komentar `examples/HELLO.PAS` yang terbuka sebagai halaman bawaan. Semuanya diambil dari `__version__` di `odin/__init__.py`. `scripts/package_app.py` menyamakan tag di HELLO.PAS setiap kali bundle dibangun, dan tes gagal bila tag itu tertinggal.
- `scripts/set_version.py X.Y.Z` menaikkan nomor versi di semua berkas yang menuliskannya: `odin/__init__.py`, workspace toolchain (`odinpc version`), banner `Install.command`, judul `README.txt` dan docs, badge serta baris pemasangan README, tag di HELLO.PAS, dan entri CHANGELOG (bagian `[Unreleased]` menjadi rilis baru beserta tautan perbandingannya). Skrip ini hanya menulis bila semua pola cocok. Klaim pengujian dan prosa rilis tetap ditulis tangan; skrip menyebutkan bagian mana saja.
- `scripts/update_checksums.py` membuat ulang `SHA256SUMS.json` dari berkas yang dilacak git.

### Pengujian

Di Mac Intel (macOS 15.7, Python 3.13, Tk 9.1, Free Pascal 3.2.2, Rust 1.99): 58 tes Python lulus (termasuk 17 tes GUI dengan jendela Tk sungguhan, 4 tes snapshot Odin Vision, dan 2 tes versi), 110 tes Rust lulus, dan korpus diferensial 77 program memberi keluaran dan kode keluar yang sama dengan Free Pascal 3.2.2, baik dengan build biasa maupun build debug.

Yang belum diverifikasi langsung sama dengan 2.0.0.

## [2.0.0] - 2026-10-15

Rilis 2.0.0. Isinya sama dengan 2.0.0-alpha.2, hanya nomor versinya yang naik. Toolchain Pascal milik Odin (compiler, assembler, linker, runtime library, debugger terpadu, dan Odin Vision) menjadi backend bawaan di Mac Intel. Di Apple Silicon, Odin tetap memakai Free Pascal dan belum punya debugger.

Ringkasan perubahan sejak 1.0.0 (rinciannya di entri 2.0.0-alpha.1 dan 2.0.0-alpha.2):

- toolchain Odin native (`odinpc`, Rust tanpa crate pihak ketiga) dan runtime library sendiri: `System`, `Crt`, `Dos`, `Strings`, `Printer`, `Objects`, serta tipe `object` TP7;
- debugger terpadu pengganti konsol LLDB: breakpoint, Trace into, Step over, Go to cursor, jendela Watches, Local variables, dan Call stack, serta Evaluate/Modify;
- Odin Vision, Turbo Vision milik Odin, dengan contoh `examples/VISION.PAS`;
- mouse, tombol bermodifier, dan layar alternatif di User screen;
- logo dan ikon baru dari proyek OTP v2.0.

### Diubah

- Nomor versi 2.0.0 di aplikasi (About, watermark desktop, baris status), `odinpc version`, pemasang, Info.plist, README, dan docs.
- Rencana rilis: dukungan arm64 dan Linux untuk backend Odin serta pelepasan Free Pascal, LLDB, dan Xcode (Tahap 8–9 di `IMPLEMENTATION_PLAN.md`) dipindah dari 2.0.0 ke 2.1.0.

### Belum tersedia

- Backend Odin untuk Apple Silicon dan Linux. Di Apple Silicon, IDE memakai Free Pascal dan belum punya debugger.
- Unit Turbo Vision opsional `ColorSel` dan `TextView` di backend Odin.

### Pengujian

Di Mac Intel (macOS 15.7, Python 3.13, Tk 9.1, Free Pascal 3.2.2, Rust 1.99): 56 tes Python lulus (termasuk 17 tes GUI dengan jendela Tk sungguhan dan 4 tes snapshot Odin Vision), 110 tes Rust lulus, dan korpus diferensial 77 program memberi keluaran dan kode keluar yang sama dengan Free Pascal 3.2.2, baik dengan build biasa maupun build debug.

Yang belum diverifikasi langsung tetap sama dengan 2.0.0-alpha.1: Apple Silicon, peluncuran lewat Finder/LaunchServices, Gatekeeper, Option sebagai Alt di keyboard Mac sungguhan, dan pencetakan lewat `Printer`.

## [2.0.0-alpha.2] - 2026-10-15

Rilis alfa kedua menuju 2.0.0: logo baru dan dokumentasi yang diperbarui. Compiler, runtime library, dan debugger sama dengan 2.0.0-alpha.1.

### Diubah

- Logo dan ikon aplikasi memakai logo ODIN Turbo Pascal dari proyek OTP v2.0: Odin bertambal mata, petir, dan buku `begin. end.`. Logo lengkap tampil di desktop IDE, jendela About, dan ikon besar. Ukuran ikon 64 px ke bawah dan banner README memakai emblemnya saja. Sumbernya `assets/odin-logo-master.png`, dirender dengan `scripts/render_logo.py` (sekarang butuh Pillow, bukan cairosvg). Sumber SVG logo lama dihapus.
- README diperbarui dengan keadaan terbaru: logo, bagian Turbo Vision (Odin Vision), mouse dan tombol bermodifier di User screen, perintah pengembang (tes snapshot, render logo), serta struktur proyek. Teks banner README tidak lagi menyebut Free Pascal sebagai compiler utama.
- Nomor versi toolchain (`odinpc version`) disamakan dengan nomor rilis aplikasi.

## [2.0.0-alpha.1] - 2026-10-15

Rilis alfa pertama menuju 2.0.0. Toolchain Pascal milik Odin sendiri (compiler, assembler, linker, runtime library, debugger, dan Odin Vision) menjadi backend bawaan di Mac Intel. Free Pascal tetap tersedia, dan dipakai otomatis di Apple Silicon. Backend Odin untuk arm64 dan Linux, serta pelepasan Free Pascal, LLDB, dan Xcode sepenuhnya, menyusul sebelum 2.0.0 (lihat `IMPLEMENTATION_PLAN.md`, Tahap 8-10).

### Ditambahkan

- Toolchain Pascal milik Odin sendiri (`toolchain/`, Rust, tanpa crate pihak ketiga), sebagai backend eksperimental di Options > Compiler. Isinya:
  - `odinpc build`/`check`: lexer, direktif dan kompilasi bersyarat, parser TP7 lengkap, analisis semantik, codegen x86-64, assembler, dan linker Mach-O dengan tanda tangan ad-hoc;
  - diagnostik bernomor gaya TP7 dalam bahasa Indonesia, dikirim ke IDE sebagai JSON.
- Runtime library Odin (`rtl/system/`, Pascal): I/O teks, `ParamStr`, operasi string, format bilangan real, dan runtime error seperti FPC.
- Korpus tes diferensial (`tests/pascal/`) dengan ekspektasi dari FPC (`scripts/oracle.py`).
- Unit standar di runtime library Odin (`rtl/`):
  - `Crt`: jendela, warna, scroll, `InsLine`/`DelLine`, `ReadKey` dengan kode scan TP, `KeyPressed`, `Delay`, dan editor baris untuk `ReadLn`;
  - `Dos`: tanggal dan waktu, environment, `FSplit`/`FExpand`/`FSearch`, `FindFirst`/`FindNext`, atribut dan waktu berkas, `DiskFree`/`DiskSize`, `Exec`/`DosExitCode`, `DosVersion`;
  - `Strings` (rutin PChar) dan `Printer` (`Lst` ke `/usr/bin/lpr`).
- Berkas bertipe dan tanpa tipe, `FillChar`, `GetMem`/`FreeMem`, `Random`, dan `RunError` di backend Odin.
- Runtime error dari kesalahan prosesor seperti FPC: akses memori tidak sah (216), pembagian real dengan nol (200), operasi real tidak sah (207), overflow real (205). Stack overflow menjadi runtime error 202.

- Debugger Odin, pengganti LLDB (backend Odin):
  - breakpoint yang ikut bergeser saat baris disisipkan dan tersimpan di pemulihan sesi;
  - Trace into (F7), Step over (F8), Go to cursor (F4), Continue, dan pause dengan Ctrl+C di User screen;
  - jendela Watches, Local variables, dan Call stack sebagai jendela desktop;
  - Evaluate/Modify (Ctrl+F7) untuk ekspresi Pascal dengan format nilai gaya Turbo Pascal;
  - baris eksekusi ditandai hijau, dan baris runtime error ditandai merah.
- Search > Find error, juga untuk runtime error dari Run biasa.
- `odinpc build --debug`, berkas `NAME.odbg`, dan `odinpc debug`.
- Tipe `object` di backend Odin: pewarisan, `private`, metode virtual, constructor dan destructor, `inherited`, `Self`, `TypeOf`, serta `New`/`Dispose` dengan constructor/destructor. Debugger juga menampilkan field object.
- Unit `Objects` di runtime library Odin: TObject, TPoint, TRect, collection (termasuk yang terurut dan koleksi string), stream (berkas, berkas ber-buffer, memori), dan registrasi tipe untuk `Put`/`Get`. Format stream sama dengan FPC.
- `packed record` tanpa padding, builtin `Ofs`/`Seg`, dan tipe `PtrInt`/`PtrUInt`/`SizeInt`/`SizeUInt`/`PPointer`.
- Odin Vision (`rtl/vision/`), Turbo Vision milik Odin untuk backend Odin. Unitnya `Drivers`, `Memory`, `HistList`, `Views`, `Menus`, `Validate`, `Dialogs`, `App`, `MsgBox`, `StdDlg`, `Editors`, dan `Outline`, dengan:
  - jendela bertumpuk dengan bayangan, menu bar dan menu drop-down, status line;
  - dialog dengan tombol, input line, check box, radio button, list box, riwayat, dan validator;
  - dialog berkas dan dialog ganti direktori, editor teks, dan outline;
  - dukungan keyboard dan mouse.

  Perilakunya dijelaskan di `rtl/vision/SPEC.md`, dan palet warnanya dirancang sendiri.
- Contoh `examples/VISION.PAS`: menu, jendela editor, dialog, dan MessageBox.
- User screen meneruskan klik, seret, dan roda mouse ke program yang memintanya (laporan mouse xterm). Shift, Ctrl, dan Alt (Option di macOS) pada tombol khusus juga diteruskan, dan Alt+huruf dikirim sebagai Esc + huruf. Layar alternatif didukung, jadi layar sebelum program kembali setelah program Turbo Vision selesai.
- Tes snapshot Odin Vision (`tests/test_vision.py`, `tests/pascal/vision/`).

### Diubah

- Kerangka jendela editor dipisah menjadi `DesktopWindow` (`odin/windows.py`), supaya jendela debug nanti bisa ikut diatur Tile, Cascade, dan Window > List. Perilaku IDE tidak berubah.
- Backend bawaan sekarang toolchain Odin. Free Pascal tetap bisa dipilih di Options > Compiler, dan otomatis dipakai bila `odinpc` tidak ditemukan.
- `scripts/package_app.py` menyertakan `rtl/` dan, bila sudah dibangun, `toolchain/target/release/odinpc` di dalam bundle. Nomor versi bundle diambil dari `odin/__init__.py`.
- Paket pemasang membawa toolchain Odin (`odinpc` untuk Mac Intel) dan runtime library-nya.

### Dihapus

- Konsol LLDB di menu Debug. Debugger terpadu menggantikannya, tetapi hanya tersedia di backend Odin. Di Apple Silicon, untuk sementara Odin tidak punya debugger.

### Belum tersedia di backend Odin

- arm64 dan Linux.
- Unit Turbo Vision opsional `ColorSel` dan `TextView`. Untuk program yang memakainya, pilih backend Free Pascal; pesan galatnya menyebutkan hal ini.

### Lisensi

Runtime library Odin (`rtl/`) berlisensi GNU GPL v3 atau yang lebih baru tanpa pengecualian runtime, jadi executable yang dibagikan ikut terikat GPL. `odinpc` di dalam bundle memuat pustaka standar Rust (MIT); lihat `THIRD_PARTY.txt`.

### Pengujian

Di Mac Intel (macOS 15.7, Python 3.13, Tk 9.1, Free Pascal 3.2.2, Rust 1.99):

- 56 tes Python lulus, termasuk 17 tes GUI dengan jendela Tk sungguhan, sesi debugger nyata, dan 4 tes snapshot Odin Vision;
- 110 tes Rust lulus;
- korpus diferensial 77 program memberi keluaran dan kode keluar yang sama dengan Free Pascal 3.2.2, baik dengan build biasa maupun build debug.

Yang belum diverifikasi langsung: Apple Silicon, Gatekeeper, Option sebagai Alt di keyboard Mac sungguhan (baru diuji dengan event sintetis), dan pencetakan lewat `Printer`.

## [1.0.0] - 2026-10-13

Rilis publik pertama.

### Ditambahkan

- IDE bergaya Turbo Pascal era DOS. Tersedia menu File, Edit, Search, Run, Compile, Debug, Options, Window, dan Help, lengkap dengan status bar dan baris tombol fungsi.
- Editor:
  - beberapa jendela sekaligus (tile, cascade, zoom);
  - undo/redo, find/replace, go to line, indentasi otomatis, mode insert/overwrite;
  - warna sintaks opsional.
- Penanganan berkas:
  - encoding UTF-8, UTF-8 BOM, dan CP437 serta akhir baris LF dan CRLF tetap seperti aslinya saat disimpan;
  - penyimpanan atomik dan deteksi perubahan dari luar;
  - pemulihan sesi otomatis setiap 10 detik.
- Kompilasi dengan Free Pascal asli:
  - mode Turbo Pascal 7, Object Pascal, dan Delphi;
  - Compile, Make, Build, dan *primary file*;
  - unit path dan include path, range check dan overflow check;
  - daftar diagnostik yang melompat ke baris error;
  - ekspor executable native.
- Hasil build disimpan di cache terpisah. Build yang gagal tidak pernah menjalankan executable lama.
- Program native untuk Mac Intel (x86_64) dan Apple Silicon (arm64).
- User screen 80×25 berbasis pseudo-terminal, dengan dukungan `Crt` (warna, `GotoXY`, `ReadKey`, tombol fungsi) dan Turbo Vision lewat Free Vision.
- Debugging dengan LLDB: breakpoint, step, next, dan evaluasi ekspresi.
- Sepuluh contoh program berbahasa Indonesia, panduan, referensi Pascal, daftar pintasan, dan catatan kompatibilitas.
- Bundel `Odin Turbo Pascal.app` dan `Uninstall.command`.
- `Install.command`, yang:
  - mendeteksi CPU dan memeriksa dependensi;
  - mengompilasi lalu menjalankan program uji;
  - mencadangkan versi sebelumnya.
- Logo dan ikon orisinal:
  - **Emblem:** Odin bermata satu dengan helm bertanduk berkepala gagak, tombak Gungnir bermata petir, dan cincin rune.
  - **Wordmark:** "ODIN TURBO PASCAL".
  - **Tempat tampil:** desktop IDE, jendela About, ikon jendela dan Dock, serta ikon aplikasi.
  - **Sumber:** SVG di `assets/`, dirender dengan `scripts/render_logo.py`.
- Kredit "Created by Syams Ideris" di desktop, baris status saat startup, jendela About (juga dari menu About macOS), dan pemasang.

### Lisensi

Dirilis di bawah GNU General Public License v3.0 atau yang lebih baru. Jendela About menampilkan pemberitahuan hukum yang diwajibkan GPL.

### Pengujian

Ke-24 tes lulus di Mac Intel (macOS 15.7, Python 3.13, Tk 9.1, Free Pascal 3.2.2), termasuk 6 tes GUI dengan jendela Tk sungguhan.

Yang belum diverifikasi langsung: Apple Silicon, peluncuran lewat Finder/LaunchServices, Gatekeeper, dan sesi LLDB interaktif.

[Unreleased]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.2.0...HEAD
[2.2.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.1.0-alpha.1...v2.2.0
[2.1.0-alpha.1]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.0.1...v2.1.0-alpha.1
[2.0.1]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.0.0-alpha.2...v2.0.0
[2.0.0-alpha.2]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.0.0-alpha.1...v2.0.0-alpha.2
[2.0.0-alpha.1]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/releases/tag/v2.0.0-alpha.1
[1.0.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/releases/tag/v1.0.0
