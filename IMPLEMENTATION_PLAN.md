# Rencana Implementasi Toolchain Pascal Odin (Rust)

Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

Status: Tahap 0–7 dikerjakan di cabang `toolchain/tahap-0`, Tahap 8 di `platform/tahap-8`. Rencana disusun 15 Oktober 2026 dari kondisi repo pada commit `e7702a8`; ringkasan kemajuan ada di bagian 0.

Rilis **2.0.0-alpha.1** (15 Oktober 2026) memuat Tahap 0–7 (gerbang G1–G7). **2.0.0-alpha.2** di hari yang sama menambahkan logo baru dari proyek OTP v2.0 dan README yang diperbarui. Rilis **2.0.0** (juga 15 Oktober 2026) dimajukan oleh pemilik proyek: isinya sama dengan 2.0.0-alpha.2, jadi backend Odin tetap hanya untuk Mac Intel. Tahap 8–9 (AArch64, Linux, dan pelepasan FPC) menjadi rilis 2.1.0.

## 0. Status pelaksanaan (per 15 Oktober 2026)

Angka G0–G7 diukur di Mac pengembang: Intel x86_64, macOS 15.7, FPC 3.2.2 sebagai pembanding. G8 juga diukur di VM Lima dan di runner GitHub Actions.

| Gerbang | Status | Bukti |
| --- | --- | --- |
| G0 | Sebagian | S1 lolos (biner x86_64 dari linker sendiri jalan, termasuk ASLR). S2 lolos secara struktur (`codesign -v`, `dyld_info -validate_only`) tetapi belum dijalankan di Apple Silicon. S4 lolos (`test_extra_descriptors_reach_grandchildren`). Lisensi sudah diputuskan. **Belum:** S2 di perangkat arm64, S3 (Gatekeeper), S5 (Alt/Option). Ketiganya butuh pemilik proyek atau perangkat lain. |
| G1 | Lolos | Sepuluh contoh, `TORTURE.PAS`, dan 15 berkas korpus galat; posisi galat sama dengan FPC (`cargo test -p odin-syntax`). Pilihan backend di Options > Compiler, diagnostik JSON. |
| G2 | Lolos | Analisis semantik lengkap untuk bahasa prosedural TP7 (tanpa `object`). Korpus `tests/pascal/semantic/` (12 kasus) memeriksa kode, baris, dan kolom. |
| G3 | Lolos | HELLO, REKURSI, PARAMETER, INPUT, UNITDEMO, dan juga ARRAY, KALKULATOR, BERKAS dikompilasi Odin dengan keluaran identik dengan FPC. `test_real_gui_compile_and_run_odin` dan `test_interactive_pty_readln` (backend Odin) lolos. Korpus diferensial `tests/pascal/lang/` (6 program) identik. |
| G4 | Lolos | Kesepuluh contoh (termasuk CRTDEMO) dan semua `CompilerTests` lolos dengan backend `odin`, termasuk `test_crt_cursor_and_readkey`, `test_crt_function_keys`, dan `test_file_io_without_overwriting_existing_file`. `test_crt_screen_matches_fpc` membandingkan layar `Crt` (Window, scroll, InsLine/DelLine, warna) sel demi sel dengan FPC: identik. Korpus diferensial 62 program (`lang`, `lang2`, `files`, `numbers`, `strings`, `dos`, `runtime`) identik dengan FPC, kecuali satu ekspektasi tulisan tangan (`DEVIATIONS.md`). Unit `Crt`, `Dos`, `Strings`, `Printer` ada di `rtl/`. **Default backend sekarang `odin`**; FPC tetap bisa dipilih, dan dipakai otomatis bila `odinpc` tidak ditemukan. |
| G5 | Lolos | Menu Debug tidak lagi memanggil `lldb`. `tests/test_debugger.py` lolos: DebugSession tanpa Tk menjalankan REKURSI, berhenti di breakpoint (yang dipindah dari baris 8 ke 9), step into/over/out, mengevaluasi `N` di dua frame, membaca call stack tiga frame, lalu Modify `N := 5` yang mengubah keluaran (`3! = 360`). Tes juga memeriksa pause, Go to cursor, dan runtime error 216 di baris yang tepat. Tes GUI baru lolos: Tile dengan Watches/Call stack/Local variables, penanda `exec`, breakpoint yang bergeser saat baris disisipkan, recovery breakpoint, sesi debug nyata lewat IDE, dan Find error setelah Run biasa. Semua tes GUI lama tetap hijau. Korpus diferensial juga dijalankan dengan build `--debug`, dan hasilnya identik. |
| G6 | Lolos | Tipe `object` lengkap: pewarisan, `private`, VMT, constructor (`Fail`), destructor, `virtual`, `inherited`, `Self`, `TypeOf`, `New(P, Init)`, `New(PT, Init)`, `Dispose(P, Done)`, dan polimorfisme lewat pointer serta parameter `var`. Unit `rtl/objects.pas`: TObject, TPoint/TRect, TCollection/TSortedCollection/TStringCollection/TStrCollection, TStream/TDosStream/TBufStream/TMemoryStream, `RegisterType`, `Get`/`Put` polimorfik, NewStr/DisposeStr. Korpus `tests/pascal/objects/` (13 program, termasuk TStringCollection dan TBufStream) identik dengan FPC dalam build biasa dan build debug. Format stream (byte demi byte) dan ukuran tipe sama dengan Objects milik FPC. `test_object_fields_and_self` memeriksa tampilan field object di debugger. |
| G7 | Lolos | Odin Vision di `rtl/vision/`: Drivers, Memory, HistList, Views, Menus, Validate, Dialogs, App, MsgBox, StdDlg, Editors, Outline, dengan spesifikasi perilaku di `rtl/vision/SPEC.md`. Program uji Turbo Vision dari 1.0 (`uses Objects, Drivers, Views, Menus, Dialogs, App, MsgBox, StdDlg`) dibangun dan berjalan dengan backend `odin` (`OdinCompilerTests.test_standard_units_and_turbo_vision`). `tests/test_vision.py` lolos: tiga demo snapshot (menu lewat F10 dan mouse, Tile/Cascade, klik ke jendela belakang, dialog dengan validator picture, check box, radio button, klik mouse, MessageBox, editor, outline, prompt simpan saat Alt-X) dibandingkan sel demi sel (karakter dan warna) dengan snapshot yang sudah ditinjau, plus `TFileDialog` dan `TChDirDialog` di direktori sementara. `examples/VISION.PAS` berjalan di User screen IDE (`test_vision_example_in_user_screen`: klik mouse membuka menu Help, Alt+X keluar, layar sebelum program kembali), dan juga dikompilasi dengan backend FPC/Free Vision. `TerminalView` mengirim laporan mouse SGR dan urutan Alt/modifier. Korpus diferensial 77 program identik dengan FPC. **Belum:** Alt/Option dari keyboard Mac sungguhan (S5) baru diuji dengan event sintetis. |
| G8a | Lolos | CI GitHub Actions di lima runner (macOS Intel, macOS arm64, Ubuntu x86_64, Ubuntu arm64, Windows); VM Lima `odin-linux` (Ubuntu 24.04, dengan qemu-user dan Wine). Plumbing target di `odinpc`; korpus untuk target lain (`ODIN_CORPUS_TARGET`/`ODIN_CORPUS_RUNNER`). |
| G8b | Lolos | Linker ELF (PIE dinamis, glibc). Korpus 77 program (biasa dan debug) dan 92 tes Python dengan backend Odin lulus di VM dan di runner Ubuntu 24.04 x86_64. |
| G8c | Lolos (CI) | Encoder AArch64 (575 golden dari clang) dan codegen AArch64. Korpus lulus di aarch64 Linux (qemu dan runner Ubuntu arm64) dan native di runner macOS 15 Apple Silicon, bersama tes GUI, debugger, dan Odin Vision. Mac Apple Silicon fisik dan `Install.command` di sana belum diuji. |
| G8d | Lolos (CI) | Konvensi Win64 di codegen, linker PE32+, RTL Windows (UCRT, Win32, konsol VT, vectored exception handler), `odinpc.exe`, debugger lewat TCP 127.0.0.1, IDE dengan User screen ConPTY (Ctrl-C lewat helper yang menempel ke pseudoconsole). Di runner Windows Server 2025: korpus 77 program (biasa dan debug) identik dengan FPC 3.2.2 untuk Windows (`oracle.yml`), 93 tes Python lulus (GUI, debugger, Odin Vision), dan pemeriksaan pemasang (`check_windows.py`, `stage_windows.py`) lulus. `Install.ps1` lengkap belum dijalankan di PC Windows sungguhan. |

Perbedaan dari rencana yang sudah terjadi:

