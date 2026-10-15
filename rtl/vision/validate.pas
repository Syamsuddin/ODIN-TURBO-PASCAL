{ Odin Turbo Pascal - GNU GPL v3 or later, Copyright (c) 2026 Syams Ideris }
{ Unit Validate dari Odin Vision: validator data untuk TInputLine.
  Implementasi clean-room berdasarkan dokumentasi API Turbo Vision TP7.

  Bahasa picture (TPXPictureValidator):
    #  angka            ?  huruf           &  huruf, dijadikan kapital
    @  karakter apa pun !  karakter apa pun, dijadikan kapital
    ;  karakter berikutnya literal        *N  ulangi elemen berikut N kali
    *  ulangi elemen berikut 0 kali atau lebih
    [..] opsional        kurung kurawal mengelompokkan   ,  pilihan
  Karakter lain adalah literal. Pencocokan mencoba setiap kemungkinan
  (backtracking) dan memilih hasil terbaik: lengkap, lalu belum lengkap,
  lalu salah. Dengan AutoFill, literal yang belum diketik diisikan. }
unit Validate;

{$R-,Q-,I-,X+}

interface

uses Objects;

const
  vsOk = 0;
  vsSyntax = 1;

  voFill = $0001;
  voTransfer = $0002;
  voOnAppend = $0004;
  voReserved = $00F8;

type
  TVTransfer = (vtDataSize, vtSetData, vtGetData);

  TPicResult = (prComplete, prIncomplete, prEmpty, prError, prSyntax, prAmbiguous, prIncompNoFill);

  PValidator = ^TValidator;
  TValidator = object(TObject)
    Status: Word;
    Options: Word;
    constructor Init;
    constructor Load(var S: TStream);
    procedure Error; virtual;
    function IsValidInput(var S: String; SuppressFill: Boolean): Boolean; virtual;
    function IsValid(const S: String): Boolean; virtual;
    procedure Store(var S: TStream);
    function Transfer(var S: String; Buffer: Pointer; Flag: TVTransfer): Word; virtual;
    function Valid(const S: String): Boolean;
  end;

  PPXPictureValidator = ^TPXPictureValidator;
  TPXPictureValidator = object(TValidator)
    Pic: PString;
    constructor Init(const APic: String; AutoFill: Boolean);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure Error; virtual;
    function IsValidInput(var S: String; SuppressFill: Boolean): Boolean; virtual;
    function IsValid(const S: String): Boolean; virtual;
    function Picture(var Input: String; AutoFill: Boolean): TPicResult; virtual;
    procedure Store(var S: TStream);
  end;

  PFilterValidator = ^TFilterValidator;
  TFilterValidator = object(TValidator)
    ValidChars: TCharSet;
    constructor Init(AValidChars: TCharSet);
    constructor Load(var S: TStream);
    procedure Error; virtual;
    function IsValid(const S: String): Boolean; virtual;
    function IsValidInput(var S: String; SuppressFill: Boolean): Boolean; virtual;
    procedure Store(var S: TStream);
  end;

  PRangeValidator = ^TRangeValidator;
  TRangeValidator = object(TFilterValidator)
    Min, Max: LongInt;
    constructor Init(AMin, AMax: LongInt);
    constructor Load(var S: TStream);
    procedure Error; virtual;
    function IsValid(const S: String): Boolean; virtual;
    procedure Store(var S: TStream);
    function Transfer(var S: String; Buffer: Pointer; Flag: TVTransfer): Word; virtual;
  end;

  PLookupValidator = ^TLookupValidator;
  TLookupValidator = object(TValidator)
    function IsValid(const S: String): Boolean; virtual;
    function Lookup(const S: String): Boolean; virtual;
  end;

  PStringLookupValidator = ^TStringLookupValidator;
  TStringLookupValidator = object(TLookupValidator)
    Strings: PStringCollection;
    constructor Init(AStrings: PStringCollection);
    constructor Load(var S: TStream);
    destructor Done; virtual;
    procedure Error; virtual;
    function Lookup(const S: String): Boolean; virtual;
    procedure NewStringList(AStrings: PStringCollection);
    procedure Store(var S: TStream);
  end;

procedure RegisterValidate;

