# Antarmuka compiler dan RTL Odin

Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

Dokumen ini adalah kontrak antara compiler (`toolchain/`, Rust) dan runtime library (`rtl/`, Pascal). Compiler memanggil rutin RTL berdasarkan nama simbolnya (`SYSTEM.NAMA`), jadi nama, urutan parameter, dan layout record di bawah ini tidak boleh diubah tanpa mengubah kedua sisi.

## 1. Konvensi panggil

- Semua rutin Pascal memakai ABI C platform (System V di x86-64, AAPCS64 varian Apple di arm64).
- Nilai ordinal, pointer, dan prosedural dikirim di register integer, diperluas ke 64 bit. Real dikirim di register floating point (Double; Single sebagai float).
- Parameter `var`, parameter `const` bertipe terstruktur, dan parameter tanpa tipe dikirim sebagai alamat.
- Parameter nilai bertipe terstruktur (string, record, array, set) dikirim sebagai alamat lalu disalin oleh rutin yang dipanggil.
- Fungsi yang hasilnya string, record, array, atau set menerima pointer hasil tersembunyi sebagai argumen pertama.
- Prosedur bersarang menerima static link di R10 (x86-64) atau X15 (AArch64).
- AArch64: X16/X17 adalah register sementara encoder dan X18 tidak pernah dipakai (register platform Apple). Di Apple, argumen variadik fungsi C (`open`, `fcntl`, `ioctl`) dikirim lewat stack; codegen juga menaruhnya di stack, jadi RTL memanggilnya seperti fungsi biasa.
- Windows x86-64 memakai konvensi Win64 untuk semua rutin: argumen posisional di RCX, RDX, R8, R9 atau XMM0–XMM3, shadow space 32 byte, RSI/RDI disimpan rutin, dan stack probe lewat `ODIN_CHKSTK`.
- Rutin RTL yang ditulis dalam assembly dideklarasikan `external 'odinrtl' name 'NAMA'` dan berada di `rtl/system/arch/<target>.s`.
- Fungsi C dideklarasikan `cdecl; external 'c' name 'nama'`. Di macOS namanya diberi awalan `_` dan diimpor dari libSystem.

## 2. Rutin yang dipanggil langsung oleh code generator

Nama ada di `odin_ir::rtl`.

| Simbol | Tanda tangan | Arti |
| --- | --- | --- |
| `SYSTEM.ODIN_STARTUP` | `(ArgC: LongInt; ArgV: Pointer)` | Dipanggil pertama oleh `_main`. |
| `SYSTEM.ODIN_HALT` | `(Code: LongInt)` | Dipanggil setelah program utama; tidak kembali. |
| `SYSTEM.ODIN_RANGEERROR` | `()` | Runtime error 201 di alamat pemanggil. |
| `SYSTEM.ODIN_OVERFLOWERROR` | `()` | Runtime error 215. |
| `SYSTEM.ODIN_DIVZEROERROR` | `()` | Runtime error 200. |
| `SYSTEM.ODIN_FPERROR` | `(Flags: Int64)` | Hanya AArch64, yang tidak punya trap FPU. Codegen membaca FPSR sesudah operasi real; bila bit 0 (invalid), 1 (pembagian nol), atau 2 (overflow) menyala, rutin ini menghasilkan runtime error 207, 200, atau 205 seperti trap di x86-64. |
| `SYSTEM.ODIN_OBJECTERROR` | `()` | Runtime error 210: metode virtual dipanggil pada object tanpa VMT yang sah (constructor belum dipanggil), di bawah `{$R+}`. |
| `SYSTEM.ODIN_STRASSIGN` | `(Dest: Pointer; MaxLen: Int64; Src: Pointer)` | Salin string, potong ke `MaxLen`. |
| `SYSTEM.ODIN_STRAPPEND` | `(Dest: Pointer; Src: Pointer)` | Tambahkan ke string 255 karakter. |
| `SYSTEM.ODIN_STRCOMPARE` | `(A, B: Pointer): LongInt` | -1, 0, atau 1. |