- `rust-toolchain.toml` tidak dipakai. Versi minimum dicatat sebagai `rust-version = "1.85"` di `Cargo.toml`, supaya tidak memaksa unduhan toolchain kedua (sisa disk di Mac pengembang terbatas).
- Kompilasi masih satu objek untuk seluruh program; cache unit `.ou` (Tahap 3) belum dibuat. Opsi `--cache` sudah diterima tetapi belum dipakai.
- Sesuai FPC, tanda minus unary mengikat ke faktor (`-1 and 3 = 3`) dan literal integer bertipe terkecil (`SizeOf(200) = 1`). Deviasi yang disengaja dicatat di `tests/pascal/DEVIATIONS.md`.
- Set selalu disimpan di memori (bukan di register), apa pun ukurannya.
- Alokasi register sederhana (Tahap 4) belum dibuat; codegen tetap menyimpan semua variabel di memori sampai Tahap 10.
- Shim untuk fungsi C variadik belum ada. Di x86-64 tidak masalah, tetapi di arm64 Apple argumen variadik lewat stack: `open` (argumen `mode`) di System dan `ioctl` di Crt harus dibungkus sebelum backend arm64 (Tahap 8) dipakai.
- Format bilangan real ada di `rtl/system/system.pas`, bukan berkas `realfmt.pas` terpisah.
- Pengecualian FPU *invalid*, *divide by zero*, dan *overflow* dibuka (unmask) di x86-64 seperti FPC, sehingga menjadi runtime error 207/200/205. Apple Silicon tidak mendukung trap FPU, jadi Tahap 8 perlu pemeriksaan eksplisit.
- Trek Pascal Odin Vision tidak dikembangkan dengan FPC sejak G0. Unit-unitnya ditulis setelah G6 dan langsung dikompilasi `odinpc`. `rtl/vision/SPEC.md` ditulis bersamaan dengan kode, bukan sebelumnya.
- Ukuran data dialog mengikuti TP7 (cluster 2 byte), bukan Free Vision. Seperti di FPC, record biasa disejajarkan, jadi record data dialog sebaiknya `packed record`.
- `ColorSel` dan `TextView` (opsional) belum dibuat. Pesan galat `odinpc` menyebutkannya.
- Rilis Tahap 8 dipadatkan atas permintaan pemilik proyek: sesudah 2.1.0-alpha.1 (8b dan 8c), Windows (8d) langsung dirilis sebagai 2.2.0, tanpa 2.1.0 final dan tanpa 2.2.0-alpha.N. Pemasang Apple Silicon dan Windows tetap belum diuji di perangkat fisik.
- Perbaikan compiler yang dibutuhkan Odin Vision: konstanta bertipe object (VMT ikut diisi), simbol konstanta lokal di metode bernama sama pada object berbeda, `Dispose` dengan typecast variabel, dan siklus unit lewat `uses` di bagian implementation. Semuanya punya program korpus (`OBJ_TCONST`, `LNG_UCYCLE`).
- `Printer` hanya diuji tanpa isi (tidak ada pekerjaan cetak yang dikirim ke `lpr`), supaya tes tidak mencetak ke printer pengembang.
- `Write` ke berkas dengan hook (misalnya `Crt`) di-flush per pernyataan lewat `ODIN_WRITE_END`, bukan per item, sama dengan TP dan FPC.
- Call stack debugger memakai *shadow stack* yang diisi prolog rutin (baris pemanggil, rutin, frame pointer), bukan penelusuran rantai fp. Hasilnya sama, dan lebih tahan terhadap frame RTL di tengah stack.
- Komunikasi program ↔ `odinpc debug` memakai satu Unix socket, bukan dua pipe, ditambah berkas memori bersama. Kontraknya ada di `rtl/COMPILER_INTERFACE.md` bagian 6.
- Tabel baris tidak ditanam di executable, tetapi selalu ditulis ke `NAME.odbg` di samping executable, termasuk untuk build tanpa `--debug`. RTL melaporkan runtime error lewat `$ODIN_ERROR_FILE`, sehingga Search > Find error juga bekerja untuk Run biasa.
- Mark breakpoint memakai gravity kanan, bukan kiri, supaya Enter di awal baris ikut menggeser breakpoint bersama kodenya.
- Step out berhenti di statement berikutnya pada frame yang lebih dangkal. Bila pemanggil tidak punya statement tersisa, tempat berhentinya bisa lebih jauh dari sekadar "setelah return".
- Constructor memakai ABI sendiri: `(Self, Vmt)`, mengembalikan `Self`, dan mengalokasikan object bila `Self = nil`. Dengan begitu `New(PT, Init)` menjadi panggilan biasa. Kontraknya ada di `rtl/COMPILER_INTERFACE.md` bagian 7.
- `ForEach`, `FirstThat`, dan `LastThat` memanggil aksinya dengan static link (R10), sehingga prosedur global pun benar. FPC hanya benar untuk prosedur lokal.
- Tipe object lokal di dalam prosedur ditolak (galat 148), sama seperti TP7. Bagian `protected` (FPC) belum didukung. Konstruktor open array (`[1, 2, 3]` untuk `array of`) juga belum didukung, karena itu fitur FPC/Delphi, bukan TP7.
- `packed record` kini benar-benar tanpa padding, sama dengan FPC.
- Untuk program dan unit FPC, System menyediakan `PtrInt`, `PtrUInt`, `SizeInt`, `SizeUInt`, dan `PPointer`. Builtin `Ofs` (alamat sebagai integer) dan `Seg` (selalu 0) juga tersedia.
- `README.md` dan `README.txt` masih menjelaskan LLDB versi 1.0.0. Keduanya ditulis ulang di Tahap 9, sedangkan Help di aplikasi (`docs/HELP.txt`, `docs/SHORTCUTS.txt`) sudah diperbarui.

Odin 1.0 meminjam semua pekerjaan berat dari pihak lain:

- **Free Pascal** untuk compiler, RTL, dan unit Turbo Vision (lewat Free Vision).
- **Xcode Command Line Tools** untuk assembler, linker, dan SDK.
- **LLDB** untuk debugger.

Rencana ini menggantikan semuanya dengan toolchain milik proyek sendiri, yang terdiri dari dua bagian. Compiler, assembler, linker, dan debugger ditulis dalam **Rust**. RTL, unit standar TP7, dan unit yang kompatibel dengan API Turbo Vision ditulis dalam **Pascal**. IDE Python/Tk beserta **sistem multi-window-nya tetap dipakai**.

---

## 1. Tujuan dan batasan

### Tujuan akhir

1. Pengguna cukup memasang Python 3.10+ dengan Tk. FPC, Xcode Command Line Tools, dan LLDB tidak lagi diperlukan.
2. Compile, Run, dan Debug hanya menjalankan kode milik proyek: `odinpc` (Rust), RTL, unit TP7, dan Odin Vision (Pascal).
3. Tampilan dan cara kerja IDE tidak berubah: desktop biru, jendela editor MDI, User screen 80×25, menu gaya TP, bar F-key, dan status bar (lihat bagian 4).

### Batasan

- **Bahasa yang didukung adalah Turbo Pascal 7 di platform 64-bit**, dengan perilaku yang sama seperti FPC `-Mtp` di Odin 1.0:
  - Integer 2 byte, LongInt 4 byte.
  - Real = Double (8 byte).
  - Pointer 8 byte.

  Setiap perbedaan yang disengaja dari perilaku ini dicatat di `tests/pascal/DEVIATIONS.md`.
- **Di luar cakupan**, sama seperti di `docs/COMPATIBILITY.txt` versi 1.0:
  - mode ObjFPC dan Delphi,
  - Graph/BGI dan Overlay,
  - akses DOS (`Mem`, `Port`, `Intr`, `absolute $Seg:$Ofs`),
  - kompatibilitas biner dengan DOS.
- **Platform:** macOS x86_64 dan arm64 adalah target utama. Linux x86_64 dan aarch64 didukung untuk CI dan pengguna Linux.
- **Clean-room.** Kode sumber FPC (compiler, RTL, Free Vision) dan Borland tidak boleh dibaca atau disalin. Rujukan yang boleh dipakai hanya dua:
  - dokumentasi publik tentang perilaku bahasa dan API,
  - pengamatan black-box atas keluaran program yang dikompilasi FPC.

  Siapa pun yang menulis RTL atau Odin Vision tidak boleh membuka sumber RTL FPC maupun Free Vision.
- **Rust tanpa crate pihak ketiga**, sepadan dengan aturan stdlib-only di sisi Python. JSON, SHA-256, parsing argumen, dan FFI libc yang kecil ditulis sendiri. Hasilnya: build bisa offline, audit lisensi sederhana, dan tidak ada rantai pasok yang perlu dipantau.

---

## 2. Inventaris bagian yang diganti

| Bagian sekarang | Asal | Pengganti | Tahap |
| --- | --- | --- | --- |
| Compiler `fpc`, dipanggil `build()` di `odin/core.py` | FPC 3.2.2 | `odinpc build` | 1–4 |
| Assembler (internal FPC, `as` Xcode) | FPC, Xcode CLT | crate `odin-asm` | 3, 8 |
| Linker `ld`, `xcrun --show-sdk-path`, tanda tangan ad-hoc dari `ld` | Xcode CLT | crate `odin-link` (Mach-O, ELF, tanda tangan kode) | 3, 8 |
| Unit `System` | RTL FPC | `rtl/system/` | 3–4 |
| `Crt`, `Dos`, `Strings`, `Printer` | RTL FPC | `rtl/*.pas` | 4 |
| `Objects` | RTL FPC | `rtl/objects.pas` | 6 |
| `App`, `Drivers`, `Views`, `Menus`, `Dialogs`, `MsgBox`, `StdDlg`, `Memory`, `HistList`, `Validate`, `Editors`, `Outline` | Free Vision | Odin Vision, `rtl/vision/` | 7 |
| Debugger LLDB di PTY | Xcode CLT | `odinpc debug`, hook RTL, jendela Watch/Locals/Call stack | 5 |
| `parse_diagnostics()` (regex keluaran FPC) | format FPC | diagnostik JSON dari `odinpc` | 1 |
| `free_vision_dir()` (jalan pintas karena unit `Menus` milik Apple) | FPC di macOS | dihapus | 9 |
| `locate_compiler()`, setting `compiler` dan `mode` | FPC | `locate_toolchain()`, setting dihapus | 9 |
| `Install.command`: `brew install fpc`, `xcode-select --install` | — | dihapus, diganti `odinpc selftest` | 9 |
| `scripts/check_mac.py`, `scripts/Validate-on-Mac.command` (`ODIN_FPC`) | FPC | `odinpc selftest` | 9 |
| `CompilerTests` yang di-skip bila FPC tidak ada | — | korpus `tests/pascal/` dengan ekspektasi tersimpan | 3–9 |
| Teks "Free Pascal" dan "LLDB" di About, Options, menu Debug, `README.md`, `README.txt`, `assets/banner.svg`, `docs/*.txt`, `THIRD_PARTY.txt`, `CLAUDE.md` | — | diperbarui | 5, 9 |

FPC masih dipakai di mesin pengembang, tetapi hanya sebagai pembanding (oracle) untuk membuat file ekspektasi tes. File ekspektasi disimpan di repo, sehingga tes bisa jalan tanpa FPC. Setelah Tahap 9, IDE tidak pernah lagi memanggil FPC.

---

## 3. Keputusan arsitektur

### 3.1 Gambaran besar

