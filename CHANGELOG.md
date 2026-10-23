# Changelog

Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

Semua perubahan penting pada Odin Turbo Pascal dicatat di berkas ini. Formatnya mengikuti [Keep a Changelog](https://keepachangelog.com/id-ID/1.1.0/), dan nomor versinya mengikuti [Semantic Versioning](https://semver.org/lang/id/).

## [Unreleased]

## [2.9.0] - 2026-10-23

Rilis 2.9.0 memperluas bahasa Turbo Pascal 7 dengan OOP berbasis `class` (Tahap 10), tanpa mode khusus dan tanpa kata tercadang baru, sehingga program TP7 tetap dikompilasi apa adanya.

### Ditambahkan

- **OOP berbasis `class`** (Tahap 10 di `IMPLEMENTATION_PLAN.md`). Bahasanya tetap Turbo Pascal 7 secara bawaan, dan `odinpc` kini juga memahami class seperti Delphi dan Free Pascal, tanpa direktif atau mode dan tanpa kata tercadang baru:
  - `class`, `class(Induk)` dengan akar `System.TObject`, deklarasi forward `TFoo = class;`, dan `class of TFoo`;
  - bagian `private`, `protected`, `public`, `published`, `strict private`, dan `strict protected` (`protected` kini juga berlaku untuk `object`);
  - constructor dan destructor (`Create`, `Destroy`, `Free`), `virtual`/`dynamic`, `override`, `abstract`, `reintroduce`, `inherited` dengan nama atau tanpa nama;
  - `property` lewat field, class var, atau getter/setter, termasuk property hanya-baca, property larik, dan property larik `default`;
  - `class var`, `class procedure`/`class function` (juga virtual), dan constructor virtual yang dipanggil lewat rujukan class;
  - overload untuk method dan constructor, dengan versi yang paling cocok dengan tipe argumen;
  - operator `is` dan `as`, `with` pada objek, typecast antara class, `Pointer`, dan integer.
- `System.TObject` dan `TClass`: `Create`, `Destroy`, `Free`, `ClassName`, `ClassNameIs`, `ClassParent`, `ClassType`, `InstanceSize`, `InheritsFrom`, `ToString`.
- Unit **Classes** (`rtl/classes.pas`): `TList` dan `TStringList` (`Sorted`, `Find`, `CaseSensitive`, `Objects`, `LoadFromFile`, `SaveToFile`). Unit **Contnrs** (`rtl/contnrs.pas`): `TObjectList` yang membebaskan objeknya sendiri. `FreeAndNil` di SysUtils.
- Galat compiler baru 904–910 (tipe class diharapkan, override tanpa method virtual, pemanggilan method abstract, akses property, overload tidak cocok atau ambigu, fitur khusus class) dan peringatan 1004 untuk method yang menyembunyikan method virtual. Runtime error baru: 211 (method abstract) dan 219 (`as` gagal).
- Debugger: variabel class menampilkan isi field objeknya, dan `Obj.Field` bisa dievaluasi di Watches dan Evaluate.
- **File › Examples - OOP...**: sembilan contoh berbahasa Indonesia di `examples-oop/`, dari `oop_01_class_pertama.pas` sampai proyek `oop_09_proyek_toko.pas`. Ikut dalam bundel macOS dan paket Windows.
- Penyorot sintaks mengenali `override`, `abstract`, `overload`, `published`, `strict`, `is`, `as`, dan kata class lainnya.
- Tes: korpus `tests/pascal/classes/` (11 program dan unit `ZOO.PAS`, termasuk program TP7 yang memakai kata-kata class sebagai nama), 10 kasus galat semantik `CLS_*`, tes parser untuk sintaks class, `test_class_fields_and_self` (debugger), `test_every_oop_example_compiles_and_runs`, dan daftar File › Examples - OOP.
- Dokumen: bagian Tahap 10 di `IMPLEMENTATION_PLAN.md`, bagian 9 (class) di `rtl/COMPILER_INTERFACE.md`, BAHASA: TP7 DENGAN PERLUASAN CLASS di `docs/COMPATIBILITY.txt`, CLASS (PERLUASAN OOP), UNIT CLASSES, dan UNIT CONTNRS di `docs/PASCAL.txt` (juga di bantuan HTML dan F1).

### Diubah

- Pointer maju `PFoo = ^TFoo` kini selalu menunjuk `TFoo` yang dideklarasikan sesudahnya di bagian `type` yang sama, walaupun nama itu sudah terlihat dari luar (misalnya `System.TObject`). Unit `Objects` bergantung pada aturan ini.
- Alias `T = Class;` ke tipe bernama `Class` kini dibaca sebagai deklarasi forward sebuah class.

### Diperbaiki

- CI Windows: setup Inno Setup dijalankan dengan `MSYS_NO_PATHCONV=1`. Git Bash mengubah `/VERYSILENT` dan flag lain menjadi path, sehingga setup menunggu wizard dan langkah itu (serta tes Python Windows sesudahnya) gagal sejak setup ditambahkan.
- Tes `test_crt_screen_matches_snapshot` di Windows: konsol Windows tidak punya blink, jadi Crt di sana menerangkan latar teks yang berkedip (sengaja, seperti Crt FPC di Windows). Tes kini membandingkan dengan `tests/pascal/crt/CRT_WINDOW.windows.snap`, yang hanya berbeda di sel-sel itu.
- Daftar isi `docs/PASCAL.txt` terpotong sesudah UNIT GRAPH oleh paragraf Graph yang salah tempat; paragraf itu kini menggantikan teks lama di bagian UNIT GRAPH.

### Pengujian

- Diuji di macOS Intel: seluruh tes Rust (korpus 97 program dalam tiga mode build, galat semantik, parser) dan 147 tes Python (10 dilewati), termasuk debugger dan tes GUI. Seluruh korpus juga lulus di VM Lima Ubuntu 24.04 untuk x86_64-linux dan aarch64-linux (qemu-user), dan korpus `classes` serta `objects` untuk x86_64-windows lulus di bawah Wine.
- CI GitHub Actions: tes Rust (termasuk korpus) dan tes Python lulus di macOS Intel, macOS Apple Silicon, Ubuntu 24.04 x86_64, dan Ubuntu 24.04 arm64. Di Windows Server 2025, tes Rust, pemeriksaan pemasang, dan setup lulus; 132 tes Python juga lulus setelah dua perbaikan di bagian Diperbaiki (setup CI dan snapshot Crt Windows); keduanya kegagalan lama yang juga muncul di `main` tanpa perubahan class. Mac Apple Silicon dan PC Windows fisik belum diuji langsung.

## [2.8.0] - 2026-10-23

### Ditambahkan

- **Jendela grafik sungguhan**: program yang memakai Graph kini membuka jendela Tk (`odin/graphwindow.py`) yang menampilkan piksel sebenarnya, bukan lagi hanya pratinjau setengah blok di User screen. IDE membuka soket TCP di 127.0.0.1 (`odin/graphics.py`), memberi program `ODIN_GRAPH_PORT` dan `ODIN_GRAPH_TOKEN`, dan `rtl/graph.pas` mengirim framebuffer dengan run-length hanya untuk baris yang berubah, bersama palet (jadi `SetRGBPalette` tampil dengan warna sebenarnya) dan perubahan mode. Tombol yang diketik di jendela diteruskan ke program lewat input User screen, jadi `ReadKey` bekerja. Jendela tetap dengan gambar terakhir bila program selesai tanpa `CloseGraph`, dan hilang saat `CloseGraph`, `RestoreCrtMode` menyembunyikannya, dan jendela yang ditutup tidak mematikan program. Tanpa IDE (terminal biasa) atau dengan setelan `graph_window` = false, Graph tetap memakai pratinjau terminal.
- **File › Examples - Graph...**: 14 contoh di `examples-graph/` (`grafik_01_halo_grafik.pas` sampai `grafik_14_teks_dan_font.pas`): garis dan gaya garis, bentuk dasar, warna dan palet berputar, pola isian dan `FloodFill`, grafik batang, diagram pai, grafik fungsi, animasi dua halaman, sprite `GetImage`/`PutImage` dengan XOR, Mandelbrot, jam analog, menggambar dengan tombol panah, dan teks. Ikut dalam bundel macOS dan paket Windows.
- Tes: `GraphChannelTests` (protokol soket dan token), `GraphExampleTests` (keempat belas contoh dikompilasi dan berakhir sendiri), tes GUI jendela grafik dengan piksel sebenarnya, dan daftar File › Examples - Graph.

### Pengujian

- Diuji di macOS Intel: 144 tes Python dan seluruh tes Rust (korpus dalam tiga mode build). Jendela grafik dan kode soketnya baru dicoba di macOS Intel (tes GUI dengan jendela Tk sungguhan dan tes protokol); versi Windows (`ws2_32`) belum dijalankan di Windows.

## [2.7.0] - 2026-10-23

### Ditambahkan

- Unit **Graph** (`rtl/graph.pas`): antarmuka BGI Turbo Pascal 7 lengkap. Gambar disimpan di framebuffer di memori (satu byte per piksel, resolusi asli mode BGI), jadi `GetPixel`, `GetImage`, dan `PutImage` memberi hasil piksel demi piksel. `InitGraph` mengenal driver CGA, MCGA, EGA, EGA64, EGAMono, IBM8514, HercMono, ATT400, VGA, dan PC3270 dengan semua modenya; ada garis dengan gaya dan ketebalan, mode tulis XOR, `Rectangle`, `Bar`, `Bar3D`, `Circle`, `Arc`, `Ellipse`, `FillEllipse`, `PieSlice`, `Sector`, `DrawPoly`, `FillPoly`, `FloodFill`, 12 pola isian dan pola buatan sendiri, palet (`SetPalette`, `SetRGBPalette`, `SetBkColor`), viewport dengan klip, halaman aktif dan visual, `GetImage`/`PutImage` dengan lima operasi, dan teks (`OutText`, `OutTextXY`, `SetTextStyle`, `SetTextJustify`, `TextWidth`, `TextHeight`) dengan font bitmap 8 x 8. Tanpa berkas `.BGI` dan `.CHR`: font stroke diganti font bitmap yang diskalakan.
- Tampilan Graph di terminal: pratinjau kasar dengan karakter setengah blok (dua subpiksel per sel, 16 warna CRT, sekitar 80 x 50 titik di layar 80 x 25), diskalakan dan ditaruh di tengah dengan perbandingan lebar-tinggi yang benar. Teks BGI ditampilkan sebagai karakter asli supaya terbaca. Layar digambar ulang saat program menunggu lewat Crt, tiap 0,1 detik saat menggambar, dan saat program selesai; gambar terakhir tetap di layar bila program selesai tanpa `CloseGraph`. Keluaran yang dialihkan ke berkas tidak menampilkan apa-apa.
- Unit Crt: `CursorOn`, `CursorOff`, `CrtScreenWidth`, `CrtScreenHeight`, `CrtOutputIsTty`, `CrtPutText` (menulis sel UTF-8 tanpa scroll), dan `CrtIdleHook` (dipanggil sebelum `ReadKey`, `KeyPressed`, dan `Delay`), dipakai Graph.
- Unit **WinDos** (`rtl/windos.pas`): `Dos` dengan `PChar`, diteruskan ke `Dos` (`FindFirst`/`FindNext`, `FileSplit`, `FileExpand`, `FileSearch`, `GetCurDir`, `SetCurDir`, `CreateDir`, `RemoveDir`, `GetArgStr`, `GetEnvVar`, `TSearchRec`, `fa*`, `fc*`, `fs*`).
- Unit **Math** (`rtl/math.pas`): trigonometri dan hiperbolik, `Power`, `IntPower`, `Log10`, `Log2`, `LogN`, `Ceil`, `Floor`, `RoundTo`, `Min`/`Max` (Int64; `MinF`/`MaxF` untuk Real), `Sign`, `SameValue`, statistik larik (`Sum`, `Mean`, `StdDev`, `Variance`, `MomentSkewKurtosis`, ...), fungsi keuangan, dan nilai khusus IEEE. Galat domain menjadi runtime error 207.
- Unit **SysUtils** (`rtl/sysutils.pas`): `IntToStr`, `IntToHex`, `StrToInt` dan variasi `Def`/`Try`, `StrToFloat`, `FloatToStr`, `FloatToStrF`, `FormatFloat`, `UpperCase`, `Trim`, `StringReplace`, rutin nama berkas dan direktori, `FileExists`, `DeleteFile`, `ForceDirectories`, `TDateTime` (`EncodeDate`, `DecodeDate`, `FormatDateTime`, `StrToDate`, `IncMonth`, ...), `Sleep`, `GetTickCount64`. Tanpa kelas, exception, `Format`, dan parameter bawaan (galat konversi menjadi runtime error 106).
- Unit **Overlay** (`rtl/overlay.pas`): antarmuka overlay TP7; `OvrInit` selalu berhasil karena seluruh kode ada di memori. Direktif `{$O ...}` diabaikan.
- Tes: `tests/pascal/graph/` (enam program yang mencetak framebuffer lewat `GetPixel`, ekspektasi `.expect`, dijalankan `tests/test_graph.py` bersama tiga tes tampilan lewat PTY), korpus untuk Math, SysUtils, WinDos, dan Overlay. `python3 tests/test_graph.py --bless` menulis ulang ekspektasi Graph.
- Dokumen: bagian UNIT GRAPH, WINDOS, MATH, SYSUTILS, dan OVERLAY di `docs/PASCAL.txt` (dan bantuan HTML), serta `docs/COMPATIBILITY.txt`.

### Pengujian

- Diuji di macOS Intel: korpus (`cargo test -p odinpc`) dan suite Python. Korpus Math, SysUtils, WinDos, dan Overlay serta keenam program Graph juga dijalankan di VM Lima Ubuntu 24.04 (x86_64) dan di bawah qemu (aarch64) dengan keluaran yang sama. Unit baru dikompilasi untuk x86_64 Windows, tetapi belum dijalankan di Windows dan Apple Silicon fisik, dan tampilan Graph di terminal baru diuji di macOS Intel.

## [2.6.0] - 2026-10-22

### Ditambahkan

- Pustaka **OTP-AI** (`otp-AI/`): 19 unit AI dan machine learning murni Pascal, 20 contoh, tes, dan buku panduan PDF. Unitnya terpasang di IDE dan langsung bisa dipanggil dengan `uses` seperti `Crt`, tanpa mengisi **Options › Directories** (`core.library_unit_paths`, ikut dalam bundel macOS dan paket Windows). Unit buatan pengguna di unit path didahulukan.
- **File › Examples - AI...**: daftar 20 contoh OTP-AI dengan topiknya, dibuka sebagai templat seperti **File › Examples** (`otp-AI/EXAMPLES` dan `otp-AI/DATA` ikut dalam bundel).

### Diubah

- Ke-20 contoh di `otp-AI/EXAMPLES/` kini punya komentar header yang menjelaskan tujuan latihan dan komentar baris penjelasan, sejalan dengan gaya contoh bawaan di `examples/`.

## [2.5.0] - 2026-10-21

### Ditambahkan

- Bantuan lengkap dalam HTML, `docs/help.html`, dibuka dari **Help › Contents** (F1): satu berkas mandiri dengan daftar isi bertingkat (penanda bagian aktif, panel "Pada halaman ini"), pencarian instan (`/`), tema terang dan Turbo, serta cetak. Isinya panduan penggunaan, referensi menu, referensi bahasa Pascal dan unit, pintasan, kompatibilitas, dan pemecahan masalah. Tabel referensi dibangun dari `docs/PASCAL.txt` dan `docs/SHORTCUTS.txt` oleh `scripts/build_help.py`; jalankan ulang skrip itu setelah mengubah docs atau nomor versi (tes `test_help_html_is_current` memeriksanya).
- Bantuan konteks di editor: F1 membuka `docs/help.html` di browser pada baris referensi untuk kata di posisi kursor (atau teks yang diseleksi). Kata yang tidak punya entri dimasukkan ke kotak pencarian halaman. Help > Contents juga membuka halaman ini; menu "Help in browser" yang kembar dihapus. `scripts/build_help.py` memberi tiap nama pada baris seperti `Cos(X), Sin(X)` anchor sendiri.
- `docs/PASCAL.txt` dilengkapi menjadi referensi lengkap dengan daftar isi: semua kata cadangan dan direktif standar beserta penjelasan, operator, tipe data, konstanta, rutin System (matematika, ordinal, string, memori, berkas, kontrol program), direktif compiler, kode runtime error, unit Crt, Dos, Strings, Objects, Odin Vision, dan perintah IDE. Potongan contoh lama pindah ke bagian "Contoh ringkas".
- Unit Odin Vision `ColorSel` (dialog warna `TColorDialog` dengan pemilih warna, daftar grup, dan daftar item) dan `TextView` (`TTextDevice`, `TTerminal`, dan `AssignDevice` sehingga `WriteLn` bisa menulis ke jendela terminal). Dengan keduanya, seluruh unit Turbo Vision TP7 kini milik Odin sendiri.
- `scripts/bless_corpus.py`: menulis ekspektasi korpus `tests/pascal/` untuk program baru dengan `odinpc`. Ekspektasi lama tidak ditimpa tanpa `--force`, dan hasilnya ditinjau terhadap perilaku Turbo Pascal 7 sebelum commit.
- CI menjalankan gerbang pemasang macOS (`scripts/check_mac.py`) di macOS Intel dan Apple Silicon.
- **Setup Windows satu berkas** (`OdinTurboPascal-VERSI-Setup-x64.exe`), dibuat dengan Inno Setup oleh `scripts/build_setup_windows.py` dan `scripts/odin_setup.iss`. Berkas ini membawa IDE, `odinpc.exe`, dan Python 3.13 dengan Tk khusus untuk Odin (installer python.org yang disematkan dengan SHA-256), sehingga pemasangan tidak memerlukan internet, hak administrator, maupun Python di komputer. Pemasangan per pengguna di `%LOCALAPPDATA%\Programs\OdinTurboPascal` (folder yang sama dengan `Install.cmd`, jadi bisa menimpa pemasangan itu), pintasan di menu Start dan Desktop, pemeriksaan kompilasi dengan `odinpc.exe` setelah penyalinan, uninstaller di Settings > Apps, dan pemasangan senyap (`/VERYSILENT`) untuk lab. CI membangun setup di job Windows, memasangnya secara senyap, menjalankan pemeriksaan, lalu mengunggahnya sebagai artefak `odin-setup-windows-x86_64`. `Install.cmd` tetap ada sebagai jalur kedua.
- **Pemasang Linux satu berkas** (`OdinTurboPascal-VERSI-linux-ARCH.run`, x86_64 dan arm64), dibuat oleh `scripts/build_setup_linux.py`. Berkas ini berisi skrip shell dan arsip tar.xz: IDE, `odinpc`, dan Python 3.13 dengan Tk khusus untuk Odin (python-build-standalone, disematkan dengan SHA-256), sehingga tidak ada yang diunduh saat memasang dan tidak perlu `python3-tk`, Rust, maupun hak root. Pemasang memeriksa integritas paket, mengompilasi dan menjalankan program uji dengan `odinpc` sebelum memasang, membuat perintah `odin-turbo-pascal` dan entri menu aplikasi, menyimpan satu cadangan versi lama, dan punya `--prefix`, `--no-menu`, `--check`, dan `--uninstall`. Satu-satunya yang diambil dari sistem adalah pustaka X11. CI Linux membangunnya, memasangnya dengan jaringan diputus (`unshare -n`), dan mengunggahnya sebagai artefak. Odin Vision/IDE berjalan di Tk 9.0 bawaan paket ini.
- **Pemasang macOS satu berkas** (`OdinTurboPascal-VERSI-macos-ARCH.pkg`), dibuat oleh `scripts/build_setup_mac.py` dengan `pkgbuild` dan `productbuild`. Paket ini memasang `Odin Turbo Pascal.app` di `~/Applications` untuk pengguna yang sedang masuk (tanpa kata sandi administrator), dan aplikasinya membawa Python 3.13 dengan Tk sendiri (python-build-standalone, disematkan dengan SHA-256) serta `odinpc`, sehingga tidak ada yang diunduh dan tidak perlu Python, Homebrew, maupun Xcode. Skrip postinstall mengompilasi dan menjalankan program uji dengan `odinpc` (gerbang `check_mac.py`). `scripts/launcher.sh` memakai Python bawaan bundel bila ada (tanpa re-exec arm64, dengan `-E -X utf8`); tanpa Python bawaan perilakunya tidak berubah. `scripts/package_app.py` menerima folder tujuan sebagai argumen. Paket belum ditandatangani Apple (macOS menahannya sampai dibuka lewat klik kanan > Open atau System Settings > Privacy & Security).
- Buku tutorial menyebut tautan repositori GitHub (`github.com/Syamsuddin/ODIN-TURBO-PASCAL`): di ringkasan pemasangan Bab 1, di Lampiran A (beserta halaman Releases), di halaman hak cipta, dan di penutup. Di PDF tautannya bisa diklik.

### Diubah

- Tampilan jendela IDE, terutama di Windows. Title bar jendela kini bergaya Turbo Vision: judul tebal dalam bingkai garis ganda (`═╡ NAMA.PAS ╞═`), tombol tutup dan zoom berupa kotak timbul (rata dan redup pada jendela yang tidak aktif), serta garis pemisah di bawahnya. Footer dirapatkan: baris tombol F-key memakai Label (bukan Button, yang di Windows menambah cincin fokus dan padding), nama tombol berwarna merah dan label hitam dengan sorotan cyan saat disentuh mouse, status bar tanpa padding vertikal, dan ada garis pemisah antara kedua baris. Menu bar ikut dirapatkan.

### Diperbaiki

- Odin Vision: `TGroup.Store` (menyimpan jendela atau dialog ke stream) hanya menulis satu subview, sehingga `Load` mengembalikan satu subview dan salah membaca data sesudahnya. Kini semua subview tersimpan.
- `scripts/build_book.py`: permainan tebak angka (Bab 8.6) dimainkan otomatis dengan membaca petunjuk dari keluaran sejak tebakan terakhir. Sebelumnya skrip membaca baris terakhir, yang selalu berupa prompt, sehingga tebakannya tidak pernah berubah. Bug ini tertutup oleh cache buku sampai `odinpc` dibangun ulang.

### Dihapus

- **Backend Free Pascal.** `odinpc` kini satu-satunya compiler. Pilihan backend, path Free Pascal, mode bahasa (TP/ObjFPC/Delphi), dan opsi Debug information (hanya dipakai Free Pascal) hilang dari **Options › Compiler**; pengaturan lama itu diabaikan saat dibaca. Program ObjFPC/Delphi tidak lagi bisa dikompilasi. Di sistem yang tidak didukung `odinpc` (misalnya Windows on ARM), IDE kini mengatakan hal itu, bukan beralih ke Free Pascal.
- Pemasang macOS tidak lagi memasang Free Pascal maupun Xcode Command Line Tools, dan pemasang Windows tidak lagi memasang Free Pascal. Satu-satunya dependensi adalah Python dengan Tk. Pemeriksaan pemasang (`check_mac.py`, `check_windows.py`) mengompilasi dan menjalankan program uji dengan `odinpc` dari paket.
- `scripts/oracle.py` dan workflow `oracle.yml` (ekspektasi korpus dari Free Pascal). Ekspektasi yang sudah ada tetap dipakai. Free Pascal tidak lagi dipasang di CI.
- Tes yang membandingkan dengan Free Pascal. Layar `Crt` kini dibandingkan dengan snapshot tersimpan (`tests/pascal/crt/CRT_WINDOW.snap`), yang dicocokkan dengan Free Pascal 3.2.2 sebelum backend itu dicabut.

### Diubah

- `scripts/package_app.py` tidak menyalin berkas yang diabaikan git ke bundel `.app`.
- `odinpc.exe` ditautkan dengan runtime C secara statis (`toolchain/.cargo/config.toml`), sehingga tidak lagi memerlukan `VCRUNTIME140.dll` (Visual C++ Redistributable) di PC Windows yang bersih. `odinpc.exe` yang tercatat di repo masih build lama; ambil yang baru dari artefak CI sebelum merilis setup.
- `scripts/stage_windows.py` tidak menyalin berkas yang diabaikan git, seperti `package_app.py`.

## [2.4.0] - 2026-10-18

Rilis 2.4.0. Odin Turbo Pascal kini bisa **mengukur** program untuk analisis dan penilaian (misalnya lomba pemrograman). `odinpc build --count-steps` menghitung langkah per pernyataan, puncak heap, dan kedalaman panggilan dengan angka yang sama di macOS, Linux, dan Windows, x86-64 maupun arm64. `odinpc metrics` melaporkan struktur kode. Di IDE, menu **Run › Ukur** (Shift+F9) menampilkan laporan itu di jendela **Metrik**, dan **Run › Periksa...** menilai program dengan paket soal.

### Ditambahkan

- `odinpc build --count-steps`: build hitung langkah untuk laporan metrik dan penilaian. Setiap pernyataan di sumber pengguna menambah penghitungnya (`for` sekali saat masuk dan sekali per iterasi), dan menyalin data (assignment dan parameter nilai bertipe terstruktur, `Move`, `FillChar`) dibebani satu langkah per 64 byte. Saat program berakhir, RTL menulis laporan ke `$ODIN_STATS_FILE`: total langkah, langkah per pernyataan (memetakan ke `lines` di `.odbg`), puncak heap, dan kedalaman panggilan. Batasnya diatur lewat `ODIN_STEP_LIMIT` (runtime error 240 yang baru), `ODIN_HEAP_LIMIT` (203), dan `ODIN_DEPTH_LIMIT` (202). Build ini juga mengisi nol variabel lokal dan memakai `RandSeed` dari `ODIN_RANDSEED`, sehingga angkanya sama di macOS, Linux, dan Windows, di x86-64 maupun arm64. Kontraknya ada di `rtl/COMPILER_INTERFACE.md` §8.
- `odinpc/tests/steps.rs` membandingkan laporan program di `tests/steps/` dengan berkas yang sama di setiap target, dan korpus `tests/pascal` kini juga dijalankan dengan build hitung langkah.
- Unit Dos di Windows mengambil handle `FindFirst` dari pustaka C, seperti `opendir` di Unix, sehingga handle itu tidak tercatat sebagai heap program.
- `odinpc metrics SOURCE`: struktur kode untuk laporan metrik. Per rutin: jumlah pernyataan, kedalaman nesting, kompleksitas siklomatik, dan rekursi. Catatan bernomor baris: variabel tidak dipakai, fungsi yang tidak mengisi hasilnya, `goto`, nesting lebih dari 4 tingkat, kompleksitas lebih dari 10, angka yang berulang atau batas larik yang sebaiknya dijadikan `const`, dan prosedur yang mengubah variabel global. Fakta untuk syarat soal (larik, record, pointer, rekursi, memori global), dan bentuk kode tanpa nama, nilai, spasi, dan komentar untuk mengukur kemiripan. Diuji di `odinpc/tests/metrics.rs`.
- Menu **Run › Ukur** (Shift+F9) menjalankan build juri di User screen lalu membuka jendela **Metrik**: angka resmi (langkah, puncak heap, memori global, kedalaman panggilan), info mesin, peta langkah, dan catatan struktur yang bisa diklik ke barisnya. **Run › Periksa...** menjalankan program dengan setiap kasus sebuah paket soal (`aturan.json`, `kasus/*.in`/`.out`) dan menampilkan hasil per kasus, skor, subtask, dan syarat. Laporan bisa disimpan sebagai JSON `otp-metrics/1`. Paket soal dan aturannya dijelaskan di Help (Metrik: Ukur dan Periksa).
- `odin/metrics.py`: laporan `otp-metrics/1` tanpa ketergantungan selain pustaka standar, yaitu pembaca laporan langkah, peta langkah per baris, pembanding keluaran (trim, exact, tokens, real), kemiripan dua program, paket soal, skor subtask dan skor terbaik per subtask, serta tampilan laporan tanpa rincian kasus tersembunyi. Diuji di `tests/test_metrics.py`.

### Diubah

- CI: `actions/checkout` dan `actions/upload-artifact` naik dari v4 ke v7, yang berjalan di Node.js 24. GitHub Actions tidak lagi memperingatkan bahwa Node.js 20 sudah usang.
- Emulator VT100 (`Screen`) dan proses pseudo-terminal (`Process`) pindah dari `odin/terminal.py` ke modul baru `odin/console.py` yang tidak membutuhkan Tk. `odin/terminal.py` kini hanya berisi widget Tk dan tetap mengekspor nama lama. `odin/debugger.py` juga tidak lagi memuat Tk.
- `Document` mendapat `from_bytes()` dan `encoded()` (membaca dan menulis isi berkas tanpa menyentuh disk), dan `core.build()` menerima `wrap` untuk menjalankan `odinpc` lewat pembungkus tanpa mengubah perintah yang ditampilkan.

### Pengujian

Di Mac Intel (macOS 15.7, Python 3.13, Tk 9.1, Free Pascal 3.2.2, Rust 1.99): 119 tes Python lulus (6 dilewati), termasuk tes GUI untuk **Run › Ukur** dan **Run › Periksa...**, dan 189 tes Rust lulus, termasuk korpus diferensial 77 program dengan build biasa, build debug, dan build hitung langkah. Universal `odinpc` 2.4.0 (x86_64 dan arm64) berhasil dibangun; hanya bagian x86_64 yang bisa dijalankan di mesin ini.

Laporan langkah program di `tests/steps/` sama persis di x86_64-darwin, di VM Ubuntu 24.04 (Lima) untuk x86_64-linux, dan untuk aarch64-linux lewat qemu-user.

Di GitHub Actions, kelima job CI lulus untuk rilis ini: macOS 15 Apple Silicon, macOS 15 Intel, Ubuntu 24.04 x86_64 dan arm64, dan Windows Server 2025 x86_64 (119 tes Python, 2 dilewati). Di semua job itu laporan langkah sama dengan berkas yang sama. `odinpc.exe` 2.4.0 berasal dari job Windows itu.

Yang belum diverifikasi langsung: Apple Silicon, PC Linux dan Windows fisik, serta jendela **Metrik** di sistem selain Mac Intel.

## [2.3.0] - 2026-10-16

Rilis 2.3.0. Odin Turbo Pascal kini menyertakan buku tutorial berwarna penuh, *Belajar Pemrograman Bahasa Pascal dengan ODIN Turbo Pascal*, yang dibuka dari menu **Help › Buku**. Rilis ini juga mengganti contoh bawaan dengan tutorial 20 bab (90 berkas) dan memberi editor warna sintaks **Turbo Biru Lembut**. Toolchain Odin tidak berubah selain nomor versinya.

### Ditambahkan

- Buku tutorial **Belajar Pemrograman Bahasa Pascal dengan ODIN Turbo Pascal** (`docs/Belajar_Pemrograman_Bahasa_Pascal.pdf`), buku PDF berwarna penuh karya Syams Ideris dengan sampul, kata pengantar, daftar isi, 20 bab dalam enam bagian, penutup, dan enam lampiran. Buku memakai ke-89 program dan unit contoh tutorial, lengkap dengan infografik, gambar layar IDE, rangkuman, dan latihan. Listing dicetak dari `examples/`, dan keluaran program adalah hasil menjalankan program itu dengan `odinpc`. Sumbernya ada di `book/`, dan `scripts/build_book.py` membangunnya dengan Google Chrome dan PyMuPDF.
- Menu **Help › Buku**, di atas **About Odin**, membuka buku itu di aplikasi PDF bawaan sistem.
- Warna sintaks **Turbo Biru Lembut** di editor: latar biru tua `#000080` (seperti skema "Pascal Classic" Lazarus) dengan warna pastel yang lebih tenang untuk sesi panjang. Warnanya: kata tercadang putih tebal; variabel dan nama buatan sendiri lainnya kuning lembut; prosedur dan fungsi buatan sendiri jingga muda; rutin bawaan seperti `WriteLn` biru langit; tipe bawaan hijau muda; angka, termasuk heksadesimal (`$0E`), dan konstanta bawaan (`True`, `False`, `nil`) merah muda; string dan konstanta karakter (`#13`) hijau toska; operator lavender; komentar biru keabuan dan miring; direktif kompiler (`{$R+}`) merah salem. Sebelumnya hanya empat jenis token yang diwarnai.

### Diubah

- Warna sintaks kini aktif secara bawaan. Pengaturannya pindah ke kunci `syntax_colors` di `settings.json`, sehingga nilai `"syntax": false` yang tersimpan dari versi lama tidak lagi mematikannya. Mematikan **Syntax colors** di **Options › Editor** mengembalikan teks kuning klasik di latar biru.
- Pewarnaan sintaks sekitar 30 kali lebih cepat pada berkas besar (4.666 baris: sekitar 0,12 detik, sebelumnya 3,6 detik), karena tag dipasang sekaligus per jenis token dengan indeks baris.kolom. String yang belum ditutup kini hanya diwarnai sampai akhir baris.

- Contoh bawaan di **File › Examples** diganti total dengan tutorial Pascal untuk pemula: 90 berkas dalam 20 bab dan enam bagian (fondasi, alur kendali, modularisasi, struktur data, algoritma dasar, lanjutan ringan), yaitu 89 program `babNN_MM_topik.pas` dan unit `matematika.pas` untuk Bab 19. Setiap kode penting diberi komentar penjelasan singkat. Program Bab 17 dan Bab 20 menulis berkas data yang namanya ditetapkan sebagai konstanta, dan menampilkan folder tempat berkas itu dibuat.
- Halaman bawaan IDE yang membawa tag versi kini `examples/bab01_01_halo_dunia.pas` (sebelumnya `HELLO.PAS`). `scripts/package_app.py` dan `scripts/set_version.py` menyamakan tag di berkas itu.
- Dialog **Examples** memakai scrollbar bila daftarnya lebih dari 15 baris, dan mengenali nama berkas `.pas` huruf kecil.
- `HELLO.PAS`, `INPUT.PAS`, `KALKULATOR.PAS`, `PARAMETER.PAS`, `ARRAY.PAS`, `BERKAS.PAS`, `CRTDEMO.PAS`, `UNITDEMO.PAS`, dan `UMATH.PAS` dihapus. `VISION.PAS` pindah ke `tests/pascal/vision/` dan `REKURSI.PAS` ke `tests/pascal/debug/`, karena tes Odin Vision dan tes debugger memakainya.
- `scripts/package_app.py` dan `scripts/stage_windows.py` hanya menyalin berkas `.pas` dari `examples/`, sehingga berkas data yang dibuat saat mencoba tutorial dari repositori tidak ikut terbawa ke paket.

### Diperbaiki

- Windows: program tidak lagi sesekali berhenti dengan runtime error 216 saat `Exec` menjalankan program lewat PATH. Handler pengecualian hanya menangani pelanggaran akses di kode program sendiri; pelanggaran akses di DLL sistem (yang bisa ditangani DLL itu sendiri) diteruskan, dan yang tidak tertangani tetap menjadi runtime error lewat filter terakhir.

### Pengujian

Di Mac Intel (macOS 15.7, Python 3.13, Tk 9.1, Free Pascal 3.2.2, Rust 1.99): 97 tes Python lulus (6 dilewati), termasuk tes GUI untuk menu **Help › Buku**, dan 177 tes Rust lulus. Universal `odinpc` 2.3.0 (x86_64 dan arm64) berhasil dibangun; hanya bagian x86_64 yang bisa dijalankan di mesin ini.

Buku dibangun dari `examples/` dengan `scripts/build_book.py`, dan setiap keluaran program di dalamnya berasal dari menjalankan program itu dengan `odinpc` 2.3.0. Halaman buku diperiksa lewat gambar hasil render, belum satu per satu di aplikasi pembaca PDF.

Di GitHub Actions, kelima job CI lulus untuk rilis ini: macOS 15 Apple Silicon, macOS 15 Intel, Ubuntu 24.04 x86_64 dan arm64, dan Windows Server 2025 x86_64. `odinpc.exe` 2.3.0 berasal dari job Windows itu.

Yang belum diverifikasi langsung: Apple Silicon, PC Linux dan Windows fisik, serta pembukaan buku lewat **Help › Buku** di sistem selain Mac Intel.

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

[Unreleased]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.9.0...HEAD
[2.9.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.8.0...v2.9.0
[2.8.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.7.0...v2.8.0
[2.7.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.6.0...v2.7.0
[2.6.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.5.0...v2.6.0
[2.5.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.4.0...v2.5.0
[2.4.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.1.0-alpha.1...v2.2.0
[2.1.0-alpha.1]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.0.1...v2.1.0-alpha.1
[2.0.1]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.0.0-alpha.2...v2.0.0
[2.0.0-alpha.2]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/compare/v2.0.0-alpha.1...v2.0.0-alpha.2
[2.0.0-alpha.1]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/releases/tag/v2.0.0-alpha.1
[1.0.0]: https://github.com/Syamsuddin/ODIN-TURBO-PASCAL/releases/tag/v1.0.0
