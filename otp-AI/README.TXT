OTP-AI 2.0.0 - Unit AI untuk Odin Turbo Pascal
Hak cipta (c) 2026 Syams Ideris
Lisensi GNU GPL versi 3.0 atau yang lebih baru (GPL-3.0-or-later)
Paket lengkap 19 unit machine learning dan AI
Paket unit untuk Odin Turbo Pascal dan compiler Pascal kompatibel.

Paket ini mandiri. Tidak perlu memasang paket versi pertama secara terpisah.
Semua fungsi tersedia sebagai kode Pascal lengkap, bukan stub atau pseudocode.
Unit ditulis dengan subset Turbo Pascal yang didukung Odin Turbo Pascal di
proyek ini; runtime unit Pascal tidak memerlukan paket Python atau library
pihak ketiga. Nama fungsi dan tipe tersedia pada unit canonical di bawah.

MULAI DI SINI
1. Baca DOCS/INSTALL.TXT untuk konfigurasi compiler.
2. Kompilasi contoh satu per satu di Odin Turbo Pascal, atau seluruh contoh
   dengan BUILDTP.BAT (DOS), BUILDFPC.SH (Free Pascal Linux/macOS), atau
   BUILDWIN.BAT (Free Pascal Windows).
3. Jalankan dari folder otp-AI agar path DATA dapat ditemukan.
4. Jalankan TESTALL dan TESTADV untuk memeriksa lingkungan Anda.
5. Latihan baru: PERDEMO, NNDEMO, TEXTDEMO, PATHDEMO, FUZDEMO, QDEMO.
6. Baca DOCS/GUIDE2.TXT untuk urutan pembelajaran dan semantik unit baru.

Contoh Free Pascal:
  sh BUILDFPC.SH
  ./BIN/TESTALL
  ./BIN/TESTADV
  ./BIN/NNDEMO
  ./BIN/TEXTDEMO
  ./BIN/QDEMO

ODIN TURBO PASCAL
Di IDE Odin Turbo Pascal 2.5.0 atau lebih baru, 19 unit OTP-AI sudah terpasang
di folder otp-AI/UNITS milik IDE dan langsung bisa dipanggil seperti Crt, tanpa
pengaturan: tulis "uses AIMATH, AIDATA, AILINEAR;" di editor lalu Ctrl+F9. Unit
Anda sendiri dengan nama sama di unit path Options > Directories didahulukan.
Untuk compiler lain, atau memakai paket ini dari folder terpisah, tambahkan
folder UNITS ke Unit search paths. Contoh memakai COMMON.INC yang dicari di
folder contoh itu sendiri. Jalankan program dengan direktori kerja otp-AI agar
folder DATA terbaca. AIPLOT mendukung ekspor SVG; backend BGI layar khusus
Turbo Pascal tidak tersedia di Odin.

ISI PAKET
UNITS     : 19 unit .PAS, masing-masing nama file DOS 8.3.
EXAMPLES  : 20 program contoh dan satu COMMON.INC.
DATA      : 8 CSV dan 2 TSV sintetis.
TESTS     : 2 program pengujian, 2 oracle Pascal, 2 pembanding NumPy.
DOCS      : instalasi, panduan dasar/lanjutan, API, source penuh, hasil uji.
OUTPUT    : contoh keluaran SVG/CSV yang dapat dibuka tanpa compiler.
BUKU      : PANDUAN_OTP_AI.PDF, tutorial berwarna 20 bab dengan peran unit,
            tujuan contoh, parameter, hasil harapan dan konteks machine learning.
BUILD_BOOK.PY: sumber pembuat PDF; perlu PyMuPDF dan Pillow (opsional).
LICENCE.TXT: GNU GPL versi 3.0 atau yang lebih baru; hak cipta Syams Ideris.

UNIT INTI
AITYPES  tipe bersama; AIMATH matematika dan matriks; AISTATS statistik dan
metrik; AIDATA CSV dan preprocessing; AISPLIT split dan cross-validation.
AILINEAR regresi linear/logistik dan perceptron.

UNIT MODEL
AIKNN, AIKMEANS, AINNET, AIBAYES, AITREE, AITEXT, AIOPTIM dan AIMODEL.

UNIT AI TAMBAHAN
AIRULE forward chaining; AISEARCH BFS/DFS/A-star; AIFUZZY Mamdani;
AIREWARD Q-learning; AIPLOT grafik BGI/SVG.

MIGRASI UNIT LAMA
Untuk program paket lama, nama unit yang berubah adalah AIMatrix menjadi
AIMath, AIPrep menjadi AIData, AIMetric menjadi AIStats, serta AIReg,
AILogReg dan AIPercep menjadi AILinear. Semua contoh dalam paket ini sudah
menggunakan unit canonical yang tersedia pada folder UNITS.

STATUS PENGUJIAN
Odin Turbo Pascal 2.5.0, macOS x86_64: 19 unit dan 20 contoh terkompilasi.
TESTALL: 139 lulus; TESTADV: 148 lulus. Total 287 assertion, 0 gagal.
Free Pascal 3.2.2: 20 contoh dan 4 program tes lolos kompilasi -Cn setelah
konsolidasi; eksekusi Free Pascal pasca-konsolidasi belum diverifikasi pada
host ini karena linker tidak menemukan library C. Hasil Linux dan NumPy yang
lebih lama berasal dari paket 24 unit sebelum konsolidasi.
Turbo Pascal 7.0 asli dan BGI DOS belum dijalankan. Mode -Mtp tidak membuktikan
kompatibilitas penuh dengan compiler Borland. Script BAT ditinjau statis.
Pada FPC mode TP yang diuji: Real=8, Integer=2, Boolean=1 byte.
Pada Turbo Pascal default: Real=6, Integer=2 byte. Pembulatan dapat berbeda.

BATAS UTAMA
Dataset: 200 baris, 8 fitur, label kelas 0..9. Model biner: label 0 atau 1.
MLP: maksimum 8 neuron hidden, satu output biner. Tidak ada GPU/autodiff.
Teks: 32 dokumen, 128 kandidat kata, vocabulary akhir maksimum 8 kata.
Pohon: 63 node, kedalaman maksimum 8. Grid: maksimum 16 x 16 sel.
Q-table: maksimum 256 state dan 4 aksi. Fuzzy: dua input dan sembilan aturan.

Berkas .TPM hanya untuk compiler, ABI dan layout record yang sama. Header
internal TPAIMDL2 dipertahankan demi kompatibilitas format model. Jangan
memindahkan .TPM FPC ke Turbo Pascal. Buat ulang model dengan compiler target.
Paket berisi source, bukan EXE DOS/TPU, compiler atau driver BGI.
Python/NumPy hanya pembanding pengujian opsional, bukan dependensi runtime.
Data sintetis dan keberhasilan contoh tidak membuktikan mutu pada data nyata.