## 3. Rutin yang dipanggil hasil penurunan fungsi bawaan

Analisis semantik menurunkan fungsi bawaan menjadi panggilan rutin berikut. Semuanya ada di bagian interface unit System.

### Teks (`Text` = `TextRec`)

| Bawaan | Rutin RTL |
| --- | --- |
| `Write(F, x:w:d)` | `ODIN_WRITE_INT(var F: Text; V: Int64; Width: LongInt)`, `ODIN_WRITE_STR(var F: Text; const S: String; Width: LongInt)`, `ODIN_WRITE_CHAR(var F: Text; C: Char; Width: LongInt)`, `ODIN_WRITE_BOOL(var F: Text; B: Boolean; Width: LongInt)`, `ODIN_WRITE_PCHAR(var F: Text; P: PChar; Width: LongInt)`, `ODIN_WRITE_REAL(var F: Text; V: Real; Width, Decimals: LongInt)` (lebar bawaan -1 untuk Real, 0 untuk lainnya; Decimals -1 berarti format eksponen) |
| `WriteLn` | lalu `ODIN_WRITELN(var F: Text)` |
| `Write` | lalu `ODIN_WRITE_END(var F: Text)` |
| `Read(F, x)` | `ODIN_READ_INT(var F: Text): Int64`, `ODIN_READ_CHAR(var F: Text): Char`, `ODIN_READ_REAL(var F: Text): Real`, `ODIN_READ_STR(var F: Text; var S; MaxLen: LongInt)` |
| `ReadLn` | lalu `ODIN_READLN(var F: Text)` |
| `Assign(F, N)` | `ODIN_TEXT_ASSIGN(var F: Text; const Name: String)` |
| `Reset(F)`, `Rewrite(F)`, `Append(F)` | `ODIN_TEXT_RESET`, `ODIN_TEXT_REWRITE`, `ODIN_TEXT_APPEND` `(var F: Text)` |
| `Close(F)`, `Flush(F)`, `Erase(F)` | `ODIN_TEXT_CLOSE`, `ODIN_TEXT_FLUSH`, `ODIN_TEXT_ERASE` `(var F: Text)` |
| `Rename(F, N)` | `ODIN_TEXT_RENAME(var F: Text; const NewName: String)` |
| `Eof[(F)]`, `Eoln[(F)]`, `SeekEof[(F)]`, `SeekEoln[(F)]` | `ODIN_TEXT_EOF`, `ODIN_TEXT_EOLN`, `ODIN_TEXT_SEEKEOF`, `ODIN_TEXT_SEEKEOLN` `(var F: Text): Boolean`; tanpa argumen berarti `Input` |

Tanpa argumen berkas, `Write`/`WriteLn` memakai `Output`, sedangkan `Read`/`ReadLn` memakai `Input`. Di bawah `{$I+}` setiap panggilan diikuti `ODIN_IOCHECK`.

### Berkas bertipe dan tanpa tipe (`file of T`, `file` = `FileRec`)

