unit SYNC_GiftOpen_Plugin;

// 「プレゼント開封」のメディアオブジェクト登録、設定と描画資源の寿命を管理する。
interface

uses AviUtl2FilterTypes;

const
  GIFTOPEN_REQUIRED_VERSION = 2011600;

procedure InitializeGiftOpen(Version: Cardinal);
function GetGiftOpenTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.Math, System.SyncObjs, PluginFilterTable, GiftOpen_Settings, GiftOpen_Renderer;

type
  TTrack = (trWidth, trHeight, trDepth, trTransparency, trBefore, trOpen,
    trEffectTime, trAmount, trRange, trPackageX, trPackageY, trPackageZ, trPackageScale,
    trEffectX, trEffectY, trEffectZ, trEffectScale);

  TGiftInstance = class
    Lock: TCriticalSection;
    Renderer: TGiftRenderer;
    constructor Create;
    destructor Destroy; override;
  end;

const
  ImageName = '画像ファイル';
  LegacyImageName = 'プレゼント画像ファイル';
  MigrateImageName = '旧画像設定を移行';
  ImageFilter = '画像ファイル (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff;*.webp)'+#0+
    '*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff;*.webp'+#0+
    'すべてのファイル (*.*)'+#0+'*.*'+#0#0;
  PackageNames: array[TGiftStyle] of PWideChar = (
    'リボン付きプレゼント箱','包装紙付きプレゼント箱','手提げ紙袋','巾着袋',
    '宝箱','四方向展開式の箱','破裂式の箱','キャンディ包み','風呂敷包み',
    'リボンによる直接包装','包装紙による直接包装','透明フィルム包装','バスケット包装',
    'クリスマスの靴下','カプセルトイ','風船','くす玉');
  EffectNames: array[TGiftEffect] of PWideChar = (
    'なし','紙吹雪','紙テープ','キラキラ','星の飛散','ハートの飛散',
    '放射状の光','包装内部からあふれる光','魔法の煙','シャボン玉','花びら','花火');

var
  Styles: array[0..Ord(High(TGiftStyle))+1] of TFILTER_ITEM_SELECT_ITEM;
  Effects: array[0..Ord(High(TGiftEffect))+1] of TFILTER_ITEM_SELECT_ITEM;
  ColorModes: array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  StyleItem, EffectItem, ColorModeItem: TFILTER_ITEM_SELECT;
  ImageItem, LegacyImageItem: TFILTER_ITEM_FILE;
  MigrateImageItem: TFILTER_ITEM_BUTTON;
  LegacyImageRule, MigrateImageRule: TFILTER_ITEM_HIDE_RULE;
  Tracks: array[TTrack] of TFILTER_ITEM_TRACK;
  Color1, Color2, EffectColor: TFILTER_ITEM_COLOR;
  TimeGroup, EffectGroup: TFILTER_ITEM_GROUP;
  TableReady, HasCameraAPI: Boolean;

constructor TGiftInstance.Create;
begin
  inherited;
  Lock := TCriticalSection.Create;
  Renderer := TGiftRenderer.Create;
end;

destructor TGiftInstance.Destroy;
begin
  Renderer.Free;
  Lock.Free;
  inherited;
end;