const
  RPXPictureValidator: TStreamRec = (ObjType: 80; VmtLink: Ofs(TypeOf(TPXPictureValidator)^);
    Load: @TPXPictureValidator.Load; Store: @TPXPictureValidator.Store);
  RFilterValidator: TStreamRec = (ObjType: 81; VmtLink: Ofs(TypeOf(TFilterValidator)^);
    Load: @TFilterValidator.Load; Store: @TFilterValidator.Store);
  RRangeValidator: TStreamRec = (ObjType: 82; VmtLink: Ofs(TypeOf(TRangeValidator)^);
    Load: @TRangeValidator.Load; Store: @TRangeValidator.Store);
  RStringLookupValidator: TStreamRec = (ObjType: 83; VmtLink: Ofs(TypeOf(TStringLookupValidator)^);
    Load: @TStringLookupValidator.Load; Store: @TStringLookupValidator.Store);

implementation

uses MsgBox;

{ ---- TValidator ------------------------------------------------------------------- }

constructor TValidator.Init;
begin
  inherited Init;
  Status := vsOk;
  Options := 0;
end;

constructor TValidator.Load(var S: TStream);
begin
  inherited Init;
  Status := vsOk;
  S.Read(Options, SizeOf(Options));
end;

procedure TValidator.Store(var S: TStream);
begin
  S.Write(Options, SizeOf(Options));
end;

procedure TValidator.Error;
begin
end;

function TValidator.IsValidInput(var S: String; SuppressFill: Boolean): Boolean;
begin
  IsValidInput := True;
end;

function TValidator.IsValid(const S: String): Boolean;
begin
  IsValid := True;
end;

function TValidator.Transfer(var S: String; Buffer: Pointer; Flag: TVTransfer): Word;
begin
  Transfer := 0;
end;

function TValidator.Valid(const S: String): Boolean;
begin
  Valid := False;
  if not IsValid(S) then
  begin
    Error;
    Exit;
  end;
  Valid := True;
end;

{ ---- TPXPictureValidator ----------------------------------------------------------- }

constructor TPXPictureValidator.Init(const APic: String; AutoFill: Boolean);
var
  S: String;
begin
  inherited Init;
  Pic := NewStr(APic);
  Options := voOnAppend;
  if AutoFill then
    Options := Options or voFill;
  S := '';
  if Picture(S, False) = prSyntax then
    Status := vsSyntax;
end;

constructor TPXPictureValidator.Load(var S: TStream);
begin
  inherited Load(S);
  Pic := S.ReadStr;
end;

procedure TPXPictureValidator.Store(var S: TStream);
begin
  inherited Store(S);
  S.WriteStr(Pic);
end;

destructor TPXPictureValidator.Done;
begin
  DisposeStr(Pic);
  inherited Done;
end;

procedure TPXPictureValidator.Error;
var
  P: PString;