| Bawaan | Rutin RTL |
| --- | --- |
| `Assign(F, N)` | `ODIN_FILE_ASSIGN(var F; const Name: String)` |
| `Reset(F[, R])`, `Rewrite(F[, R])` | `ODIN_FILE_RESET(var F; RecSize: LongInt)`, `ODIN_FILE_REWRITE(var F; RecSize: LongInt)`; `RecSize` = `SizeOf(T)` untuk `file of T`, argumen kedua atau 128 untuk `file` |
| `Close(F)`, `Erase(F)`, `Truncate(F)` | `ODIN_FILE_CLOSE`, `ODIN_FILE_ERASE`, `ODIN_FILE_TRUNCATE` `(var F)` |
| `Rename(F, N)` | `ODIN_FILE_RENAME(var F; const NewName: String)` |
| `Read(F, v)` (per variabel) | `ODIN_FILE_READ(var F; var V; Size: LongInt)` |
| `Write(F, v)` (per nilai) | `ODIN_FILE_WRITE(var F; const V; Size: LongInt)`; nilai yang bukan variabel disalin dulu ke variabel sementara |
| `BlockRead(F, Buf, N[, Res])`, `BlockWrite(...)` | `ODIN_FILE_BLOCKREAD(var F; var Buf; Count: Int64; var Res: LongInt)`, `ODIN_FILE_BLOCKWRITE(var F; const Buf; Count: Int64; var Res: LongInt)`; tanpa `Res`, RTL memakai `Res = -1` sebagai tanda "tidak diminta" dan menyetel error 100/101 bila jumlahnya kurang |
| `Seek(F, N)` | `ODIN_FILE_SEEK(var F; N: Int64)` |
| `FilePos(F)`, `FileSize(F)` | `ODIN_FILE_POS(var F): Int64`, `ODIN_FILE_SIZE(var F): Int64` |
| `Eof(F)` | `ODIN_FILE_EOF(var F): Boolean` |

### Lain-lain

| Bawaan | Rutin RTL |
| --- | --- |
| `New(P)`, `GetMem(P, N)` | `ODIN_GETMEM(Size: Int64): Pointer` |
| `Dispose(P)`, `FreeMem(P[, N])` | `ODIN_FREEMEM(P: Pointer; Size: Int64)` |
| `FillChar(X, N, V)` | `ODIN_FILLCHAR(var X; Count: Int64; Value: Byte)` (`V` boleh ordinal apa pun) |
| `Random`, `Random(N)` | `ODIN_RANDOM_REAL: Real`, `ODIN_RANDOM_INT(Range: Int64): Int64` |
| `RunError[(N)]` | `ODIN_RUNERROR(Code: LongInt)` (tanpa argumen: 0) |
| `Halt[(N)]` | `ODIN_HALT(Code: LongInt)` |
| `Str(x:w:d, S)` | `ODIN_STR_INT(V: Int64; Width: LongInt; var S; MaxLen: LongInt)`, `ODIN_STR_REAL(V: Real; Width, Decimals: LongInt; var S; MaxLen: LongInt)` |
| `Val(S, x, Code)` | `ODIN_VAL_INT(const S: String; var Code: LongInt): Int64`, `ODIN_VAL_REAL(const S: String; var Code: LongInt): Real` |
| `{$I+}` setelah I/O | `ODIN_IOCHECK` |

Rutin biasa (bukan bawaan) yang tetap dideklarasikan di unit System: `ParamCount`, `ParamStr`, `IOResult`, `UpCase`, `Copy`, `Pos`, `Delete`, `Insert`, `Move`, `Pi`, `Sin`, `Cos`, `ArcTan`, `Exp`, `Ln`, `Randomize`, `MkDir`, `ChDir`, `RmDir`, `GetDir`.

## 4. `TextRec` dan `FileRec`

```pascal
TextRec = record
  Handle: LongInt;      { deskriptor berkas }
  Mode: LongInt;        { fmClosed, fmInput, fmOutput }
  BufSize: LongInt;
  BufPos: LongInt;
  BufEnd: LongInt;
  Flags: LongInt;       { bit 0: terminal; bit 1: flush setiap Write }
  FlushFunc: Pointer;   { procedure(var F: TextRec), atau nil }
  UserData: array[1..16] of Byte;
  Name: array[0..255] of Char;   { diakhiri #0 }
  Buffer: TextBuf;
end;
```

