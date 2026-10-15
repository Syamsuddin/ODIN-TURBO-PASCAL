# Spesifikasi Perilaku Odin Vision

Lisensi GNU GPL v3 atau yang lebih baru, hak cipta (c) 2026 Syams Ideris.

Odin Vision adalah implementasi clean-room API Turbo Vision TP7 untuk runtime library Odin. Dokumen ini satu-satunya rujukan perilaku untuk kode di `rtl/vision/`. Isinya diturunkan dari dokumentasi publik API Turbo Vision dan dari keputusan desain proyek ini, bukan dari kode sumber Borland atau Free Vision. Kode tersebut tidak boleh dibuka saat mengubah unit-unit ini.

Catatan sejarah: rencana meminta dokumen ini ditulis sebelum kode. Kenyataannya dokumen ini ditulis bersamaan dengan kode Tahap 7, lalu disesuaikan dengan perilaku yang diuji.

## 1. Unit dan ketergantungan

| Unit | Isi | `uses` di interface |
| --- | --- | --- |
| `Drivers` | layar, keyboard, mouse, `TEvent`, `MoveBuf`/`MoveChar`/`MoveStr`/`MoveCStr`, `FormatStr` | `Objects` |
| `Memory` | buffer dengan ukuran tersimpan; `LowMemory` selalu False | `Objects` |
| `HistList` | riwayat input line per nomor Id | `Objects` |
| `Views` | `TView`, `TGroup`, `TFrame`, `TScrollBar`, `TScroller`, `TListViewer`, `TWindow` | `Objects`, `Drivers` |
| `Menus` | `TMenuBar`, `TMenuBox`, `TMenuPopup`, `TStatusLine` | `Objects`, `Drivers`, `Views` |
| `Validate` | `TFilterValidator`, `TRangeValidator`, `TPXPictureValidator`, `TStringLookupValidator` | `Objects` |
| `Dialogs` | `TDialog` dan kontrolnya, `THistory` | `Objects`, `Drivers`, `Views`, `Validate` |
| `App` | `TBackground`, `TDesktop`, `TProgram`, `TApplication` | `Objects`, `Drivers`, `Memory`, `HistList`, `Views`, `Menus`, `Dialogs` |
| `MsgBox` | `MessageBox`, `InputBox` | `Objects` |
| `StdDlg` | `TFileDialog`, `TChDirDialog`, `TFileList`, `TDirListBox` | `Objects`, `Drivers`, `Views`, `Dialogs`, `Dos` |
| `Editors` | `TEditor`, `TMemo`, `TFileEditor`, `TEditWindow`, `TIndicator` | `Objects`, `Drivers`, `Views`, `Dialogs` |
| `Outline` | `TOutlineViewer`, `TOutline` | `Objects`, `Drivers`, `Views` |

`Validate`, `MsgBox`, `StdDlg`, dan `Editors` saling memakai lewat `uses` di bagian implementation (misalnya `Validate` → `MsgBox` → `App` → `Dialogs` → `Validate`). Seperti TP, compiler hanya melarang siklus di bagian interface.

`ColorSel` dan `TextView` belum ada.

## 2. Layar (Drivers)

- `InitVideo` membaca ukuran terminal dengan `TIOCGWINSZ` (bawaan 80×25, maksimum 255×255), lalu masuk ke layar alternatif (`ESC[?1049h`). `DoneVideo` kembali ke layar normal.
- `ScreenBuffer^` berisi sel `Word`: byte rendah karakter CP437, byte tinggi atribut (warna depan di bit 0–3, latar di bit 4–6, bit 7 = latar terang).
- `UpdateScreen` hanya mengirim sel yang berubah sejak kiriman terakhir, sebagai UTF-8. Atribut menjadi SGR 30–37/90–97 dan 40–47/100–107. Kursor perangkat keras mengikuti `SetCursorState`.
- `WaitForEvent(ms)` memanggil `UpdateScreen`, lalu menunggu input paling lama `ms` milidetik.

## 3. Input (Drivers)

- Terminal dipasang dalam mode raw (tanpa `ICANON`, `ECHO`, `IEXTEN`, `ISIG`, `ICRNL`, `IXON`), jadi Ctrl+C, Ctrl+S, dan Ctrl+Q sampai ke program. Mode dipulihkan oleh `DoneEvents`, oleh `ExitProc`, dan oleh handler sinyal.
- Kode tombol mengikuti TP: `KeyCode = ScanCode shl 8 + CharCode`. Urutan CSI dan SS3 xterm didekode, termasuk parameter modifier (`1 + Shift + 2·Alt + 4·Ctrl`). Shift, Ctrl, dan Alt untuk F1–F10 memberi kode `kbShiftF1`, `kbCtrlF1`, dan `kbAltF1`. `ESC` diikuti sebuah huruf berarti Alt+huruf. UTF-8 dari keyboard dipetakan balik ke CP437.
- `GetShiftState` mengembalikan modifier dari tombol terakhir.
- Mouse memakai pelaporan SGR (`ESC[?1000h`, `?1002h`, `?1006h`). Selama tombol mouse ditekan, `evMouseAuto` dibuat berulang. Dua klik di sel yang sama dalam `DoubleDelay` tick menyalakan `Event.Double`.