begin
  P := Pic;
  MessageBox('Input does not conform to picture:'#13' %s', @P, mfError + mfOKButton);
end;

function TPXPictureValidator.IsValidInput(var S: String; SuppressFill: Boolean): Boolean;
var
  T: String;
begin
  T := S;
  if (Pic = nil) or (Picture(T, (Options and voFill <> 0) and not SuppressFill) <> prError) then
  begin
    S := T;
    IsValidInput := True;
  end
  else
    IsValidInput := False;
end;

function TPXPictureValidator.IsValid(const S: String): Boolean;
var
  T: String;
  R: TPicResult;
begin
  T := S;
  if Pic = nil then
    IsValid := True
  else
  begin
    R := Picture(T, False);
    IsValid := (R = prComplete) or (R = prEmpty);
  end;
end;

type
  PCont = ^TCont;
  { What is left to match after a group: picture positions [Lo, Hi), then
    Next. A star continuation (Star) repeats the element at Lo while the
    input moves on from StarSI. }
  TCont = record
    Lo, Hi: Integer;
    Star: Boolean;
    StarSI: Integer;
    Next: PCont;
  end;

function Rank(R: TPicResult): Integer;
begin
  case R of
    prComplete: Rank := 3;
    prIncomplete: Rank := 2;
  else
    Rank := 1;
  end;
end;

function TPXPictureValidator.Picture(var Input: String; AutoFill: Boolean): TPicResult;
var
  P: String;

  { Picture position after the closing bracket matching P[I]. }
  function CloseOf(I: Integer): Integer;
  var
    Depth: Integer;
  begin
    Depth := 0;
    CloseOf := 0;
    while I <= Length(P) do
    begin
      case P[I] of
        ';': Inc(I);
        '[', '{': Inc(Depth);
        ']', '}':
          begin
            Dec(Depth);
            if Depth = 0 then
            begin
              CloseOf := I + 1;
              Exit;
            end;
          end;
      end;
      Inc(I);
    end;
  end;

  { Picture position after the element at I (0 on a syntax error). }
  function SkipElem(I: Integer): Integer;
  begin
    SkipElem := 0;
    if I > Length(P) then
      Exit;
    case P[I] of
      ';':
        if I < Length(P) then
          SkipElem := I + 2;
      '*':
        begin
          Inc(I);
          while (I <= Length(P)) and (P[I] >= '0') and (P[I] <= '9') do
            Inc(I);
          SkipElem := SkipElem(I);
        end;
      '[', '{':
        SkipElem := CloseOf(I);
      ']', '}', ',':
        SkipElem := 0;
    else
      SkipElem := I + 1;
    end;
  end;

  { Checks brackets and escapes of P[Lo..Hi-1]. }
  function SyntaxOk(Lo, Hi: Integer): Boolean;
  var
    I, J: Integer;
  begin
    SyntaxOk := False;
    I := Lo;
    while I < Hi do
    begin
      if P[I] = ',' then
        J := I + 1
      else
      begin
        J := SkipElem(I);
        if (J = 0) or (J > Hi) then
          Exit;
        if (P[I] = '[') or (P[I] = '{') then
        begin
          if not SyntaxOk(I + 1, J - 1) then
            Exit;
          if (P[I] = '[') <> (P[J - 1] = ']') then
            Exit;
        end
        else if P[I] = '*' then
          if P[J - 1] in [']', '}'] then
            if not SyntaxOk(I + 1, J) then
              Exit;
      end;
      I := J;
    end;
    SyntaxOk := True;
  end;

  { Replaces *N X by N copies of X (unbounded * stays). }
  function Expand(const Src: String): String;
  var
    Save, Out, Elem, Inner: String;
    I, J, N, K: Integer;
  begin
    Save := P;
    P := Src;
    Out := '';
    I := 1;
    while I <= Length(P) do
    begin
      if P[I] = ',' then
      begin
        Out := Out + ',';
        Inc(I);
        Continue;
      end;
      J := SkipElem(I);
      if J = 0 then
      begin
        Out := Out + Copy(P, I, 255);
        Break;
      end;
      if (P[I] = '[') or (P[I] = '{') then
        Out := Out + P[I] + Expand(Copy(P, I + 1, J - I - 2)) + P[J - 1]
      else if P[I] = '*' then
      begin
        K := I + 1;
        N := 0;
        while (K < J) and (P[K] >= '0') and (P[K] <= '9') do
        begin
          N := N * 10 + Ord(P[K]) - Ord('0');
          Inc(K);
        end;
        Elem := Copy(P, K, J - K);
        Inner := Expand(Elem);
        if K = I + 1 then
          Out := Out + '*' + Inner
        else
          for N := N downto 1 do
            if Length(Out) + Length(Inner) <= 255 then
              Out := Out + Inner;
      end
      else
        Out := Out + Copy(P, I, J - I);
      I := J;
    end;
    P := Save;
    Expand := Out;
  end;

  function Alts(Lo, Hi: Integer; Cont: PCont; var S: String; SI: Integer): TPicResult; forward;

  function Seq(I, Hi: Integer; Cont: PCont; var S: String; SI: Integer): TPicResult;
  var
    J, K: Integer;
    C, L: Char;
    Lit: Boolean;
    NewCont: TCont;
    SA, SB: String;
    RA, RB: TPicResult;
  begin
    if I >= Hi then
    begin
      if Cont = nil then
      begin
        if SI > Length(S) then
          Seq := prComplete
        else
          Seq := prError;
      end
      else if Cont^.Star and (Cont^.StarSI = SI) then
        { The repeated element matched nothing: leave the loop. }
        Seq := Seq(SkipElem(Cont^.Lo), Cont^.Hi, Cont^.Next, S, SI)
      else
        Seq := Seq(Cont^.Lo, Cont^.Hi, Cont^.Next, S, SI);
      Exit;
    end;
    J := SkipElem(I);
    case P[I] of
      '[', '*':
        begin
          NewCont.Hi := Hi;
          NewCont.Next := Cont;
          if P[I] = '[' then
          begin
            NewCont.Lo := J;
            NewCont.Star := False;
            K := J - 1;
          end
          else
          begin
            NewCont.Lo := I;
            NewCont.Star := True;
            NewCont.StarSI := SI;
            K := J;
          end;
          SA := S;
          SB := S;
          if SI > Length(S) then
          begin
            { Out of input: prefer leaving the element out. }
            RA := Seq(J, Hi, Cont, SA, SI);
            RB := Alts(I + 1, K, @NewCont, SB, SI);
          end
          else
          begin
            RA := Alts(I + 1, K, @NewCont, SA, SI);
            RB := Seq(J, Hi, Cont, SB, SI);
          end;
          if Rank(RB) > Rank(RA) then
          begin
            S := SB;
            Seq := RB;
          end
          else
          begin
            S := SA;
            Seq := RA;
          end;
          Exit;
        end;
      '{':
        begin
          NewCont.Lo := J;
          NewCont.Hi := Hi;
          NewCont.Star := False;
          NewCont.Next := Cont;
          Seq := Alts(I + 1, J - 1, @NewCont, S, SI);
          Exit;
        end;
    end;
    { One character. }
    Lit := not (P[I] in ['#', '?', '&', '@', '!']);
    if P[I] = ';' then
      L := P[I + 1]
    else
      L := P[I];
    if SI > Length(S) then
    begin
      if AutoFill and Lit and (Length(S) < 255) then
      begin
        S := S + L;
        Seq := Seq(J, Hi, Cont, S, SI + 1);
      end
      else
        Seq := prIncomplete;
      Exit;
    end;
    C := S[SI];
    if Lit then
    begin
      if UpCase(C) = UpCase(L) then
        S[SI] := L
      else if AutoFill and (Length(S) < 255) then
      begin
        { Insert the literal the user skipped. }
        Insert(L, S, SI);
        Seq := Seq(J, Hi, Cont, S, SI + 1);
        Exit;
      end
      else
      begin
        Seq := prError;
        Exit;
      end;
    end
    else
      case P[I] of
        '#':
          if not (C in ['0'..'9']) then
          begin
            Seq := prError;
            Exit;
          end;
        '?', '&':
          if not (UpCase(C) in ['A'..'Z']) and (C < #128) then
          begin
            Seq := prError;
            Exit;
          end
          else if P[I] = '&' then
            S[SI] := UpCase(C);
        '!':
          S[SI] := UpCase(C);
      end;
    Seq := Seq(J, Hi, Cont, S, SI + 1);
  end;

  function Alts(Lo, Hi: Integer; Cont: PCont; var S: String; SI: Integer): TPicResult;
  var
    A, J: Integer;
    Best, R: TPicResult;
    BestS, T: String;
  begin
    Best := prError;
    BestS := S;
    A := Lo;
    J := Lo;
    while J <= Hi do
    begin
      if (J = Hi) or (P[J] = ',') then
      begin
        T := S;
        R := Seq(A, J, Cont, T, SI);
        if Rank(R) > Rank(Best) then
        begin
          Best := R;
          BestS := T;
        end;
        A := J + 1;
        Inc(J);
      end
      else
      begin
        J := SkipElem(J);
        if J = 0 then
          J := Hi + 1;
      end;
    end;
    S := BestS;
    Alts := Best;
  end;

var
  T: String;
  R: TPicResult;
begin
  if Pic = nil then
  begin
    Picture := prEmpty;
    Exit;
  end;
  P := Pic^;
  if not SyntaxOk(1, Length(P) + 1) then
  begin
    Picture := prSyntax;
    Exit;
  end;
  P := Expand(P);
  if Input = '' then
  begin
    Picture := prEmpty;
    Exit;
  end;
  T := Input;
  if Length(P) > 0 then
    R := Alts(1, Length(P) + 1, nil, T, 1)
  else if T = '' then
    R := prComplete
  else
    R := prError;
  if R <> prError then
    Input := T;
  Picture := R;
end;

{ ---- TFilterValidator -------------------------------------------------------------- }

constructor TFilterValidator.Init(AValidChars: TCharSet);
begin
  inherited Init;
  ValidChars := AValidChars;
end;

constructor TFilterValidator.Load(var S: TStream);
begin
  inherited Load(S);
  S.Read(ValidChars, SizeOf(TCharSet));
end;

procedure TFilterValidator.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(ValidChars, SizeOf(TCharSet));
end;

procedure TFilterValidator.Error;
begin
  MessageBox('Invalid character in input', nil, mfError + mfOKButton);
end;

function TFilterValidator.IsValid(const S: String): Boolean;
var
  I: Integer;
begin
  IsValid := False;
  for I := 1 to Length(S) do
    if not (S[I] in ValidChars) then
      Exit;
  IsValid := True;
end;

function TFilterValidator.IsValidInput(var S: String; SuppressFill: Boolean): Boolean;
var
  I: Integer;
begin
  IsValidInput := False;
  for I := 1 to Length(S) do
    if not (S[I] in ValidChars) then
      Exit;
  IsValidInput := True;
end;

{ ---- TRangeValidator ------------------------------------------------------------------ }

constructor TRangeValidator.Init(AMin, AMax: LongInt);
begin
  inherited Init(['0'..'9', '+', '-']);
  if AMin >= 0 then
    ValidChars := ValidChars - ['-'];
  Min := AMin;
  Max := AMax;
end;

constructor TRangeValidator.Load(var S: TStream);
begin
  inherited Load(S);
  S.Read(Min, SizeOf(Min));
  S.Read(Max, SizeOf(Max));
end;

procedure TRangeValidator.Store(var S: TStream);
begin
  inherited Store(S);
  S.Write(Min, SizeOf(Min));
  S.Write(Max, SizeOf(Max));
end;

procedure TRangeValidator.Error;
var
  Params: array[0..1] of PtrInt;
begin
  Params[0] := Min;
  Params[1] := Max;
  MessageBox('Value not in the range %d to %d', @Params, mfError + mfOKButton);
end;

function TRangeValidator.IsValid(const S: String): Boolean;
var
  Value: LongInt;
  Code: Integer;
begin
  IsValid := False;
  if inherited IsValid(S) then
  begin
    Val(S, Value, Code);
    if (Code = 0) and (Value >= Min) and (Value <= Max) then
      IsValid := True;
  end;
end;

function TRangeValidator.Transfer(var S: String; Buffer: Pointer; Flag: TVTransfer): Word;
var
  Value: LongInt;
  Code: Integer;
begin
  Transfer := 0;
  if Options and voTransfer = 0 then
    Exit;
  case Flag of
    vtGetData:
      begin
        Val(S, Value, Code);
        PLongInt(Buffer)^ := Value;
      end;
    vtSetData:
      Str(PLongInt(Buffer)^, S);
  end;
  Transfer := SizeOf(LongInt);
end;

{ ---- TLookupValidator ------------------------------------------------------------------ }

function TLookupValidator.IsValid(const S: String): Boolean;
begin
  IsValid := Lookup(S);
end;

function TLookupValidator.Lookup(const S: String): Boolean;
begin
  Lookup := True;
end;

{ ---- TStringLookupValidator --------------------------------------------------------------- }

constructor TStringLookupValidator.Init(AStrings: PStringCollection);
begin
  inherited Init;
  Strings := AStrings;
end;

constructor TStringLookupValidator.Load(var S: TStream);
begin
  inherited Load(S);
  Strings := PStringCollection(S.Get);
end;

procedure TStringLookupValidator.Store(var S: TStream);
begin
  inherited Store(S);
  S.Put(Strings);
end;

destructor TStringLookupValidator.Done;
begin
  NewStringList(nil);
  inherited Done;
end;

procedure TStringLookupValidator.Error;
begin
  MessageBox('Input not in valid-list', nil, mfError + mfOKButton);
end;

function TStringLookupValidator.Lookup(const S: String): Boolean;
var
  Index: Sw_Integer;
  T: String;
begin
  Lookup := False;
  if Strings <> nil then
  begin
    T := S;
    Lookup := Strings^.Search(@T, Index);
  end;
end;

procedure TStringLookupValidator.NewStringList(AStrings: PStringCollection);
begin
  if Strings <> nil then
    Dispose(Strings, Done);
  Strings := AStrings;
end;

procedure RegisterValidate;
begin
  RegisterType(RPXPictureValidator);
  RegisterType(RFilterValidator);
  RegisterType(RRangeValidator);
  RegisterType(RStringLookupValidator);
end;

end.