```
IDE Python/Tk (desain tetap)
  app.py / windows.py   desktop + jendela MDI: Editor, Watch, Locals, Call stack
  core.py   build() ───── subprocess, keluaran JSON ─────► odinpc build
  debugger.py  DebugSession ──── pipe JSON-lines ──────► odinpc debug
  terminal.py  PTY 80×25 ◄──── stdin/stdout ────┐              │ pipe hook + memori bersama
                                                 └── program native (build debug)

odinpc (Rust, satu biner):
  lexer → parser → sema → IR → codegen → assembler → linker → executable
  RTL + Odin Vision (sumber Pascal di rtl/) dikompilasi seperti unit biasa lalu di-cache
```

Lapisan Python tetap mengikuti aturan saat ini:

- `core.py` dan `debugger.py` tidak mengimpor Tk.
- Thread pekerja tidak pernah menyentuh Tk; semuanya lewat `App.messages` dan `poll()`.
- Tidak ada pemanggilan shell; semua argv dikirim sebagai list.

### 3.2 Satu biner dengan banyak perintah: `odinpc`

| Perintah | Fungsi |
| --- | --- |
| `odinpc build` | Kompilasi program dan unit, lalu tulis executable |
| `odinpc check` | Hanya analisis sintaks dan semantik (dipakai Tahap 1–2) |
| `odinpc debug` | Menjalankan program build debug dan melayani protokol debug IDE |
| `odinpc addr2line` | Memetakan alamat runtime error ke berkas dan baris (Search > Find error) |
| `odinpc selftest` | Kompilasi dan jalankan program uji, lalu periksa arsitektur CPU (pengganti `check_mac.py`) |
| `odinpc version` | Versi toolchain, target yang didukung, dan hash RTL |

Compiler dan debugger sengaja digabung dalam satu biner, dengan tiga alasan: cukup satu persetujuan Gatekeeper, cukup satu berkas yang ditandatangani, dan versi compiler dengan debugger dijamin selalu cocok.

### 3.3 Kompilasi whole-program dengan cache unit

- **Cache unit `.ou`** (padanan `.TPU`). Satu berkas `.ou` berisi antarmuka unit (simbol dan tipe), kode mesin yang bisa direlokasi, dan info debug. Kunci cache-nya adalah gabungan dari:
  - hash sumber,
  - hash antarmuka unit yang dipakai,
  - opsi build (`{$R}`, `{$Q}`, debug),
  - target,
  - versi `odinpc`.
- **Make (F9)** hanya mengompilasi ulang unit yang sumbernya berubah atau yang antarmuka dependensinya berubah. **Build** (`--build-all`) mengompilasi semuanya, menggantikan `-B` yang dipakai sekarang.
- **RTL dan Odin Vision** diperlakukan seperti unit biasa. Sumbernya ada di `rtl/`, dikompilasi sekali per versi `odinpc`, lalu di-cache di `data_dir()/build/units/<target>/`.
- **Smart linking.** Executable hanya berisi prosedur yang terjangkau dari program utama, ditambah VMT yang dipakai.
- **Pencarian berkas unit tidak peka huruf besar/kecil.** Ini perlu karena Linux peka huruf, sementara contoh memakai nama seperti `UMATH.PAS`.

### 3.4 Target dan ABI

| Target | Format | Akses OS | Urutan |
| --- | --- | --- | --- |
| `x86_64-darwin` | Mach-O | impor dinamis dari libSystem | Pertama, karena bisa diuji di Mac pengembang (Intel) |
| `aarch64-darwin` | Mach-O dengan tanda tangan ad-hoc (wajib) | libSystem | Tahap 8; butuh Mac Apple Silicon atau CI arm64 |
| `x86_64-linux`, `aarch64-linux` | ELF statis | syscall langsung | Tahap 8 |

- **macOS tidak menjamin ABI syscall yang stabil.** Karena itu program memanggil `/usr/lib/libSystem.B.dylib` lewat GOT yang diisi oleh dyld. Linker hanya menulis nama simbol dan path dylib, jadi SDK tidak diperlukan.
- **Konvensi panggil internal sama dengan ABI C platform** (SysV untuk x86-64, AAPCS64 varian Apple untuk arm64), supaya RTL bisa langsung memanggil libSystem. Aturan tambahan khusus Pascal:
  - static link dikirim sebagai parameter tersembunyi untuk prosedur bersarang;
  - fungsi yang mengembalikan string, record, atau set menerima pointer hasil tersembunyi;
  - parameter `var` dan `const` yang besar dikirim sebagai pointer;
  - parameter nilai yang besar disalin oleh callee.
- **Frame pointer selalu dipasang** (rbp di x86-64, x29 di arm64). Di arm64 Apple hal ini memang wajib, dan debugger memakainya untuk menelusuri call stack.
- **Jebakan: fungsi C variadik** (`open`, `fcntl`, `ioctl`). Di arm64 Apple, argumen variadik dikirim lewat stack. Fungsi-fungsi ini harus dipanggil lewat shim assembly di `rtl/system/arch/`, bukan lewat deklarasi `external` biasa.

### 3.5 Debugger berbasis instrumentasi

**Yang disisipkan compiler.** Hanya build debug (Debug > Start debugging) yang berisi hook; build biasa untuk Run tidak. Di setiap statement, compiler menyisipkan:

1. penulisan `cur_line := id`;
2. pemeriksaan murah `if dbg_flags[id] or dbg_pause then dbg_hook(id)`.

Selain itu, setiap prosedur menaikkan penghitung kedalaman saat masuk dan menurunkannya saat keluar.

**Memori bersama.** Tabel `dbg_flags` dan flag `dbg_pause` ada di berkas yang di-`mmap` bersama oleh program dan `odinpc debug`. Dengan cara ini, breakpoint dan Pause bisa diubah saat program sedang berjalan tanpa ptrace.

**Kanal pipe.** Hook berkomunikasi dengan `odinpc debug` lewat dua pipe. Nomor fd-nya dikirim lewat env `ODIN_DEBUG_FDS`. Selama program berhenti, kanal ini dipakai untuk baca/tulis memori dan perintah lanjut (bagian 6.3).

**Pembagian kerja.** Hook di sisi program sengaja dibuat sederhana. Semua kecerdasan ada di `odinpc debug`:

- tabel baris dan tipe dari berkas `.odbg`;
- penelusuran frame;
- evaluasi ekspresi Pascal, memakai parser dan pemeriksa tipe compiler yang sama.

**Yang tidak dipakai:** ptrace, `task_for_pid`, entitlement, maupun LLDB. Akibatnya perilaku debugger sama di macOS dan Linux.

**Sinyal.**

- Ctrl-C di User screen saat sesi debug: RTL menangkap SIGINT, menyalakan `dbg_pause`, dan program berhenti di statement berikutnya.
- Crash (SIGSEGV, SIGBUS, SIGFPE): handler RTL melaporkan kode runtime error gaya TP beserta baris terakhir.

**Batasan yang diterima:**

- Tidak ada step per instruksi.
- Unit tanpa info debug dilewati oleh Trace into.
- Mode debugger native lewat Mach/ptrace hanya opsi di Tahap 10.

### 3.6 RTL dalam Pascal yang bisa dikompilasi oleh dua compiler

- Unit di atas `System` (Crt, Dos, Strings, Printer, Objects, Odin Vision) ditulis dalam subset TP yang juga diterima FPC `-Mtp`.
- Deklarasi fungsi OS memakai bentuk yang juga dikenal FPC: `cdecl; external 'c' name 'write';`. `odinpc` menerima sintaks yang sama dan memetakan `'c'` ke libSystem di macOS.
- Manfaatnya: **Odin Vision dan RTL tingkat atas bisa dikembangkan dan dites dengan FPC sejak Tahap 0**, sebelum `odinpc` mendukung `object` di Tahap 6. Dengan begitu, trek RTL/Vision bisa berjalan paralel dengan trek compiler. Ini tetap clean-room, karena FPC hanya dipakai sebagai compiler untuk kode kita sendiri.
- Unit yang namanya bentrok dengan RTL FPC (`Crt`, `Dos`, `Objects`, `Strings`) dites dengan `-Fu rtl/` di urutan pertama. Kalau FPC tetap memilih unit miliknya, harness tes memakai nama alias sementara.
- `System` hanya dikompilasi oleh `odinpc`, karena FPC punya `System` sendiri.

### 3.7 Distribusi

- **Biner universal2** `odinpc` (x86_64 dan arm64) dibangun di mesin pengembang oleh `scripts/build_toolchain.py`, yang menjalankan `cargo build` untuk dua target lalu menggabungkannya dengan `lipo`. Setelah itu `scripts/package_app.py` menyalin `odinpc` ke `Contents/Resources/toolchain/odinpc` bersama `rtl/`. Pengguna tidak membutuhkan Rust maupun Xcode.
- **Gatekeeper.** Biner yang berasal dari zip unduhan akan berstatus karantina. `Install.command` menjalankan `odinpc selftest`, sehingga kalau macOS meminta persetujuan "Open Anyway", hal itu terjadi saat instalasi dengan petunjuk di layar. Installer tetap tidak menghapus atribut karantina, sesuai kebijakan yang sekarang. Perilaku ini **belum diverifikasi**; ujinya ada di Tahap 0 (S3) dan Tahap 9.
- **Kalau sudah punya Apple Developer ID:** tandatangani dan notarisasi `odinpc` serta `.app` (lihat keputusan terbuka 2).
- **Cadangan:** `scripts/build_toolchain.py --local` membangun dari sumber di Mac yang sudah punya Rust dan Xcode CLT. Biner hasil build lokal tidak berstatus karantina.

### 3.8 Lisensi RTL — sudah diputuskan

**Keputusan pemilik proyek (15 Oktober 2026):** seluruh repo, termasuk `rtl/` dan Odin Vision, berlisensi GPL-3.0-or-later **tanpa** pengecualian runtime.

Akibatnya:

- Program yang dikompilasi Odin memuat kode RTL secara statis, sehingga executable hasil kompilasi adalah karya turunan GPL. Siapa pun yang **mendistribusikan** executable itu wajib melakukannya di bawah GPL-3.0-or-later dan menyertakan sumbernya. Program yang hanya dipakai sendiri tidak terkena kewajiban apa pun.
- Hal ini harus dijelaskan kepada pengguna di `README.txt`, `docs/HELP.txt`, dan `docs/COMPATIBILITY.txt` pada Tahap 9. Perlu diingat bahwa Odin 1.0 memakai RTL FPC, yang punya pengecualian static linking.
- Template File > New tetap tanpa notice, karena kode sumber program tetap milik pengguna.
- Berkas RTL memakai header Pascal yang biasa (bagian 5), tanpa `RUNTIME-EXCEPTION.txt`.
- `odinpc` menautkan pustaka standar Rust secara statis (lisensi MIT OR Apache-2.0), jadi `THIRD_PARTY.txt` wajib menyebutkannya.

