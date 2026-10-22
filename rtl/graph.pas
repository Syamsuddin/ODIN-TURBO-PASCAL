{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Graph dari runtime library Odin: antarmuka BGI Turbo Pascal 7
  (InitGraph, Line, Circle, Bar, FloodFill, OutTextXY, GetImage, ...).
  Implementasi clean-room berdasarkan dokumentasi publik BGI.

  Cara kerjanya: gambar disimpan di framebuffer di memori, satu byte per
  piksel (indeks palet), dengan resolusi mode BGI yang dipilih (mis. VGAHi
  640x480). Semua rutin menggambar ke framebuffer itu, jadi GetPixel,
  GetImage, dan PutImage memberi hasil yang persis sama seperti di DOS.
  Ke layar, framebuffer ditampilkan di terminal teks lewat karakter
  setengah blok: tiap sel terminal memuat dua subpiksel (atas dan bawah)
  dengan 16 warna CRT, dan gambar diskalakan supaya muat di terminal dengan
  perbandingan lebar-tinggi yang benar (lingkaran tetap bulat). Karena itu
  layar hanya pratinjau kasar (sekitar 80x50 subpiksel di terminal 80x25).
  Layar digambar ulang saat program menunggu lewat Crt (ReadKey, KeyPressed,
  Delay), sambil menggambar tiap 0,1 detik, dan saat program selesai. Bila
  keluaran bukan terminal (dialihkan ke berkas), tidak ada yang ditampilkan.

  Di IDE, program dijalankan dengan ODIN_GRAPH_PORT dan ODIN_GRAPH_TOKEN: unit
  ini menyambung ke port itu di 127.0.0.1 dan mengirim isi framebuffer
  (hanya baris yang berubah, dengan run-length) supaya IDE menampilkan piksel
  sebenarnya di jendela grafik. Pratinjau terminal dimatikan selama jendela itu
  ada, dan pengiriman yang gagal mengembalikannya. Protokolnya dijelaskan di
  odin/graphics.py; kedua sisi harus diubah bersama.

  Yang berbeda dari BGI Borland: tidak ada berkas driver (*.BGI) atau font
  (*.CHR), jadi PathToDriver diabaikan dan RegisterBGIdriver hanya
  mencatat; semua font memakai font bitmap 8x8, diskalakan menurut
  CharSize, jadi TextWidth dan TextHeight bukan ukuran font stroke
  aslinya. Mode CGA/EGA/VGA dan lainnya dikenali dengan resolusi aslinya.
  SetRGBPalette diterima, lalu warnanya dipetakan ke 16 warna terminal
  terdekat. Tidak ada mouse atau halaman video sungguhan, tetapi
  SetActivePage dan SetVisualPage bekerja untuk mode yang punya banyak
  halaman. }
unit Graph;

{$R-,Q-,I-,X+}

interface

const
  { Nomor driver }
  CurrentDriver = -128;
  Detect = 0;
  CGA = 1;
  MCGA = 2;
  EGA = 3;
  EGA64 = 4;
  EGAMono = 5;
  IBM8514 = 6;
  HercMono = 7;
  ATT400 = 8;
  VGA = 9;
  PC3270 = 10;

  { Mode tiap driver }
  CGAC0 = 0;
  CGAC1 = 1;
  CGAC2 = 2;
  CGAC3 = 3;
  CGAHi = 4;
  MCGAC0 = 0;
  MCGAC1 = 1;
  MCGAC2 = 2;
  MCGAC3 = 3;
  MCGAMed = 4;
  MCGAHi = 5;
  EGALo = 0;
  EGAHi = 1;
  EGA64Lo = 0;
  EGA64Hi = 1;
  EGAMonoHi = 3;
  HercMonoHi = 0;
  ATT400C0 = 0;
  ATT400C1 = 1;
  ATT400C2 = 2;
  ATT400C3 = 3;
  ATT400Med = 4;
  ATT400Hi = 5;
  VGALo = 0;
  VGAMed = 1;
  VGAHi = 2;
  PC3270Hi = 0;
  IBM8514LO = 0;
  IBM8514HI = 1;

  { Warna }
  Black = 0;
  Blue = 1;
  Green = 2;
  Cyan = 3;
  Red = 4;
  Magenta = 5;
  Brown = 6;
  LightGray = 7;
  DarkGray = 8;
  LightBlue = 9;
  LightGreen = 10;
  LightCyan = 11;
  LightRed = 12;
  LightMagenta = 13;
  Yellow = 14;
  White = 15;

  MaxColors = 15;

  { Kode galat (GraphResult) }
  grOk = 0;
  grNoInitGraph = -1;
  grNotDetected = -2;
  grFileNotFound = -3;
  grInvalidDriver = -4;
  grNoLoadMem = -5;
  grNoScanMem = -6;
  grNoFloodMem = -7;
  grFontNotFound = -8;
  grNoFontMem = -9;
  grInvalidMode = -10;
  grError = -11;
  grIOerror = -12;
  grInvalidFont = -13;
  grInvalidFontNum = -14;
  grInvalidDeviceNum = -15;
  grInvalidVersion = -18;

  { Gaya garis }
  SolidLn = 0;
  DottedLn = 1;
  CenterLn = 2;
  DashedLn = 3;
  UserBitLn = 4;

  NormWidth = 1;
  ThickWidth = 3;

  { Gaya isian }
  EmptyFill = 0;
  SolidFill = 1;
  LineFill = 2;
  LtSlashFill = 3;
  SlashFill = 4;
  BkSlashFill = 5;
  LtBkSlashFill = 6;
  HatchFill = 7;
  XHatchFill = 8;
  InterleaveFill = 9;
  WideDotFill = 10;
  CloseDotFill = 11;
  UserFill = 12;

  { Mode tulis }
  CopyPut = 0;
  XORPut = 1;
  OrPut = 2;
  AndPut = 3;
  NotPut = 4;

  { Font dan arah teks }
  DefaultFont = 0;
  TriplexFont = 1;
  SmallFont = 2;
  SansSerifFont = 3;
  GothicFont = 4;
  HorizDir = 0;
  VertDir = 1;
  UserCharSize = 0;

  { Perataan teks }
  LeftText = 0;
  CenterText = 1;
  RightText = 2;
  BottomText = 0;
  TopText = 2;

  ClipOn = True;
  ClipOff = False;
  TopOn = True;
  TopOff = False;

type
  PaletteType = record
    Size: Byte;
    Colors: array[0..MaxColors] of ShortInt;
  end;

  LineSettingsType = record
    LineStyle: Word;
    Pattern: Word;
    Thickness: Word;
  end;

  TextSettingsType = record
    Font: Word;
    Direction: Word;
    CharSize: Word;
    Horiz: Word;
    Vert: Word;
  end;

  FillSettingsType = record
    Pattern: Word;
    Color: Word;
  end;

  FillPatternType = array[1..8] of Byte;

  PointType = record
    X, Y: Integer;
  end;

  ViewPortType = record
    X1, Y1, X2, Y2: Integer;
    Clip: Boolean;
  end;

  ArcCoordsType = record
    X, Y: Integer;
    Xstart, Ystart: Integer;
    Xend, Yend: Integer;
  end;

procedure InitGraph(var GraphDriver: Integer; var GraphMode: Integer; PathToDriver: String);
procedure CloseGraph;
procedure DetectGraph(var GraphDriver, GraphMode: Integer);
function GraphResult: Integer;
function GraphErrorMsg(ErrorCode: Integer): String;
procedure GraphDefaults;
procedure RestoreCrtMode;
procedure SetGraphMode(Mode: Integer);
function GetGraphMode: Integer;
function GetDriverName: String;
function GetModeName(ModeNumber: Integer): String;
procedure GetModeRange(GraphDriver: Integer; var LoMode, HiMode: Integer);
function GetMaxMode: Integer;
function GetMaxX: Integer;
function GetMaxY: Integer;
function GetMaxColor: Word;
function GetX: Integer;
function GetY: Integer;
procedure GetAspectRatio(var Xasp, Yasp: Word);
procedure SetAspectRatio(Xasp, Yasp: Word);
procedure SetGraphBufSize(BufSize: Word);
function InstallUserDriver(DriverFileName: String; AutoDetectPtr: Pointer): Integer;
function InstallUserFont(FontFileName: String): Integer;
function RegisterBGIdriver(Driver: Pointer): Integer;
function RegisterBGIfont(Font: Pointer): Integer;

procedure ClearDevice;
procedure ClearViewPort;
procedure SetViewPort(X1, Y1, X2, Y2: Integer; Clip: Boolean);
procedure GetViewSettings(var ViewPort: ViewPortType);
procedure SetActivePage(Page: Word);
procedure SetVisualPage(Page: Word);

procedure PutPixel(X, Y: Integer; Pixel: Word);
function GetPixel(X, Y: Integer): Word;
procedure Line(X1, Y1, X2, Y2: Integer);
procedure LineTo(X, Y: Integer);
procedure LineRel(Dx, Dy: Integer);
procedure MoveTo(X, Y: Integer);
procedure MoveRel(Dx, Dy: Integer);
procedure Rectangle(X1, Y1, X2, Y2: Integer);
procedure Bar(X1, Y1, X2, Y2: Integer);
procedure Bar3D(X1, Y1, X2, Y2: Integer; Depth: Word; Top: Boolean);
procedure Circle(X, Y: Integer; Radius: Word);
procedure Arc(X, Y: Integer; StAngle, EndAngle, Radius: Word);
procedure Ellipse(X, Y: Integer; StAngle, EndAngle: Word; XRadius, YRadius: Word);
procedure FillEllipse(X, Y: Integer; XRadius, YRadius: Word);
procedure PieSlice(X, Y: Integer; StAngle, EndAngle, Radius: Word);
procedure Sector(X, Y: Integer; StAngle, EndAngle, XRadius, YRadius: Word);
procedure GetArcCoords(var ArcCoords: ArcCoordsType);
procedure DrawPoly(NumPoints: Word; var PolyPoints);
procedure FillPoly(NumPoints: Word; var PolyPoints);
procedure FloodFill(X, Y: Integer; Border: Word);

procedure SetColor(Color: Word);
function GetColor: Word;
procedure SetBkColor(ColorNum: Word);
function GetBkColor: Word;
procedure SetPalette(ColorNum: Word; Color: ShortInt);
procedure SetAllPalette(var Palette);
procedure GetPalette(var Palette: PaletteType);
function GetPaletteSize: Integer;
procedure GetDefaultPalette(var Palette: PaletteType);
procedure SetRGBPalette(ColorNum, RedValue, GreenValue, BlueValue: Integer);
procedure SetLineStyle(LineStyle: Word; Pattern: Word; Thickness: Word);
procedure GetLineSettings(var LineInfo: LineSettingsType);
procedure SetFillStyle(Pattern: Word; Color: Word);
procedure SetFillPattern(Pattern: FillPatternType; Color: Word);
procedure GetFillSettings(var FillInfo: FillSettingsType);
procedure GetFillPattern(var FillPattern: FillPatternType);
procedure SetWriteMode(WriteMode: Integer);

function ImageSize(X1, Y1, X2, Y2: Integer): LongInt;
procedure GetImage(X1, Y1, X2, Y2: Integer; var BitMap);
procedure PutImage(X, Y: Integer; var BitMap; BitBlt: Word);

procedure OutText(TextString: String);
procedure OutTextXY(X, Y: Integer; TextString: String);
procedure SetTextStyle(Font, Direction: Word; CharSize: Word);
procedure SetTextJustify(Horiz, Vert: Word);
procedure GetTextSettings(var TextInfo: TextSettingsType);
procedure SetUserCharSize(MultX, DivX, MultY, DivY: Word);
function TextHeight(TextString: String): Word;
function TextWidth(TextString: String): Word;

implementation

uses
  Crt, Dos;

{ ---- soket ke jendela grafik IDE ---------------------------------------------------- }

type
  TSockAddrIn = record
{$IFDEF DARWIN}
    Len, Family: Byte;
{$ELSE}
    Family: Word;
{$ENDIF}
    Port: Word;
    Addr: LongWord;
    Zero: array[0..7] of Byte;
  end;

{$IFDEF WINDOWS}
function WSAStartup(Version: Word; Data: Pointer): LongInt; external 'ws2_32' name 'WSAStartup';
function w_socket(Family, Kind, Protocol: LongInt): Int64; external 'ws2_32' name 'socket';
function w_connect(S: Int64; Addr: Pointer; Len: LongInt): LongInt; external 'ws2_32' name 'connect';
function w_send(S: Int64; Buf: Pointer; Len, Flags: LongInt): LongInt; external 'ws2_32' name 'send';
function c_getenv(Name: PChar): PChar; cdecl; external 'c' name 'getenv';
{$ELSE}
function c_socket(Domain, Kind, Protocol: LongInt): LongInt; cdecl; external 'c' name 'socket';
function c_connect(Fd: LongInt; Addr: Pointer; Len: LongInt): LongInt; cdecl; external 'c' name 'connect';
function c_write(Fd: LongInt; Buf: Pointer; Count: Int64): Int64; cdecl; external 'c' name 'write';
function c_signal(Sig: LongInt; Handler: Pointer): Pointer; cdecl; external 'c' name 'signal';
function c_getenv(Name: PChar): PChar; cdecl; external 'c' name 'getenv';
{$ENDIF}