- Bila `FlushFunc` tidak nil, `FlushText` memanggilnya alih-alih menulis `Buffer[0..BufPos-1]` ke `Handle`. Hook ini wajib mengosongkan buffer (`BufPos := 0`).
- Pada berkas input, `FlushFunc` dipanggil saat buffer habis, alih-alih `read` dari `Handle`. Hook mengisi `Buffer` dan menyetel `BufEnd` (0 berarti akhir berkas).
- `Assign` mengosongkan `FlushFunc`; `Reset`/`Rewrite` mempertahankannya dan menyalakan bit 1 `Flags` bila hook terpasang. Jadi `AssignCrt(F)` = `Assign(F, '')` lalu memasang hook.
- Unit Crt memasang hook ini di `Output` supaya setiap karakter melewati Crt: posisi kursor, jendela `Window`, warna, dan scroll.
- Bit 1 di `Flags` membuat `ODIN_WRITE_END` dan `ODIN_WRITELN` memanggil `FlushText`, sehingga keluaran tampil di akhir setiap pernyataan `Write`/`WriteLn` seperti di TP. Item-item dalam satu pernyataan tidak di-flush satu per satu, jadi `Write('A', WhereX)` mencetak posisi sebelum `A`, sama dengan TP dan FPC.
- `FileRec` dimulai dengan `Handle`, `Mode`, `RecSize`, lalu data internal RTL, lalu `Name` (diakhiri #0).
- `Name` berada di offset 48 pada `TextRec` maupun `FileRec`, sehingga rutin dengan parameter berkas tanpa tipe (misalnya `GetFAttr` di unit Dos) bisa membaca nama berkas dari jenis berkas apa pun.

## 5. Akhir program dan runtime error

- Variabel System: `ExitProc: Pointer`, `ExitCode: LongInt`, `ErrorAddr: Pointer`, `InOutRes: LongInt`.
- `Halt(N)` menyetel `ExitCode := N`, lalu menjalankan rantai `ExitProc` (selama `ExitProc <> nil`: ambil, setel `nil`, panggil). Setelah itu Output di-flush dan proses keluar dengan `ExitCode`.
- Runtime error menyetel `ErrorAddr` dan `ExitCode`, menjalankan rantai `ExitProc` yang sama, lalu menulis ke stderr `Runtime error N at $XXXXXXXXXXXXXXXX`, diikuti satu baris `  $XXXXXXXXXXXXXXXX` dan satu baris kosong, seperti FPC.
- Alamat galat adalah alamat kembali ke kode pengguna. Rutin Pascal mendapatkannya lewat `ODIN_RETADDR` (shim assembly yang membaca `[rbp+8]` milik rutin pemanggilnya).

## 6. Build debug (`odinpc build --debug`)

Compiler menyisipkan pengait debugger hanya di rutin dari sumber pengguna, tidak di RTL. Variabel dan rutinnya ada di bagian interface unit System, dan kodenya di `rtl/system/debug.inc`.

| Simbol | Arti |
| --- | --- |
| `ODIN_DBG_LINE: LongInt` | Id statement yang sedang berjalan. Indeksnya ke tabel `lines` di `.odbg`. |
| `ODIN_DBG_DEPTH: LongInt` | Jumlah rutin terinstrumentasi di call stack. Program utama berada di kedalaman 1. |
| `ODIN_DBG_SHARED: PByteArray` | Memori bersama dengan debugger, atau `nil` tanpa debugger. Byte 0 = mode langkah, byte 1 = permintaan pause, byte `16 + id` = breakpoint. |
| `ODIN_DBG_STACK: array[0..4095] of TDbgFrame` | Shadow stack. Entri ke-`d` berisi id baris pemanggil, indeks rutin, dan frame pointer rutin pada kedalaman `d`. |
| `ODIN_DBG_INIT(LineCount)` | Dipanggil `_main` sesudah `ODIN_STARTUP`. Menghubungi debugger bila `$ODIN_DEBUG_SOCKET` dan `$ODIN_DEBUG_SHM` ada. |
| `ODIN_DBG_HOOK(Id)` | Dipanggil di awal statement bila debugger terpasang dan sedang melangkah, ada pause, atau ada breakpoint di statement itu. |

Kode yang disisipkan:

- **Setiap statement sumber:** `ODIN_DBG_LINE := id`, lalu `ODIN_DBG_HOOK(id)` bila `ODIN_DBG_SHARED <> nil` dan byte 0/1 atau byte `16 + id` tidak nol. Potongan hasil penurunan satu statement (`Write`, `Inc`, ...) berbagi satu titik. Loop `while` diperiksa sekali per iterasi pada kondisinya, dan `repeat` pada `until`.
- **Masuk rutin:** kedalaman naik, lalu entri shadow stack diisi.
- **Keluar rutin:** `ODIN_DBG_LINE` dikembalikan ke baris pemanggil, lalu kedalaman turun.

Tanpa debugger, build debug berjalan seperti build biasa. Korpus `tests/pascal` dijalankan dengan kedua jenis build.

### Protokol program ↔ `odinpc debug`

Lewat Unix socket. Setiap frame terdiri dari 1 byte jenis, panjang payload u32, lalu payload. Semua bilangan little-endian.

| Arah | Frame | Payload |
| --- | --- | --- |
| program → | `HELLO` (1) | protokol u16, alamat `ODIN_DBG_LINE` u64, alamat `ODIN_DBG_STACK` u64 |
| program → | `STOP` (2) | id baris u32, kedalaman u32, alasan u8 (1 pause, 2 breakpoint, 3 langkah) |
| program → | `RTERR` (3) | kode u32, alamat u64, id baris u32 |
| program → | `EXIT` (4) | kode keluar i32 |
| program → | `DATA` (5) | status u8 (0 = berhasil), lalu byte-byte memori |
| program → | `ACK` (6) | status u8 |
| → program | `RESUME` (1) | mode u8 (0 run, 1 into, 2 over, 3 out), kedalaman target u32 |
| → program | `READ` (2) | alamat u64, panjang u32 (maksimal 4096) |
| → program | `WRITE` (3) | alamat u64, lalu byte-byte yang ditulis |

- Sesudah `HELLO`, program menunggu `RESUME` pertama. Selama berhenti, program melayani `READ`/`WRITE` sampai ada `RESUME`.
- Memori disalin lewat pipe, sehingga alamat yang tidak sah menghasilkan status gagal, bukan crash.
- Mode `over` berhenti pada kedalaman ≤ target, dan mode `out` pada kedalaman < target.
- Ctrl-C (SIGINT) menyalakan byte pause. Unit Crt tidak mengambil alih SIGINT yang sudah ditangani.

### Laporan runtime error untuk Run biasa

Bila `$ODIN_ERROR_FILE` ada, `RunErrorAt` menulis `kode alamat header` (desimal) ke berkas itu. `header` adalah alamat header image saat program berjalan. IDE lalu menghitung alamat link-time (`alamat - header + image_base`) dan mencari barisnya di tabel `addresses` pada `.odbg`. Cara ini juga berlaku untuk build tanpa `--debug`.

## 7. Object (`object`)

**Layout.** Field warisan diletakkan lebih dulu, lalu field milik object itu sendiri, dengan alignment alami seperti record. Pointer VMT diletakkan sesudah field milik tipe pertama dalam hierarki yang membutuhkannya, yaitu tipe yang punya constructor, destructor, atau metode virtual. Ukurannya dibulatkan ke alignment. Aturan ini sama dengan FPC `-Mtp`.

**VMT.** VMT adalah data global baca-saja bernama `UNIT.TOBJ.$VMT`:

| Offset | Isi |
| --- | --- |
| 0 | ukuran object (Int64) |
| 8 | minus ukuran object (Int64) |
| 16 | VMT induk, atau nil |
| 24 + 8·n | alamat metode virtual slot `n` |

Metode yang meng-override memakai slot milik leluhurnya.

**Metode.** Sebuah metode adalah rutin `UNIT.TOBJ.NAMA` dengan parameter pertama `Self: ^TObj`, yaitu pointer ke object.

- **Constructor** menerima parameter kedua, `Vmt: Pointer`, dan mengembalikan `Self`. Hasilnya nil bila `Fail` dipanggil. Isi constructor diawali kode berikut:
  - bila `Self = nil`, constructor mengalokasikan object dengan `ODIN_GETMEM` sebesar ukuran yang tercatat di VMT;
  - bila `Vmt <> nil`, pointer VMT disimpan ke object.

  `Fail` membebaskan object hanya bila constructor itu sendiri yang mengalokasikannya, lalu mengembalikan nil.
- **Pemanggilan constructor:**
  - `New(P, Init)` dan `New(PT, Init)` memanggil constructor dengan `Self = nil` dan VMT tipe itu;
  - `Obj.Init` memanggilnya dengan `Self = @Obj`;
  - `inherited Init` dan `TParent.Init` memakai `Vmt = nil`.
- **`Dispose(P, Done)`** memanggil destructor (virtual bila dideklarasikan virtual), lalu `ODIN_FREEMEM`.
- **Panggilan virtual** mengambil alamat metode dari `[[Self + offset VMT] + 24 + 8·slot]`. Di bawah `{$R+}`, VMT diperiksa lebih dulu: VMT nil, atau `ukuran + (-ukuran) <> 0`, menghasilkan `ODIN_OBJECTERROR` (runtime error 210).
- **`TypeOf`:** `TypeOf(T)` adalah alamat VMT T, dan `TypeOf(Obj)` adalah pointer VMT yang tersimpan di object. `SizeOf(Obj)` untuk object yang punya VMT membaca ukuran dari VMT.

**Shim untuk unit Objects** (`rtl/system/arch/*.s`):

| Simbol | Arti |
| --- | --- |
| `ODIN_CALLERFRAME` | Frame pointer dari pemanggil rutin Pascal yang memanggil shim ini. |
| `ODIN_CALLLOCAL(Code, Frame, Item)` | Memanggil `Code(Item)` dengan `Frame` sebagai static link (R10). `ForEach`, `FirstThat`, dan `LastThat` memakainya untuk prosedur lokal milik pemanggilnya. |
| `ODIN_CALLLOCAL5(Code, Frame, A1..A5)` | Seperti `ODIN_CALLLOCAL` dengan lima argumen (argumen kelima lewat slot stack pertama). `TOutlineViewer.FirstThat`/`ForEach` di Odin Vision memakainya. |

`TStream.Get` dan `TStream.Put` memanggil `Load` dan `Store` lewat tipe prosedural yang mengikuti ABI di atas: `function(Self, Vmt: Pointer; var S: TStream): Pointer` dan `procedure(Self: Pointer; var S: TStream)`.

## 8. Build hitung langkah (`odinpc build --count-steps`)

Build untuk laporan metrik dan penilaian (latihan, lomba). Compiler menginstrumentasi rutin dari sumber pengguna seperti `--debug`, tetapi menghitung langkah alih-alih memanggil debugger; RTL tidak diinstrumentasi. `--debug` dan `--count-steps` tidak bisa dipakai bersama. Variabel dan rutinnya ada di bagian interface unit System, dan kodenya di `rtl/system/stats.inc`.

Tujuannya angka yang sama untuk sumber, masukan, dan versi `odinpc` yang sama di setiap OS dan CPU. `odinpc/tests/steps.rs` membandingkan laporan program di `tests/steps/` dengan berkas yang sama di semua target CI.

| Simbol | Arti |
| --- | --- |
| `$STEPS` | Larik milik code generator, satu Int64 per id statement (indeks yang sama dengan `lines` di `.odbg`). |
| `ODIN_STEP_BUDGET: Int64` | Sisa langkah. Setiap langkah mengurangi satu; di bawah nol statement itu memanggil `ODIN_STEPLIMIT`. |
| `ODIN_STEP_WEIGHT: Int64` | Langkah yang dibebankan untuk menyalin data (lihat di bawah). |
| `ODIN_STAT_DEPTH`, `ODIN_STAT_MAXDEPTH`, `ODIN_STAT_DEPTHLIMIT: LongInt` | Kedalaman rutin terinstrumentasi di call stack (program utama = 1), maksimumnya, dan batasnya. |
| `ODIN_STEPS_INIT(PointCount; Counts)` | Dipanggil `_main` sesudah `ODIN_STARTUP` dengan jumlah id dan alamat `$STEPS`. Membaca variabel lingkungan di bawah. |
| `ODIN_STEPLIMIT` | Runtime error 240 (batas langkah) di statement pemanggil. |
| `ODIN_DEPTHLIMIT` | Runtime error 202 (stack overflow) di rutin pemanggil. |

Yang dihitung, satu langkah per kejadian:

- setiap statement sumber, dengan titik yang sama seperti build debug: potongan hasil penurunan satu statement (`Write`, `Inc`, ...) berbagi satu titik; `while` dihitung setiap kali kondisinya diperiksa; `repeat` sekali saat masuk dan setiap kali `until` diperiksa;
- `for` sekali saat masuk dan sekali lagi setiap iterasi, sehingga `for i := 1 to N do ;` bernilai N + 1 langkah;
- menyalin data: assignment bertipe terstruktur dan parameter nilai bertipe terstruktur di rutin terinstrumentasi, juga `Move` dan `FillChar`, dibebani satu langkah per 64 byte (dibulatkan ke bawah), dicatat di `ODIN_STEP_WEIGHT` dan dikurangkan dari anggaran.

Statement di dalam RTL (isi `WriteLn`, `Pos`, ...) tidak dihitung; rutin RTL yang biayanya bergantung pada ukuran data tak terbatas hanya `Move` dan `FillChar`, dan keduanya dibebani seperti di atas. Ekspresi tidak dihitung terpisah: pemanggilan fungsi pengguna di dalam ekspresi dihitung lewat statement di fungsi itu.

Agar hasilnya sama di semua mesin, build ini juga:

- mengisi nol setiap variabel lokal dan hasil fungsi saat rutin dimulai (isi lokal yang belum diisi bergantung pada OS);
- membuat `Randomize` mempertahankan `RandSeed` dari `$ODIN_RANDSEED` (bawaan 0);
- mencatat heap dalam ukuran yang diminta lewat `New`/`GetMem` dan dibebaskan lewat `Dispose`/`FreeMem`, bukan ukuran yang dibulatkan pustaka C. Handle pencarian berkas unit Dos tidak termasuk heap program.

Variabel lingkungan (bilangan desimal; kosong, 0, atau tidak sah berarti tanpa batas):

| Variabel | Arti |
| --- | --- |
| `ODIN_STATS_FILE` | Berkas laporan. Tanpa variabel ini tidak ada laporan. |
| `ODIN_STEP_LIMIT` | Langkah maksimum; langkah berikutnya menjadi runtime error 240. |
| `ODIN_HEAP_LIMIT` | Byte heap maksimum yang boleh terpakai bersamaan; permintaan yang melewatinya menjadi runtime error 203. |
| `ODIN_DEPTH_LIMIT` | Kedalaman rutin maksimum; panggilan yang melewatinya menjadi runtime error 202. |
| `ODIN_RANDSEED` | Nilai awal `RandSeed`. |

Sebelum runtime error 240 atau 202, batasnya diangkat agar rantai `ExitProc` tetap bisa berjalan. Laporan ditulis sekali di akhir program (normal maupun runtime error) oleh `DoExit`, sesudah `ExitProc`; program yang dihentikan dari luar (sinyal, batas waktu OS) tidak menulis laporan. Bentuknya teks, satu butir per baris, diakhiri LF:

```
otp-stats 1
exit KODE
steps TOTAL
weight LANGKAH_SALIN
heap_peak BYTE
heap_end BYTE
depth_max N
points JUMLAH_ID
p ID JUMLAH
...
```

`steps` = jumlah semua penghitung ditambah `weight`. Baris `p` hanya untuk id yang pernah berjalan, urut naik; baris sumbernya diambil dari `lines` di `.odbg`. Pembaca harus mengabaikan kunci yang tidak dikenalnya, dan versi di baris pertama naik bila arti angka yang sudah ada berubah.