---

## 4. Sistem multi-window yang dipertahankan

### 4.1 Hal yang tidak boleh berubah

| Aspek | Kondisi sekarang yang dipertahankan |
| --- | --- |
| Desktop | Frame biru dengan logo, kredit penulis, dan watermark |
| Jendela editor | Frame MDI yang di-`place` di desktop, dengan title bar `[■]`/`[↕]`, drag, zoom (double-click atau F5), dan gutter breakpoint |
| Window | Tile, Cascade, Zoom, Next (F6), Close (Alt+F3), List |
| User screen | `Toplevel` terpisah berisi `TerminalView` 80×25, toolbar Copy screen/Editor/Stop, Alt+F5 |
| Menu | Sembilan menu utama: File, Edit, Search, Run, Compile, Debug, Options, Window, Help (`test_menus_dialogs_and_terminal` memeriksa ini) |
| Bar F-key dan status bar | Warna, isi, dan banner "Created by" |
| Dialog | Pola `App.dialog()` dan `App.input()` |
| Threading | `messages` diproses `poll()` tiap 40 ms; pekerja tidak menyentuh Tk |
| Sesi | Kunci single-instance, autosave `recovery.json` tiap 10 detik |

### 4.2 Perubahan yang menambah tanpa membongkar

**1. Refactor `DesktopWindow` (Tahap 5a).** Ini refactor murni tanpa perubahan perilaku, dan boleh dikerjakan kapan saja.

- Ambil frame, title bar, drag, zoom, dan tombol tutup dari `Editor` menjadi kelas dasar `DesktopWindow`, lalu pindahkan ke `odin/windows.py`.
- `Editor` menjadi turunan `DesktopWindow`.
- `App.windows` menyimpan semua jendela desktop dan dipakai oleh `tile`, `cascade`, `zoom`, `next_editor`, `window_list`, dan `activate`.
- `App.editors` tetap ada sebagai daftar jendela yang punya dokumen, untuk Save all, recovery, breakpoint, dan Compile.
- `close_editor` menjadi `close_window`; dialog Save changes hanya muncul untuk `Editor`.
- `update_status` hanya membaca posisi kursor kalau jendela aktif adalah `Editor`.
- Pagar pengamannya adalah `test_window_layout_and_cancelled_close` dan seluruh `tests/test_gui.py`, yang harus hijau tanpa diubah.

**2. Jendela debug baru** sebagai turunan `DesktopWindow`, sehingga ikut diatur oleh Tile, Cascade, dan List:

- **Watch:** posisi awal di strip bawah desktop seperti TP. Insert untuk menambah, Delete untuk menghapus, Enter untuk mengedit. Nilainya diperbarui setiap kali program berhenti.
- **Locals:** isi frame terpilih, menggantikan perintah LLDB `frame variable`.
- **Call stack:** daftar frame. Double-click membuka editor di baris frame tersebut dan menjadikannya frame aktif untuk Watch dan Locals.

**3. Editor:**

- Tag `exec` menandai baris eksekusi, dengan warna yang berbeda dari tag `error` dan `found`.
- Breakpoint disimpan sebagai *mark* Tk dengan gravity kiri, sehingga ikut bergeser saat baris disisipkan atau dihapus. `Document.breakpoints` dihitung ulang dari mark.
- `recovery.json` mendapat field `breakpoints`. Sesi lama tanpa field ini tetap bisa dipulihkan.
- Kalau sumber diedit di tengah sesi debug, perintah step berikutnya menanyakan "Sumber berubah. Build ulang?" seperti TP.

**4. Menu dan shortcut.** Menu utama tetap sembilan. Isi menu Debug menjadi:

- Start debugging
- Step over (F8)
- Trace into (F7)
- Go to cursor (F4, saat ini belum dipakai)
- Continue
- Toggle breakpoint (Ctrl+F8)
- Clear breakpoints
- Watch window
- Add watch...
- Local variables
- Call stack
- Evaluate/Modify... (Ctrl+F7, sama seperti sekarang)

Perubahan lain:

- Search mendapat item **Find error** untuk runtime error.
- Run > Run (Ctrl+F9) saat program sedang berhenti di debugger berarti Continue, seperti di TP.
- Penyelarasan shortcut ke TP7 (Ctrl+F4 untuk Evaluate, Ctrl+F7 untuk Add watch) masih menjadi keputusan terbuka 5.

**5. User screen:**

- Judul menjadi "Odin • User screen". Selama sesi debug, isinya murni layar program.
- F7/F8 di jendela ini dikirim ke sesi debug, bukan diketik ke PTY.
- Untuk Odin Vision (Tahap 7a), `Screen` dan `TerminalView` diperluas dengan laporan mouse xterm (mode 1000/1002/1006) dan urutan Alt/Option. Ini hanya mengubah isi jendela, bukan sistem jendelanya.

**6. Options > Compiler:**

- Ada pilihan backend (Odin native / Free Pascal) sampai Tahap 9.
- Label "Debug information for LLDB" menjadi "Debug information".
- Pilihan mode ObjFPC/Delphi dinonaktifkan untuk backend Odin.

---

## 5. Struktur repo baru

```
toolchain/                      Cargo workspace, edition 2024, tanpa crate pihak ketiga
  Cargo.toml                    [workspace.package] license = "GPL-3.0-or-later"
  rust-toolchain.toml           versi stable dipatok di Tahap 0
  crates/
    odin-base/                  Span, SourceMap, Diagnostic + katalog pesan Indonesia,
                                interner, JSON mini, SHA-256, FFI libc kecil (modul sys)
    odin-syntax/                lexer, direktif + kompilasi bersyarat, include, parser, AST, dump AST
    odin-sema/                  scope, simbol, tipe, konstanta, rutin bawaan, antarmuka unit
    odin-ir/                    IR, lowering AST→IR, pemeriksaan runtime, verifier, dump IR
    odin-codegen/               seleksi instruksi, layout frame, alokasi register
      src/x86_64/  src/aarch64/
    odin-asm/                   encoder x86-64 dan AArch64, label/fixup, relaksasi cabang, parser .s
    odin-link/                  resolusi simbol, smart linking, relokasi, Mach-O, ELF, tanda tangan ad-hoc
    odin-debuginfo/             tabel baris, scope/variabel/tipe, format .odbg, tabel baris tertanam
    odin-unitcache/             format .ou dan logika Make
    odin-debug/                 sesi debug, protokol hook, evaluator ekspresi, format nilai gaya TP
    odinpc/                     biner: build, check, debug, addr2line, selftest, version
  tests/                        tes integrasi dan runner korpus tests/pascal
rtl/
  RUNTIME-EXCEPTION.txt         setelah keputusan 3.8
  system/                       system.pas, textio.pas, realfmt.pas, heap.pas, sets.pas,
                                strops.pas, runerr.pas, debughook.pas, os_darwin.pas, os_linux.pas
    arch/                       x86_64-darwin.s, aarch64-darwin.s, x86_64-linux.s, aarch64-linux.s
  crt.pas  dos.pas  strings.pas  printer.pas  objects.pas
  vision/
    SPEC.md                     spesifikasi perilaku clean-room, ditulis sebelum kode
    drivers.pas memory.pas views.pas menus.pas dialogs.pas app.pas msgbox.pas
    stddlg.pas histlist.pas validate.pas editors.pas outline.pas
    colorsel.pas textview.pas   opsional, karena Free Vision pun tidak menyediakannya
odin/
  core.py                       build() memanggil odinpc; locate_toolchain()
  debugger.py                   BARU, tanpa Tk: DebugSession (proses, pipe, thread pembaca)
  windows.py                    BARU: DesktopWindow, Editor, WatchWindow, LocalsWindow, StackWindow
  terminal.py                   Process(pass_fds=...), mode mouse, Alt
  app.py                        App (menu, dialog, orkestrasi)
tests/
  pascal/                       lang/ rtl/ crt/ objects/ errors/ debug/ vision/
                                tiap kasus: X.pas (+ X.in, X.args, X.out, X.code, X.err)
  pascal/DEVIATIONS.md          perbedaan perilaku yang disengaja dari FPC -Mtp
  test_core.py  test_gui.py  test_debugger.py  test_vision.py
scripts/
  build_toolchain.py  oracle.py  gen_asm_golden.py  update_checksums.py   (ditambah skrip yang sudah ada)
```

Setiap berkas baru diberi header lisensi:

- **Rust:** `// SPDX-License-Identifier: GPL-3.0-or-later` dan `// Copyright (c) 2026 Syams Ideris`.
- **Pascal di `rtl/`:** `{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }`, ditambah rujukan ke pengecualian runtime setelah keputusan 3.8.
- **Python dan skrip:** mengikuti `CLAUDE.md`.

---

## 6. Antarmuka IDE ↔ toolchain

### 6.1 Build

```
odinpc build SOURCE --out EXE --cache DIR --rtl DIR
        [--unit-path P]... [--include-path P]...
        [--range-checks|--no-range-checks] [--overflow-checks|--no-overflow-checks]
        [--debug] [--build-all] [--target x86_64-darwin] --diag-format json
```

Setiap baris stdout berisi satu objek JSON:

```json
{"type":"diagnostic","severity":"error","code":85,"file":"/abs/X.PAS","line":3,"column":12,"end_line":3,"end_column":13,"message":"\";\" diharapkan"}
{"type":"progress","unit":"CRT","state":"compiling"}
{"type":"result","success":true,"executable":"/abs/X","debug_info":"/abs/X.odbg","lines":123,"units":["SYSTEM","CRT"],"elapsed_ms":42}
```

**Kode keluar:** 0 berarti sukses, 1 berarti ada galat kompilasi, 2 berarti salah pemakaian atau galat internal (teks di stderr). Untuk galat internal, IDE menampilkan "Kesalahan internal compiler" lalu menulis detailnya ke `last-error.log`.

