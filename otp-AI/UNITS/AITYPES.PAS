unit AITypes;
{ OTP-AI 2.0 - tipe bersama. Indeks data dimulai dari 1. }
interface
const
  MaxSamples = 200;
  MaxFeatures = 8;
  MaxClasses = 10;
  MaxClusters = 8;
  MaxMatrix = 16;
  MaxCategories = 16;
  AIInputLimit = 1.0E12;
  AIEpsilon = 1.0E-10;
  TargetNone = 0;
  TargetReal = 1;
  TargetClass = 2;
  ScaleMinMax = 1;
  ScaleStandard = 2;
  ErrNone = 0;
  ErrSize = 1;
  ErrValue = 2;
  ErrMissing = 3;
  ErrIO = 4;
  ErrFormat = 5;
  ErrModel = 6;
  ErrSingular = 7;
  ErrMemory = 8;
  ErrGraphics = 9;
type
  TFloat = Real;
  TErrorText = string[127];
  TFileName = string[127];
  TName = string[31];
  TVector = array[1..MaxFeatures] of TFloat;
  TSeries = array[1..MaxSamples] of TFloat;
  TLabels = array[1..MaxSamples] of Integer;
  TIndexList = array[1..MaxSamples] of Integer;
  TFeatureNames = array[1..MaxFeatures] of TName;
  TDataSet = record
    Count, Features, TargetKind: Integer;
    X: array[1..MaxSamples] of TVector;
    Y: TSeries;
    Labels: TLabels;
    Missing: array[1..MaxSamples,1..MaxFeatures] of Boolean;
    Names: TFeatureNames;
    TargetName: TName;
  end;
  PDataSet = ^TDataSet;
  TMatrix = record
    Rows, Cols: Integer;
    V: array[1..MaxMatrix,1..MaxMatrix] of TFloat;
  end;
  TScaler = record
    Fitted: Boolean;
    Features, Kind: Integer;
    Offset, Divisor: TVector;
  end;
  TImputer = record
    Fitted: Boolean;
    Features: Integer;
    Means: TVector;
  end;
  TCategoryMap = record
    Count: Integer;
    Names: array[1..MaxCategories] of TName;
  end;
  TLinearModel = record
    Fitted: Boolean;
    Features: Integer;
    Intercept: TFloat;
    Coeff: TVector;
  end;
  TKNNModel = record
    Fitted: Boolean;
    K, TargetKind, Features, Count: Integer;
    { Data tetap dimiliki pemanggil, bukan salinan. }
    Data: PDataSet;
  end;
  TKMeansModel = record
    Fitted, Converged: Boolean;
    K, Features, Iterations: Integer;
    Centers: array[1..MaxClusters] of TVector;
    Inertia: TFloat;
  end;
  TRegMetrics = record
    MAE, MSE, RMSE, R2: TFloat;
    R2Defined: Boolean;
  end;
  TConfusion = record
    Classes, Total: Integer;
    Cells: array[0..MaxClasses-1,0..MaxClasses-1] of Integer;
  end;
  TClassMetrics = record
    Accuracy, MacroPrecision, MacroRecall, MacroF1: TFloat;
    Precision, Recall, F1: array[0..MaxClasses-1] of TFloat;
    Support: array[0..MaxClasses-1] of Integer;
  end;
var
  AIErrorCode: Integer;
  AIError: TErrorText;
procedure ClearAIError;
procedure SetAIError(Code: Integer; Msg: TErrorText);
function ValidNumber(X: TFloat): Boolean;
procedure InitData(var D: TDataSet; Features, TargetKind: Integer);
function NewData(var D: PDataSet): Boolean;
procedure FreeData(var D: PDataSet);
function CheckData(var D: TDataSet; AllowMissing: Boolean): Boolean;
function CheckVector(var V: TVector; N: Integer): Boolean;
implementation
procedure ClearAIError;
begin AIErrorCode := ErrNone; AIError := '' end;
procedure SetAIError(Code: Integer; Msg: TErrorText);
begin AIErrorCode := Code; AIError := Msg end;
function ValidNumber(X: TFloat): Boolean;
begin ValidNumber := (X = X) and (Abs(X) <= AIInputLimit) end;
procedure InitData(var D: TDataSet; Features, TargetKind: Integer);
var J: Integer; S: string[8];
begin
  FillChar(D, SizeOf(D), 0);
  D.Features := Features; D.TargetKind := TargetKind;
  for J := 1 to MaxFeatures do begin
    Str(J, S); D.Names[J] := 'X' + S
  end;
  D.TargetName := 'TARGET'
end;
function NewData(var D: PDataSet): Boolean;
{$IFDEF FPC}
var OldNil: Boolean;
{$ENDIF}
begin
  ClearAIError; D := nil; NewData := False;
  {$IFNDEF FPC}
    {$IFNDEF ODIN}
  if MaxAvail < SizeOf(TDataSet) then begin
    SetAIError(ErrMemory, 'Heap tidak cukup untuk dataset'); Exit
  end;
    {$ENDIF}
  {$ENDIF}
  {$IFDEF FPC}
  OldNil := ReturnNilIfGrowHeapFails; ReturnNilIfGrowHeapFails := True;
  {$ENDIF}
  New(D);
  {$IFDEF FPC}
  ReturnNilIfGrowHeapFails := OldNil;
  {$ENDIF}
  if D = nil then begin
    SetAIError(ErrMemory, 'Alokasi dataset gagal'); Exit
  end;
  InitData(D^, 0, TargetNone); NewData := True
end;
procedure FreeData(var D: PDataSet);
begin if D <> nil then begin Dispose(D); D := nil end end;
function CheckData(var D: TDataSet; AllowMissing: Boolean): Boolean;
var I,J: Integer;
begin
  ClearAIError; CheckData := False;
  if (D.Count < 1) or (D.Count > MaxSamples) or
     (D.Features < 1) or (D.Features > MaxFeatures) then begin
    SetAIError(ErrSize, 'Ukuran dataset tidak valid'); Exit
  end;
  if (D.TargetKind < TargetNone) or (D.TargetKind > TargetClass) then begin
    SetAIError(ErrValue, 'Jenis target tidak valid'); Exit
  end;
  for I := 1 to D.Count do begin
    for J := 1 to D.Features do begin
      if D.Missing[I,J] then begin
        if not AllowMissing then begin
          SetAIError(ErrMissing, 'Fitur kosong, lakukan imputasi'); Exit
        end
      end else if not ValidNumber(D.X[I,J]) then begin
        SetAIError(ErrValue, 'Fitur melampaui batas angka'); Exit
      end
    end;
    if D.TargetKind = TargetReal then
      if not ValidNumber(D.Y[I]) then begin
        SetAIError(ErrValue, 'Target numerik tidak valid'); Exit
      end;
    if D.TargetKind = TargetClass then
      if (D.Labels[I] < 0) or (D.Labels[I] >= MaxClasses) then begin
        SetAIError(ErrValue, 'Label harus 0 sampai 9'); Exit
      end
  end;
  CheckData := True
end;
function CheckVector(var V: TVector; N: Integer): Boolean;
var J: Integer;
begin
  ClearAIError; CheckVector := False;
  if (N < 1) or (N > MaxFeatures) then begin
    SetAIError(ErrSize, 'Panjang vektor tidak valid'); Exit
  end;
  for J := 1 to N do if not ValidNumber(V[J]) then begin
    SetAIError(ErrValue, 'Nilai vektor tidak valid'); Exit
  end;
  CheckVector := True
end;
begin ClearAIError end.