const
  MaxPixels = 786432;     { 1024 x 768 }
  MaxPages = 4;
  MaxPts = 8192;
  MaxScreenCells = 65025;
  MaxTexts = 200;
  MaxTextLen = 80;
  GfxBufSize = 2097152;
  { Jenis pesan ke IDE (odin/graphics.py). }
  GfxHello = 1;
  GfxMode = 2;
  GfxPalette = 3;
  GfxFrame = 4;
  GfxHide = 5;
  GfxClose = 6;
  PortVar: array[0..15] of Char = 'ODIN_GRAPH_PORT'#0;
  TokenVar: array[0..16] of Char = 'ODIN_GRAPH_TOKEN'#0;

type
  TBigBuf = array[0..GfxBufSize - 1] of Byte;
  PBigBuf = ^TBigBuf;
  { Satu teks mendatar yang sudah digambar: PX/PY adalah satu piksel penanda tiap
    karakter, untuk memeriksa teksnya masih ada di framebuffer. }
  TTextRec = record
    Used: Boolean;
    Page: Byte;
    Color: Byte;
    Len: Integer;
    Chars: String[MaxTextLen];
    X, Y, CW, CH: LongInt;
    PX, PY: array[1..MaxTextLen] of Integer;
  end;

  TPix = array[0..MaxPixels - 1] of Byte;
  PPix = ^TPix;
  TPt = record
    X, Y: LongInt;
  end;
  TPts = array[0..MaxPts - 1] of TPt;
  PPts = ^TPts;
  TLongs = array[0..MaxPts - 1] of LongInt;
  PLongs = ^TLongs;
  TPointArray = array[0..16383] of PointType;
  PPointArray = ^TPointArray;
  PPaletteType = ^PaletteType;
  TRGB = record
    R, G, B: Byte;
  end;
  TImageHeader = record
    Width, Height: Word;
  end;
  PImageHeader = ^TImageHeader;

const
  { Warna DOS -> kode EGA 6-bit, untuk GetPalette/SetPalette. }
  DosToEga: array[0..15] of Byte = (0, 1, 2, 3, 4, 5, 20, 7, 56, 57, 58, 59, 60, 61, 62, 63);

  { RGB 16 warna CRT. }
  TermRGB: array[0..15, 0..2] of Byte = (
    (0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170),
    (170, 0, 0), (170, 0, 170), (170, 85, 0), (170, 170, 170),
    (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255),
    (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255));

  { Pola isian 8x8; bit 7 = piksel paling kiri. }
  FillPatterns: array[0..11, 0..7] of Byte = (
    ($00, $00, $00, $00, $00, $00, $00, $00),
    ($FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF),
    ($FF, $FF, $00, $00, $FF, $FF, $00, $00),
    ($01, $02, $04, $08, $10, $20, $40, $80),
    ($E0, $C1, $83, $07, $0E, $1C, $38, $70),
    ($F0, $78, $3C, $1E, $0F, $87, $C3, $E1),
    ($A5, $D2, $69, $B4, $5A, $2D, $96, $4B),
    ($FF, $88, $88, $88, $FF, $88, $88, $88),
    ($81, $42, $24, $18, $18, $24, $42, $81),
    ($CC, $33, $CC, $33, $CC, $33, $CC, $33),
    ($80, $00, $08, $00, $80, $00, $08, $00),
    ($88, $00, $22, $00, $88, $00, $22, $00));

  LinePatterns: array[0..3] of Word = ($FFFF, $CCCC, $FC78, $F8F8);

  { Font bitmap 8x8 untuk karakter 32..126 (domain publik); bit 0 = piksel
    paling kiri. }
  Font8x8: array[32..126, 0..7] of Byte = (
    ($00, $00, $00, $00, $00, $00, $00, $00),
    ($18, $3C, $3C, $18, $18, $00, $18, $00),
    ($36, $36, $00, $00, $00, $00, $00, $00),
    ($36, $36, $7F, $36, $7F, $36, $36, $00),
    ($0C, $3E, $03, $1E, $30, $1F, $0C, $00),
    ($00, $63, $33, $18, $0C, $66, $63, $00),
    ($1C, $36, $1C, $6E, $3B, $33, $6E, $00),
    ($06, $06, $03, $00, $00, $00, $00, $00),
    ($18, $0C, $06, $06, $06, $0C, $18, $00),
    ($06, $0C, $18, $18, $18, $0C, $06, $00),
    ($00, $66, $3C, $FF, $3C, $66, $00, $00),
    ($00, $0C, $0C, $3F, $0C, $0C, $00, $00),
    ($00, $00, $00, $00, $00, $0C, $0C, $06),
    ($00, $00, $00, $3F, $00, $00, $00, $00),
    ($00, $00, $00, $00, $00, $0C, $0C, $00),
    ($60, $30, $18, $0C, $06, $03, $01, $00),
    ($3E, $63, $73, $7B, $6F, $67, $3E, $00),
    ($0C, $0E, $0C, $0C, $0C, $0C, $3F, $00),
    ($1E, $33, $30, $1C, $06, $33, $3F, $00),
    ($1E, $33, $30, $1C, $30, $33, $1E, $00),
    ($38, $3C, $36, $33, $7F, $30, $78, $00),
    ($3F, $03, $1F, $30, $30, $33, $1E, $00),
    ($1C, $06, $03, $1F, $33, $33, $1E, $00),
    ($3F, $33, $30, $18, $0C, $0C, $0C, $00),
    ($1E, $33, $33, $1E, $33, $33, $1E, $00),
    ($1E, $33, $33, $3E, $30, $18, $0E, $00),
    ($00, $0C, $0C, $00, $00, $0C, $0C, $00),
    ($00, $0C, $0C, $00, $00, $0C, $0C, $06),
    ($18, $0C, $06, $03, $06, $0C, $18, $00),
    ($00, $00, $3F, $00, $00, $3F, $00, $00),
    ($06, $0C, $18, $30, $18, $0C, $06, $00),
    ($1E, $33, $30, $18, $0C, $00, $0C, $00),
    ($3E, $63, $7B, $7B, $7B, $03, $1E, $00),
    ($0C, $1E, $33, $33, $3F, $33, $33, $00),
    ($3F, $66, $66, $3E, $66, $66, $3F, $00),
    ($3C, $66, $03, $03, $03, $66, $3C, $00),
    ($1F, $36, $66, $66, $66, $36, $1F, $00),
    ($7F, $46, $16, $1E, $16, $46, $7F, $00),
    ($7F, $46, $16, $1E, $16, $06, $0F, $00),
    ($3C, $66, $03, $03, $73, $66, $7C, $00),
    ($33, $33, $33, $3F, $33, $33, $33, $00),
    ($1E, $0C, $0C, $0C, $0C, $0C, $1E, $00),
    ($78, $30, $30, $30, $33, $33, $1E, $00),
    ($67, $66, $36, $1E, $36, $66, $67, $00),
    ($0F, $06, $06, $06, $46, $66, $7F, $00),
    ($63, $77, $7F, $7F, $6B, $63, $63, $00),
    ($63, $67, $6F, $7B, $73, $63, $63, $00),
    ($1C, $36, $63, $63, $63, $36, $1C, $00),
    ($3F, $66, $66, $3E, $06, $06, $0F, $00),
    ($1E, $33, $33, $33, $3B, $1E, $38, $00),
    ($3F, $66, $66, $3E, $36, $66, $67, $00),
    ($1E, $33, $07, $0E, $38, $33, $1E, $00),
    ($3F, $2D, $0C, $0C, $0C, $0C, $1E, $00),
    ($33, $33, $33, $33, $33, $33, $3F, $00),
    ($33, $33, $33, $33, $33, $1E, $0C, $00),
    ($63, $63, $63, $6B, $7F, $77, $63, $00),
    ($63, $63, $36, $1C, $1C, $36, $63, $00),
    ($33, $33, $33, $1E, $0C, $0C, $1E, $00),
    ($7F, $63, $31, $18, $4C, $66, $7F, $00),
    ($1E, $06, $06, $06, $06, $06, $1E, $00),
    ($03, $06, $0C, $18, $30, $60, $40, $00),
    ($1E, $18, $18, $18, $18, $18, $1E, $00),
    ($08, $1C, $36, $63, $00, $00, $00, $00),
    ($00, $00, $00, $00, $00, $00, $00, $FF),
    ($0C, $0C, $18, $00, $00, $00, $00, $00),
    ($00, $00, $1E, $30, $3E, $33, $6E, $00),
    ($07, $06, $06, $3E, $66, $66, $3B, $00),
    ($00, $00, $1E, $33, $03, $33, $1E, $00),
    ($38, $30, $30, $3E, $33, $33, $6E, $00),
    ($00, $00, $1E, $33, $3F, $03, $1E, $00),
    ($1C, $36, $06, $0F, $06, $06, $0F, $00),
    ($00, $00, $6E, $33, $33, $3E, $30, $1F),
    ($07, $06, $36, $6E, $66, $66, $67, $00),
    ($0C, $00, $0E, $0C, $0C, $0C, $1E, $00),
    ($30, $00, $30, $30, $30, $33, $33, $1E),
    ($07, $06, $66, $36, $1E, $36, $67, $00),
    ($0E, $0C, $0C, $0C, $0C, $0C, $1E, $00),
    ($00, $00, $33, $7F, $7F, $6B, $63, $00),
    ($00, $00, $1F, $33, $33, $33, $33, $00),
    ($00, $00, $1E, $33, $33, $33, $1E, $00),
    ($00, $00, $3B, $66, $66, $3E, $06, $0F),
    ($00, $00, $6E, $33, $33, $3E, $30, $78),
    ($00, $00, $3B, $6E, $66, $06, $0F, $00),
    ($00, $00, $3E, $03, $1E, $30, $1F, $00),
    ($08, $0C, $3E, $0C, $0C, $2C, $18, $00),
    ($00, $00, $33, $33, $33, $33, $6E, $00),
    ($00, $00, $33, $33, $33, $1E, $0C, $00),
    ($00, $00, $63, $6B, $7F, $7F, $36, $00),
    ($00, $00, $63, $36, $1C, $36, $63, $00),
    ($00, $00, $33, $33, $33, $3E, $30, $1F),
    ($00, $00, $3F, $19, $0C, $26, $3F, $00),
    ($38, $0C, $0C, $07, $0C, $0C, $38, $00),
    ($18, $18, $18, $00, $18, $18, $18, $00),
    ($07, $0C, $0C, $38, $0C, $0C, $07, $00),
    ($6E, $3B, $00, $00, $00, $00, $00, $00));

  GlyphSpace = ' ';
  GlyphUpper = #$E2#$96#$80;
  GlyphLower = #$E2#$96#$84;
  GlyphFull = #$E2#$96#$88;

var
  Active: Boolean;          { InitGraph sudah berhasil }
  InText: Boolean;          { sedang di mode teks (RestoreCrtMode) }
  Display: Boolean;         { keluaran adalah terminal }
  ErrorCode: Integer;
  CurDriver, CurMode: Integer;
  XRes, YRes: LongInt;
  NumColors: Integer;
  NumPages: Integer;
  Pages: array[0..MaxPages - 1] of PPix;
  ActivePage, VisualPage: Integer;
  Pix: PPix;                { halaman aktif }
  VP: ViewPortType;
  ClipX1, ClipY1, ClipX2, ClipY2: LongInt;
  CPX, CPY: LongInt;
  CurColor, BkColor: Word;
  LineSet: LineSettingsType;
  FillSet: FillSettingsType;
  UserPat: FillPatternType;
  TextSet: TextSettingsType;
  UMultX, UDivX, UMultY, UDivY: Word;
  CurWriteMode: Integer;
  AspX, AspY: Word;
  ArcInfo: ArcCoordsType;
  Pal: array[0..255] of TRGB;
  PalCode: array[0..255] of ShortInt;
  TermCol: array[0..255] of Byte;
  OldExitProc: Pointer;
  HooksSet: Boolean;

  { Tampilan }
  Cols, Rows: Integer;
  Dirty: Boolean;
  TouchCount: LongInt;
  LastRender: LongInt;
  Shown: array[0..MaxScreenCells - 1] of Word;
  SubX0, SubX1: array[0..254] of Integer;
  SubY0, SubY1: array[0..509] of Integer;
  ImgOX, ImgOY, ImgW, ImgH: Integer;
  DPW, DPH: Double;         { piksel per subpiksel, lebar dan tinggi }

  { Jendela grafik IDE }
  GfxOn: Boolean;           { mengirim ke jendela IDE saat ini }
  GfxConn: Boolean;         { soketnya terbuka }
  GfxTried: Boolean;
  GfxSock: Int64;
  GfxBuf: PBigBuf;
  GfxSent: PPix;            { isi terakhir yang dikirim }
  GfxSentSize: LongInt;
  GfxPalSent: Boolean;
  GfxPal: array[0..255] of TRGB;

  { Teks BGI yang ditampilkan sebagai karakter terminal (lapisan teks). }
  Texts: array[0..MaxTexts - 1] of TTextRec;
  TextNext: Integer;
  OvChr: array[0..MaxScreenCells - 1] of Byte;     { karakter di sel, 0 = tidak ada }
  OvIgn: array[0..MaxScreenCells - 1] of Word;     { indeks warna teks + 1, 0 = sel biasa }

