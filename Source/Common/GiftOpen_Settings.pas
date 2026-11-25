unit GiftOpen_Settings;

// 各スタイルの共通設定と、シーク可能な時間評価を定義する。
interface

type
  TGiftStyle = (gsRibbonBox, gsPaperBox, gsPaperBag, gsChest, gsFlapBox,
    gsBurstBox, gsCandy, gsDirectRibbon, gsDirectPaper, gsFilm, gsBasket,
    gsStocking, gsCapsule, gsKusudama);
  TGiftEffect = (geNone, geConfetti, geStreamers, geSparkles, geStars, geHearts,
    geRays, geInnerGlow, geSmoke, geBubbles, gePetals, geFireworks);

  TGiftSettings = record
    Style: TGiftStyle;
    Effect: TGiftEffect;
    FileName: string;
    Width, Height, Depth: Double;
    PackageX, PackageY, PackageZ, PackageScale: Double;
    EffectX, EffectY, EffectZ, EffectScale: Double;
    Color1, Color2, EffectColor: Cardinal; // $RRGGBB
    Opacity, BeforeSeconds, OpenSeconds, EffectSeconds: Double;
    Amount, Range: Double;
    AutoColor: Boolean;
  end;

  TGiftTime = record
    Opening: Double;       // 0 = 閉、1 = 開封完了
    EffectAge: Double;     // 開封完了からの実時間
    EffectProgress: Double;
    EffectActive: Boolean;
  end;

function Bounded(Value, Lower, Upper, Fallback: Double): Double;
function Smooth(Value: Double): Double;
function Phase(Value, StartAt, EndAt: Double): Double;
function Mix(A, B, Progress: Double): Double;
function EvaluateGiftTime(const Settings: TGiftSettings; Seconds: Double): TGiftTime;
function GiftRandom(Index, Channel: Integer): Double;

implementation

uses System.Math;

function Bounded(Value, Lower, Upper, Fallback: Double): Double;
begin
  if IsNan(Value) or IsInfinite(Value) then Exit(Fallback);
  Result := EnsureRange(Value, Lower, Upper);
end;

function Smooth(Value: Double): Double;
begin
  Value := EnsureRange(Value, 0.0, 1.0);
  Result := Value * Value * (3 - 2 * Value);
end;

function Phase(Value, StartAt, EndAt: Double): Double;
begin
  Result := Smooth((Value - StartAt) / (EndAt - StartAt));
end;

function Mix(A, B, Progress: Double): Double;
begin
  Result := A + (B - A) * Progress;
end;

function EvaluateGiftTime(const Settings: TGiftSettings; Seconds: Double): TGiftTime;
var
  CompleteAt: Double;
begin
  Result := Default(TGiftTime);
  CompleteAt := Settings.BeforeSeconds + Settings.OpenSeconds;
  if Seconds < Settings.BeforeSeconds then Exit;
  // 最終フレームの境界誤差でエフェクトの開始が1フレームずれるのを防ぐ。
  if Seconds + 1E-9 < CompleteAt then
  begin
    Result.Opening := EnsureRange((Seconds - Settings.BeforeSeconds) /
      Settings.OpenSeconds, 0.0, 1.0);
    Exit;
  end;
  Result.Opening := 1;
  Result.EffectAge := Max(0.0, Seconds - CompleteAt);
  Result.EffectActive := (Settings.Effect <> geNone) and (Settings.Amount > 0) and
    (Result.EffectAge < Settings.EffectSeconds);
  if Result.EffectActive then
    Result.EffectProgress := Result.EffectAge / Settings.EffectSeconds;
end;

function GiftRandom(Index, Channel: Integer): Double;
var
  Key: UInt64;
begin
  // 32ビットの結果だけを抽出し、Debugのオーバーフロー検査でも同じ値を返す。
  Key := (UInt64(Index + 1) * 747796405 + UInt64(Channel + 1) * 2891336453) and $FFFFFFFF;
  Key := ((Key xor (Key shr ((Key shr 28) + 4))) * 277803737) and $FFFFFFFF;
  Result := (Key xor (Key shr 22)) / 4294967296.0;
end;

end.