## 4. View dan group

- Urutan-z: subview sebuah group membentuk daftar melingkar. `Last^.Next = First`, dan `First` adalah view paling atas. `Insert` menaruh view paling atas. Urutan penyisipan adalah arah `Prev`.
- Menggambar memakai clipping per sel. `WriteBuf`/`WriteLine` hanya menulis sel yang berada di dalam semua owner dan tidak tertutup view lain di depannya atau di depan salah satu owner. Sel yang jatuh di bayangan view depan (`sfShadow`, ukuran `ShadowSize`) diberi atribut `ShadowAttr`. Karena itu urutan menggambar tidak penting. Menyembunyikan, memindah, atau mengubah ukuran view cukup diikuti `Owner^.Redraw`.
- Sebuah view hanya menggambar bila `sfVisible` dan `sfExposed`. `sfExposed` mengalir dari owner ke subview yang tampak.
- Palet: `GetColor`/`MapColor` memetakan indeks lewat palet view, lalu lewat palet setiap owner sampai aplikasi. Palet aplikasi memberi atribut akhirnya. Indeks 0 atau indeks di luar palet memberi `ErrorAttr`.
- Event: event posisional (mouse) diberikan ke subview paling atas di bawah mouse. Event terfokus (keyboard, perintah) melewati tiga fase: subview `ofPreProcess`, lalu `Current`, lalu subview `ofPostProcess`. Broadcast diberikan ke semua subview.
- Fokus: `Select` membuat view menjadi `Current` di owner-nya. View `ofTopSelect` dipindah ke depan. `ResetCurrent` memilih view terpilih pertama dari depan.
- `ExecView` menjalankan view secara modal: view dimasukkan bila belum punya owner, diberi `sfModal`, lalu `Execute` mengambil event sampai `EndModal` dan `Valid(EndState)` lolos. Perintah dan `Current` dipulihkan sesudahnya.
- `TFrame` adalah subview pertama (terbawah) sebuah jendela. Ia menggambar seluruh bidang jendela: garis tunggal untuk jendela pasif, garis ganda untuk jendela aktif, ikon tutup `[■]`, ikon zoom `[↑]` (atau `[↕]` bila jendela memenuhi owner), nomor jendela, dan pojok ubah-ukuran. Judul tidak menimpa ikon dan nomor.
- `TGroup.ForEach`/`FirstThat` menerima prosedur lokal milik pemanggil (konvensi TP), dipanggil lewat shim `ODIN_CALLLOCAL`.

## 5. Menu dan status line

- `TMenuView.Execute` modal. Di menu bar: Left/Right berpindah item, Down/Enter membuka submenu. Setelah submenu pernah terbuka, berpindah item langsung membuka submenu item itu. Di menu box: Up/Down/Home/End berpindah item (garis pemisah dilewati), Enter memilih. Left/Right di box yang induknya menu bar menutup box lalu berpindah item bar. Esc menutup satu tingkat. Huruf `~X~` memilih item di menu aktif. Alt+huruf memakai menu bar. Hotkey item (`KeyCode`) bekerja dari mana saja.
- Mouse: klik item bar membuka submenu, dan melepas tombol di item box memilihnya. Klik di luar semua menu menutup menu tanpa diteruskan ke aplikasi.
- Item dengan perintah yang dinonaktifkan ditampilkan redup dan tidak bisa dipilih. Menu diperbarui saat broadcast `cmCommandSetChanged`.
- `TStatusLine` adalah pre-process. Tombol item diubah menjadi perintah di tempat. `TProgram.GetEvent` juga memberikan setiap event keyboard ke status line, termasuk saat dialog modal berjalan. Definisi status dipilih menurut help context view modal teratas (`Update` dipanggil dari `Idle`).

## 6. Aplikasi