{ ---- galat ---------------------------------------------------------------------- }

procedure SetError(Code: Integer);
begin
  ErrorCode := Code;
end;

function Ready: Boolean;
begin
  Ready := Active;
  if not Active then
    ErrorCode := grNoInitGraph;
end;

function GraphResult: Integer;
begin
  GraphResult := ErrorCode;
  ErrorCode := grOk;
end;

function GraphErrorMsg(ErrorCode: Integer): String;
begin
  case ErrorCode of
    grOk: GraphErrorMsg := 'No error';
    grNoInitGraph: GraphErrorMsg := '(BGI) graphics not installed (use InitGraph)';
    grNotDetected: GraphErrorMsg := 'Graphics hardware not detected';
    grFileNotFound: GraphErrorMsg := 'Device driver file not found ()';
    grInvalidDriver: GraphErrorMsg := 'Invalid device driver file ()';
    grNoLoadMem: GraphErrorMsg := 'Not enough memory to load driver';
    grNoScanMem: GraphErrorMsg := 'Out of memory in scan fill';
    grNoFloodMem: GraphErrorMsg := 'Out of memory in flood fill';
    grFontNotFound: GraphErrorMsg := 'Font file not found ()';
    grNoFontMem: GraphErrorMsg := 'Not enough memory to load font';
    grInvalidMode: GraphErrorMsg := 'Invalid graphics mode for selected driver';
    grError: GraphErrorMsg := 'Graphics error';
    grIOerror: GraphErrorMsg := 'Graphics I/O error';
    grInvalidFont: GraphErrorMsg := 'Invalid font file ()';
    grInvalidFontNum: GraphErrorMsg := 'Invalid font number';
    grInvalidDeviceNum: GraphErrorMsg := 'Invalid device number';
    grInvalidVersion: GraphErrorMsg := 'Invalid version of file';
  else
    GraphErrorMsg := 'Graphics error';
  end;
end;

{ ---- tabel mode ------------------------------------------------------------------- }

{ Resolusi, jumlah warna, halaman, dan AspX (AspY selalu 10000) untuk driver dan
  mode; False bila kombinasinya tidak ada. }
function ModeInfo(Driver, Mode: Integer; var W, H, Colors, Pgs, Asp: LongInt): Boolean;
var
  Ok: Boolean;
begin
  Ok := True;
  Pgs := 1;
  W := 0;
  H := 0;
  Colors := 16;
  case Driver of
    CGA, MCGA, ATT400:
      case Mode of
        0..3:
          begin
            W := 320;
            H := 200;
            Colors := 4;
          end;
        4:
          begin
            W := 640;
            H := 200;
            Colors := 2;
          end;
        5:
          if Driver = CGA then
            Ok := False
          else
          begin
            W := 640;
            if Driver = MCGA then
              H := 480
            else
              H := 400;
            Colors := 2;
          end;
      else
        Ok := False;
      end;
    EGA:
      case Mode of
        0:
          begin
            W := 640;
            H := 200;
            Pgs := 4;
          end;
        1:
          begin
            W := 640;
            H := 350;
            Pgs := 2;
          end;
      else
        Ok := False;
      end;
    EGA64:
      case Mode of
        0:
          begin
            W := 640;
            H := 200;
          end;
        1:
          begin
            W := 640;
            H := 350;
            Colors := 4;
          end;
      else
        Ok := False;
      end;
    EGAMono:
      if Mode = 3 then
      begin
        W := 640;
        H := 350;
        Colors := 2;
      end
      else
        Ok := False;
    HercMono:
      if Mode = 0 then
      begin
        W := 720;
        H := 348;
        Colors := 2;
        Pgs := 2;
      end
      else
        Ok := False;
    VGA:
      case Mode of
        0:
          begin
            W := 640;
            H := 200;
            Pgs := 2;
          end;
        1:
          begin
            W := 640;
            H := 350;
            Pgs := 2;
          end;
        2:
          begin
            W := 640;
            H := 480;
          end;
      else
        Ok := False;
      end;
    PC3270:
      if Mode = 0 then
      begin
        W := 720;
        H := 350;
        Colors := 2;
      end
      else
        Ok := False;
    IBM8514:
      case Mode of
        0:
          begin
            W := 640;
            H := 480;
            Colors := 256;
          end;
        1:
          begin
            W := 1024;
            H := 768;
            Colors := 256;
          end;
      else
        Ok := False;
      end;
  else
    Ok := False;
  end;
  Asp := 10000;
  if Ok then
  begin
    { Nilai BGI untuk mode 200 dan 350 garis; selain itu dihitung dari
      layar 4:3. }
    if (W = 640) and (H = 200) and ((Driver = EGA) or (Driver = EGA64) or (Driver = VGA)) then
      Asp := 4400
    else if (W = 640) and (H = 350) and ((Driver = EGA) or (Driver = VGA)) then
      Asp := 7750
    else
      Asp := (H * 40000 + W * 3 div 2) div (W * 3);
  end;
  ModeInfo := Ok;
end;

function DriverName(Driver: Integer): String;
begin
  case Driver of
    CGA: DriverName := 'CGA';
    MCGA: DriverName := 'MCGA';
    EGA: DriverName := 'EGA';
    EGA64: DriverName := 'EGA64';
    EGAMono: DriverName := 'EGAMONO';
    IBM8514: DriverName := 'IBM8514';
    HercMono: DriverName := 'HERCMONO';
    ATT400: DriverName := 'ATT400';
    VGA: DriverName := 'VGA';
    PC3270: DriverName := 'PC3270';
  else
    DriverName := '';
  end;
end;

function GetDriverName: String;
begin
  if Active then
    GetDriverName := DriverName(CurDriver)
  else
    GetDriverName := '';
end;

function GetModeName(ModeNumber: Integer): String;
var
  W, H, C, P, A: LongInt;
  SW, SH, S: String;
begin
  GetModeName := '';
  if not Active then
    Exit;
  if not ModeInfo(CurDriver, ModeNumber, W, H, C, P, A) then
    Exit;
  Str(W, SW);
  Str(H, SH);
  S := SW + ' x ' + SH + ' ' + DriverName(CurDriver);
  if ((CurDriver = CGA) or (CurDriver = MCGA) or (CurDriver = ATT400)) and (ModeNumber <= 3) then
  begin
    Str(ModeNumber, SW);
    S := S + ' C' + SW;
  end;
  GetModeName := S;
end;

procedure GetModeRange(GraphDriver: Integer; var LoMode, HiMode: Integer);
var
  W, H, C, P, A: LongInt;
  M: Integer;
begin
  LoMode := -1;
  HiMode := -1;
  if GraphDriver = CurrentDriver then
    GraphDriver := CurDriver;
  for M := 0 to 7 do
    if ModeInfo(GraphDriver, M, W, H, C, P, A) then
    begin
      if LoMode < 0 then
        LoMode := M;
      HiMode := M;
    end;
end;

function GetMaxMode: Integer;
var
  Lo, Hi: Integer;
begin
  if not Ready then
  begin
    GetMaxMode := 0;
    Exit;
  end;
  GetModeRange(CurDriver, Lo, Hi);
  GetMaxMode := Hi;
end;

procedure DetectGraph(var GraphDriver, GraphMode: Integer);
begin
  GraphDriver := VGA;
  GraphMode := VGAHi;
end;

{ ---- palet ------------------------------------------------------------------------ }

procedure EgaToRGB(Code: Integer; var C: TRGB);
begin
  Code := Code and 63;
  C.R := (((Code shr 2) and 1) * 2 + ((Code shr 5) and 1)) * 85;
  C.G := (((Code shr 1) and 1) * 2 + ((Code shr 4) and 1)) * 85;
  C.B := ((Code and 1) * 2 + ((Code shr 3) and 1)) * 85;
end;

{ Warna CRT yang paling dekat dengan C. }
function NearestTerm(const C: TRGB): Byte;
var
  I, Best: Integer;
  D, BestD, DR, DG, DB: LongInt;
begin
  Best := 0;
  BestD := 2147483647;
  for I := 0 to 15 do
  begin
    DR := C.R - TermRGB[I, 0];
    DG := C.G - TermRGB[I, 1];
    DB := C.B - TermRGB[I, 2];
    D := DR * DR + DG * DG + DB * DB;
    if D < BestD then
    begin
      BestD := D;
      Best := I;
    end;
  end;
  NearestTerm := Best;
end;

procedure SetEntry(Index: Integer; const C: TRGB);
begin
  Pal[Index] := C;
  TermCol[Index] := NearestTerm(C);
end;

procedure SetEntryEga(Index, Code: Integer);
var
  C: TRGB;
begin
  EgaToRGB(Code, C);
  PalCode[Index] := Code;
  SetEntry(Index, C);
end;

{ Kode EGA warna ke-I pada palet bawaan driver dan mode yang aktif. }
function DefaultEga(I: Integer): Integer;
var
  R: Integer;
begin
  R := 0;
  if NumColors = 2 then
  begin
    if I = 1 then
      R := 63;
  end
  else if (NumColors = 4) and ((CurDriver = CGA) or (CurDriver = MCGA) or (CurDriver = ATT400)) then
  begin
    if I > 0 then
      case CurMode of
        0: R := DosToEga[8 + 2 * I];
        1: R := DosToEga[9 + 2 * I];
        2: R := DosToEga[2 * I];
      else
        R := DosToEga[2 * I + 1];
      end;
  end
  else if NumColors = 4 then
  begin
    if I > 0 then
      R := DosToEga[9 + 2 * I];
  end
  else
    R := DosToEga[I and 15];
  DefaultEga := R;
end;

procedure DefaultPalette;
var
  I: Integer;
begin
  for I := 0 to 255 do
    PalCode[I] := 0;
  for I := 0 to NumColors - 1 do
    SetEntryEga(I, DefaultEga(I));
end;

function GetPaletteSize: Integer;
begin
  if Ready then
  begin
    if NumColors > 16 then
      GetPaletteSize := 16
    else
      GetPaletteSize := NumColors;
  end
  else
    GetPaletteSize := 0;
end;

procedure GetPalette(var Palette: PaletteType);
var
  I, N: Integer;
begin
  if not Ready then
    Exit;
  N := GetPaletteSize;
  Palette.Size := N;
  for I := 0 to MaxColors do
    if I < N then
      Palette.Colors[I] := PalCode[I]
    else
      Palette.Colors[I] := 0;
end;

procedure GetDefaultPalette(var Palette: PaletteType);
var
  I, N: Integer;
begin
  if not Ready then
    Exit;
  N := GetPaletteSize;
  Palette.Size := N;
  for I := 0 to MaxColors do
    if I < N then
      Palette.Colors[I] := DefaultEga(I)
    else
      Palette.Colors[I] := 0;
end;

procedure SetPalette(ColorNum: Word; Color: ShortInt);
begin
  if not Ready then
    Exit;
  if (ColorNum >= GetPaletteSize) or (Color < 0) then
  begin
    SetError(grError);
    Exit;
  end;
  SetEntryEga(ColorNum, Color);
  Dirty := True;
end;

procedure SetAllPalette(var Palette);
var
  P: PPaletteType;
  I: Integer;
begin
  if not Ready then
    Exit;
  P := @Palette;
  for I := 0 to P^.Size - 1 do
    if (I < GetPaletteSize) and (I <= MaxColors) and (P^.Colors[I] >= 0) then
      SetEntryEga(I, P^.Colors[I]);
  Dirty := True;
end;

function ScaleRGB(V: Integer): Byte;
begin
  if V < 0 then
    V := 0;
  if V > 255 then
    V := 255;
  { 0..63 (DAC VGA) dipakai apa adanya; yang lebih besar dianggap 8 bit. }
  if V > 63 then
    V := V shr 2;
  ScaleRGB := (V * 255) div 63;
end;

