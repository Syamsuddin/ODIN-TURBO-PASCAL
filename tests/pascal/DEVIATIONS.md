# Perbedaan yang disengaja dari FPC

Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

Sampai 2.3.0, ekspektasi korpus `tests/pascal/` dibuat dengan FPC 3.2.2 (`fpc -Mtp`) sebagai pembanding. Sejak FPC dicabut, ekspektasi program baru dibuat dengan `scripts/bless_corpus.py` dan ditinjau terhadap perilaku Turbo Pascal 7. Bagian ini mencatat perilaku Odin yang sengaja berbeda dari FPC. Program di daftar bawah (dalam tanda petik balik, misalnya `lang/CONTOH.PAS`) punya ekspektasi tulisan tangan.

## Perilaku

| Hal | FPC 3.2.2 | Odin | Alasan |
| --- | --- | --- | --- |
| `Extended` | 10 byte (x87) | sama dengan `Double`, 8 byte | Tidak ada x87 di arm64; `SizeOf(Extended)` berbeda. |
| `WriteLn(1.5)` tanpa lebar | Format ikut tipe yang dipilih FPC untuk literal (Single: 9 digit, Extended: 20 digit) | Selalu format `Real` (Double), 17 digit signifikan | Literal real di Odin selalu bertipe `Real`. |
| `Write` untuk enumerasi | Menulis nama nilai | Galat 64 | Turbo Pascal 7 tidak mengizinkannya. |
| `Exit(nilai)` | Didukung | Galat 900 | Bukan sintaks Turbo Pascal 7. |
| Runtime error | Baris alamat untuk setiap frame | Satu baris alamat | Penelusuran frame menyusul bersama debugger (Tahap 5). |
| Posisi beberapa galat semantik | Token sesudah identifier atau operator | Identifier atau operand itu sendiri | Lihat `semantic/README.txt`. |
| `Exp`, `Ln`, `Sin`, `Cos`, `ArcTan` | Dihitung dalam `Extended` x87: `WriteLn(Exp(1000))` mencetak `1.97...E+0434`, `Sin(1e300)` menghasilkan `1e300` (batas instruksi `fsin`) | Dihitung dalam `Double`: `Exp(1000)` berakhir dengan runtime error 205, `Sin(1e300)` bernilai benar | Tidak ada x87 di arm64; hasil `Double` sama dengan yang disimpan ke variabel `Real`. |
| Stack overflow | Mati karena SIGSEGV (exit 139), keluaran yang masih di buffer hilang | Runtime error 202 setelah keluaran di-flush dan rantai `ExitProc` dijalankan | Perilaku TP; pesan lebih jelas. |
| `TCollection.Pack` (unit Objects) | Ikut memadatkan slot sisa sesudah `Count` (sampai `Limit`). Setelah `Delete`, pointer lama di slot itu bisa muncul lagi dan terbebaskan dua kali | Hanya membuang item `nil` di dalam `Count`, sesuai dokumentasi TP7 | Bug FPC 3.2.2; korpus menghindari urutan `Delete` lalu `Pack`. |
| `TBufStream.Truncate` sesudah membaca lewat buffer (unit Objects) | `Done` menulis ulang isi buffer baca, sehingga berkas kembali memanjang | Berkas tetap terpotong | Perilaku FPC itu tidak sesuai maksud `Truncate`. |
| `ForEach`/`FirstThat`/`LastThat` dengan prosedur global | Frame pemanggil dikirim sebagai argumen pertama, sehingga prosedur global menerima argumen yang salah | Frame dikirim lewat static link (R10), sehingga prosedur lokal maupun global benar | TP mensyaratkan prosedur lokal; korpus memakai prosedur lokal. |
| Slot ketiga VMT | Pointer ke pointer VMT induk | Pointer VMT induk langsung | Hanya terlihat bila VMT dibaca mentah. |
| `Dos.Exec` | Tidak mem-flush `Output` sebelum menjalankan program lain | Mem-flush `Output` dulu | Urutan keluaran di layar sama dengan urutan di program. |

## Program dengan ekspektasi tulisan tangan

- `runtime/RTE_STACK.PAS`: stack overflow, lihat tabel di atas.