**Pemetaan di `core.build()`:**

- Nilai `severity` dipetakan ke `Diagnostic.kind` (`Fatal`, `Error`, `Warning`, `Note`, `Hint`).
- `BuildResult` tidak berubah bentuknya. Karena itu Compiler messages, Go to error, dan Next error di `app.py` tetap jalan.
- `BuildResult.output` diisi teks ringkasan yang mudah dibaca, misalnya "Compile successful: 123 lines".

**Nomor galat** mengikuti penomoran TP7 bila ada padanannya, misalnya 85 untuk `";" expected`. Teks pesannya ditulis sendiri dalam bahasa Indonesia.

### 6.2 Protokol debug IDE ↔ `odinpc debug` (JSON-lines)

IDE menjalankan program debug lewat `Process` seperti yang sudah ada sekarang, dengan argv berikut:

```
odinpc debug --exe EXE --odbg EXE.odbg --ide-fds R,W -- ARGS...
```

- PTY menjadi terminal milik `odinpc debug`, dan program anak mewarisinya, sama seperti LLDB sekarang.
- `Process` mendapat parameter `pass_fds` (sekarang ia memakai `close_fds=True` tanpa pengecualian).
- `odinpc debug` mengabaikan SIGINT, sehingga Ctrl-C hanya menghentikan sementara program.

| Arah | Pesan |
| --- | --- |
| IDE → | `start`, `continue`, `step_into`, `step_over`, `step_out`, `run_to {file,line}`, `pause`, `set_breakpoints {file,lines}`, `evaluate {id,expr,frame}`, `modify {id,expr,value,frame}`, `stack {id}`, `locals {id,frame}`, `terminate` |
| → IDE | `ready`, `stopped {reason: entry/breakpoint/step/pause/runtime_error, file, line, depth}`, `breakpoints {file, verified, moved, rejected}`, `result {id, ok, value, type}`, `runtime_error {code, file, line}`, `exited {code}`, `error {message}` |

- Breakpoint yang dipasang di baris tanpa kode dipindahkan ke baris berikutnya yang punya kode. Pemindahan itu dilaporkan lewat `moved`, sehingga titik merah di gutter ikut pindah.
- `odin/debugger.py` membaca pipe di thread terpisah dan mendorong `("debug", event)` ke `App.messages`. `poll()` lalu memperbarui editor dan jendela debug.

### 6.3 Protokol hook (program ↔ `odinpc debug`)

Bentuknya frame biner little-endian di dua pipe, ditambah satu berkas memori bersama yang berisi `dbg_flags[]` dan `dbg_pause`.

| Arah | Frame |
| --- | --- |
| program → | `HELLO(image_base u64, protocol u16)`; `STOP(line_id u32, depth u32, fp u64, reason u8)`; `RTERR(code u16, addr u64, line_id u32)`; `EXIT(code i32)` |
| → program | `RESUME(mode u8: run/into/over/out, target_depth u32)`; `READ(addr u64, len u32)` dibalas `DATA(bytes)`; `WRITE(addr u64, bytes)` dibalas `ACK` |

- `image_base` diperlukan karena executable bersifat PIE (alamatnya acak saat dimuat).
- Semua alamat di `.odbg` disimpan relatif terhadap basis image.

### 6.4 Berkas `.odbg`

Ditulis compiler di samping executable dalam format JSON berversi. Isinya:

- daftar berkas;
- tabel baris (`line_id` → berkas, baris, offset kode);
- prosedur (nama, unit, rentang alamat, layout frame, parameter dan variabel lokal dengan offset terhadap fp, static link);
- variabel global;
- tipe (ordinal, enum, subrange, set, array, record varian, string[N], pointer, file, prosedural, object beserta VMT).

Selain `.odbg`, tabel baris yang ringkas juga ditanam di executable. Dengan begitu `odinpc addr2line` dan pesan runtime error tetap bisa menunjuk baris sumber meski program dibangun tanpa mode debug.

---

## 7. Tahapan

Urutan dan dependensi:

```
T0 ─► T1 ─► T2 ─► T3 ─► T4 ─► T5 ─► T6 ─► T7(kompilasi odinpc) ─► T9
                          └────► T8 (arm64 + Linux, bisa paralel dengan T5–T7 bila ada perangkat arm64)
T5a (refactor DesktopWindow, Python murni) : kapan saja sebelum T5
T7 trek Pascal (Odin Vision dengan FPC)    : mulai setelah T0, paralel dengan T1–T6
```

Setiap tahap ditutup oleh sebuah **gerbang**. Tahap berikutnya baru boleh dimulai setelah gerbangnya lolos. Sebelum G4, backend Odin hanya bisa diaktifkan lewat setting `backend`, dan FPC tetap menjadi default.

### Tahap 0 — Persiapan dan spike kelayakan

**Pekerjaan:**

- Pasang rustup di Mac pengembang, patok versi stable di `rust-toolchain.toml`, siapkan workspace kosong dan CI.
- **S1:** prototipe `odin-link` menulis Mach-O x86_64 yang memanggil `write` dan `exit` dari libSystem. Berkas ditulis, diberi `chmod +x`, dijalankan, lalu diperiksa keluarannya `hello` dengan exit code 3.
- **S2:** hal yang sama untuk arm64 plus tanda tangan ad-hoc buatan sendiri. Struktur tanda tangan diperiksa dengan `codesign -v` (khusus tes), lalu biner dijalankan di Apple Silicon.
- **S3:** uji Gatekeeper. Zip berisi `odinpc` yang diberi atribut karantina dijalankan dari subprocess Python. Catat perilakunya di Mac Intel ini, dan di arm64 bila perangkatnya tersedia.
- **S4:** prototipe kanal debug. `Process` dengan `pass_fds` menjalankan biner Rust yang kemudian menjalankan program anak di PTY. Pastikan Ctrl-C dan Stop bekerja pada process group.
- **S5:** catat urutan byte yang dikirim `TerminalView` untuk Alt/Option di macOS. Free Vision 1.0 menerima Alt-X; Odin Vision harus mendekode urutan yang sama.
- Ambil keputusan lisensi RTL (3.8).
- Mulai menulis `rtl/vision/SPEC.md` dan siapkan harness FPC untuk trek Pascal (3.6).

**Gerbang G0:**

- S1, S4, dan S5 lolos di Mac pengembang.
- S2 lolos minimal secara struktur. Kalau belum ada perangkat arm64, S2 dicatat sebagai risiko terbuka.
- Hasil S3 terdokumentasi.
- Keputusan 3.8 sudah diambil.

### Tahap 1 — Fondasi dan sintaks

**Rust:**

- `odin-base`:
  - SourceMap dan Span, dengan kolom dihitung seperti FPC (satu karakter = satu kolom).
  - `Diagnostic` dan katalog pesan Indonesia dengan nomor TP7.
  - Interner, JSON mini, dan SHA-256.
- `odin-syntax`, lexer:
  - identifier tidak peka huruf;
  - komentar `{ }`, `(* *)`, dan `//`;
  - string dengan `''`, `#13`, dan notasi `^M`;
  - angka dengan `$hex` dan eksponen.
- `odin-syntax`, direktif:
  - `{$I+/-}`, `{$R+/-}`, `{$Q+/-}`, `{$B}`, `{$V}`, `{$X}`;
  - `{$I file}`, `{$DEFINE}`, `{$IFDEF}`, `{$IFNDEF}`, `{$ELSE}`, `{$ENDIF}`;
  - direktif lain diabaikan dengan hint;
  - simbol bawaan: `ODIN`, `VER70`, `CPUX86_64` atau `CPUAARCH64`, `DARWIN` atau `LINUX`.
- `odin-syntax`, parser recursive descent untuk **seluruh** grammar TP7, termasuk `object`, `asm` (ditangkap mentah), `goto`/`label`, `forward`, dan `external`. Hasilnya AST lengkap dengan span dan `--dump-ast` untuk golden test.
- Perilaku TP: kompilasi berhenti di galat pertama. Opsi `--max-errors` tersedia untuk tooling.
- `odinpc check` dan `odinpc version`.

**Python:**

- Tambahkan `locate_toolchain()` dengan urutan pencarian:
  1. env `ODIN_TOOLCHAIN`,
  2. `ASSETS/toolchain/odinpc` (di dalam bundle),
  3. `toolchain/target/release/odinpc` (build pengembang di repo).
- Setting `backend` di `DEFAULTS` dengan nilai `"fpc"` atau `"odin"`, divalidasi seperti `mode`, dan dimasukkan ke cache key.
- Radio backend di Options > Compiler.
- Selama Tahap 1–2, backend Odin menjalankan `check` saja dan memberi tahu bahwa executable belum bisa dibuat.

**Tes:**

- Unit test lexer dan parser.
- Golden AST untuk kesepuluh contoh.
- Korpus `tests/pascal/errors/` dengan berkas `.err`.

**Gerbang G1:**

- Semua contoh, seluruh korpus valid, dan stub RTL berhasil di-parse.
- Untuk korpus galat, baris dan kolom sama dengan FPC. Selisih kolom yang disengaja dicatat di `DEVIATIONS.md`.

### Tahap 2 — Analisis semantik dan unit

**Rust (`odin-sema`):**

- **Scope:** antarmuka dan implementasi unit, prosedur bersarang, `with`, dan anggota record.
- **Tipe:**
  - ordinal (Integer, LongInt, ShortInt, Byte, Word, Char, Boolean), enum, dan subrange;
  - set, array (multidimensi; `packed` diterima), dan record (dengan bagian varian);
  - `string` dan `string[N]`, pointer, file, Text, tipe prosedural;
  - `object` di-parse sekarang, semantiknya di Tahap 6.
- **Evaluasi konstanta**, termasuk konstanta bertipe berstruktur.
- **Aturan kompatibilitas** penugasan dan parameter.
- **Rutin bawaan** sebagai pseudo-prosedur:
  - I/O: `Write`, `WriteLn`, `Read`, `ReadLn`;
  - `Inc`, `Dec`, `New`, `Dispose`, `High`, `Low`, `SizeOf`;
  - `Ord`, `Chr`, `Succ`, `Pred`;
  - `Str`, `Val`, `Copy`, `Concat`;
  - `Exit`, `Halt`, dan lainnya.
