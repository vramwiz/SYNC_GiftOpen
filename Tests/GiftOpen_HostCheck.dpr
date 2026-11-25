program GiftOpen_HostCheck;

{$APPTYPE CONSOLE}
{$POINTERMATH ON}

// 本番 AUF2 を読み込み、SDK コールバックを代行するコマンドライン検査。
uses
  Winapi.Windows, System.SysUtils, System.Math, System.Generics.Collections,
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas';

type
  PSelectItem = ^TFILTER_ITEM_SELECT_ITEM;
  TInit = function(Version: Cardinal): Byte; cdecl;
  TRequired = function: Cardinal; cdecl;
  TShutdown = procedure; cdecl;
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  TPoint = record X,Y,Z: Double end;
  TQuad = record
    Point: array[0..3] of TPoint;
    Color: array[0..3,0..3] of Single;
  end;

var
  Plugin: PFILTER_PLUGIN_TABLE;
  Frames: TOBJECT_INFO;
  Scene: TSCENE_INFO;
  Video: TFILTER_PROC_VIDEO;
  Edit: TEDIT_SECTION;
  Style, Effect, Mode: PFILTER_ITEM_SELECT;
  FileItem: PFILTER_ITEM_FILE;
  Alpha, Before, Opening, Duration, Amount: PFILTER_ITEM_TRACK;
  PackageX, PackageY, PackageZ, PackageScale: PFILTER_ITEM_TRACK;
  EffectX, EffectY, EffectZ, EffectScale: PFILTER_ITEM_TRACK;
  Color: PFILTER_ITEM_COLOR;
  WhiteReady, CallbackFailed, CameraOn: Boolean;
  TrackCalls, TexCount, ColorVerts, AnchorW, AnchorH, CardOrder: Integer;
  BlendMode, LightQuads: Integer;
  CameraX, CameraY: Double;
  Card: TQuad;
  Quads: TList<TQuad>;
  Digest, CardDigest: UInt64;

procedure Require(Pass: Boolean; const Detail: string);
begin
  if not Pass then raise Exception.Create(Detail);
end;

procedure Hash(P: PByte; Count: Integer);
var I: Integer;
begin
  for I := 0 to Count-1 do
    Digest := ((Digest xor P[I]) * 16777619) and $FFFFFFFF;
end;

