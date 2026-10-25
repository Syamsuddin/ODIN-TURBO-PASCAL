# Rencana OTP-Win: IDE berjendela modern

Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

Cabang `OTP-Win`, dibuat 23 Oktober 2026 dari `platform/tahap-10` (commit `1e63b6f`). Rilisnya **v3.0.0** (keputusan pemilik proyek): versi dinaikkan dengan `scripts/set_version.py 3.0.0` dan tag `v3.0.0` dibuat setelah W5 lulus, bukan sebelumnya, supaya tag tidak menunjuk ke IDE gaya DOS.

## Tujuan

IDE Odin Turbo Pascal menjadi aplikasi GUI biasa di setiap OS (macOS, Windows, Linux), bukan tiruan layar DOS. Keputusan pemilik proyek (direvisi 25 Oktober 2026 setelah meninjau versi bertab):

1. **GUI modern di semua OS.** "Win" berarti berjendela, bukan khusus Microsoft Windows. Widget `ttk` dengan tema OS (`aqua` di macOS, `vista` di Windows, `clam` di Linux), dialog file dan pesan milik OS.
2. **Menu teks di dalam jendela utama**, sama di semua OS: File Edit Search Run Compile Debug Options Window Help, masing-masing dropdown dengan submenu cascade (Open recent, Examples), Alt+huruf dan F10 membuka menu. Di macOS bar global hanya berisi menu aplikasi (About, Quit).
3. **Jendela child (MDI) di dalam jendela utama.** Editor, Output, Messages, Watches, Local variables, dan Call stack masing-masing punya title bar dengan tombol minimize, maximize, close; bisa digeser dan diubah ukurannya; menu Window berisi Tile, Cascade, Arrange icons, Zoom (F5), Next (F6), Close (Alt+F3), dan daftar jendela.
4. **Program berjalan di jendela Output** (konsol PTY, ConPTY di Windows) dengan input, warna, GotoXY Crt, mouse Odin Vision. Terminal OS tidak dipakai.
5. **IDE gaya DOS diganti total di cabang ini.** Gaya DOS tetap hidup di `main` dan cabang lain.

Versi bertab dengan Run di terminal OS (23 Oktober 2026, `launch.py`/`runner.py`) ditinggalkan dan dihapus. Dari situ yang tetap dipakai: `DebugSession` menerima sambungan TCP di thread pembaca (Tk tidak tertahan di Windows), editor dengan nomor baris dan tema terang/gelap, nama menu aplikasi macOS (`macos_app_name`).

Yang tidak berubah: bahasa, `odinpc`, RTL, Odin Vision, `core.py`, `console.py`/`terminal.py`, protokol debugger, `metrics.py`, jendela Graph, format `settings.json` dan `recovery.json`, pintasan Turbo Pascal (F9 Make, Ctrl+F9 Run, F7/F8, Ctrl+F8, Alt+F8 ...).

## Tata letak awal

Area kerja (abu-abu, dengan logo, nama, versi, kredit, hak cipta, dan lisensi di tengah) berisi: editor di bagian atas (64% tinggi, editor baru bertumpuk/cascade), Output di kiri bawah, Messages di kanan bawah. Watches, Local variables, dan Call stack bertumpuk di kanan area editor saat dibuka. Jendela yang di-minimize berjajar di dasar area kerja.

## Tahapan

Status 26 Oktober 2026: W1–W4 selesai; W5 selesai kecuali gambar. Pra-rilis **3.0.0-beta.1**: seluruh suite lulus di Mac Intel dan di CI lima runner (macOS Intel, macOS Apple Silicon, Ubuntu x86_64 dan arm64, Windows), keempat jenis pemasang dibangun di CI, dan `.pkg` Intel dipasang serta dibuka di Mac pengembang. Pra-rilis diterbitkan di GitHub (tag `v3.0.0-beta.1`, ditandai Pre-release; 2.9.0 tetap rilis stabil) dengan kelima pemasang, `odinpc.exe`, dan buku PDF. Fit Output membuat layar 80×25 selalu terlihat di jendela Output. Belum: tangkapan layar README dan `assets/banner.svg` (tampilan klasik), gambar layar buku, pemeriksaan di perangkat fisik Apple Silicon, Windows, dan Linux, lalu rilis v3.0.0 final.

| Tahap | Isi | Gerbang |
| --- | --- | --- |
| W1 | Jendela child: title bar, minimize/maximize/close, geser, ubah ukuran; Tile, Cascade, Arrange icons; menu Window | Tes geometri dan menu Window |
| W2 | Menu teks dalam jendela, toolbar, editor dengan nomor baris, breakpoint, tema; Output (PTY) dan Messages sebagai jendela child; status bar | IDE terbuka, Compile, Run di Output, lompat ke galat |
| W3 | Watches, Local variables, Call stack sebagai jendela child, Evaluate/Modify, penanda eksekusi | Sesi debug nyata lewat IDE |
| W4 | Ikon toolbar, dialog Options bertab, ukuran font konsol Output sendiri, simpan tata letak jendela | Semua menu lama punya padanan |
| W5 | `docs/HELP.txt`, `SHORTCUTS.txt`, README; `package_app.py`, `stage_windows.py`; CHANGELOG `[Unreleased]` | Seluruh suite hijau di Mac Intel; CI lima runner; lalu rilis v3.0.0 |

## Belum diuji (dijaga jujur di dokumen)

Tampilan hanya diperiksa lewat tes geometri di Mac Intel (tangkapan layar tidak bisa dibuat di sini). Windows, Linux, dan Apple Silicon belum diuji untuk cabang ini.
