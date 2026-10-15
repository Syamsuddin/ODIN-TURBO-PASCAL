KORPUS GALAT SEMANTIK
Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

Setiap NAMA.PAS berisi satu galat semantik. NAMA.err berisi "kode baris
kolom" dari galat pertama yang dilaporkan `odinpc check`. Baris dan kolom
sama dengan FPC 3.2.2 (fpc -Mtp), kecuali tiga kasus yang sengaja berbeda:
- DUPLICATE: Odin menunjuk identifier ganda (kolom 5), FPC menunjuk token
  sesudahnya (kolom 6).
- DIV_ZERO: Odin menunjuk pembagi nol (kolom 15), FPC menunjuk operator div
  (kolom 11).
- NOT_VAR: Odin menunjuk argumen yang bukan variabel (kolom 10), FPC
  menunjuk token sesudahnya (kolom 11).
Diuji oleh toolchain/crates/odinpc/tests/semantic.rs.