procedure SetRGBPalette(ColorNum, RedValue, GreenValue, BlueValue: Integer);
var
  C: TRGB;
begin
  if not Ready then
    Exit;
  if (ColorNum < 0) or (ColorNum >= NumColors) then
  begin
    SetError(grError);
    Exit;
  end;
  C.R := ScaleRGB(RedValue);
  C.G := ScaleRGB(GreenValue);
  C.B := ScaleRGB(BlueValue);
  SetEntry(ColorNum, C);
  Dirty := True;
end;

procedure SetColor(Color: Word);
begin
  if not Ready then
    Exit;
  if Color >= NumColors then
  begin
    SetError(grError);
    Exit;
  end;
  CurColor := Color;
end;

function GetColor: Word;
begin
  if Ready then
    GetColor := CurColor
  else
    GetColor := 0;
end;

function GetMaxColor: Word;
begin
  if Ready then
    GetMaxColor := NumColors - 1
  else
    GetMaxColor := 0;
end;

procedure SetBkColor(ColorNum: Word);
begin
  if not Ready then
    Exit;
  if ColorNum >= NumColors then
  begin
    SetError(grError);
    Exit;
  end;
  BkColor := ColorNum;
  PalCode[0] := PalCode[ColorNum];
  SetEntry(0, Pal[ColorNum]);
  Dirty := True;
end;

function GetBkColor: Word;
begin
  if Ready then
    GetBkColor := BkColor
  else
    GetBkColor := 0;
end;

{ ---- jendela grafik IDE ---------------------------------------------------------------- }

function GfxWrite(P: Pointer; N: LongInt): Boolean;
var
  Done: LongInt;
  R: Int64;
begin
  Done := 0;
  GfxWrite := True;
  while Done < N do
  begin
{$IFDEF WINDOWS}
    R := w_send(GfxSock, Pointer(Int64(P) + Done), N - Done, 0);
{$ELSE}
    R := c_write(GfxSock, Pointer(Int64(P) + Done), N - Done);
{$ENDIF}
    if R <= 0 then
    begin
      GfxWrite := False;
      Exit;
    end;
    Done := Done + R;
  end;
end;

{ Mengirim pesan Kind yang isinya (N byte) sudah ada di GfxBuf mulai byte 5. }
procedure GfxMsg(Kind: Byte; N: LongInt);
begin
  if not GfxOn then
    Exit;
  GfxBuf^[0] := Kind;
  Move(N, GfxBuf^[1], 4);
  if not GfxWrite(@GfxBuf^[0], N + 5) then
  begin
    GfxOn := False;
    GfxConn := False;
  end;
end;

procedure GfxConnect;
var
  Addr: TSockAddrIn;
  PortText, TokenText: PChar;
  Port, I, N: LongInt;
{$IFDEF WINDOWS}
  WsaData: array[0..511] of Byte;
{$ENDIF}
begin
  GfxTried := True;
  PortText := c_getenv(@PortVar);
  TokenText := c_getenv(@TokenVar);
  if (PortText = nil) or (TokenText = nil) then
    Exit;
  Port := 0;
  I := 0;
  while (PortText[I] >= '0') and (PortText[I] <= '9') do
  begin
    Port := Port * 10 + Ord(PortText[I]) - Ord('0');
    Inc(I);
  end;
  if (I = 0) or (Port < 1) or (Port > 65535) then
    Exit;
  FillChar(Addr, SizeOf(Addr), 0);
{$IFDEF DARWIN}
  Addr.Len := SizeOf(Addr);
{$ENDIF}
  Addr.Family := 2;
  Addr.Port := ((Port and $FF) shl 8) or ((Port shr 8) and $FF);
  Addr.Addr := $0100007F;
{$IFDEF WINDOWS}
  if WSAStartup($0202, @WsaData) <> 0 then
    Exit;
  GfxSock := w_socket(2, 1, 6);
  if (GfxSock = -1) or (w_connect(GfxSock, @Addr, SizeOf(Addr)) <> 0) then
    Exit;
{$ELSE}
  GfxSock := c_socket(2, 1, 0);
  if (GfxSock < 0) or (c_connect(GfxSock, @Addr, SizeOf(Addr)) <> 0) then
    Exit;
  { Jendela yang ditutup tidak boleh mematikan program lewat SIGPIPE. }
  c_signal(13, Pointer(1));
{$ENDIF}
  GetMem(GfxBuf, SizeOf(TBigBuf));
  GfxConn := True;
  GfxOn := True;
  N := 0;
  while TokenText[N] <> #0 do
  begin
    GfxBuf^[5 + N] := Ord(TokenText[N]);
    Inc(N);
  end;
  GfxMsg(GfxHello, N);
end;

procedure GfxSendMode;
var
  V: Word;
begin
  if not GfxOn then
    Exit;
  V := XRes;
  Move(V, GfxBuf^[5], 2);
  V := YRes;
  Move(V, GfxBuf^[7], 2);
  V := AspX;
  Move(V, GfxBuf^[9], 2);
  V := NumColors;
  Move(V, GfxBuf^[11], 2);
  GfxMsg(GfxMode, 8);
  if GfxSent <> nil then
    FreeMem(GfxSent, GfxSentSize);
  GfxSentSize := XRes * YRes;
  GetMem(GfxSent, GfxSentSize);
  FillChar(GfxSent^, GfxSentSize, 0);
  FillChar(GfxPal, SizeOf(GfxPal), 0);
  GfxPalSent := False;
end;

{ Mengirim palet bila berubah, lalu baris-baris halaman visual yang berubah. }
procedure GfxSendFrame;
var
  I, Y, X, At, Rows, Start, Run: LongInt;
  Page: PPix;
  Row, Old: LongInt;
  Changed: Boolean;
  V: Word;
  B, Last: Byte;
begin
  Page := Pages[VisualPage];
  if (Page = nil) or (GfxSent = nil) then
    Exit;
  Changed := not GfxPalSent;
  if not Changed then
    for I := 0 to NumColors - 1 do
      if (Pal[I].R <> GfxPal[I].R) or (Pal[I].G <> GfxPal[I].G) or (Pal[I].B <> GfxPal[I].B) then
        Changed := True;
  if Changed then
  begin
    V := NumColors;
    Move(V, GfxBuf^[5], 2);
    for I := 0 to NumColors - 1 do
    begin
      GfxBuf^[7 + I * 3] := Pal[I].R;
      GfxBuf^[8 + I * 3] := Pal[I].G;
      GfxBuf^[9 + I * 3] := Pal[I].B;
      GfxPal[I] := Pal[I];
    end;
    GfxPalSent := True;
    GfxMsg(GfxPalette, 2 + NumColors * 3);
  end;
  At := 7;
  Rows := 0;
  for Y := 0 to YRes - 1 do
  begin
    Row := Y * XRes;
    Changed := False;
    for X := 0 to XRes - 1 do
      if Page^[Row + X] <> GfxSent^[Row + X] then
      begin
        Changed := True;
        Break;
      end;
    if not Changed then
      Continue;
    { Run-length: (panjang 1..255, nilai). }
    Start := At + 4;
    X := 0;
    while X < XRes do
    begin
      Last := Page^[Row + X];
      Run := 1;
      while (X + Run < XRes) and (Run < 255) and (Page^[Row + X + Run] = Last) do
        Inc(Run);
      GfxBuf^[Start] := Run;
      GfxBuf^[Start + 1] := Last;
      Inc(Start, 2);
      Inc(X, Run);
    end;
    V := Y;
    Move(V, GfxBuf^[At], 2);
    V := Start - At - 4;
    Move(V, GfxBuf^[At + 2], 2);
    At := Start;
    Move(Page^[Row], GfxSent^[Row], XRes);
    Inc(Rows);
  end;
  if Rows > 0 then
  begin
    V := Rows;
    Move(V, GfxBuf^[5], 2);
    GfxMsg(GfxFrame, At - 5);
  end;
end;

{ ---- tampilan di terminal ------------------------------------------------------------ }

{ Waktu dalam perseratus detik sejak tengah malam. }
function Ticks: LongInt;
var
  H, M, S, S100: Word;
begin
  GetTime(H, M, S, S100);
  Ticks := ((H * 60 + M) * 60 + S) * 100 + S100;
end;

{ Menghitung pemetaan piksel ke subpiksel terminal: gambar muat di terminal
  dengan perbandingan lebar-tinggi fisik layar, dan ditaruh di tengah. }
procedure SetupDisplay;
var
  SW, SH, I: Integer;
  PhysH, Scale, PW, PH: Double;
  X0, X1, Y0, Y1: LongInt;
begin
  Cols := CrtScreenWidth;
  Rows := CrtScreenHeight;
  if Cols > 255 then
    Cols := 255;
  if Rows > 255 then
    Rows := 255;
  SW := Cols;
  SH := Rows * 2;
  { Tinggi fisik layar, dalam lebar piksel: satu piksel setinggi
    AspY / AspX kali lebarnya. }
  PhysH := YRes * 10000.0 / AspX;
  Scale := XRes / SW;
  if PhysH / SH > Scale then
    Scale := PhysH / SH;
  { Satu subpiksel selebar PW piksel dan setinggi PH piksel. }
  PW := Scale;
  PH := Scale * YRes / PhysH;
  DPW := PW;
  DPH := PH;
  ImgW := Trunc(XRes / PW + 0.999);
  ImgH := Trunc(YRes / PH + 0.999);
  if ImgW > SW then
    ImgW := SW;
  if ImgH > SH then
    ImgH := SH;
  ImgOX := (SW - ImgW) div 2;
  ImgOY := (SH - ImgH) div 2;
  for I := 0 to ImgW - 1 do
  begin
    X0 := Trunc(I * PW);
    X1 := Trunc((I + 1) * PW);
    if X1 <= X0 then
      X1 := X0 + 1;
    if X1 > XRes then
      X1 := XRes;
    if X0 >= XRes then
      X0 := XRes - 1;
    SubX0[I] := X0;
    SubX1[I] := X1;
  end;
  for I := 0 to ImgH - 1 do
  begin
    Y0 := Trunc(I * PH);
    Y1 := Trunc((I + 1) * PH);
    if Y1 <= Y0 then
      Y1 := Y0 + 1;
    if Y1 > YRes then
      Y1 := YRes;
    if Y0 >= YRes then
      Y0 := YRes - 1;
    SubY0[I] := Y0;
    SubY1[I] := Y1;
  end;
end;

{ Warna CRT subpiksel (SX, SY) pada halaman Page; warna palet Ign (bila >= 0)
  dianggap tidak ada, untuk sel yang berisi teks. }
function SubColor(Page: PPix; SX, SY, Ign: Integer): Byte;
var
  X, Y, Best, BestN, I: Integer;
  Count: array[0..255] of Word;
  Row: LongInt;
begin
  SX := SX - ImgOX;
  SY := SY - ImgOY;
  if (SX < 0) or (SY < 0) or (SX >= ImgW) or (SY >= ImgH) then
  begin
    SubColor := TermCol[0];
    Exit;
  end;
  FillChar(Count, SizeOf(Count), 0);
  for Y := SubY0[SY] to SubY1[SY] - 1 do
  begin
    Row := Y * XRes;
    for X := SubX0[SX] to SubX1[SX] - 1 do
      Inc(Count[Page^[Row + X]]);
  end;
  { Warna selain latar yang paling banyak; garis tipis tetap terlihat. }
  Best := 0;
  BestN := 0;
  for I := 1 to NumColors - 1 do
    if (Count[I] > BestN) and (I <> Ign) then
    begin
      BestN := Count[I];
      Best := I;
    end;
  SubColor := TermCol[Best];
end;

{ Sesudah ClrScr semua sel kosong berlatar hitam, sama dengan sel sebuah
  subpiksel hitam. }
procedure ClearScreenCells;
begin
  FillChar(Shown, SizeOf(Shown), 0);
end;

{ Menyusun lapisan teks halaman Page: karakter tiap teks ditaruh di sel
  terminal, satu karakter per sel (lebih dari satu sel bila hurufnya lebar),
  dan sel-sel teks tidak digambar sebagai blok. Teks yang pikselnya sudah
  tertimpa dibuang. }
procedure BuildOverlay(Page: PPix; PageNo: Integer);
var
  I, K, C0, CA, Pitch, R0, R1, CR, CC, C1, R, C, Idx: Integer;
  Valid, Total: Integer;
