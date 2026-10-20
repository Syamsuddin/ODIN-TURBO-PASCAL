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
| `ColorSel` | `TColorDialog`, `TColorSelector`, `TMonoSelector`, `TColorDisplay`, `TColorGroupList`, `TColorItemList` | `Objects`, `Drivers`, `Views`, `Dialogs` |
| `TextView` | `TTextDevice`, `TTerminal`, `AssignDevice` | `Objects`, `Drivers`, `Views` |

`Validate`, `MsgBox`, `StdDlg`, dan `Editors` saling memakai lewat `uses` di bagian implementation (misalnya `Validate` → `MsgBox` → `App` → `Dialogs` → `Validate`). Seperti TP, compiler hanya melarang siklus di bagian interface.

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

## 13. ColorSel

- Perintah (semuanya broadcast ke owner, yaitu dialog): `cmColorForegroundChanged` 71, `cmColorBackgroundChanged` 72, `cmColorSet` 73, `cmNewColorItem` 74, `cmNewColorIndex` 75, `cmSaveColorIndex` 76. Nilai kecil dikirim di `InfoByte`.
- `TColorItem` berisi nama, indeks palet aplikasi, dan `Next`. `TColorGroup` berisi nama, `Index` (nomor item yang terakhir dipilih di grup itu), daftar item, dan `Next`. Keduanya dibuat dengan `ColorItem` dan `ColorGroup`. `DesktopColorItems`, `MenuColorItems`, `DialogColorItems(dpXxx, Next)`, dan `WindowColorItems(wpXxx, Next)` membuat daftar item standar menurut tata letak palet di bagian 7. Nama itemnya berbahasa Inggris. Daftar dialog berisi 31 entri pertama palet dialog (entri cadangan tidak), dan daftar jendela berisi 7 entri pertama palet jendela.
- `TColorSelector`: setiap warna selebar 3 kolom, 4 warna per baris. `csForeground` punya 16 warna (4 baris) dan `csBackground` 8 warna (2 baris). Warna digambar sebagai `███` dengan warna itu di atas hitam. Warna terpilih memakai `◘` di kolom tengahnya; untuk hitam, lubangnya abu-abu. Panah kiri/kanan berpindah satu warna dan berputar di ujung daftar. Panah atas/bawah berpindah satu baris dan berputar di kolom yang sama. Klik atau seret mouse memilih warna di bawah mouse. Setiap perubahan mengirim `cmColorForegroundChanged` atau `cmColorBackgroundChanged` dengan nomor warnanya. `cmColorSet` (sebuah atribut) memasang warna dari bit 0–3 (depan) atau bit 4–6 (latar). Kursor ada di warna terpilih.
- `TMonoSelector`: radio button Normal ($07), Highlight ($0F), Underline ($01), dan Inverse ($70). Memilih item mengirim kedua broadcast perubahan warna. `cmColorSet` memilih item yang atributnya sama.
- `TColorDisplay`: setiap baris diisi `Text` yang diulang, dengan atribut `Color^` apa adanya (tidak lewat palet). `cmColorForegroundChanged` mengganti bit 0–3 `Color^`, dan `cmColorBackgroundChanged` mengganti bit 4–7, sehingga memilih latar dari selector (0–7) mematikan bit 7 (latar terang). `SetColor` menunjuk byte baru, lalu mengirim `cmColorSet` dengan isinya. Bila `Color` nil, view memakai warna indeks 6 owner-nya (teks statis di dialog).
- `TColorGroupList` dan `TColorItemList` adalah list viewer satu kolom. Memfokus grup mengirim `cmNewColorItem` dengan pointer grup. Daftar item lalu memakai item grup itu dan memfokus item ke-`Index`. Memfokus item mengirim `cmSaveColorIndex` (nomor item, disimpan ke `Index` grup yang terfokus), lalu `cmNewColorIndex` (indeks palet item itu). `TColorGroupList.Done` membebaskan semua grup dan itemnya.
- `TColorDialog.Init(APalette, AGroups)`: dialog 62×18 berjudul `Colors`, ditengahkan. Dari kiri ke kanan isinya daftar Group, daftar Item, lalu selector Foreground, selector Background, contoh teks (`'Text '` yang diulang), serta tombol OK (default) dan Cancel. Di layar monokrom (`ScreenMode` = `smMono`), kedua selector warna beserta labelnya disembunyikan dan `TMonoSelector` berlabel Color ditampilkan. Pada layar lain `TMonoSelector` yang disembunyikan. `cmNewColorIndex` membuat contoh teks menunjuk ke `Pal[indeks]`, jadi setiap perubahan warna langsung mengubah `Pal`. Indeks di luar panjang `Pal` membuat contoh teks tidak menunjuk ke mana pun.
- Data dialog adalah `TPalette` (256 byte). `SetData` menyalin palet ke `Pal`, memulihkan grup dan item terpilih dari `ColorIndexes` (bila jumlah grupnya cocok), lalu memfokus ulang grup. `GetData` menyalin `Length(Pal) + 1` byte kembali dan menyimpan pilihan ke `ColorIndexes`. Jadi `ExecuteDialog(D, Application^.GetPalette)` yang diikuti `Application^.Redraw` langsung memakai warna baru, dan dialog berikutnya dibuka di grup dan item yang sama.
- `ColorIndexes` (`TColorIndex`: grup terpilih, jumlah grup, dan item terpilih per grup) ditulis ke stream dengan `StoreIndexes` dan dibaca dengan `LoadIndexes`. Formatnya satu byte jumlah grup (0 berarti tidak ada), lalu byte grup terpilih dan satu byte per grup.
- Stream:
  - `TColorSelector` menyimpan `Color` dan `SelType`, masing-masing 1 byte.
  - `TColorDisplay` menyimpan `Text`; pointer `Color` tidak disimpan.
  - `TColorGroupList` menyimpan jumlah grup (`Sw_Integer`), lalu per grup nama, `Index` (1 byte), dan jumlah item (`Sw_Integer`), lalu per item nama dan indeks (1 byte).
  - `TColorItemList` dimuat tanpa item.
  - `TColorDialog` menyimpan pointer subview-nya, `GroupIndex`, dan `Pal` (panjang lalu isinya). Setelah dimuat, dialog memfokus ulang grupnya sehingga daftar item dan contoh teks terhubung lagi.
  - ObjType: `TColorSelector` 21, `TMonoSelector` 22, `TColorDisplay` 23, `TColorGroupList` 24, `TColorItemList` 25, `TColorDialog` 26. `RegisterColorSel` mendaftarkan keenamnya.