- **Perluasan tipe integer** dalam ekspresi mengikuti FPC `-Mtp`. Contohnya `Integer*Integer` (lihat `UMATH.PAS`, yang sengaja menulis `LongInt(X) * X`) dikunci lewat tes diferensial.
- **`odin-unitcache`:** format `.ou` (bagian antarmuka saja dulu), graf dependensi, dan deteksi siklus `uses`.

**Python:** galat dari `odinpc check` tampil di Compiler messages, dan Go to error berfungsi.

**Gerbang G2:**

- `odinpc check` menerima semua program valid di korpus, termasuk kesepuluh contoh.
- Program di korpus galat ditolak dengan kode yang benar.

### Tahap 3 — Program native pertama (x86_64-darwin)

**Rust:**

- **`odin-ir`:**
  - lowering untuk statement, ekspresi, dan prosedur bersarang (static link);
  - parameter `var`;
  - hasil fungsi lewat variabel bernama fungsi;
  - pemeriksaan runtime `{$R+}` (201), `{$Q+}` (215), `{$I+}`, dan pembagian nol (200).
- **`odin-codegen` x86_64**, versi naif:
  - semua nilai di slot stack, dengan register scratch tetap;
  - ABI SysV;
  - frame rbp;
  - perhitungan alamat global relatif RIP.
- **`odin-asm` x86_64:**
  - encoder untuk subset yang dipakai codegen: mov, lea, aritmetika, imul/idiv, cmp/jcc/setcc, call/ret, push/pop, movzx/movsx, dan SSE2 skalar;
  - label, fixup, dan relaksasi jump pendek/dekat;
  - parser berkas `.s` bersintaks Intel.
- **`odin-link` Mach-O x86_64:** segmen dan load command yang dibutuhkan dyld, impor libSystem lewat GOT, `LC_MAIN`, `LC_BUILD_VERSION` (minos 11.0, sama dengan Info.plist), serta tanda tangan ad-hoc (opsional di x86_64, tetap ditulis). Format fixup (chained fixups atau dyld info) diputuskan dari hasil S1.
- **`odin-unitcache`:** kode mesin dan relokasi disimpan per unit; logika Make.

**Pascal:** RTL minimal di `rtl/system/`:

- entri `main` yang menyimpan argc/argv;
- `Halt` dan `ExitCode`;
- `Write`/`WriteLn` untuk Integer, LongInt, Char, String, dan Boolean, dengan lebar `:w`;
- `ReadLn` untuk Integer dan String;
- `ParamCount` dan `ParamStr`;
- laporan `Runtime error N at $ADDR` dalam format TP;
- buffer `Output` di-flush sebelum membaca `Input` dan saat `Halt`, supaya prompt muncul di PTY sebelum `ReadLn`.

**Python:**

- `build()` dengan backend `odin` memanggil `odinpc build` dan mem-parse JSON (6.1).
- Opsi Build dipetakan ke `--build-all`.

**Gerbang G3:**

- HELLO, REKURSI, PARAMETER, INPUT, dan UNITDEMO menghasilkan keluaran identik dengan FPC di runner korpus.
- `test_real_gui_compile_and_run` lolos dengan backend `odin`.
- `test_interactive_pty_readln` lolos dengan backend `odin`.

### Tahap 4 — Bahasa prosedural lengkap dan RTL standar

**Rust:**

- Codegen untuk:
  - Real (SSE2), set (bitset 32 byte), dan enum;
  - record varian, pointer, dan heap;
  - `case` dengan rentang, `with`, `goto`/`label`;
  - konstanta bertipe, tipe prosedural;
  - parameter open array dan open string;
  - `absolute` (alias variabel, bukan segmen:offset);
  - fungsi `external cdecl` dan shim variadik.
- Alokasi register sederhana di dalam satu basic block, sebagai jembatan sebelum Tahap 10.

**Pascal: `System` lengkap** sesuai daftar di `docs/COMPATIBILITY.txt`:

- **String:** `Copy`, `Delete`, `Insert`, `Pos`, `Length`, `UpCase`, `Concat`.
- **Matematika:** `Abs`, `Sqr`, `Sqrt`, `Sin`, `Cos`, `ArcTan`, `Exp`, `Ln`, `Int`, `Frac`, `Round`, `Trunc`, `Random`, `Randomize`.
- **Konversi:** `Str`/`Val` dan format Real `:w:d` serta format bawaan. Implementasinya memakai aritmetika desimal eksak di `realfmt.pas`, dengan vektor uji dari FPC.
- **Berkas:** Text, berkas bertipe, dan berkas tanpa tipe. Rutinnya: `Assign`, `Reset`, `Rewrite`, `Append`, `Close`, `Erase`, `Rename`, `Eof`, `Eoln`, `SeekEof`, `SeekEoln`, `Flush`, `BlockRead`, `BlockWrite`, `Seek`, `FilePos`, `FileSize`, `Truncate`, `IOResult`.
- **Direktori:** `ChDir`, `MkDir`, `RmDir`, `GetDir`.
- **Heap dan memori:** `New`, `Dispose`, `GetMem`, `FreeMem`, `FillChar`, `Move`.
- **Lain-lain:** `Include`/`Exclude`, `ExitProc`, `ErrorAddr`.

**Pascal: unit standar lain**

- **`Crt`**, di atas termios dan escape ANSI, dengan buffer bayangan layar yang nanti dipakai bersama Odin Vision:
  - `ClrScr`, `GotoXY`, `WhereX`/`WhereY`;
  - `TextColor`, `TextBackground`, `TextAttr`, `LowVideo`, `HighVideo`, `NormVideo`;
  - `Window`, `ClrEol`, `DelLine`, `InsLine`;
  - `Delay`, `Sound`/`NoSound` (tanpa efek suara), `KeyPressed`;
  - `ReadKey` dengan kode scan TP: F1–F10 = 59–68, F11/F12 = 133/134, Insert = 82, Up = 72;
  - `CheckBreak`, `TextMode`, `AssignCrt`.
- **`Dos`:**
  - `GetDate`, `GetTime`;
  - `GetEnv`, `EnvCount`, `EnvStr`;
  - `FSplit`, `FExpand`, `FSearch`;
  - `FindFirst`/`FindNext`/`FindClose` dengan pencocokan wildcard sendiri;
  - `DiskFree`, `DiskSize`;
  - `GetFAttr`, `GetFTime`, `PackTime`, `UnpackTime`;
  - `Exec` (lewat `posix_spawn`), `DosExitCode`, `DosVersion`.
- **`Strings`:** rutin PChar.
- **`Printer`:** `Lst` diteruskan ke `/usr/bin/lpr`, sama seperti 1.0.

**Python:** program yang memakai unit Vision sebelum Tahap 7 mendapat pesan jelas: "Unit App belum tersedia di backend Odin; pilih backend Free Pascal".

**Gerbang G4:**

- Kesepuluh contoh dan semua `CompilerTests` lolos dengan backend `odin`, kecuali bagian Objects dan Turbo Vision. Termasuk dalam hitungan ini `test_crt_cursor_and_readkey`, `test_crt_function_keys`, dan `test_file_io_without_overwriting_existing_file`.
- **Default backend dipindah ke `odin`.** FPC tetap bisa dipilih.

### Tahap 5 — Debugger dan jendela debug

- **5a. Python:** refactor `DesktopWindow` (bagian 4.2 no. 1). Boleh dikerjakan lebih awal.
- **5b. Rust (compiler):**
  - opsi `--debug` menyisipkan hook, `cur_line`, dan penghitung kedalaman;
  - menulis berkas `.odbg`;
  - menanam tabel baris di setiap build.
- **5c. Pascal:** `debughook.pas`:
  - `HELLO`/`STOP`/`RESUME`/`READ`/`WRITE`;
  - `mmap` memori bersama;
  - handler SIGINT untuk pause;
  - handler crash yang mengirim `RTERR`.
- **5d. Rust (`odin-debug`):**
  - menjalankan program dan menangani protokol 6.2 dan 6.3;
  - stepping into/over/out dan run-to-cursor berbasis kedalaman;
  - penelusuran frame lewat rantai fp;
  - evaluator ekspresi yang memakai parser dan sema: variabel, field, indeks dengan cek batas, `^`, aritmetika dan perbandingan, typecast, `Ord`/`Chr`/`Length`/`High`/`Low`/`SizeOf`, tanpa pemanggilan fungsi;
  - Modify (tulis nilai);
  - format nilai gaya TP: `'abc'`, `(1, 2, 3)`, `(X:1; Y:2)`, `[1, 3..5]`, `TRUE`, `PTR($...)`, nama enum.
- **5e. Python:**
  - `odin/debugger.py`;
  - jendela Watch, Locals, dan Call stack;
  - tag `exec` dan breakpoint sebagai mark;
  - field `breakpoints` di recovery;
  - menu Debug versi baru dan Search > Find error;
  - User screen tanpa LLDB.

**Gerbang G5:**

- Menu Debug tidak lagi memanggil `lldb`.
- `tests/test_debugger.py` lolos: DebugSession tanpa Tk menjalankan REKURSI, berhenti di breakpoint, step over/into/out, mengevaluasi `N`, membaca call stack sedalam N frame, lalu menjalankan Modify.
- Tes GUI baru lolos: Tile dengan jendela Watch, penanda `exec`, breakpoint yang bergeser saat baris disisipkan, dan recovery breakpoint.
- Semua tes GUI lama tetap hijau.

### Tahap 6 — Model object TP dan unit `Objects`

**Rust:**

- tipe `object` dengan pewarisan dan bagian `private`/`public`;
- VMT, `constructor` (inisialisasi VMT, `Fail`), `destructor`, `virtual`, `inherited`, `Self`, `TypeOf`;
- sintaks perluasan `New(P, Init(...))` dan `Dispose(P, Done)`;
- kompatibilitas turunan ke leluhur, termasuk polimorfisme lewat pointer;
- info tipe object di `.odbg`.

**Pascal: `rtl/objects.pas`:**

- `TObject`, `TPoint`, `TRect`;
- `TCollection`, `TSortedCollection`, `TStringCollection`, `TStrCollection`;
- `TStream`, `TDosStream`, `TBufStream`, `TMemoryStream`;
- registrasi `TStreamRec` dengan `RegisterType`, `Get`/`Put` polimorfik;
- `NewStr`/`DisposeStr`.