begin
  FillChar(OvChr, SizeOf(OvChr), 0);
  FillChar(OvIgn, SizeOf(OvIgn), 0);
  for I := 0 to MaxTexts - 1 do
    if Texts[I].Used and (Texts[I].Page = PageNo) then
    begin
      Valid := 0;
      Total := Texts[I].Len;
      for K := 1 to Total do
        if (Texts[I].PX[K] >= 0) and (Texts[I].PX[K] < XRes) and (Texts[I].PY[K] >= 0) and
          (Texts[I].PY[K] < YRes) and (Page^[Texts[I].PY[K] * XRes + Texts[I].PX[K]] = Texts[I].Color) then
          Inc(Valid);
      if Valid * 5 < Total * 3 then
      begin
        Texts[I].Used := False;
        Continue;
      end;
      { Sel yang tertutup kotak teks, lalu karakternya satu per sel (atau tiap
        Pitch sel bila hurufnya lebar), di tengah kotak itu. }
      CA := ImgOX + Trunc(Texts[I].X / DPW);
      C1 := ImgOX + Trunc((Texts[I].X + Total * Texts[I].CW - 1) / DPW);
      Pitch := Round(Texts[I].CW / DPW);
      if Pitch < 1 then
        Pitch := 1;
      C0 := CA + ((C1 - CA + 1) - ((Total - 1) * Pitch + 1)) div 2;
      if C0 < CA then
        C0 := CA;
      { Teks yang lebih dari satu sel per karakter melebar melewati kotaknya. }
      if C0 + (Total - 1) * Pitch > C1 then
        C1 := C0 + (Total - 1) * Pitch;
      R0 := (ImgOY + Trunc(Texts[I].Y / DPH)) div 2;
      R1 := (ImgOY + Trunc((Texts[I].Y + Texts[I].CH - 1) / DPH)) div 2;
      CR := (ImgOY + Trunc((Texts[I].Y + Texts[I].CH div 2) / DPH)) div 2;
      if R1 >= Rows then
        R1 := Rows - 1;
      for R := R0 to R1 do
        for C := CA to C1 do
          if (C >= 0) and (C < Cols) and (R >= 0) then
            OvIgn[R * Cols + C] := Texts[I].Color + 1;
      for K := 1 to Total do
      begin
        CC := C0 + (K - 1) * Pitch;
        if (CC >= 0) and (CC < Cols) and (CR >= 0) and (CR < Rows) then
        begin
          Idx := CR * Cols + CC;
          if (Texts[I].Chars[K] > ' ') and (Texts[I].Chars[K] <= '~') then
            OvChr[Idx] := Ord(Texts[I].Chars[K])
          else
            OvChr[Idx] := 0;
        end;
      end;
    end;
end;

procedure Render;
var
  CX, CY, Idx, Ign: Integer;
  T, B, Attr, Kind: Byte;
  W: Word;
  Page: PPix;
  Run: String;
  RunX, RunCells: Integer;
  RunAttr: Byte;
  Glyph: String;
begin
  Dirty := False;
  LastRender := Ticks;
  if (not Active) or InText then
    Exit;
  if GfxOn then
  begin
    GfxSendFrame;
    if GfxOn then
      Exit;
    { Jendela hilang: kembali ke pratinjau terminal. }
    Display := CrtOutputIsTty;
    if Display then
    begin
      SetupDisplay;
      ClearScreenCells;
      ClrScr;
      CursorOff;
    end;
  end;
  if not Display then
    Exit;
  Page := Pages[VisualPage];
  if Page = nil then
    Exit;
  BuildOverlay(Page, VisualPage);
  for CY := 0 to Rows - 1 do
  begin
    Run := '';
    RunCells := 0;
    RunX := 0;
    RunAttr := 0;
    for CX := 0 to Cols - 1 do
    begin
      Idx := CY * Cols + CX;
      Ign := OvIgn[Idx] - 1;
      T := SubColor(Page, CX, CY * 2, Ign);
      B := SubColor(Page, CX, CY * 2 + 1, Ign);
      { Latar sel hanya 8 warna; warna terang dipakai sebagai warna depan. }
      if OvChr[Idx] <> 0 then
      begin
        { Karakter teks di atas latar sel. }
        Kind := OvChr[Idx];
        if T > 7 then
          Attr := (T - 8) shl 4
        else
          Attr := T shl 4;
        Attr := Attr or TermCol[Ign];
      end
      else if T = B then
      begin
        if T <= 7 then
        begin
          Kind := 0;
          Attr := T shl 4;
        end
        else
        begin
          Kind := 3;
          Attr := T;
        end;
      end
      else if B <= 7 then
      begin
        Kind := 1;
        Attr := T or (B shl 4);
      end
      else if T <= 7 then
      begin
        Kind := 2;
        Attr := B or (T shl 4);
      end
      else
      begin
        Kind := 1;
        Attr := T or ((B - 8) shl 4);
      end;
      W := Kind or (Word(Attr) shl 8);
      if W = Shown[CY * Cols + CX] then
      begin
        if RunCells > 0 then
        begin
          CrtPutText(RunX, CY, Run, RunAttr);
          Run := '';
          RunCells := 0;
        end;
        Continue;
      end;
      Shown[CY * Cols + CX] := W;
      case Kind of
        0: Glyph := GlyphSpace;
        1: Glyph := GlyphUpper;
        2: Glyph := GlyphLower;
        3: Glyph := GlyphFull;
      else
        Glyph := Chr(Kind);
      end;
      if (RunCells > 0) and ((Attr <> RunAttr) or (Length(Run) > 240)) then
      begin
        CrtPutText(RunX, CY, Run, RunAttr);
        Run := '';
        RunCells := 0;
      end;
      if RunCells = 0 then
      begin
        RunX := CX;
        RunAttr := Attr;
      end;
      Run := Run + Glyph;
      Inc(RunCells);
    end;
    if RunCells > 0 then
      CrtPutText(RunX, CY, Run, RunAttr);
  end;
end;

{ Dipanggil Crt sebelum menunggu tombol atau Delay. }
procedure IdleHook;
begin
  if Dirty then
    Render;
end;

{ Dipanggil tiap rutin yang mengubah gambar; menggambar ulang paling sering
  tiap 0,1 detik supaya gambar yang lama dibuat terlihat bertahap. }
procedure Touch;
var
  Elapsed: LongInt;
begin
  Dirty := True;
  Inc(TouchCount);
  if (TouchCount and 255 = 0) and (Display or GfxOn) and Active and not InText then
  begin
    Elapsed := Ticks - LastRender;
    if Elapsed < 0 then
      Elapsed := Elapsed + 8640000;
    if Elapsed >= 10 then
      Render;
  end;
end;

procedure ShowTextScreen;
begin
  if Display then
  begin
    TextAttr := LightGray;
    ClrScr;
    CursorOn;
  end;
end;

procedure GraphExit;
begin
  ExitProc := OldExitProc;
  if Active and (Display or GfxOn) and not InText then
  begin
    if Dirty then
      Render;
    { Gambar terakhir tetap terlihat; kursor kembali di baris bawah. }
    if Display then
    begin
      TextAttr := LightGray;
      GotoXY(1, Rows);
      CursorOn;
    end;
  end;
end;

{ ---- mode dan halaman --------------------------------------------------------------- }

procedure FreePages;
var
  I: Integer;
begin
  for I := 0 to MaxPages - 1 do
    if Pages[I] <> nil then
    begin
      FreeMem(Pages[I], XRes * YRes);
      Pages[I] := nil;
    end;
end;

procedure ResetState;
begin
  VP.X1 := 0;
  VP.Y1 := 0;
  VP.X2 := XRes - 1;
  VP.Y2 := YRes - 1;
  VP.Clip := True;
  ClipX1 := 0;
  ClipY1 := 0;
  ClipX2 := XRes - 1;
  ClipY2 := YRes - 1;
  CPX := 0;
  CPY := 0;
  DefaultPalette;
  CurColor := NumColors - 1;
  BkColor := 0;
  LineSet.LineStyle := SolidLn;
  LineSet.Pattern := $FFFF;
  LineSet.Thickness := NormWidth;
  FillSet.Pattern := SolidFill;
  FillSet.Color := NumColors - 1;
  FillChar(UserPat, SizeOf(UserPat), $FF);
  TextSet.Font := DefaultFont;
  TextSet.Direction := HorizDir;
  TextSet.CharSize := 1;
  TextSet.Horiz := LeftText;
  TextSet.Vert := TopText;
  UMultX := 1;
  UDivX := 1;
  UMultY := 1;
  UDivY := 1;
  CurWriteMode := CopyPut;
end;

procedure GraphDefaults;
begin
  if not Ready then
    Exit;
  ResetState;
  Dirty := True;
end;

{ Memasang mode (driver, mode) yang sudah diperiksa: alokasi, kondisi awal,
  dan layar terminal. }
procedure EnterMode(Driver, Mode: Integer);
var
  W, H, C, P, A: LongInt;
  I: Integer;
begin
  ModeInfo(Driver, Mode, W, H, C, P, A);
  FreePages;
  XRes := W;
  YRes := H;
  NumColors := C;
  NumPages := P;
  CurDriver := Driver;
  CurMode := Mode;
  AspX := A;
  AspY := 10000;
  GetMem(Pages[0], XRes * YRes);
  FillChar(Pages[0]^, XRes * YRes, 0);
  ActivePage := 0;
  VisualPage := 0;
  Pix := Pages[0];
  for I := 0 to MaxTexts - 1 do
    Texts[I].Used := False;
  ArcInfo.X := 0;
  ArcInfo.Y := 0;
  ArcInfo.Xstart := 0;
  ArcInfo.Ystart := 0;
  ArcInfo.Xend := 0;
  ArcInfo.Yend := 0;
  Active := True;
  InText := False;
  ResetState;
  if GfxConn then
    GfxOn := True
  else if not GfxTried then
    GfxConnect;
  GfxSendMode;
  Display := CrtOutputIsTty and not GfxOn;
  if Display then
  begin
    SetupDisplay;
    ClearScreenCells;
    TextAttr := LightGray;
    ClrScr;
    CursorOff;
  end;
  if (Display or GfxOn) and not HooksSet then
  begin
    CrtIdleHook := IdleHook;
    OldExitProc := ExitProc;
    ExitProc := @GraphExit;
    HooksSet := True;
  end;
  Dirty := True;
  LastRender := Ticks;
end;

procedure InitGraph(var GraphDriver: Integer; var GraphMode: Integer; PathToDriver: String);
var
  W, H, C, P, A: LongInt;
begin
  ErrorCode := grOk;
  if GraphDriver = Detect then
    DetectGraph(GraphDriver, GraphMode);
  if (GraphDriver < CGA) or (GraphDriver > PC3270) then
  begin
    if GraphDriver > PC3270 then
      ErrorCode := grInvalidDriver
    else
      ErrorCode := grNotDetected;
    GraphDriver := ErrorCode;
    Exit;
  end;
  if not ModeInfo(GraphDriver, GraphMode, W, H, C, P, A) then
  begin
    ErrorCode := grInvalidMode;
    GraphDriver := ErrorCode;
    Exit;
  end;
  EnterMode(GraphDriver, GraphMode);
end;

procedure CloseGraph;
begin
  if not Active then
  begin
    ErrorCode := grNoInitGraph;
    Exit;
  end;
  if not InText then
    ShowTextScreen;
  if GfxOn then
  begin
    GfxMsg(GfxClose, 0);
    GfxOn := False;
  end;
  FreePages;
  Pix := nil;
  Active := False;
  Dirty := False;
  ErrorCode := grOk;
end;

procedure RestoreCrtMode;
begin
  if not Ready then
    Exit;
  if not InText then
  begin
    InText := True;
    GfxMsg(GfxHide, 0);
    ShowTextScreen;
  end;
end;

procedure SetGraphMode(Mode: Integer);
var
  W, H, C, P, A: LongInt;
begin
  if not Ready then
    Exit;
  if not ModeInfo(CurDriver, Mode, W, H, C, P, A) then
  begin
    SetError(grInvalidMode);
    Exit;
  end;
  EnterMode(CurDriver, Mode);
end;

function GetGraphMode: Integer;
begin
  if Ready then
    GetGraphMode := CurMode
  else
    GetGraphMode := 0;
end;

function GetMaxX: Integer;
begin
  if Ready then
    GetMaxX := XRes - 1
  else
    GetMaxX := 0;
end;

function GetMaxY: Integer;
begin
  if Ready then
    GetMaxY := YRes - 1
  else
    GetMaxY := 0;
end;

function GetX: Integer;
begin
  if Ready then
    GetX := CPX
  else
    GetX := 0;
end;

function GetY: Integer;
begin
  if Ready then
    GetY := CPY
  else
    GetY := 0;
end;

procedure GetAspectRatio(var Xasp, Yasp: Word);
begin
  if Ready then
  begin
    Xasp := AspX;
    Yasp := AspY;
  end;
end;

procedure SetAspectRatio(Xasp, Yasp: Word);
begin
  if not Ready then
    Exit;
  if (Xasp = 0) or (Yasp = 0) then
  begin
    SetError(grError);
    Exit;
  end;
  AspX := Xasp;
  AspY := Yasp;
end;

procedure SetGraphBufSize(BufSize: Word);
begin
end;