## 14. TextView

- `TTextDevice` adalah `TScroller` dengan `StrRead` (bawaannya mengembalikan 0) dan `StrWrite` (abstrak).
- `TTerminal` menyimpan teks di buffer melingkar sebesar `BufSize` byte (paling sedikit 2), yang memuat paling banyak `BufSize - 1` karakter. `QueBack` menunjuk karakter tertua dan `QueFront` tempat karakter berikutnya ditulis. Buffer kosong bila keduanya sama. Baris dipisah `#10`, dan banyak baris adalah jumlah `#10` ditambah 1. Jadi teks yang diakhiri `#10` punya baris terakhir yang kosong, tempat kursor berada.
- `StrWrite` membuang `#13` (akhir baris CR LF di Windows) dan menyalin karakter lainnya. Bila buffer penuh, baris teratas dibuang utuh. Satu baris yang lebih panjang dari buffer dibuang per karakter dari depan. Sesudah menulis, `Limit.Y` menjadi banyak baris dan `Limit.X` lebar baris terpanjang. View lalu digeser sehingga baris terakhir tampak di baris paling bawah (`Delta.X` tidak berubah), kemudian digambar ulang. Tanpa scroll bar vertikal, `Delta.Y` digeser langsung.
- `Draw` menampilkan baris mulai `Delta.Y` dan kolom mulai `Delta.X` dengan warna scroller normal. Tab maju ke kolom kelipatan 8, dan karakter kontrol lain tampil sebagai glyph CP437. Kursor ada di akhir teks.
- `NextLine(Pos)` mengembalikan awal baris sesudah baris yang memuat `Pos`, atau `QueFront` bila tidak ada. `PrevLines(Pos, N)` mengembalikan awal baris yang memuat `Pos` bila N = 1, awal baris di atasnya bila N = 2, dan seterusnya, paling jauh sampai `QueBack`. N = 0 mengembalikan `Pos`. `CalcWidth` mengembalikan lebar baris terpanjang (tab dihitung sampai kolom kelipatan 8). `CanInsert(N)` bernilai True bila N karakter muat tanpa membuang baris. `BufInc` dan `BufDec` memajukan dan memundurkan offset dengan putaran. `TTerminal.StrRead` mengembalikan 0.
- `AssignDevice(T, Screen)` sama dengan `Assign(T, '')`, lalu memasang hook `FlushFunc` dan menyimpan `Screen` di `UserData`. Sesudah `Rewrite(T)`, setiap pernyataan `Write`/`WriteLn` ke `T` diteruskan ke `Screen^.StrWrite` dalam potongan paling banyak 255 karakter (`Count: Byte`). Sesudah `Reset(T)`, `Read`/`ReadLn` mengisi buffer lewat `Screen^.StrRead`, dan hasil 0 berarti akhir berkas. `Close(T)` tidak menutup deskriptor apa pun. `T` harus ditutup sebelum view-nya dibuang.
- Seperti di TP7, unit ini tidak punya registrasi stream.

## 15. User screen IDE

`odin/terminal.py` mencatat mode mouse 9/1000/1002/1003, mode 1006 (SGR), dan layar alternatif 1049/1047/47. Selama program meminta mouse, `TerminalView` mengirim laporan klik, gerakan selama tombol ditekan, dan roda. Shift, Ctrl, dan Alt pada tombol khusus menjadi parameter modifier xterm, Shift+Tab menjadi `ESC[Z`, dan Alt+huruf menjadi `ESC` + huruf. Di macOS, Alt adalah Option; karakter Option tata letak US dipetakan balik ke hurufnya.