function CreateGift(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := Pointer(TGiftInstance.Create);
  except
    // 初期化失敗時はホストに nil を返す。
  end;
end;

procedure DestroyGift(EffectID: Int64; Data: Pointer); cdecl;
begin
  try
    TGiftInstance(Data).Free;
  except
    // Delphi 例外は DLL 境界を越えない。
  end;
end;

function RGB(const Item: TFILTER_ITEM_COLOR): Cardinal;
begin
  Result := (Cardinal(Item.R) shl 16) or (Cardinal(Item.G) shl 8) or Item.B;
end;

function Track(Kind: TTrack; Fallback: Double): Double;
begin
  Result := Bounded(Tracks[Kind].Value,Tracks[Kind].S,Tracks[Kind].E,Fallback);
end;

procedure MigrateImage(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect, Item: LPCWSTR); cdecl;
const
  EmptyValue: array[0..0] of AnsiChar = (#0);
var
  Previous, Current: UTF8String;
begin
  try
    if (Edit = nil) or (Obj = nil) or (Effect = nil) or
      not Assigned(Edit^.GetObjectItemValue) or not Assigned(Edit^.SetObjectItemValue) then Exit;
    Previous := UTF8String(Edit^.GetObjectItemValue(Obj,Effect,LegacyImageName));
    if Previous = '' then Exit;
    Current := UTF8String(Edit^.GetObjectItemValue(Obj,Effect,ImageName));
    if (Current = '') and
      not Edit^.SetObjectItemValue(Obj,Effect,ImageName,PAnsiChar(Previous)) then Exit;
    // 新しい項目を優先し、移行した後は通常どおり選択解除できるようにする。
    Edit^.SetObjectItemValue(Obj,Effect,LegacyImageName,@EmptyValue[0]);
  except
    // 編集コールバックの外へ Delphi 例外を漏らさない。
  end;
end;

function ReadSettings: TGiftSettings;
begin
  Result.Style := TGiftStyle(EnsureRange(StyleItem.Value,0,Ord(High(TGiftStyle))));
  Result.Effect := TGiftEffect(EnsureRange(EffectItem.Value,0,Ord(High(TGiftEffect))));
  if ImageItem.Value <> nil then Result.FileName := ImageItem.Value
  else Result.FileName := '';
  if (Result.FileName = '') and (LegacyImageItem.Value <> nil) then
    Result.FileName := LegacyImageItem.Value;
  Result.Width := Track(trWidth,380);
  Result.Height := Track(trHeight,280);
  Result.Depth := Track(trDepth,245);
  Result.PackageX := Track(trPackageX,0);
  Result.PackageY := Track(trPackageY,0);
  Result.PackageZ := Track(trPackageZ,0);
  Result.PackageScale := Track(trPackageScale,100)*0.01;
  Result.EffectX := Track(trEffectX,0);
  Result.EffectY := Track(trEffectY,0);
  Result.EffectZ := Track(trEffectZ,0);
  Result.EffectScale := Track(trEffectScale,100)*0.01;
  Result.Color1 := RGB(Color1);
  Result.Color2 := RGB(Color2);
  Result.Opacity := 1-Track(trTransparency,0)*0.01;
  Result.BeforeSeconds := Track(trBefore,1);
  Result.OpenSeconds := Track(trOpen,1);
  Result.EffectSeconds := Track(trEffectTime,1);
  Result.Amount := Track(trAmount,100)*0.01;
  Result.Range := Track(trRange,100)*0.01;
  Result.AutoColor := ColorModeItem.Value = 0;
  Result.EffectColor := RGB(EffectColor);
end;

function ProcGiftVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  Instance: TGiftInstance;
  S: TGiftSettings;
  Seconds: Double;
begin
  Result := 0; // 直接描画と標準画像の二重出力を防ぐ。
  try
    if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) then Exit;
    S := ReadSettings;
    Seconds := Video^.Object_^.Time;
    if IsNan(Seconds) or IsInfinite(Seconds) then Exit;
    Instance := TGiftInstance(Video^.UserData);
    Instance.Lock.Acquire;
    try
      Instance.Renderer.Draw(Video,S,Seconds,HasCameraAPI);
    finally
      Instance.Lock.Release;
    end;
  except
    // 読み込めない素材やホスト呼び出しの失敗をコールバックの外へ漏らさない。
  end;
end;

function GetGiftOpenTable: PFILTER_PLUGIN_TABLE;
var
  Style: TGiftStyle;
  Effect: TGiftEffect;
begin
  if not TableReady then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA,
      'プレゼント開封','SYNC','プレゼント開封 v1.0.0'+#13#10+
      '包装を立体で開封し、指定画像と付加演出を表示します。',
      ProcGiftVideo,nil);
    for Style := Low(TGiftStyle) to High(TGiftStyle) do
    begin
      Styles[Ord(Style)].Name := PackageNames[Style];
      Styles[Ord(Style)].Value := Ord(Style);
    end;
    for Effect := Low(TGiftEffect) to High(TGiftEffect) do
    begin
      Effects[Ord(Effect)].Name := EffectNames[Effect];
      Effects[Ord(Effect)].Value := Ord(Effect);
    end;
    ColorModes[0].Name := '自動配色';
    ColorModes[0].Value := 0;
    ColorModes[1].Name := '指定色';
    ColorModes[1].Value := 1;

    AddSelect(StyleItem,'包装スタイル',Ord(gsRibbonBox),@Styles[0]);
    AddFile(ImageItem,ImageName,'',ImageFilter);
    AddFile(LegacyImageItem,LegacyImageName,'',ImageFilter);
    AddButton(MigrateImageItem,MigrateImageName,MigrateImage);
    AddHideRule(LegacyImageRule,LegacyImageName);
    AddHideRule(MigrateImageRule,MigrateImageName,LegacyImageName);
    AddTrack(Tracks[trWidth],'包装幅',380,8,8192,1);
    AddTrack(Tracks[trHeight],'包装高さ',280,8,8192,1);
    AddTrack(Tracks[trDepth],'包装奥行き',245,8,8192,1);
    AddTrack(Tracks[trPackageX],'包装X',0,-8192,8192,0.01);
    AddTrack(Tracks[trPackageY],'包装Y',0,-8192,8192,0.01);
    AddTrack(Tracks[trPackageZ],'包装Z',0,-8192,8192,0.01);
    AddTrack(Tracks[trPackageScale],'包装拡大率',100,0,1000,0.01);
    AddColor(Color1,'色1',$43,$38,$D9);
    AddColor(Color2,'色2',$67,$C2,$F7);
    AddTrack(Tracks[trTransparency],'包装透明度',0,0,100,0.01);
    AddGroup(TimeGroup,'時間設定',1);
    AddTrack(Tracks[trBefore],'開封前時間',1,0,120,0.01);
    AddTrack(Tracks[trOpen],'開封時間',1,0,120,0.01);
    AddGroup(EffectGroup,'付加演出',1);
    AddSelect(EffectItem,'付加演出スタイル',Ord(geConfetti),@Effects[0]);
    AddTrack(Tracks[trEffectTime],'付加演出時間',1,0,120,0.01);
    AddTrack(Tracks[trAmount],'付加演出量',100,0,250,0.01);
    AddTrack(Tracks[trRange],'付加演出範囲',100,1,500,0.01);
    AddTrack(Tracks[trEffectX],'付加演出X',0,-8192,8192,0.01);
    AddTrack(Tracks[trEffectY],'付加演出Y',0,-8192,8192,0.01);
    AddTrack(Tracks[trEffectZ],'付加演出Z',0,-8192,8192,0.01);
    AddTrack(Tracks[trEffectScale],'付加演出拡大率',100,0,1000,0.01);
    AddSelect(ColorModeItem,'付加演出色モード',0,@ColorModes[0]);
    AddColor(EffectColor,'付加演出色',$63,$CC,$FF);
    Result := GetPluginTable;
    Result^.Func_Create := CreateGift;
    Result^.Func_Destroy := DestroyGift;
    TableReady := True;
  end else
    Result := GetPluginTable;
end;

procedure InitializeGiftOpen(Version: Cardinal);
begin
  HasCameraAPI := Version >= 2011700;
  GetGiftOpenTable;
end;

end.