**Gerbang G6:** korpus `tests/pascal/objects/` (termasuk kasus `TStringCollection` dan `TBufStream` dari 1.0) menghasilkan keluaran identik dengan FPC, dan debugger menampilkan field object.

### Tahap 7 — Odin Vision (kompatibel dengan API Turbo Vision, clean-room)

Trek Pascal ini mulai sejak G0 dan dikompilasi dengan FPC (3.6). Setelah G6, trek ini dipindahkan ke `odinpc`.

**7a. Drivers dan terminal**

Pascal:

- buffer layar bayangan berisi (karakter, atribut), dengan ukuran dari `TIOCGWINSZ`;
- flush hanya bagian yang berubah, lewat ANSI;
- karakter bingkai CP437 dipetakan ke Unicode;
- event keyboard memakai kode scan TP dan Alt sesuai temuan S5;
- event mouse dari laporan SGR xterm;
- `TEvent`, `GetKeyEvent`, `GetMouseEvent`.

Python (`terminal.py`):

- `Screen` mencatat mode privat 1000/1002/1006;
- `TerminalView` mengirim laporan mouse (posisi sel dihitung dengan `index("@x,y")`) dan urutan Alt.

**7b. Views inti dan aplikasi**

- `TView`: `Draw`, `HandleEvent`, state, options, grow mode, `TDrawBuffer`, `WriteBuf`, `WriteLine`, `MoveChar`, `MoveStr`, `MoveCStr`.
- `TGroup`: urutan-z, rantai fokus, `ExecView` modal, redraw dengan clipping.
- `TFrame`, `TScrollBar`, `TScroller`, `TListViewer`, `TWindow`, `TDesktop`, `TBackground`.
- Palet: tata letak indeksnya mengikuti dokumentasi API, sedangkan nilai warnanya ditetapkan sendiri.
- `TProgram` dan `TApplication`: `Init`/`Run`/`Done`, `Idle`, `InitMenuBar`, `InitStatusLine`, `InitDesktop`.
- Menu: `TMenuBar`, `TMenuBox`, `TStatusLine`, `NewMenu`, `NewSubMenu`, `NewItem`, `NewLine`, `NewStatusDef`, `NewStatusKey`, hotkey `~X~`.

**7c. Dialog**

- `TDialog`, `TButton`, `TInputLine`, `TCheckBoxes`, `TRadioButtons`, `TStaticText`, `TLabel`, `TParamText`, `TListBox`.
- `THistory` dan `HistList`.
- `MsgBox`: `MessageBox` dan `InputBox`.
- `Validate`: `TFilterValidator`, `TRangeValidator`, `TPXPictureValidator`, `TStringLookupValidator`.

**7d. Dialog standar dan memori**

- `StdDlg`: `TFileDialog`, `TChDirDialog`, `TFileList`, `TDirListBox`, di atas `Dos.FindFirst`.
- `Memory`.

**7e. Editor dan sisanya**

- `Editors`: `TEditor`, `TMemo`, `TFileEditor`, `TEditWindow`, `TIndicator`.
- `Outline`.
- Opsional: `ColorSel` dan `TextView`.

**Cara mengujinya:** program demo dijalankan di PTY, lalu grid `Screen` (karakter dan warna) dibandingkan dengan snapshot di `tests/pascal/vision/`. Skenario yang diuji: buka menu dengan F10, navigasi, buka dialog, isi input, tutup, lalu keluar dengan Alt-X. Snapshot dibuat dari implementasi kita sendiri setelah ditinjau manual. FPC tidak dipakai sebagai pembanding di sini, karena Free Vision sendiri berbeda dari TP.

**Gerbang G7:**

- Program uji Turbo Vision dari 1.0 (`uses Objects, Drivers, Views, Menus, Dialogs, App, MsgBox, StdDlg`) dan semua demo snapshot lolos dengan backend `odin`.
- Satu contoh Vision baru, misalnya `examples/VISION.PAS` dengan header lisensi, berjalan di User screen.

### Tahap 8 — Apple Silicon, Linux, dan Windows

**Keputusan pemilik proyek (15 Oktober 2026):**

- Ketiga platform dikerjakan dalam tahap ini. Windows langsung mendapat backend Odin native, bukan hanya IDE dengan Free Pascal.
- Verifikasi dilakukan di runner GitHub Actions: macOS Intel, macOS arm64, Ubuntu x86_64, Ubuntu arm64, dan Windows x86_64. Linux juga diuji lokal di VM Lima (`odin-linux`). Untuk aarch64 Linux, VM itu memakai qemu-user.
- Rilis dibuat bertahap per platform.

**Target baru:** `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`, dan `x86_64-windows`.

**Keputusan arsitektur yang berubah dari bagian 3.4:**

- **Linux memakai ELF PIE dinamis yang bergantung pada glibc**, bukan ELF statis dengan syscall langsung.
  - Fungsi C (`libc.so.6`, `libm.so.6`) diambil lewat GOT yang diisi `ld-linux`, sama seperti cara Mach-O memakai dyld.
  - Alasannya: RTL tetap memanggil fungsi C yang sama seperti di macOS (`localtime_r`, `posix_spawn`, `opendir`, dan lainnya), jadi tidak perlu menulis mini-libc.
  - Akibatnya: Odin butuh distro berbasis glibc. musl (Alpine) tidak didukung.
  - Entry `_start` ada di shim `arch/<target>.s` dan memanggil `__libc_start_main`.
- **Windows memakai PE32+ x86-64** yang mengimpor `kernel32.dll` dan `ucrtbase.dll` (Windows 10 1809 atau lebih baru).
  - ABI-nya Win64: argumen di rcx, rdx, r8, r9, shadow space 32 byte, xmm6–xmm15 dipertahankan callee, dan stack probe untuk frame di atas 4 KB.
  - Crt memakai mode konsol VT (`ENABLE_VIRTUAL_TERMINAL_PROCESSING`/`_INPUT`), jadi jalur escape sequence-nya sama dengan Unix.
  - Runtime error dari prosesor ditangkap lewat vectored exception handler.
  - Debugger memakai TCP loopback dan file mapping, bukan Unix socket dan `mmap`.
- **AArch64** memakai AAPCS64; di Apple, x18 dicadangkan dan argumen variadik dikirim lewat stack.
  - Static link ada di x15.
  - arm64 tidak punya trap FPU. Codegen membaca bendera FPSR sesudah operasi real, lalu menghasilkan runtime error 200, 205, atau 207 seperti di x86-64.
- **RTL:** bagian yang bergantung pada OS dipisah per OS (`{$IFDEF DARWIN}`, `LINUX`, `WINDOWS`, `UNIX`). Layout struct (`stat`, `dirent`, `termios`, `sigaction`, konteks sinyal) dan konstanta ditulis per OS dan per CPU. Shim assembly dibuat satu per target.
- **IDE di Windows:**
  - User screen memakai ConPTY lewat `ctypes` (tetap stdlib saja), dan proses dihentikan lewat job object;
  - data disimpan di `%APPDATA%\OdinTurboPascal`;
  - pemasangnya `Install.ps1`.

**Sub-tahap dan gerbang:**

| Sub-tahap | Isi | Gerbang | Rilis |
| --- | --- | --- | --- |
| 8a Fondasi | Plumbing target di `odinpc` (dispatch per arsitektur dan format, define `WINDOWS`), CI GitHub Actions di lima runner, VM Lima | G8a: CI hijau untuk yang sudah didukung, dan tes yang belum didukung dilewati dengan alasan tertulis | — |
| 8b Linux x86-64 | Linker ELF, RTL Linux, IDE dengan backend Odin di Linux | G8b: korpus diferensial, tes debugger, tes Vision, dan tes GUI hijau di Ubuntu x86_64 (VM dan CI) | 2.1.0-alpha.1 |
| 8c AArch64 | Encoder (golden dibandingkan dengan `clang -arch arm64`), codegen, shim. Linux arm64 dulu, lalu Apple Silicon | G8c: yang sama hijau di macOS arm64 dan Ubuntu arm64 | 2.1.0-alpha.2, lalu 2.1.0 setelah pemasang Apple Silicon lolos di CI |
| 8d Windows | IDE (ConPTY, pemasang), `odinpc` untuk Windows, linker PE, ABI Win64, RTL Windows, debugger TCP | G8d: yang sama hijau di CI Windows | 2.2.0-alpha.N, lalu 2.2.0 |

**Batasan verifikasi:** Apple Silicon dan Windows hanya diuji di runner CI, tanpa perangkat fisik, dan dokumen menyebutkan hal itu. Gatekeeper, SmartScreen, dan peluncuran dari Finder atau Explorer tetap belum diverifikasi.

### Tahap 9 — Melepas FPC, LLDB, dan Xcode

**Python — hapus kode yang terkait FPC:**

- `locate_compiler()`, `free_vision_dir()`, regex `parse_diagnostics()`;
- setting `compiler`, `mode`, dan `backend`. Settings lama tidak perlu dimigrasi, karena `Settings` memang hanya membaca kunci yang ada di `DEFAULTS`;
- radio mode dan backend di Options > Compiler.

**Installer:**

- Hapus `find_fpc`, `brew install fpc`, dan `xcode-select --install`.
- Homebrew hanya tersisa untuk `python-tk` kalau Python dengan Tk belum ada.
- Tambahkan langkah `odinpc selftest`.

**Skrip:**

- `package_app.py` ikut menyalin `rtl/` dan `toolchain/odinpc`.
- `check_mac.py` dan `Validate-on-Mac.command` memakai `odinpc selftest`, tanpa `ODIN_FPC`.
- Buat `scripts/update_checksums.py`, lalu buat ulang `SHA256SUMS.json`.

**Tes:**

- `CompilerTests` tidak lagi bergantung pada FPC.
- `scripts/oracle.py` hanya dipakai untuk membuat ulang ekspektasi di mesin pengembang.