- `TApplication.Init` memanggil `InitMemory`, `InitVideo`, `InitEvents`, `InitSysError`, dan `InitHistory`, lalu membuat desktop, status line, dan menu bar. `Done` membalikkannya.
- `TProgram.GetEvent` mengambil event tertunda (`PutEvent`), lalu mouse, lalu keyboard. Bila semuanya kosong, ia memanggil `Idle` lalu `WaitForEvent(50)`.
- Alt+1…Alt+9 memilih jendela bernomor. `cmQuit` mengakhiri `Run`.
- `TDesktop.Tile` menyusun jendela `ofTileable` yang tampak dalam grid sekitar akar N kolom, dengan jendela depan di kiri atas. Kolom terakhir menampung sisa jendela. `Cascade` menumpuk jendela bergeser satu sel, dengan jendela depan di posisi terdalam. `cmNext` membawa jendela terbawah ke depan, sedangkan `cmPrev` menaruh jendela depan di belakang semuanya. Jendela tidak `ofTileable` secara bawaan; `TEditWindow` memasangnya.
- `DosShell` menjalankan `$SHELL` (atau `/bin/sh`) di layar normal.

## 7. Palet

Tata letak indeks mengikuti dokumentasi API Turbo Vision. Nilai warnanya ditetapkan sendiri oleh proyek ini:

| Indeks aplikasi | Isi |
| --- | --- |
| 1 | desktop (pola `░`, cyan di atas biru) |
| 2–7 | menu dan status line: normal, redup, shortcut, terpilih, terpilih redup, shortcut terpilih (sorotan hijau) |
| 8–15, 16–23, 24–31 | jendela biru, cyan, abu-abu: bingkai pasif, bingkai aktif, ikon, scroll bar (2), teks scroller normal dan terpilih, cadangan |
| 32–63, 64–95, 96–127 | dialog abu-abu, biru, cyan |

Urutan 32 entri palet dialog: bingkai (3), scroll bar (2), static text, label (normal, terpilih, shortcut), tombol (normal, default, terpilih, redup, shortcut, bayangan), cluster (normal, terpilih, shortcut), input line (normal, terpilih, panah), riwayat (panah, sisi), scroll bar jendela riwayat (2), list viewer (normal, fokus, terpilih, pemisah), info pane, cluster redup, cadangan.

Palet hitam-putih dan monokrom diturunkan otomatis dari palet warna. `smBW80` dan `smMono` memilih palet itu.

## 8. Kontrol dialog

- Esc di dialog menjadi `cmCancel`, dan Enter menjadi broadcast `cmDefault` (ditangkap tombol default). `cmOK`/`cmCancel`/`cmYes`/`cmNo` mengakhiri dialog modal. `Valid(cmCancel)` selalu True.
- Tab dan Shift+Tab berpindah kontrol menurut urutan penyisipan. Huruf `~X~` label dan tombol bekerja dengan Alt, atau tanpa Alt di fase post-process (saat kontrol terfokus tidak memakai tombol itu).
- `TButton`: muka tombol mengisi semua kolom kecuali yang terakhir. Bayangan `▄`/`█` ada di kolom kanan dan `▀` di baris bawah. Tombol yang ditekan bergeser satu sel ke kanan tanpa bayangan. Tombol yang mendapat fokus menjadi default sementara (`cmGrabDefault`/`cmReleaseDefault`).
- `TInputLine`: geser, seleksi dengan Shift+panah dan mouse, klik ganda memilih semua, Ins untuk mode timpa, Ctrl+Y untuk mengosongkan. Validator dengan `voOnAppend` hanya diperiksa saat mengetik di akhir teks. Mengetik menimpa seleksi yang sampai ke akhir teks dihitung sebagai menambah di akhir. Tombol yang ditolak validator membuat isi, kursor, dan seleksi tetap seperti sebelumnya.
- `TCluster`: item disusun per kolom setinggi view, dan lebar kolom mengikuti teks terpanjang. Up/Down berputar, Left/Right pindah kolom, spasi menekan item. Radio button ikut berpindah nilai saat kursor berpindah.
- `TStaticText`: teks dibungkus per kata. `#13` memulai baris baru, dan baris yang diawali `#3` ditengahkan.
- `THistory`: Down di input line atau klik ikon `▐↓▌` membuka daftar riwayat. Entri 0 adalah yang terbaru, dan daftar membuka dengan entri 1 terfokus. Isi input dicatat ke riwayat saat fokus pindah dan saat tombol mana pun ditekan.

Ukuran data `GetData`/`SetData` mengikuti TP7, berurutan sesuai penyisipan:

| Kontrol | Ukuran |
| --- | --- |
| `TInputLine` | `MaxLen + 1` (string pendek), atau ukuran dari validator dengan `voTransfer` |
| `TCheckBoxes`, `TRadioButtons` | 2 (`Word`) |
| `TMultiCheckBoxes` | 4 (`LongInt`) |
| `TListBox` | `SizeOf(TListBoxRec)`: pointer + `Word`, 16 byte di 64-bit |
| `TParamText` | satu `PtrInt` per parameter |
| `TMemo` | `SizeOf(Sw_Word)` + `BufSize` |