procedure SetWhite(P: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  WhiteReady := (Width = 1) and (Height = 1) and (P <> nil) and
    (P^.R = 255) and (P^.G = 255) and (P^.B = 255) and (P^.A = 255);
end;

procedure SetAnchor(Width, Height: Integer); cdecl;
begin
  AnchorW := Width;
  AnchorH := Height;
end;

procedure SetBlend(Mode: Integer); cdecl;
begin
  BlendMode := Mode;
end;

function ImageSize(Resource: PWideChar; Width, Height: PInteger): Boolean; cdecl;
begin
  Result := SameStr(Resource,'image:C:\検査\present.png');
  if Result then
  begin
    Width^ := 640;
    Height^ := 480;
  end;
end;

function Draw(Kind: Integer; Vertices: Pointer; Count: Integer; Resource: PWideChar): Boolean; cdecl;
var
  I, J, Stride: Integer;
  C: PVertexColor;
  T: ^TVertexTexture;
  Q: TQuad;
  Saved: UInt64;
begin
  Result := False;
  try
    Require(WhiteReady,'white source was not initialized');
    Require((Count > 0) and (Count mod 4 = 0),'invalid vertex buffer');
    case Kind of
      VERTEX_QUAD_COLOR, VERTEX_QUAD_COLOR_NORM:
        begin
          if Kind = VERTEX_QUAD_COLOR then
          begin
            Require(BlendMode = BLEND_ADD,'light must use additive blending');
            Inc(LightQuads,Count div 4);
            Stride := SizeOf(TVertexColor);
          end else
          begin
            Require(BlendMode = BLEND_NONE,'normal geometry must use the host blend');
            Stride := SizeOf(TVertexColorNorm);
          end;
          Inc(ColorVerts,Count);
          Hash(Vertices,Count*Stride);
          I := 0;
          while I < Count do
          begin
            for J := 0 to 3 do
            begin
              C := PVertexColor(PByte(Vertices)+(I+J)*Stride);
              Require(not IsNan(C^.Z) and not IsInfinite(C^.Z),'invalid Z');
              Require((C^.A >= 0) and (C^.A <= 1) and (C^.R <= C^.A) and
                (C^.G <= C^.A) and (C^.B <= C^.A),'invalid premultiplied RGBA');
              Q.Point[J].X := C^.X;
              Q.Point[J].Y := C^.Y;
              Q.Point[J].Z := C^.Z;
              Q.Color[J,0] := C^.R;
              Q.Color[J,1] := C^.G;
              Q.Color[J,2] := C^.B;
              Q.Color[J,3] := C^.A;
            end;
            Quads.Add(Q);
            Inc(I,4);
          end;
        end;
      VERTEX_QUAD_TEXTURE:
        begin
          Require(BlendMode = BLEND_NONE,'image must use the host blend');
          Require(SameStr(Resource,'image:C:\検査\present.png') and (Count = 4),'texture binding');
          Inc(TexCount);
          CardOrder := Quads.Count;
          Saved := Digest;
          Digest := 2166136261;
          Hash(Vertices,Count*SizeOf(TVertexTexture));
          CardDigest := Digest;
          Digest := Saved xor CardDigest;
          for J := 0 to 3 do
          begin
            T := Pointer(PByte(Vertices)+J*SizeOf(TVertexTexture));
            Card.Point[J].X := T^.X;
            Card.Point[J].Y := T^.Y;
            Card.Point[J].Z := T^.Z;
          end;
        end;
    else
      raise Exception.Create('invalid vertex type');
    end;
    Result := True;
  except
    on E: Exception do
    begin
      CallbackFailed := True;
      Writeln(E.Message);
    end;
  end;
end;

function CameraMode: Integer; cdecl;
begin
  Result := Ord(CameraOn);
end;

function CameraObject: OBJECT_HANDLE; cdecl;
begin
  Result := Pointer(2);
end;

function FindObject(Layer, Frame: Integer): OBJECT_HANDLE; cdecl;
begin
  if CameraOn and (Layer = 0) then Result := CameraObject else Result := nil;
end;

function CameraRange(Obj: OBJECT_HANDLE): TOBJECT_LAYER_FRAME; cdecl;
begin
  Result.Layer := 0;
  Result.StartFrame := 0;
  Result.EndFrame := 10000;
end;

function CountCamera(Obj: OBJECT_HANDLE; Name: PWideChar): Integer; cdecl;
begin
  Result := Ord((Obj = CameraObject) and SameStr(Name,'カメラ制御'));
end;

function ReadCameraTrack(Obj: OBJECT_HANDLE; Name, Item: PWideChar;
  Frame: Double; Value: PDouble): Boolean; cdecl;
begin
  Inc(TrackCalls);
  Value^ := 0;
  if SameStr(Item,'X') then Value^ := CameraX;
  if SameStr(Item,'Y') then Value^ := CameraY;
  if SameStr(Item,'Z') then Value^ := -900;
  Result := Obj = CameraObject;
end;

function DrawAt(Seconds: Double): UInt64;
begin
  Frames.Time := Seconds;
  Frames.Frame := Round(60*Seconds);
  WhiteReady := False;
  CallbackFailed := False;
  TexCount := 0;
  ColorVerts := 0;
  LightQuads := 0;
  BlendMode := BLEND_NONE;
  Quads.Clear;
  AnchorW := 0;
  AnchorH := 0;
  TrackCalls := 0;
  Digest := 2166136261;
  CardDigest := 0;
  Require(Plugin^.Func_Proc_Video(@Video) = 0,'standard output was not suppressed');
  Require(WhiteReady and not CallbackFailed and (AnchorW = 380) and (AnchorH = 280),'incomplete frame');
  Require(BlendMode = BLEND_NONE,'blend mode must be restored');
  Result := Digest;
end;

function Project(const P: TPoint): TPoint;
var AxisX, AxisY, XZ, Len: Double;
begin
  Len := Sqrt(Sqr(CameraX)+Sqr(CameraY)+Sqr(900.0));
  AxisX := -CameraX/Len;
  AxisY := -CameraY/Len;
  XZ := Sqrt(Sqr(CameraX)+Sqr(900.0));
  Result.X := P.X*900/XZ-P.Z*AxisX*Len/XZ;
  Result.Y := P.Y-AxisY*(P.X*AxisX+P.Z*900/Len)/(1-Sqr(AxisY));
  Result.Z := P.X*AxisX + P.Y*AxisY + P.Z*900/Len;
end;

function SurfaceDepth(const R, A, B, C: TPoint; out Z: Double): Boolean;
var D, U, V: Double;
begin
  D := (B.Y-C.Y)*(A.X-C.X)+(C.X-B.X)*(A.Y-C.Y);
  if Abs(D) < 1E-9 then Exit(False);
  U := ((B.Y-C.Y)*(R.X-C.X)+(C.X-B.X)*(R.Y-C.Y))/D;
  V := ((C.Y-A.Y)*(R.X-C.X)+(A.X-C.X)*(R.Y-C.Y))/D;
  Result := (U >= -1E-7) and (V >= -1E-7) and (U+V <= 1.0000001);
  Z := U*A.Z+V*B.Z+(1-U-V)*C.Z;
end;

function Hit(const R, A, B, C: TPoint): Boolean;
var Z: Double;
begin
  Result := SurfaceDepth(R,A,B,C,Z) and (Z < R.Z-0.01);
end;

function Covered: Integer;
var
  List: TArray<TQuad>;
  Q: TQuad;
  R: TPoint;
  I, J, X, Y: Integer;
  A, B: Double;
begin
  List := Quads.ToArray;
  for I := 0 to High(List) do
    for J := 0 to 3 do List[I].Point[J] := Project(List[I].Point[J]);
  Result := 0;
  for X := 1 to 9 do
    for Y := 1 to 9 do
    begin
      A := X/10;
      B := Y/10;
      R.X := Card.Point[0].X+(Card.Point[3].X-Card.Point[0].X)*A+(Card.Point[1].X-Card.Point[0].X)*B;
      R.Y := Card.Point[0].Y+(Card.Point[3].Y-Card.Point[0].Y)*A+(Card.Point[1].Y-Card.Point[0].Y)*B;
      R.Z := Card.Point[0].Z+(Card.Point[3].Z-Card.Point[0].Z)*A+(Card.Point[1].Z-Card.Point[0].Z)*B;
      R := Project(R);
      for Q in List do
        if (Q.Color[0,3] = 1) and (Hit(R,Q.Point[0],Q.Point[1],Q.Point[2]) or
          Hit(R,Q.Point[0],Q.Point[2],Q.Point[3])) then
        begin
          Inc(Result);
          Break;
        end;
    end;
end;

procedure CheckTransparentOrdering;
var
  Q: TQuad;
  P, AnyDepth: TPoint;
  I, J, Front, Back: Integer;
begin
  P.X := Card.Point[0].X+(Card.Point[3].X-Card.Point[0].X)*0.76+
    (Card.Point[1].X-Card.Point[0].X)*0.46;
  P.Y := Card.Point[0].Y+(Card.Point[3].Y-Card.Point[0].Y)*0.76+
    (Card.Point[1].Y-Card.Point[0].Y)*0.46;
  P.Z := Card.Point[0].Z+(Card.Point[3].Z-Card.Point[0].Z)*0.76+
    (Card.Point[1].Z-Card.Point[0].Z)*0.46;
  P := Project(P);
  AnyDepth := P;
  AnyDepth.Z := 1000000;
  Front := 0;
  Back := 0;
  for I := 0 to Quads.Count-1 do
  begin
    Q := Quads[I];
    if Q.Color[0,3] <> 0.5 then Continue;
    for J := 0 to 3 do Q.Point[J] := Project(Q.Point[J]);
    if Hit(P,Q.Point[0],Q.Point[1],Q.Point[2]) or
      Hit(P,Q.Point[0],Q.Point[2],Q.Point[3]) then
    begin
      Require(I >= CardOrder,'translucent front must be drawn after texture');
      Inc(Front);
    end else if Hit(AnyDepth,Q.Point[0],Q.Point[1],Q.Point[2]) or
      Hit(AnyDepth,Q.Point[0],Q.Point[2],Q.Point[3]) then
    begin
      Require(I < CardOrder,'translucent back must be drawn before texture');
      Inc(Back);
    end;
  end;
  Require((Front > 0) and (Back > 0),'translucent front and back geometry');
end;

function IsGold(const Q: TQuad): Boolean;
begin
  Result := Q.Color[0,1] > Q.Color[0,0]*0.6;
end;

procedure CheckPrintedPaper;
var
  List: TArray<TQuad>;
  Pattern, Q: TQuad;
  P: TPoint;
  I, J, Visible: Integer;
  Z, Nearest: Double;
  LastGold, NearestGold: Boolean;
begin
  List := Quads.ToArray;
  for I := 0 to High(List) do
    for J := 0 to 3 do List[I].Point[J] := Project(List[I].Point[J]);
  Visible := 0;
  for Pattern in List do
  begin
    if not IsGold(Pattern) then Continue;
    // ひし形の内側を調べ、実際に手前にある色と送出順で最後に描く色が一致するか比較する。
    for J := 0 to 3 do
    begin
      P.X := (Pattern.Point[J].X*2+Pattern.Point[(J+1) mod 4].X+
        Pattern.Point[(J+2) mod 4].X)*0.25;
      P.Y := (Pattern.Point[J].Y*2+Pattern.Point[(J+1) mod 4].Y+
        Pattern.Point[(J+2) mod 4].Y)*0.25;
      Nearest := Infinity;
      LastGold := False;
      NearestGold := False;
      for Q in List do
        if SurfaceDepth(P,Q.Point[0],Q.Point[1],Q.Point[2],Z) or
          SurfaceDepth(P,Q.Point[0],Q.Point[2],Q.Point[3],Z) then
        begin
          LastGold := IsGold(Q);
          if Z < Nearest then
          begin
            Nearest := Z;
            NearestGold := LastGold;
          end;
        end;
      Require(LastGold = NearestGold,'printed paper pattern is drawn at the wrong depth');
      if NearestGold then Inc(Visible);
    end;
  end;
  Require(Visible >= 64,'printed paper pattern coverage');
end;

procedure SavePreview(const Name: string);
var F: file; N: Integer;
begin
  AssignFile(F,Name);
  Rewrite(F,1);
  try
    N := Quads.Count;
    BlockWrite(F,N,SizeOf(N));
    for var Q in Quads do BlockWrite(F,Q,SizeOf(Q));
    BlockWrite(F,Card,SizeOf(Card));
  finally
    CloseFile(F);
  end;
end;

function FindItem(const Name: string): Pointer;
var I: Integer; P: PPointer;
begin
  I := 0;
  while Plugin^.Items[I] <> nil do
  begin
    P := Plugin^.Items[I];
    if SameStr(PWideChar(P[1]),Name) then Exit(P);
    Inc(I);
  end;
  Result := nil;
end;

function Item(const Name: string): Pointer;
begin
  Result := FindItem(Name);
  Require(Result <> nil,'missing setting '+Name);
end;

procedure ColorBounds(out Low, High: TPoint);
var
  Q: TQuad;
  P: TPoint;
begin
  Require(Quads.Count > 0,'colored geometry for bounds');
  Low := Quads[0].Point[0];
  High := Low;
  for Q in Quads do
    for P in Q.Point do
    begin
      Low.X := Min(Low.X,P.X);
      Low.Y := Min(Low.Y,P.Y);
      Low.Z := Min(Low.Z,P.Z);
      High.X := Max(High.X,P.X);
      High.Y := Max(High.Y,P.Y);
      High.Z := Max(High.Z,P.Z);
    end;
end;

function MatchesTransform(const Before, After: TPoint; X, Y, Z, Scale: Double): Boolean;
begin
  Result := SameValue(After.X,Before.X*Scale+X,0.001) and
    SameValue(After.Y,Before.Y*Scale+Y,0.001) and
    SameValue(After.Z,Before.Z*Scale+Z,0.001);
end;

procedure CheckPackageTransform(Seconds: Double);
var
  BeforeLow, BeforeHigh, AfterLow, AfterHigh: TPoint;
  ImageDigest, Initial: UInt64;
begin
  Initial := DrawAt(Seconds);
  ImageDigest := CardDigest;
  ColorBounds(BeforeLow,BeforeHigh);
  PackageX^.Value := 53.25;
  PackageY^.Value := -28.5;
  PackageZ^.Value := 104.75;
  PackageScale^.Value := 135.5;
  DrawAt(Seconds);
  Require((TexCount = 1) and (CardDigest = ImageDigest),'image is independent of package transform');
  ColorBounds(AfterLow,AfterHigh);
  Require(MatchesTransform(BeforeLow,AfterLow,53.25,-28.5,104.75,1.355) and
    MatchesTransform(BeforeHigh,AfterHigh,53.25,-28.5,104.75,1.355),
    'package uses local X, Y, Z and uniform scale');
  PackageScale^.Value := 0;
  DrawAt(Seconds);
  Require((ColorVerts = 0) and (TexCount = 1) and (CardDigest = ImageDigest),'zero scale hides package only');
  PackageX^.Value := 0;
  PackageY^.Value := 0;
  PackageZ^.Value := 0;
  PackageScale^.Value := 100;
  Require(DrawAt(Seconds) = Initial,'restoring local transform restores the frame');
end;

procedure CheckEffectTransform(Seconds: Double; Initial, WithoutEffect: UInt64;
  const PackageFaces: TArray<TQuad>);
var
  BeforeLow, BeforeHigh, AfterLow, AfterHigh: TPoint;
  ImageDigest: UInt64;
  EffectFaces, I: Integer;
  Face: TQuad;
begin
  ImageDigest := CardDigest;
  PackageScale^.Value := 0;
  DrawAt(Seconds);
  ColorBounds(BeforeLow,BeforeHigh);
  EffectFaces := Quads.Count;
  EffectX^.Value := -37.25;
  EffectY^.Value := 65.5;
  EffectZ^.Value := 4096.25;
  EffectScale^.Value := 63.5;
  DrawAt(Seconds);
  ColorBounds(AfterLow,AfterHigh);
  Require(MatchesTransform(BeforeLow,AfterLow,-37.25,65.5,4096.25,0.635) and
    MatchesTransform(BeforeHigh,AfterHigh,-37.25,65.5,4096.25,0.635),
    'effect uses local X, Y, Z and uniform scale');
  Require((TexCount = 1) and (CardDigest = ImageDigest) and
    (CardOrder = EffectFaces),'effect Z controls blend order against unchanged image');

  PackageScale^.Value := 100;
  DrawAt(Seconds);
  Require(Quads.Count = EffectFaces+Length(PackageFaces),'effect and package face count');
  // Zを奥へ大きく動かした演出の後ろに、元の順序で包装面が並ぶ。
  for I := 0 to High(PackageFaces) do
  begin
    Face := Quads[EffectFaces+I];
    Require(CompareMem(@Face,@PackageFaces[I],SizeOf(TQuad)),'effect transform leaves package unchanged');
  end;
  Require(CardDigest = ImageDigest,'image vertices stay fixed with both effect and packaging');
  EffectScale^.Value := 0;
  Require(DrawAt(Seconds) = WithoutEffect,'zero scale hides effect only');
  EffectX^.Value := 0;
  EffectY^.Value := 0;
  EffectZ^.Value := 0;
  EffectScale^.Value := 100;
  Require(DrawAt(Seconds) = Initial,'restoring effect transform restores the frame');
end;

function PeakAlpha: Single;
var
  Face: TQuad;
  J: Integer;
begin
  Result := 0;
  for Face in Quads do
    for J := 0 to 3 do
      Result := Max(Result,Face.Color[J,3]);
end;

function GeometrySpan: Double;
var
  Lo, Hi: TPoint;
begin
  ColorBounds(Lo,Hi);
  Result := Sqrt(Sqr(Hi.X-Lo.X)+Sqr(Hi.Y-Lo.Y)+Sqr(Hi.Z-Lo.Z));
end;

procedure CheckLightBehindImage;
var
  Q: TQuad;
  Center: TPoint;
  FaceIndex, I, Overlap: Integer;
  Z: Double;
begin
  Require((LightQuads > 0) and (CardOrder = LightQuads),'unlit glow must be drawn before the image');
  Center.X := (Card.Point[0].X+Card.Point[2].X)*0.5;
  Center.Y := (Card.Point[0].Y+Card.Point[2].Y)*0.5;
  Center.Z := (Card.Point[0].Z+Card.Point[2].Z)*0.5;
  Center := Project(Center);
  Overlap := 0;
  for FaceIndex := 0 to Quads.Count-1 do
  begin
    Q := Quads[FaceIndex];
    for I := 0 to 3 do Q.Point[I] := Project(Q.Point[I]);
    if SurfaceDepth(Center,Q.Point[0],Q.Point[1],Q.Point[2],Z) or
      SurfaceDepth(Center,Q.Point[0],Q.Point[2],Q.Point[3],Z) then
    begin
      Require(Z > Center.Z,'light must stay behind the image in camera depth');
      Inc(Overlap);
    end;
  end;
  Require(Overlap > 0,'light must overlap the image center');
end;

procedure CheckEffectAppearance;
var
  InitialSpan: Double;
  I: Integer;
begin
  PackageScale^.Value := 0;
  Effect^.Value := 2;
  Amount^.Value := 5;
  DrawAt(2.06);
  InitialSpan := GeometrySpan;
  DrawAt(2.35);
  Require((GeometrySpan > 2.5*InitialSpan) and (PeakAlpha > 0.9),
    'streamer length grows along its flight');
  DrawAt(2.95);
  Require((PeakAlpha > 0) and (PeakAlpha < 0.15),'streamer fades out near the end');
  Amount^.Value := 100;
  for I := 6 to 7 do
  begin
    Effect^.Value := I;
    DrawAt(2.45);
    Require(PeakAlpha > 0.4,'glow must have a visible core');
    CheckLightBehindImage;
    CameraOn := True;
    CameraX := 650;
    CameraY := -380;
    DrawAt(2.45);
    CheckLightBehindImage;
    CameraOn := False;
    CameraX := 0;
    CameraY := 0;
  end;
  Effect^.Value := 11;
  DrawAt(2.82);
  Require((LightQuads > 100) and (PeakAlpha > 0.45),'fireworks should remain bright late in the effect');
  DrawAt(2.98);
  Require((PeakAlpha > 0) and (PeakAlpha < 0.12),'fireworks fade before the end');
  PackageScale^.Value := 100;
end;

procedure Test(Init: TInit);
const
  PackageNames: array[0..13] of string = (
    'リボン付きプレゼント箱','包装紙付きプレゼント箱','手提げ紙袋',
    '宝箱','四方向展開式の箱','破裂式の箱','キャンディ包み',
    'リボンによる直接包装','包装紙による直接包装','透明フィルム包装','バスケット包装',
    'クリスマスの靴下','カプセルトイ','くす玉');
  EffectNames: array[0..11] of string = (
    'なし','紙吹雪','紙テープ','キラキラ','星','ハート','放射光','光の噴出','煙','シャボン玉','花びら','花火');
var
  I, J, Closed, Opened, More, BaseVerts, CoverageIssues: Integer;
  D, D0, StaticCard: UInt64;
  PackageFaces: TArray<TQuad>;
  SelectItem: PSelectItem;
begin
  Style := Item('包装スタイル');
  Effect := Item('演出スタイル');
  FileItem := Item('画像ファイル');
  PackageX := Item('包装X');
  PackageY := Item('包装Y');
  PackageZ := Item('包装Z');
  PackageScale := Item('包装拡大率');
  EffectX := Item('演出X');
  EffectY := Item('演出Y');
  EffectZ := Item('演出Z');
  EffectScale := Item('演出拡大率');
  Alpha := Item('包装透明度');
  Before := Item('開封前時間');
  Opening := Item('開封時間');
  Duration := Item('演出時間');
  Amount := Item('演出量');
  Mode := Item('演出色モード');
  Color := Item('演出色');
  Require((Style^.Value = 0) and (Effect^.Value = 1) and (Alpha^.Value = 0),'style defaults');
  Require((PackageX^.Value = 0) and (PackageY^.Value = 0) and (PackageZ^.Value = 0) and
    (PackageScale^.Value = 100),'package transform defaults');
  Require((EffectX^.Value = 0) and (EffectY^.Value = 0) and (EffectZ^.Value = 0) and
    (EffectScale^.Value = 100),'effect transform defaults');
  Require((Before^.Value = 1) and (Opening^.Value = 1) and (Duration^.Value = 1) and
    (Before^.Step = 0.01) and (Opening^.Step = 0.01) and (Duration^.Step = 0.01),'time defaults');
  Require(not Assigned(Plugin^.Func_Proc_Audio),'unexpected audio callback');
  Require(Plugin^.Flag = (FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA),'registration flags');
  SelectItem := PSelectItem(Style^.List);
  for I := Low(PackageNames) to High(PackageNames) do
  begin
    Require(SameStr(SelectItem^.Name,PackageNames[I]) and (SelectItem^.Value = I),'package list entry');
    Inc(SelectItem);
  end;
  Require(SelectItem^.Name = nil,'package list terminator');
  SelectItem := PSelectItem(Effect^.List);
  for I := Low(EffectNames) to High(EffectNames) do
  begin
    Require(SameStr(SelectItem^.Name,EffectNames[I]) and (SelectItem^.Value = I),'effect list entry');
    Inc(SelectItem);
  end;
  Require(SelectItem^.Name = nil,'effect list terminator');
  Item('演出');
  Item('演出範囲');
  Require(FindItem('付加演出スタイル') = nil,'old effect label is still registered');
  FileItem^.Value := '';
  DrawAt(0.5);
  Require((TexCount = 0) and (ColorVerts > 0),'initial scene without a file');
  FileItem^.Value := 'missing.png';
  DrawAt(1.45);
  Require((TexCount = 0) and (ColorVerts > 0),'missing image preserves opening');
  FileItem^.Value := 'C:\検査\present.png';
  Effect^.Value := 0;
  CoverageIssues := 0;
  for I := Low(PackageNames) to High(PackageNames) do
  begin
    Style^.Value := I;
    CameraX := 0;
    CameraY := 0;
    CameraOn := False;
    D0 := DrawAt(0);
    D := DrawAt(0.999);
    Require((D0 = D) and (TexCount = 1) and (ColorVerts > 0),Format('closed package %d',[I]));
    StaticCard := CardDigest;
    Closed := Covered;
    if I = 1 then CheckPrintedPaper;
    SavePreview(Format('Win64\Verification\Style%.2d_Closed.bin',[I]));
    D := DrawAt(1.6);
    Require((D <> D0) and (TexCount = 1) and (CardDigest = StaticCard),Format('opening package %d',[I]));
    if I = 1 then CheckPrintedPaper;
    CheckPackageTransform(1.6);
    D := DrawAt(2);
    Require((D <> D0) and (ColorVerts > 0) and (CardDigest = StaticCard),Format('open package %d',[I]));
    Opened := Covered;
    SavePreview(Format('Win64\Verification\Style%.2d_Open.bin',[I]));
    Require(D = DrawAt(22),Format('finished pose %d',[I]));
    Require(D0 = DrawAt(0.3),Format('reverse seek %d',[I]));
    Alpha^.Value := 50;
    DrawAt(0.5);
    Require((TexCount = 1) and (ColorVerts > 0),Format('transparent package %d',[I]));
    if I = 1 then CheckPrintedPaper;
    if I = 0 then
    begin
      CheckTransparentOrdering;
      PackageZ^.Value := 600;
      DrawAt(0.5);
      Require(CardOrder = Quads.Count,'moving back in Z draws the package before the image');
      PackageZ^.Value := -600;
      DrawAt(0.5);
      Require(CardOrder = 0,'moving forward in Z draws the package after the image');
      PackageZ^.Value := 0;
    end;
    Alpha^.Value := 100;
    DrawAt(0.5);
    Require(TexCount = 1,Format('hidden package body %d',[I]));
    Alpha^.Value := 0;
    CameraOn := True;
    CameraX := 650;
    CameraY := -380;
    DrawAt(0.5);
    Require(TrackCalls = 6,'2.1.16 camera tracks');
    More := Covered;
    DrawAt(2.0);
    J := Covered;
    Writeln(Format('%2d coverage closed=%2d/%2d opened=%2d/%2d',[I,Closed,More,Opened,J]));
    if PackageNames[I] = 'バスケット包装' then
      Require(More < 81,'basket opening exposes the gift from above')
    else if (Closed < 81) or (More < 81) then Inc(CoverageIssues);
    if (Opened > 0) or (J > 0) then Inc(CoverageIssues);
  end;
  Require(CoverageIssues = 0,'closed/open coverage');
  Require((FindItem('プレゼント画像ファイル') = nil) and (FindItem('旧画像設定を移行') = nil),
    'obsolete image settings are still registered');
  CameraOn := False;
  CameraX := 0;
  CameraY := 0;
  Style^.Value := 0;
  Effect^.Value := 0;
  D0 := DrawAt(2.47);
  BaseVerts := ColorVerts;
  PackageFaces := Quads.ToArray;
  for I := 1 to 11 do
  begin
    Effect^.Value := I;
    D := DrawAt(2.47);
    Require((D <> D0) and (ColorVerts > BaseVerts),Format('effect %d',[I]));
    CheckEffectTransform(2.47,D,D0,PackageFaces);
    DrawAt(0.13);
    Require(D = DrawAt(2.47),Format('effect seek %d',[I]));
    Require(D0 = DrawAt(3.00),Format('effect end %d',[I]));
  end;
  CheckEffectAppearance;
  Effect^.Value := 1;
  D := DrawAt(2.17);
  Mode^.Value := 1;
  Color^.R := 3;
  Color^.G := 55;
  Color^.B := 220;
  Require(D <> DrawAt(2.17),'manual color');
  Before^.Value := 0;
  Opening^.Value := 0;
  Require(ColorVerts > 0,'precondition');
  DrawAt(0);
  Require(ColorVerts > BaseVerts,'zero duration opens immediately');
  Duration^.Value := 0;
  Require(D0 = DrawAt(0),'zero duration bypasses effect');
  Require(Init(2011700) = 1,'2.1.17 accepted');
  CameraOn := True;
  DrawAt(0);
  Require(TrackCalls = 6,'2.1.17 camera API');
  Writeln(Format('PASS: registration, %d styles, 11 effects, seek, texture, alpha, timing and camera ABI. Coverage issues: %d',
    [Length(PackageNames),CoverageIssues]));
  Writeln('PASS: basket is open at the top before opening.');
  Writeln('PASS: package-only transform, transparent Z order and printed paper draw order.');
  Writeln('PASS: one image file setting.');
  Writeln('PASS: independent effect transform and depth order for all 11 effects.');
  Writeln('PASS: streamer growth, light behind the image, and sustained additive fireworks.');
end;

var
  LibHandle: HMODULE;
  Init: TInit;
  Required: TRequired;
  Shutdown: TShutdown;
  Table: TGetTable;
begin
  try
    LibHandle := LoadLibrary(PChar(ParamStr(1)));
    Require(LibHandle <> 0,'load AUF2');
    try
      Init := GetProcAddress(LibHandle,'InitializePlugin');
      Required := GetProcAddress(LibHandle,'RequiredVersion');
      Shutdown := GetProcAddress(LibHandle,'UninitializePlugin');
      Table := GetProcAddress(LibHandle,'GetFilterPluginTable');
      Require(Assigned(Init) and Assigned(Required) and Assigned(Shutdown) and Assigned(Table),'exports');
      Require((Required() = 2011600) and (Init(2011500) = 0) and (Init(2011600) = 1),'version gate');
      Plugin := Table();
      Require((Plugin <> nil) and SameStr(Plugin^.Name,'プレゼント開封') and
        SameStr(Plugin^.Label_,'SYNC'),'plugin name and group');
      Quads := TList<TQuad>.Create;
      try
        Frames.Layer := 1;
        Scene.Rate := 60;
        Scene.Scale := 1;
        Video.Scene := @Scene;
        Video.Object_ := @Frames;
        Video.Edit := @Edit;
        Video.UserData := Plugin^.Func_Create(1);
        Require(Video.UserData <> nil,'instance creation');
        try
          Video.DrawPoly := Draw;
          Video.SetImageData := SetWhite;
          Video.SetDefaultAnchor := SetAnchor;
          Video.SetBlendMode := SetBlend;
          Video.GetImageResourceSize := ImageSize;
          Video.GetCameraMode := CameraMode;
          Video.GetCameraControlObject := CameraObject;
          Edit.GetObjectTrackValue := ReadCameraTrack;
          Edit.FindObject := FindObject;
          Edit.GetObjectLayerFrame := CameraRange;
          Edit.CountObjectEffect := CountCamera;
          Test(Init);
        finally
          Plugin^.Func_Destroy(1,Video.UserData);
        end;
      finally
        Quads.Free;
      end;
      Shutdown;
    finally
      FreeLibrary(LibHandle);
    end;
  except
    on E: Exception do
    begin
      Writeln('FAIL: ',E.Message);
      Halt(1);
    end;
  end;
end.