function InstallUserDriver(DriverFileName: String; AutoDetectPtr: Pointer): Integer;
begin
  { Tidak ada driver pemakai: nomor driver sesudah yang bawaan. }
  InstallUserDriver := PC3270 + 1;
end;

function InstallUserFont(FontFileName: String): Integer;
begin
  InstallUserFont := GothicFont + 1;
end;

function RegisterBGIdriver(Driver: Pointer): Integer;
begin
  RegisterBGIdriver := PC3270 + 1;
end;

function RegisterBGIfont(Font: Pointer): Integer;
begin
  RegisterBGIfont := GothicFont + 1;
end;

procedure UsePage(Page: Integer);
begin
  if Pages[Page] = nil then
  begin
    GetMem(Pages[Page], XRes * YRes);
    FillChar(Pages[Page]^, XRes * YRes, 0);
  end;
end;

procedure SetActivePage(Page: Word);
begin
  if not Ready then
    Exit;
  if Page >= NumPages then
  begin
    SetError(grError);
    Exit;
  end;
  UsePage(Page);
  ActivePage := Page;
  Pix := Pages[Page];
end;

procedure SetVisualPage(Page: Word);
begin
  if not Ready then
    Exit;
  if Page >= NumPages then
  begin
    SetError(grError);
    Exit;
  end;
  UsePage(Page);
  VisualPage := Page;
  Dirty := True;
end;

{ ---- viewport ------------------------------------------------------------------------ }

{ Buang catatan teks halaman Page (halamannya dikosongkan). }
procedure ClearTexts(Page: Integer);
var
  I: Integer;
begin
  for I := 0 to MaxTexts - 1 do
    if Texts[I].Page = Page then
      Texts[I].Used := False;
end;

procedure UpdateClip;
begin
  if VP.Clip then
  begin
    ClipX1 := VP.X1;
    ClipY1 := VP.Y1;
    ClipX2 := VP.X2;
    ClipY2 := VP.Y2;
  end
  else
  begin
    ClipX1 := 0;
    ClipY1 := 0;
    ClipX2 := XRes - 1;
    ClipY2 := YRes - 1;
  end;
end;

procedure SetViewPort(X1, Y1, X2, Y2: Integer; Clip: Boolean);
begin
  if not Ready then
    Exit;
  if (X1 < 0) or (Y1 < 0) or (X2 < X1) or (Y2 < Y1) or (X2 >= XRes) or (Y2 >= YRes) then
  begin
    SetError(grError);
    Exit;
  end;
  VP.X1 := X1;
  VP.Y1 := Y1;
  VP.X2 := X2;
  VP.Y2 := Y2;
  VP.Clip := Clip;
  UpdateClip;
  CPX := 0;
  CPY := 0;
end;

procedure GetViewSettings(var ViewPort: ViewPortType);
begin
  if Ready then
    ViewPort := VP;
end;

procedure FillRectRaw(X1, Y1, X2, Y2: LongInt; C: Byte);
var
  Y: LongInt;
begin
  if X1 < 0 then
    X1 := 0;
  if Y1 < 0 then
    Y1 := 0;
  if X2 >= XRes then
    X2 := XRes - 1;
  if Y2 >= YRes then
    Y2 := YRes - 1;
  if (X2 < X1) or (Y2 < Y1) then
    Exit;
  for Y := Y1 to Y2 do
    FillChar(Pix^[Y * XRes + X1], X2 - X1 + 1, C);
end;

procedure ClearDevice;
begin
  if not Ready then
    Exit;
  FillRectRaw(0, 0, XRes - 1, YRes - 1, 0);
  ClearTexts(ActivePage);
  CPX := 0;
  CPY := 0;
  Touch;
end;

procedure ClearViewPort;
begin
  if not Ready then
    Exit;
  FillRectRaw(VP.X1, VP.Y1, VP.X2, VP.Y2, 0);
  CPX := 0;
  CPY := 0;
  Touch;
end;

{ ---- piksel dan garis ----------------------------------------------------------------- }

{ Menulis piksel di koordinat layar (bukan viewport), dengan klip. }
procedure PutRaw(X, Y: LongInt; C: Byte);
begin
  if (X < ClipX1) or (X > ClipX2) or (Y < ClipY1) or (Y > ClipY2) then
    Exit;
  Pix^[Y * XRes + X] := C;
end;

procedure PutRawMode(X, Y: LongInt; C: Byte; Mode: Integer);
var
  Off: LongInt;
begin
  if (X < ClipX1) or (X > ClipX2) or (Y < ClipY1) or (Y > ClipY2) then
    Exit;
  Off := Y * XRes + X;
  case Mode of
    XORPut: Pix^[Off] := Pix^[Off] xor C;
    OrPut: Pix^[Off] := Pix^[Off] or C;
    AndPut: Pix^[Off] := Pix^[Off] and C;
    NotPut: Pix^[Off] := (not C) and (NumColors - 1);
  else
    Pix^[Off] := C;
  end;
end;

procedure PutPixel(X, Y: Integer; Pixel: Word);
begin
  if not Ready then
    Exit;
  PutRaw(VP.X1 + X, VP.Y1 + Y, Pixel);
  Touch;
end;

function GetPixel(X, Y: Integer): Word;
var
  AX, AY: LongInt;
begin
  GetPixel := 0;
  if not Ready then
    Exit;
  AX := VP.X1 + X;
  AY := VP.Y1 + Y;
  if (AX < ClipX1) or (AX > ClipX2) or (AY < ClipY1) or (AY > ClipY2) then
    Exit;
  GetPixel := Pix^[AY * XRes + AX];
end;

{ Garis Bresenham antara dua titik layar. Pat dipakai bit demi bit (bit 15
  dulu) dan diulang tiap 16 piksel; Thick = 3 menebalkan satu piksel ke tiap
  sisi. }
procedure DrawLineRaw(X1, Y1, X2, Y2: LongInt; Pat: Word; Thick: Integer; Mode: Integer; C: Byte);
var
  Dx, Dy, Sx, Sy, Err, E2, Step: LongInt;
  Horizontal: Boolean;

  procedure Plot(X, Y: LongInt);
  begin
    if Thick > 1 then
    begin
      if Horizontal then
      begin
        PutRawMode(X, Y - 1, C, Mode);
        PutRawMode(X, Y, C, Mode);
        PutRawMode(X, Y + 1, C, Mode);
      end
      else
      begin
        PutRawMode(X - 1, Y, C, Mode);
        PutRawMode(X, Y, C, Mode);
        PutRawMode(X + 1, Y, C, Mode);
      end;
    end
    else
      PutRawMode(X, Y, C, Mode);
  end;

begin
  Dx := Abs(X2 - X1);
  Dy := Abs(Y2 - Y1);
  if X1 < X2 then
    Sx := 1
  else
    Sx := -1;
  if Y1 < Y2 then
    Sy := 1
  else
    Sy := -1;
  Horizontal := Dx >= Dy;
  Err := Dx - Dy;
  Step := 0;
  while True do
  begin
    if (Pat shl (Step and 15)) and $8000 <> 0 then
      Plot(X1, Y1);
    if (X1 = X2) and (Y1 = Y2) then
      Break;
    E2 := 2 * Err;
    if E2 > -Dy then
    begin
      Err := Err - Dy;
      X1 := X1 + Sx;
    end;
    if E2 < Dx then
    begin
      Err := Err + Dx;
      Y1 := Y1 + Sy;
    end;
    Inc(Step);
  end;
end;

{ Garis penuh (lingkaran, busur, tepi isian); koordinat layar. }
procedure SolidLine(X1, Y1, X2, Y2: LongInt);
begin
  DrawLineRaw(X1, Y1, X2, Y2, $FFFF, LineSet.Thickness, CopyPut, CurColor);
end;

{ Garis dengan gaya garis, ketebalan, dan mode tulis kini; koordinat viewport. }
procedure StyledLine(X1, Y1, X2, Y2: LongInt);
begin
  DrawLineRaw(VP.X1 + X1, VP.Y1 + Y1, VP.X1 + X2, VP.Y1 + Y2, LineSet.Pattern, LineSet.Thickness,
    CurWriteMode, CurColor);
end;

procedure Line(X1, Y1, X2, Y2: Integer);
begin
  if not Ready then
    Exit;
  StyledLine(X1, Y1, X2, Y2);
  Touch;
end;

procedure LineTo(X, Y: Integer);
begin
  if not Ready then
    Exit;
  StyledLine(CPX, CPY, X, Y);
  CPX := X;
  CPY := Y;
  Touch;
end;

procedure LineRel(Dx, Dy: Integer);
begin
  if not Ready then
    Exit;
  StyledLine(CPX, CPY, CPX + Dx, CPY + Dy);
  CPX := CPX + Dx;
  CPY := CPY + Dy;
  Touch;
end;

procedure MoveTo(X, Y: Integer);
begin
  if not Ready then
    Exit;
  CPX := X;
  CPY := Y;
end;

procedure MoveRel(Dx, Dy: Integer);
begin
  if not Ready then
    Exit;
  CPX := CPX + Dx;
  CPY := CPY + Dy;
end;

procedure Rectangle(X1, Y1, X2, Y2: Integer);
begin
  if not Ready then
    Exit;
  StyledLine(X1, Y1, X2, Y1);
  StyledLine(X2, Y1, X2, Y2);
  StyledLine(X2, Y2, X1, Y2);
  StyledLine(X1, Y2, X1, Y1);
  Touch;
end;

procedure SetLineStyle(LineStyle: Word; Pattern: Word; Thickness: Word);
begin
  if not Ready then
    Exit;
  if (LineStyle > UserBitLn) or ((Thickness <> NormWidth) and (Thickness <> ThickWidth)) then
  begin
    SetError(grError);
    Exit;
  end;
  LineSet.LineStyle := LineStyle;
  LineSet.Thickness := Thickness;
  if LineStyle = UserBitLn then
    LineSet.Pattern := Pattern
  else
    LineSet.Pattern := LinePatterns[LineStyle];
end;

procedure GetLineSettings(var LineInfo: LineSettingsType);
begin
  if Ready then
    LineInfo := LineSet;
end;

procedure SetWriteMode(WriteMode: Integer);
begin
  if not Ready then
    Exit;
  if (WriteMode <> CopyPut) and (WriteMode <> XORPut) then
  begin
    SetError(grError);
    Exit;
  end;
  CurWriteMode := WriteMode;
end;

{ ---- isian ------------------------------------------------------------------------------ }

procedure SetFillStyle(Pattern: Word; Color: Word);
begin
  if not Ready then
    Exit;
  if (Pattern > UserFill) or (Color >= NumColors) then
  begin
    SetError(grError);
    Exit;
  end;
  FillSet.Pattern := Pattern;
  FillSet.Color := Color;
end;

procedure SetFillPattern(Pattern: FillPatternType; Color: Word);
begin
  if not Ready then
    Exit;
  if Color >= NumColors then
  begin
    SetError(grError);
    Exit;
  end;
  UserPat := Pattern;
  FillSet.Pattern := UserFill;
  FillSet.Color := Color;
end;

procedure GetFillSettings(var FillInfo: FillSettingsType);
begin
  if Ready then
    FillInfo := FillSet;
end;

procedure GetFillPattern(var FillPattern: FillPatternType);
var
  I: Integer;
begin
  if not Ready then
    Exit;
  if FillSet.Pattern = UserFill then
    FillPattern := UserPat
  else
    for I := 1 to 8 do
      FillPattern[I] := FillPatterns[FillSet.Pattern, I - 1];
end;

{ Baris pola isian (0..7) pada koordinat layar Y. }
function PatternRow(Y: LongInt): Byte;
var
  R: Integer;
begin
  R := Y and 7;
  if FillSet.Pattern = UserFill then
    PatternRow := UserPat[R + 1]
  else
    PatternRow := FillPatterns[FillSet.Pattern, R];
end;

{ Isi persegi panjang (koordinat layar) dengan pola isian; bit 1 memakai warna
  isian, bit 0 warna latar. }
procedure FillRectPattern(X1, Y1, X2, Y2: LongInt);
var
  X, Y: LongInt;
  Row: Byte;
begin
  if X1 < ClipX1 then
    X1 := ClipX1;
  if Y1 < ClipY1 then
    Y1 := ClipY1;
  if X2 > ClipX2 then
    X2 := ClipX2;
  if Y2 > ClipY2 then
    Y2 := ClipY2;
  if (X2 < X1) or (Y2 < Y1) then
    Exit;
  for Y := Y1 to Y2 do
  begin
    Row := PatternRow(Y);
    if Row = $FF then
      FillChar(Pix^[Y * XRes + X1], X2 - X1 + 1, FillSet.Color)
    else if Row = 0 then
      FillChar(Pix^[Y * XRes + X1], X2 - X1 + 1, 0)
    else
      for X := X1 to X2 do
        if (Row shr (7 - (X and 7))) and 1 <> 0 then
          Pix^[Y * XRes + X] := FillSet.Color
        else
          Pix^[Y * XRes + X] := 0;
  end;
