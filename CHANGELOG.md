# Changelog

Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

Semua perubahan penting pada Odin Turbo Pascal dicatat di berkas ini. Formatnya mengikuti [Keep a Changelog](https://keepachangelog.com/id-ID/1.1.0/), dan nomor versinya mengikuti [Semantic Versioning](https://semver.org/lang/id/).

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

[1.0.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/releases/tag/v1.0.0
