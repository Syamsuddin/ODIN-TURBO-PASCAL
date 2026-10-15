# Changelog

Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

Semua perubahan penting pada Odin Turbo Pascal dicatat di berkas ini. Formatnya mengikuti [Keep a Changelog](https://keepachangelog.com/id-ID/1.1.0/), dan nomor versinya mengikuti [Semantic Versioning](https://semver.org/lang/id/).

## [Unreleased]

### Diubah

- Logo dan ikon aplikasi memakai logo ODIN Turbo Pascal dari proyek OTP v2.0: Odin bertambal mata, petir, dan buku `begin. end.`. Logo lengkap tampil di desktop IDE, jendela About, dan ikon besar. Ukuran ikon 64 px ke bawah dan banner README memakai emblemnya saja. Sumbernya `assets/odin-logo-master.png`, dirender dengan `scripts/render_logo.py` (sekarang butuh Pillow, bukan cairosvg). Sumber SVG logo lama dihapus.

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

[Unreleased]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.0.0-alpha.1...HEAD
[2.0.0-alpha.1]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/releases/tag/v2.0.0-alpha.1
[1.0.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/releases/tag/v1.0.0