**Dokumen:** perbarui `README.md` (termasuk alt text `assets/banner.svg`), `README.txt`, `docs/HELP.txt`, `docs/SHORTCUTS.txt`, `docs/PASCAL.txt`, `docs/COMPATIBILITY.txt` (tabel baru dengan kolom "diuji di"), `docs/TEST_REPORT.txt`, `THIRD_PARTY.txt` (hapus FPC, LLDB, dan Xcode; tambahkan pustaka standar Rust), `CHANGELOG.md`, `CLAUDE.md`, serta teks About ("Python / Tk + Odin native toolchain").

**Nomor versi** dinaikkan dengan `scripts/set_version.py`. Skrip itu memperbarui semua tempat yang menuliskannya langsung:

- `odin/__init__.py`;
- `package_app.py` (Info.plist);
- string di `app.py`, termasuk watermark dan banner status "1.0";
- banner `Install.command`;
- `README.txt` dan `docs/`.

**Gerbang G9:** di Mac Intel dan Apple Silicon yang bersih, tanpa FPC dan tanpa Xcode CLT, semua langkah berikut lolos:

1. instalasi;
2. buka dari Finder;
3. Compile dan Run INPUT.PAS serta CRTDEMO.PAS;
4. Debug dengan breakpoint, Watch, dan Call stack;
5. demo Vision;
6. Gatekeeper dan Uninstall.

Ini adalah enam pemeriksaan macOS di `COMPATIBILITY.txt`, dengan versi baru.

### Tahap 10 — Opsional

- Optimasi: alokasi register linear scan, peephole, dan inline untuk rutin RTL kecil.
- Blok `asm` x86-64/AArch64 di dalam program Pascal, memakai parser `.s` yang sudah ada.
- Mode debugger native lewat Mach/ptrace, untuk attach ke proses dan step per instruksi. Mode ini butuh entitlement `com.apple.security.cs.debugger` dan harus dibuktikan dulu lewat spike.
- `ColorSel` dan `TextView`, kalau belum dikerjakan di 7e.

---

## 8. Strategi pengujian

| Lapisan | Cara | Kebutuhan alat |
| --- | --- | --- |
| Lexer, parser, sema, IR | Unit test dan golden dump (`--dump-ast`, `--dump-ir`), diperbarui dengan flag `ODIN_BLESS=1` | `cargo test` |
| Assembler | Byte hasil encoder dibandingkan dengan golden yang dibuat `scripts/gen_asm_golden.py` (`as` + `objdump`) | Xcode CLT hanya saat membuat golden |
| Linker | Executable dijalankan di host; struktur Mach-O diperiksa oleh parser milik sendiri; `codesign -v` di CI macOS | macOS / CI |
| Bahasa dan RTL | Runner korpus `tests/pascal/` (stdin `.in`, argumen `.args`, ekspektasi `.out` dan `.code`) | `cargo test -p odinpc --test corpus` |
| Diferensial | `scripts/oracle.py` mengompilasi korpus dengan FPC `-Mtp` dan menulis `.out`; kasus di `DEVIATIONS.md` dikecualikan | FPC hanya di mesin pengembang |
| Integrasi IDE | `tests/test_core.py` (`build()`, PTY, Crt), `tests/test_debugger.py`, `tests/test_vision.py` | Python dengan Tk, PTY di luar sandbox |
| GUI | `tests/test_gui.py` versi lama tanpa diubah, ditambah tes jendela debug | Desktop macOS atau Xvfb |
| Fuzz (setelah G4) | Generator program acak untuk subset prosedural, dibandingkan dengan FPC | FPC di mesin pengembang |

**CI**, misalnya GitHub Actions:

- macOS arm64;
- macOS Intel, bila runner-nya tersedia (Mac pengembang sendiri sudah Intel);
- Linux x86_64 dengan Xvfb.

Setiap job menjalankan `cargo test`, runner korpus, dan `python -m unittest discover -s tests -v`.

---

## 9. Skala pekerjaan (perkiraan kasar)

| Komponen | Bahasa | Perkiraan baris |
| --- | --- | --- |
| base + syntax | Rust | 6–9 ribu |
| sema + unit cache | Rust | 9–13 ribu |
| IR + codegen x86-64 | Rust | 6–9 ribu |
| assembler x86-64 | Rust | 3–4 ribu |
| linker (Mach-O, ELF, tanda tangan) | Rust | 3–4 ribu |
| debuginfo + debugger | Rust | 4–6 ribu |
| codegen + assembler AArch64 | Rust | 5–7 ribu |
| System, Crt, Dos, Strings, Printer | Pascal | 8–12 ribu |
| Objects | Pascal | 3–4 ribu |
| Odin Vision | Pascal | 15–25 ribu |
| Perubahan IDE | Python | 1,5–2,5 ribu |
| Tes dan korpus | campuran | kira-kira sebanyak kode di atas |

Totalnya sekitar 65–95 ribu baris kode produk, atau 40–60 kali ukuran Odin 1.0 (sekitar 1.600 baris). Proyek ini dihitung dalam bulan sampai tahun, bukan minggu. Itulah sebabnya backend FPC tetap tersedia sampai G9, dan setiap gerbang menghasilkan sesuatu yang bisa dipakai.

---

## 10. Risiko

| Risiko | Dampak | Mitigasi |
| --- | --- | --- |
| Aturan dyld atau tanda tangan kode berubah di versi macOS baru | Program tidak bisa jalan | Spike S1/S2, tes `selftest` di CI per versi macOS, format load command diikuti dari biner buatan `ld` sebagai referensi struktur |
| Gatekeeper memblokir `odinpc` dari zip | Instalasi macet | S3; persetujuan diminta saat instalasi; notarisasi bila punya Developer ID; cadangan build lokal |
| Tidak ada perangkat arm64 (Mac pengembang Intel) | Tahap 8 dan G9 tertunda | Runner CI arm64; kompilasi silang dari Intel; S2 di Tahap 0 |
| Apple mengakhiri dukungan Mac Intel (macOS 26 adalah rilis terakhir untuk Intel) | Target pertama menua | x86-64 dipilih karena bisa diuji di Mac ini; arch dipisah sejak awal agar AArch64 tidak tertunda |
| Semantik integer dan Real halus (perluasan tipe, `Round`, format `:w:d`) | Keluaran berbeda dari 1.0 | Tes diferensial dan `DEVIATIONS.md`; keputusan terbuka 4 |
| Cakupan Odin Vision membengkak | Tahap 7 molor | Sub-tahap 7a–7e dengan gerbang masing-masing; `SPEC.md` ditulis dulu; mulai paralel sejak G0 |
| Tercampur kode FPC atau Free Vision | Masalah lisensi dan klaim clean-room | Aturan clean-room di bagian 1; `SPEC.md` sebagai satu-satunya rujukan perilaku; tinjauan sebelum merge |
| Alt/Option di Tk macOS tidak konsisten | Shortcut Alt di Vision gagal | Spike S5; uji manual di Mac |
| Shortcut Ctrl+F-key bentrok dengan pintasan sistem macOS | Perintah debug tidak sampai ke IDE | Uji manual; keputusan terbuka 5 |
| Dua backend dirawat bersamaan selama transisi | Beban ganda | FPC hanya disentuh untuk perbaikan kritis; dihapus di Tahap 9 |

---

## 11. Keputusan terbuka

| No | Keputusan | Kapan | Usulan |
| --- | --- | --- | --- |
| 1 | Lisensi RTL dan Odin Vision (3.8) | **Diputuskan 15 Oktober 2026** | GPL-3.0-or-later tanpa pengecualian runtime |
| 2 | Apple Developer ID untuk tanda tangan dan notarisasi | Sebelum Tahap 9 | Kalau tidak ada, pakai persetujuan saat instalasi |
| 3 | Akses perangkat atau CI arm64 | **Diputuskan 15 Oktober 2026** | GitHub Actions: macOS arm64, Ubuntu arm64, dan Windows |
| 4 | `Round` dan format Real: tetap seperti FPC 1.0 (pembulatan ke genap) atau seperti TP7 (menjauhi nol) | Tahap 4 | Tetap seperti FPC demi kompatibilitas dengan 1.0; perbedaan dicatat di dokumen |
| 5 | Shortcut debug: tetap seperti 1.0 (Ctrl+F7 = Evaluate) atau diselaraskan ke TP7 (Ctrl+F4 = Evaluate, Ctrl+F7 = Add watch) | Tahap 5 | Tetap seperti 1.0 sampai ada uji bentrok shortcut di Mac |
| 6 | Nomor versi rilis | **Diputuskan 15 Oktober 2026** | 2.0.0 dirilis sesudah Tahap 7 (backend Odin hanya Mac Intel). Tahap 8: 2.1.0 untuk Apple Silicon + Linux, 2.2.0 untuk Windows. Nomor untuk Tahap 9 ditentukan nanti |

---

## 12. Aturan kerja (Definition of Done per tugas)

1. **Kode disertai tes.** Tes yang sudah ada tidak boleh dilonggarkan supaya hijau. Kalau perilakunya memang sengaja berubah, catat di `CHANGELOG.md` dan, bila menyangkut FPC, di `DEVIATIONS.md`.
2. **Dua suite tes harus hijau:**
   - `cd toolchain && cargo test`;
   - `/usr/local/opt/python@3.13/bin/python3.13 -m unittest discover -s tests -v` dijalankan dari root repo dengan Python ber-Tk. Tes PTY dijalankan di luar sandbox.
3. **Header lisensi** ada di setiap berkas baru (bagian 5).
4. **Bahasa:**
   - pesan untuk pengguna dan dokumentasi dalam bahasa Indonesia;
   - label menu dan status bar tetap bahasa Inggris gaya TP;
   - pesan galat compiler dalam bahasa Indonesia dengan nomor TP7.
5. **Klaim dokumen sesuai bukti.** Dokumen hanya mengklaim hal yang sudah diuji, dengan menyebut perangkat dan OS-nya. Pemisahan "terverifikasi" dan "belum diuji di Mac asli" tetap berlaku.
6. **`Odin Turbo Pascal.app/` tidak diedit langsung.** Jalankan ulang `scripts/package_app.py`.
7. **Cabang:** satu cabang per tahap, dan `main` harus selalu bisa dirilis. Backend Odin tetap di balik setting `backend` sampai G4.
8. **Struktur IDE:** tidak ada perubahan pada sistem jendela di luar bagian 4.2. Perubahan lain di luar itu memerlukan persetujuan pemilik proyek.