end;

procedure Bar(X1, Y1, X2, Y2: Integer);
var
  T: Integer;
begin
  if not Ready then
    Exit;
  if X1 > X2 then
  begin
    T := X1;
    X1 := X2;
    X2 := T;
  end;
  if Y1 > Y2 then
  begin
    T := Y1;
    Y1 := Y2;
    Y2 := T;
  end;
  FillRectPattern(VP.X1 + X1, VP.Y1 + Y1, VP.X1 + X2, VP.Y1 + Y2);
  Touch;
end;

procedure Bar3D(X1, Y1, X2, Y2: Integer; Depth: Word; Top: Boolean);
var
  Dy: LongInt;
  T: Integer;
begin
  if not Ready then
    Exit;
  if X1 > X2 then
  begin
    T := X1;
    X1 := X2;
    X2 := T;
  end;
  if Y1 > Y2 then
  begin
    T := Y1;
    Y1 := Y2;
    Y2 := T;
  end;
  FillRectPattern(VP.X1 + X1, VP.Y1 + Y1, VP.X1 + X2, VP.Y1 + Y2);
  { Sisi samping dan atas menyerong 45 derajat menurut perbandingan piksel. }
  Dy := (Depth * LongInt(AspX)) div AspY;
  StyledLine(X1, Y1, X2, Y1);
  StyledLine(X2, Y1, X2, Y2);
  StyledLine(X2, Y2, X1, Y2);
  StyledLine(X1, Y2, X1, Y1);
  if Depth > 0 then
  begin
    StyledLine(X2, Y2, X2 + Depth, Y2 - Dy);
    StyledLine(X2 + Depth, Y2 - Dy, X2 + Depth, Y1 - Dy);
    StyledLine(X2 + Depth, Y1 - Dy, X2, Y1);
    if Top then
    begin
      StyledLine(X1, Y1, X1 + Depth, Y1 - Dy);
      StyledLine(X1 + Depth, Y1 - Dy, X2 + Depth, Y1 - Dy);
    end;
  end;
  Touch;
end;

{ Mengisi poligon (koordinat layar, even-odd) dengan pola isian. }
procedure FillPolyRaw(N: Integer; Pts: PPts);
var
  MinY, MaxY, Y, I, J, K, Cnt: LongInt;
  X1, Y1, X2, Y2, T: LongInt;
  Xs: PLongs;
  XA, XB, X: LongInt;
  Row: Byte;
begin
  if N < 3 then
    Exit;
  MinY := Pts^[0].Y;
  MaxY := MinY;
  for I := 1 to N - 1 do
  begin
    if Pts^[I].Y < MinY then
      MinY := Pts^[I].Y;
    if Pts^[I].Y > MaxY then
      MaxY := Pts^[I].Y;
  end;
  if MinY < ClipY1 then
    MinY := ClipY1;
  if MaxY > ClipY2 then
    MaxY := ClipY2;
  GetMem(Xs, (N + 1) * SizeOf(LongInt));
  for Y := MinY to MaxY do
  begin
    Cnt := 0;
    for I := 0 to N - 1 do
    begin
      X1 := Pts^[I].X;
      Y1 := Pts^[I].Y;
      J := I + 1;
      if J = N then
        J := 0;
      X2 := Pts^[J].X;
      Y2 := Pts^[J].Y;
      if Y1 = Y2 then
        Continue;
      if Y1 > Y2 then
      begin
        T := X1;
        X1 := X2;
        X2 := T;
        T := Y1;
        Y1 := Y2;
        Y2 := T;
      end;
      if (Y >= Y1) and (Y < Y2) then
      begin
        { Perpotongan dibulatkan ke piksel terdekat. }
        T := (Y - Y1) * (X2 - X1) * 2;
        if T >= 0 then
          Xs^[Cnt] := X1 + (T + (Y2 - Y1)) div ((Y2 - Y1) * 2)
        else
          Xs^[Cnt] := X1 - ((-T + (Y2 - Y1)) div ((Y2 - Y1) * 2));
        Inc(Cnt);
      end;
    end;
    { Urutkan perpotongan. }
    for I := 1 to Cnt - 1 do
    begin
      T := Xs^[I];
      K := I - 1;
      while (K >= 0) and (Xs^[K] > T) do
      begin
        Xs^[K + 1] := Xs^[K];
        Dec(K);
      end;
      Xs^[K + 1] := T;
    end;
    Row := PatternRow(Y);
    I := 0;
    while I + 1 < Cnt do
    begin
      XA := Xs^[I];
      XB := Xs^[I + 1];
      if XA < ClipX1 then
        XA := ClipX1;
      if XB > ClipX2 then
        XB := ClipX2;
      for X := XA to XB do
        if (Row shr (7 - (X and 7))) and 1 <> 0 then
          Pix^[Y * XRes + X] := FillSet.Color
        else
          Pix^[Y * XRes + X] := 0;
      Inc(I, 2);
    end;
  end;
  FreeMem(Xs, (N + 1) * SizeOf(LongInt));
end;

procedure DrawPoly(NumPoints: Word; var PolyPoints);
var
  P: PPointArray;
  I: Integer;
begin
  if not Ready then
    Exit;
  if NumPoints < 1 then
  begin
    SetError(grError);
    Exit;
  end;
  P := @PolyPoints;
  if NumPoints = 1 then
    PutRawMode(VP.X1 + P^[0].X, VP.Y1 + P^[0].Y, CurColor, CurWriteMode)
  else
    for I := 0 to NumPoints - 2 do
      StyledLine(P^[I].X, P^[I].Y, P^[I + 1].X, P^[I + 1].Y);
  Touch;
end;

procedure FillPoly(NumPoints: Word; var PolyPoints);
var
  P: PPointArray;
  Pts: PPts;
  I, N: Integer;
begin
  if not Ready then
    Exit;
  if NumPoints < 1 then
  begin
    SetError(grError);
    Exit;
  end;
  P := @PolyPoints;
  N := NumPoints;
  if N > MaxPts then
    N := MaxPts;
  GetMem(Pts, N * SizeOf(TPt));
  for I := 0 to N - 1 do
  begin
    Pts^[I].X := VP.X1 + P^[I].X;
    Pts^[I].Y := VP.Y1 + P^[I].Y;
  end;
  FillPolyRaw(N, Pts);
  { Garis tepi dengan gaya garis kini. }
  for I := 0 to N - 1 do
    if I = N - 1 then
      StyledLine(P^[I].X, P^[I].Y, P^[0].X, P^[0].Y)
    else
      StyledLine(P^[I].X, P^[I].Y, P^[I + 1].X, P^[I + 1].Y);
  FreeMem(Pts, N * SizeOf(TPt));
  Touch;
end;

{ ---- lingkaran dan busur ------------------------------------------------------------------ }

{ Titik busur elips pada sudut A (derajat, berlawanan jarum jam dari jam 3),
  dalam koordinat layar. }
procedure ArcPoint(CX, CY, RX, RY: LongInt; A: Double; var X, Y: LongInt);
begin
  X := CX + Round(RX * Cos(A * Pi / 180));
  Y := CY - Round(RY * Sin(A * Pi / 180));
end;

{ Mengisi Pts mulai indeks Start dengan titik-titik busur dari St ke En
  derajat; mengembalikan indeks sesudah titik terakhir. En < St berarti
  melewati 360. }
function ArcPoints(CX, CY, RX, RY: LongInt; St, En: Integer; Pts: PPts; Start: Integer): Integer;
var
  N, Count, I: Integer;
  A, Span, Step: Double;
  R: LongInt;
begin
  if En < St then
    En := En + 360;
  Span := En - St;
  R := RX;
  if RY > R then
    R := RY;
  if R < 1 then
    R := 1;
  Count := Trunc(Span * Pi / 180 * R) + 1;
  if Count < 2 then
    Count := 2;
  if Count > MaxPts - Start - 2 then
    Count := MaxPts - Start - 2;
  Step := Span / Count;
  N := Start;
  for I := 0 to Count do
  begin
    A := St + I * Step;
    if I = Count then
      A := En;
    ArcPoint(CX, CY, RX, RY, A, Pts^[N].X, Pts^[N].Y);
    Inc(N);
  end;
  ArcPoints := N;
end;

procedure SetArcCoords(X, Y: Integer; St, En: Integer; RX, RY: LongInt);
var
  PX, PY: LongInt;
begin
  ArcInfo.X := X;
  ArcInfo.Y := Y;
  ArcPoint(X, Y, RX, RY, St, PX, PY);
  ArcInfo.Xstart := PX;
  ArcInfo.Ystart := PY;
  ArcPoint(X, Y, RX, RY, En, PX, PY);
  ArcInfo.Xend := PX;
  ArcInfo.Yend := PY;
end;

procedure EllipseArc(X, Y: Integer; St, En: Integer; RX, RY: LongInt);
var
  Pts: PPts;
  N, I: Integer;
begin
  GetMem(Pts, MaxPts * SizeOf(TPt));
  N := ArcPoints(VP.X1 + X, VP.Y1 + Y, RX, RY, St, En, Pts, 0);
  if N = 1 then
    PutRaw(Pts^[0].X, Pts^[0].Y, CurColor)
  else
    for I := 0 to N - 2 do
      SolidLine(Pts^[I].X, Pts^[I].Y, Pts^[I + 1].X, Pts^[I + 1].Y);
  FreeMem(Pts, MaxPts * SizeOf(TPt));
  SetArcCoords(X, Y, St, En, RX, RY);
end;

function AspectY(R: LongInt): LongInt;
begin
  AspectY := (R * AspX + AspY div 2) div AspY;
end;

procedure Circle(X, Y: Integer; Radius: Word);
begin
  if not Ready then
    Exit;
  EllipseArc(X, Y, 0, 360, Radius, AspectY(Radius));
  Touch;
end;

procedure Arc(X, Y: Integer; StAngle, EndAngle, Radius: Word);
begin
  if not Ready then
    Exit;
  EllipseArc(X, Y, StAngle mod 361, EndAngle mod 361, Radius, AspectY(Radius));
  Touch;
end;

procedure Ellipse(X, Y: Integer; StAngle, EndAngle: Word; XRadius, YRadius: Word);
begin
  if not Ready then
    Exit;
  EllipseArc(X, Y, StAngle mod 361, EndAngle mod 361, XRadius, YRadius);
  Touch;
end;

procedure FillEllipse(X, Y: Integer; XRadius, YRadius: Word);
var
  Pts: PPts;
  N, I: Integer;
begin
  if not Ready then
    Exit;
  GetMem(Pts, MaxPts * SizeOf(TPt));
  N := ArcPoints(VP.X1 + X, VP.Y1 + Y, XRadius, YRadius, 0, 360, Pts, 0);
  FillPolyRaw(N, Pts);
  for I := 0 to N - 2 do
    SolidLine(Pts^[I].X, Pts^[I].Y, Pts^[I + 1].X, Pts^[I + 1].Y);
  FreeMem(Pts, MaxPts * SizeOf(TPt));
  Touch;
end;

procedure SectorRaw(X, Y: Integer; St, En: Integer; RX, RY: LongInt);
var
  Pts: PPts;
  N, I: Integer;
  CX, CY: LongInt;
begin
  CX := VP.X1 + X;
  CY := VP.Y1 + Y;
  GetMem(Pts, MaxPts * SizeOf(TPt));
  Pts^[0].X := CX;
  Pts^[0].Y := CY;
  N := ArcPoints(CX, CY, RX, RY, St, En, Pts, 1);
  FillPolyRaw(N, Pts);
  { Garis tepi: busur dan dua jari-jari. }
  for I := 1 to N - 2 do
    SolidLine(Pts^[I].X, Pts^[I].Y, Pts^[I + 1].X, Pts^[I + 1].Y);
  SolidLine(CX, CY, Pts^[1].X, Pts^[1].Y);
  SolidLine(CX, CY, Pts^[N - 1].X, Pts^[N - 1].Y);
  FreeMem(Pts, MaxPts * SizeOf(TPt));
  SetArcCoords(X, Y, St, En, RX, RY);
end;

procedure PieSlice(X, Y: Integer; StAngle, EndAngle, Radius: Word);
begin
  if not Ready then
    Exit;
  SectorRaw(X, Y, StAngle mod 361, EndAngle mod 361, Radius, AspectY(Radius));
  Touch;
end;

procedure Sector(X, Y: Integer; StAngle, EndAngle, XRadius, YRadius: Word);
begin
  if not Ready then
    Exit;
  SectorRaw(X, Y, StAngle mod 361, EndAngle mod 361, XRadius, YRadius);
  Touch;
end;