Record data sebaiknya `packed record`, karena record biasa disejajarkan seperti FPC.

## 9. Validator

Bahasa picture:

| Karakter | Arti |
| --- | --- |
| `#` | angka |
| `?` | huruf |
| `&` | huruf, dijadikan kapital |
| `@` | karakter apa pun |
| `!` | karakter apa pun, dijadikan kapital |
| `;` | karakter berikutnya literal |
| `*N` | elemen berikutnya diulang N kali |
| `*` | elemen berikutnya diulang 0 kali atau lebih |
| `[ ]` | opsional |
| `{ }` | kelompok |
| `,` | pilihan |

Karakter lain adalah literal yang dicocokkan tanpa membedakan huruf besar-kecil, lalu diganti dengan bentuk di picture. Pencocokan mencoba semua kemungkinan dan memilih hasil terbaik: lengkap, lalu belum lengkap, lalu salah. Dengan AutoFill, literal di akhir input diisikan, dan literal yang dilewati pengguna disisipkan. Input kosong selalu sah (`prEmpty`). Picture yang kurungnya tidak seimbang membuat `Status = vsSyntax`.

Pesan galat validator, judul `MessageBox`, dan label tombol bawaan berbahasa Inggris, seperti label menu Turbo Vision.

## 10. Dialog standar

- `TFileDialog`: path memakai `/`, dan nama yang diawali titik tidak ditampilkan. Berkas tampil lebih dulu, lalu direktori (dengan akhiran `/`), lalu `..`. Urutannya tidak membedakan huruf besar-kecil. Nama tanpa ekstensi mendapat ekstensi wildcard. Nama dengan wildcard mengganti wildcard, dan nama direktori membuka direktori itu. Input line menampung 255 karakter, jadi data dialog ini adalah `PathStr` (256 byte).
- `TChDirDialog` menampilkan pohon dari `/` sampai direktori kerja beserta subdirektorinya. OK menjalankan `ChDir`, dan direktori yang tidak ada memunculkan pesan galat.

## 11. Editor

- Gap buffer. Akhir baris boleh LF, CR LF, atau CR. Enter menyisipkan LF, ditambah indentasi baris itu bila `AutoIndent`. Tab tampil sampai kolom kelipatan 8. Panjang baris dibatasi `MaxLineLength` (256).
- Tombol TP/WordStar: panah, Ctrl+panah, Home/End, PgUp/PgDn, Ctrl+PgUp/PgDn, ^A ^C ^D ^E ^F ^G ^H ^L ^O ^R ^S ^T ^U ^V ^X ^Y, ^K B/C/H/K/Y, dan ^Q A/C/D/F/H/R/S/Y. Clipboard memakai Shift+Del, Ctrl+Ins, Shift+Ins, dan Ctrl+Del. Shift+gerak memperluas seleksi.
- Undo satu langkah. Ketikan atau hapusan yang berurutan di tempat yang sama dihitung satu langkah. Undo kedua mengulangi perubahannya.
- `TFileEditor` membuat cadangan `.bak` bila `efBackupFiles`. Saat menutup berkas yang berubah, editor bertanya lewat `EditorDialog`. `DefEditorDialog` selalu menjawab Cancel, jadi aplikasi yang memakai editor harus memasang `EditorDialog := StdEditorDialog`.

## 12. Outline

Baris yang tampil adalah akar, lalu anak dari setiap simpul yang terbuka, dinomori dari 0. Cabang digambar dengan `├ └ │ ─`, dengan `+` untuk simpul tertutup dan `─` untuk simpul terbuka atau daun. Klik pada gambar cabang membuka atau menutup simpul. `FirstThat`/`ForEach` memanggil fungsi lokal pemanggil dengan lima argumen (simpul, level, posisi, garis, flag) lewat shim `ODIN_CALLLOCAL5`.

## 13. User screen IDE

`odin/terminal.py` mencatat mode mouse 9/1000/1002/1003, mode 1006 (SGR), dan layar alternatif 1049/1047/47. Selama program meminta mouse, `TerminalView` mengirim laporan klik, gerakan selama tombol ditekan, dan roda. Shift, Ctrl, dan Alt pada tombol khusus menjadi parameter modifier xterm, Shift+Tab menjadi `ESC[Z`, dan Alt+huruf menjadi `ESC` + huruf. Di macOS, Alt adalah Option; karakter Option tata letak US dipetakan balik ke hurufnya.