procedure GetArcCoords(var ArcCoords: ArcCoordsType);
begin
  if Ready then
    ArcCoords := ArcInfo;
end;

{ ---- FloodFill ---------------------------------------------------------------------------- }

procedure FloodFill(X, Y: Integer; Border: Word);
const
  StackSize = 200000;
var
  Visited: PPix;
  Stack: PLongs;
  SP: LongInt;
  VBytes: LongInt;
  AX, AY: LongInt;
  CX, CY, XL, XR, I, NY: LongInt;
  Row: Byte;
  InRun: Boolean;

  function IsVisited(PX, PY: LongInt): Boolean;
  var
    Idx: LongInt;
  begin
    Idx := PY * XRes + PX;
    IsVisited := (Visited^[Idx shr 3] shr (Idx and 7)) and 1 <> 0;
  end;

  procedure MarkVisited(PX, PY: LongInt);
  var
    Idx: LongInt;
  begin
    Idx := PY * XRes + PX;
    Visited^[Idx shr 3] := Visited^[Idx shr 3] or (1 shl (Idx and 7));
  end;

  function Open(PX, PY: LongInt): Boolean;
  begin
    Open := (PX >= ClipX1) and (PX <= ClipX2) and (PY >= ClipY1) and (PY <= ClipY2) and
      (Pix^[PY * XRes + PX] <> Border) and not IsVisited(PX, PY);
  end;

  procedure Push(PX, PY: LongInt);
  begin
    if SP + 2 <= StackSize * 2 then
    begin
      Stack^[SP] := PX;
      Stack^[SP + 1] := PY;
      Inc(SP, 2);
    end
    else
      SetError(grNoFloodMem);
  end;

begin
  if not Ready then
    Exit;
  if Border >= NumColors then
  begin
    SetError(grError);
    Exit;
  end;
  AX := VP.X1 + X;
  AY := VP.Y1 + Y;
  if (AX < ClipX1) or (AX > ClipX2) or (AY < ClipY1) or (AY > ClipY2) then
    Exit;
  VBytes := (XRes * YRes + 7) div 8;
  GetMem(Visited, VBytes);
  FillChar(Visited^, VBytes, 0);
  GetMem(Stack, StackSize * 2 * SizeOf(LongInt));
  SP := 0;
  Push(AX, AY);
  while SP > 0 do
  begin
    Dec(SP, 2);
    CX := Stack^[SP];
    CY := Stack^[SP + 1];
    if not Open(CX, CY) then
      Continue;
    XL := CX;
    while Open(XL - 1, CY) do
      Dec(XL);
    XR := CX;
    while Open(XR + 1, CY) do
      Inc(XR);
    Row := PatternRow(CY);
    for I := XL to XR do
    begin
      MarkVisited(I, CY);
      if (Row shr (7 - (I and 7))) and 1 <> 0 then
        Pix^[CY * XRes + I] := FillSet.Color
      else
        Pix^[CY * XRes + I] := 0;
    end;
    for NY := CY - 1 to CY + 1 do
      if NY <> CY then
      begin
        InRun := False;
        for I := XL to XR do
          if Open(I, NY) then
          begin
            if not InRun then
              Push(I, NY);
            InRun := True;
          end
          else
            InRun := False;
      end;
  end;
  FreeMem(Stack, StackSize * 2 * SizeOf(LongInt));
  FreeMem(Visited, VBytes);
  Touch;
end;

{ ---- gambar ---------------------------------------------------------------------------------- }

{ Bitmap: dua Word (lebar, tinggi) lalu satu byte per piksel. }
function ImageSize(X1, Y1, X2, Y2: Integer): LongInt;
var
  W, H: LongInt;
begin
  W := Abs(X2 - X1) + 1;
  H := Abs(Y2 - Y1) + 1;
  ImageSize := SizeOf(TImageHeader) + W * H;
end;

procedure GetImage(X1, Y1, X2, Y2: Integer; var BitMap);
var
  Hdr: PImageHeader;
  Data: PPix;
  T, X, Y, W, H, AX, AY: LongInt;
begin
  if not Ready then
    Exit;
  if X1 > X2 then
  begin
    T := X1;
    X1 := X2;
    X2 := T;
  end;
  if Y1 > Y2 then
  begin
    T := Y1;
    Y1 := Y2;
    Y2 := T;
  end;
  W := X2 - X1 + 1;
  H := Y2 - Y1 + 1;
  Hdr := @BitMap;
  Hdr^.Width := W;
  Hdr^.Height := H;
  Data := PPix(Int64(@BitMap) + SizeOf(TImageHeader));
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      AX := VP.X1 + X1 + X;
      AY := VP.Y1 + Y1 + Y;
      if (AX >= 0) and (AX < XRes) and (AY >= 0) and (AY < YRes) then
        Data^[Y * W + X] := Pix^[AY * XRes + AX]
      else
        Data^[Y * W + X] := 0;
    end;
end;

procedure PutImage(X, Y: Integer; var BitMap; BitBlt: Word);
var
  Hdr: PImageHeader;
  Data: PPix;
  PX, PY, W, H: LongInt;
begin
  if not Ready then
    Exit;
  if BitBlt > NotPut then
  begin
    SetError(grError);
    Exit;
  end;
  Hdr := @BitMap;
  W := Hdr^.Width;
  H := Hdr^.Height;
  Data := PPix(Int64(@BitMap) + SizeOf(TImageHeader));
  for PY := 0 to H - 1 do
    for PX := 0 to W - 1 do
      PutRawMode(VP.X1 + X + PX, VP.Y1 + Y + PY, Data^[PY * W + PX], BitBlt);
  Touch;
end;

{ ---- teks ------------------------------------------------------------------------------------- }

procedure SetTextStyle(Font, Direction: Word; CharSize: Word);
begin
  if not Ready then
    Exit;
  if Font > GothicFont then
  begin
    SetError(grInvalidFontNum);
    Exit;
  end;
  if CharSize > 10 then
    CharSize := 10;
  TextSet.Font := Font;
  TextSet.Direction := Direction and 1;
  TextSet.CharSize := CharSize;
end;

procedure SetTextJustify(Horiz, Vert: Word);
begin
  if not Ready then
    Exit;
  if (Horiz > RightText) or (Vert > TopText) then
  begin
    SetError(grError);
    Exit;
  end;
  TextSet.Horiz := Horiz;
  TextSet.Vert := Vert;
end;

procedure GetTextSettings(var TextInfo: TextSettingsType);
begin
  if Ready then
    TextInfo := TextSet;
end;

procedure SetUserCharSize(MultX, DivX, MultY, DivY: Word);
begin
  if not Ready then
    Exit;
  if (DivX = 0) or (DivY = 0) then
  begin
    SetError(grError);
    Exit;
  end;
  UMultX := MultX;
  UDivX := DivX;
  UMultY := MultY;
  UDivY := DivY;
end;

{ Lebar dan tinggi satu karakter dalam piksel. }
procedure CharBox(var W, H: LongInt);
begin
  if TextSet.CharSize = UserCharSize then
  begin
    W := (8 * LongInt(UMultX)) div UDivX;
    H := (8 * LongInt(UMultY)) div UDivY;
    if W < 1 then
      W := 1;
    if H < 1 then
      H := 1;
  end
  else
  begin
    W := 8 * LongInt(TextSet.CharSize);
    H := W;
  end;
end;

function TextWidth(TextString: String): Word;
var
  W, H: LongInt;
begin
  if not Ready then
  begin
    TextWidth := 0;
    Exit;
  end;
  CharBox(W, H);
  if TextSet.Direction = HorizDir then
    TextWidth := W * Length(TextString)
  else
    TextWidth := W;
end;

function TextHeight(TextString: String): Word;
var
  W, H: LongInt;
begin
  if not Ready then
  begin
    TextHeight := 0;
    Exit;
  end;
  CharBox(W, H);
  if TextSet.Direction = HorizDir then
    TextHeight := H
  else
    TextHeight := H * Length(TextString);
end;

{ Satu karakter dengan kotak kiri-atas (BX, BY), lebar W, tinggi H; Vertical
  berarti diputar 90 derajat berlawanan jarum jam. }
procedure DrawGlyph(Ch: Char; BX, BY, W, H: LongInt; Vertical: Boolean; var FirstX, FirstY: Integer);
var
  DX, DY, GX, GY, Code: LongInt;
  Bits: Byte;
begin
  FirstX := -1;
  FirstY := -1;
  Code := Ord(Ch);
  if (Code < 32) or (Code > 126) then
    Exit;
  for DY := 0 to H - 1 do
    for DX := 0 to W - 1 do
    begin
      if Vertical then
      begin
        { Kolom kotak = baris glyph, baris kotak = 7 - kolom glyph. }
        GY := (DX * 8) div W;
        GX := 7 - (DY * 8) div H;
      end
      else
      begin
        GX := (DX * 8) div W;
        GY := (DY * 8) div H;
      end;
      Bits := Font8x8[Code, GY];
      if (Bits shr GX) and 1 <> 0 then
      begin
        PutRaw(BX + DX, BY + DY, CurColor);
        if (FirstX < 0) and (BX + DX >= ClipX1) and (BX + DX <= ClipX2) and (BY + DY >= ClipY1) and
          (BY + DY <= ClipY2) then
        begin
          FirstX := BX + DX;
          FirstY := BY + DY;
        end;
      end;
    end;
end;

{ Mencatat teks mendatar yang baru digambar untuk lapisan teks. Teks yang
  digambar lagi di tempat yang sama menggantikan catatan lamanya. }
procedure AddText(const S: String; Left, Top, CW, CH: LongInt; const PX, PY: array of Integer);
var
  I, K, Slot: Integer;
begin
  if (S = '') or (CurWriteMode <> CopyPut) then
    Exit;
  Slot := -1;
  for I := 0 to MaxTexts - 1 do
    if Texts[I].Used and (Texts[I].Page = ActivePage) and (Texts[I].X = Left) and (Texts[I].Y = Top) then
      Slot := I;
  if Slot < 0 then
  begin
    Slot := TextNext;
    TextNext := (TextNext + 1) mod MaxTexts;
  end;
  Texts[Slot].Used := True;
  Texts[Slot].Page := ActivePage;
  Texts[Slot].Color := CurColor;
  Texts[Slot].X := Left;
  Texts[Slot].Y := Top;
  Texts[Slot].CW := CW;
  Texts[Slot].CH := CH;
  Texts[Slot].Len := Length(S);
  if Texts[Slot].Len > MaxTextLen then
    Texts[Slot].Len := MaxTextLen;
  Texts[Slot].Chars := Copy(S, 1, Texts[Slot].Len);
  for K := 1 to Texts[Slot].Len do
  begin
    Texts[Slot].PX[K] := PX[K - 1];
    Texts[Slot].PY[K] := PY[K - 1];
  end;
end;

procedure DrawText(X, Y: LongInt; const S: String);
var
  CW, CH, TW, TH, Left, Top, I: LongInt;
  PX, PY: array[0..MaxTextLen - 1] of Integer;
  FX, FY: Integer;
begin
  CharBox(CW, CH);
  if TextSet.Direction = HorizDir then
  begin
    TW := CW * Length(S);
    TH := CH;
  end
  else
  begin
    TW := CW;
    TH := CH * Length(S);
  end;
  case TextSet.Horiz of
    CenterText: Left := X - TW div 2;
    RightText: Left := X - TW;
  else
    Left := X;
  end;
  case TextSet.Vert of
    CenterText: Top := Y - TH div 2;
    BottomText: Top := Y - TH;
  else
    Top := Y;
  end;
  Left := Left + VP.X1;
  Top := Top + VP.Y1;
  for I := 1 to Length(S) do
    if TextSet.Direction = HorizDir then
    begin
      DrawGlyph(S[I], Left + (I - 1) * CW, Top, CW, CH, False, FX, FY);
      if I <= MaxTextLen then
      begin
        PX[I - 1] := FX;
        PY[I - 1] := FY;
      end;
    end
    else
      DrawGlyph(S[I], Left, Top + TH - I * CH, CW, CH, True, FX, FY);
  if TextSet.Direction = HorizDir then
    AddText(S, Left, Top, CW, CH, PX, PY);
end;

procedure OutTextXY(X, Y: Integer; TextString: String);
begin
  if not Ready then
    Exit;
  DrawText(X, Y, TextString);
  Touch;
end;

procedure OutText(TextString: String);
begin
  if not Ready then
    Exit;
  DrawText(CPX, CPY, TextString);
  { Hanya teks mendatar yang rata kiri menggeser titik kini. }
  if (TextSet.Direction = HorizDir) and (TextSet.Horiz = LeftText) then
    CPX := CPX + TextWidth(TextString);
  Touch;
end;

begin
  Active := False;
  InText := False;
  Display := False;
  ErrorCode := grOk;
  HooksSet := False;
  Dirty := False;
end.
