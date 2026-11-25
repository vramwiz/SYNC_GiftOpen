unit GiftOpen_Renderer;

// 立体モデルを組み立て、AviUtl2 の Direct3D フレームバッファへ送る。
// ホストの画像・カメラ・編集データは現在のコールバックの間だけ参照する。
interface

uses AviUtl2FilterTypes, GiftOpen_Mesh, GiftOpen_Settings, GiftOpen_Packages,
  System.Generics.Defaults;

type
  TDrawPart = (dpImage, dpPackage, dpEffect);
  TDrawPass = (dpassOpaque, dpassBackLight, dpassSorted);
  TDrawOrder = record
    Face: Integer;
    Depth: Double;
    Pass: TDrawPass;
    Finish, PaperOrder: Byte;
    Part: TDrawPart;
    Textured, Emissive: Boolean;
  end;

  TGiftRenderer = class
  private
    FMesh: TGiftMesh;
    FPackage: TGiftSettings;
    FPackageProgress: Double;
    FPackageCount: Integer;
    FPaperFaces: TPaperFaceStarts;
    FHasPackage: Boolean;
    FCompare: IComparer<TDrawOrder>;
    FOrder: TArray<TDrawOrder>;
    FColor: TArray<TVertexColorNorm>;
    FLight: TArray<TVertexColor>;
    FTexture: TArray<TVertexTexture>;
    procedure BuildPackage(const S: TGiftSettings; Opening: Double);
    procedure AddImage(Video: PFILTER_PROC_VIDEO; const S: TGiftSettings;
      out Resource: string);
    procedure DrawFaces(Video: PFILTER_PROC_VIDEO; const Resource: string;
      const Axis: TVec; const S: TGiftSettings; EffectStart: Integer; UseOpaquePass: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
    // 幾何とバッファの再利用を行う。エフェクトごとに呼び出しを直列化すること。
    procedure Draw(Video: PFILTER_PROC_VIDEO; const S: TGiftSettings;
      Seconds: Double; HasCameraAPI: Boolean);
  end;

implementation

uses
  System.Math, System.SysUtils, System.Generics.Collections, GiftOpen_Wraps, GiftOpen_Effects;

type
  TDrawTransform = record
    Offset: TVec;
    Scale: Double;
    Active: Boolean;
  end;

  TPaperPlane = record
    Normal, Point: TVec;
  end;
  TPaperPlanes = array[Low(TPaperFaceStarts)..High(TPaperFaceStarts)] of TPaperPlane;

const
  WhitePixel: TPIXEL_RGBA = (R:255; G:255; B:255; A:255);
  Shine: array[0..3] of Single = (0.04,0.29,0.78,0.0);
  CameraEffect = 'カメラ制御';
  UV: array[0..3,0..1] of Single = ((0,0),(0,1),(1,1),(1,0));

function ModelToHost(const P: TVec): TVec;
begin
  // 造形に固定の傾きを持たせる。配置、カメラ、回転は以降すべてホストで処理する。
  Result := V(P.X*0.963770896+P.Y*0.050372765+P.Z*0.261899799,
    P.Y*0.982004235-P.Z*0.188858895,
    -P.X*0.266731437+P.Y*0.182016730+P.Z*0.946427119);
end;

function DrawTransform(const Offset: TVec; Scale: Double): TDrawTransform;
begin
  Result.Offset := Offset;
  Result.Scale := Scale;
  Result.Active := (Scale <> 1) or (Offset.X <> 0) or (Offset.Y <> 0) or (Offset.Z <> 0);
end;

function BuildPaperPlanes(Mesh: TGiftMesh; const PaperFaces: TPaperFaceStarts;
  const Axis: TVec; const Transform: TDrawTransform; out Planes: TPaperPlanes): Integer;
var
  FirstFace: Integer;
  Face: TFace;
  N: TVec;
  Facing: Double;
begin
  Result := 0;
  for FirstFace in PaperFaces do
  begin
    Face := Mesh.Faces[FirstFace];
    N := UnitVector(Cross(ModelToHost(Face.P[1]-Face.P[0]),ModelToHost(Face.P[2]-Face.P[0])));
    Facing := Dot(N,Axis);
    if Abs(Facing) < 1E-7 then Continue;
    if Facing < 0 then N := N*(-1);
    Planes[Result].Normal := N;
    Planes[Result].Point := ModelToHost(Face.P[0])*Transform.Scale+Transform.Offset;
    Inc(Result);
  end;
end;

function PaperOrder(const Center: TVec; const Planes: TPaperPlanes; Count: Integer): Byte;
var
  I: Integer;
  Distance: Double;
begin
  Result := 0;
  for I := 0 to Count-1 do
  begin
    Distance := Dot(Center-Planes[I].Point,Planes[I].Normal);
    // 各面で区切った領域を、奥・面上・手前の順に並べる。
    Result := Result*3;
    if Distance < -1E-7 then Inc(Result,2)
    else if Distance <= 1E-7 then Inc(Result);
  end;
end;

function FindLegacyCamera(Video: PFILTER_PROC_VIDEO; Frame: Integer): OBJECT_HANDLE;
var
  Edit: PEDIT_SECTION;
  Layer, TargetCount: Integer;
  Candidate: OBJECT_HANDLE;
  Span: TOBJECT_LAYER_FRAME;
  Raw: PAnsiChar;
begin
  Result := nil;
  Edit := Video^.Edit;
  if (Edit = nil) or not Assigned(Edit^.FindObject) or
    not Assigned(Edit^.GetObjectLayerFrame) or not Assigned(Edit^.CountObjectEffect) then Exit;
  if (Video^.Object_^.Handle <> nil) and Assigned(Edit^.GetObjectFlag) and
    not Edit^.GetObjectFlag(Video^.Object_^.Handle,OBJECT_FLAG_ENABLE_CAMERA) then Exit;
  for Layer := Video^.Object_^.Layer-1 downto 0 do
  begin
    Candidate := Edit^.FindObject(Layer,Frame);
    if Candidate = nil then Continue;
    Span := Edit^.GetObjectLayerFrame(Candidate);
    if (Frame < Span.StartFrame) or (Frame > Span.EndFrame) then Continue;
    if Edit^.CountObjectEffect(Candidate,CameraEffect) = 0 then Continue;
    TargetCount := 0;
    if Assigned(Edit^.GetObjectItemValue) then
    begin
      Raw := Edit^.GetObjectItemValue(Candidate,CameraEffect,'対象レイヤー数');
      if Raw <> nil then TargetCount := StrToIntDef(string(AnsiString(Raw)),0);
    end;
    if (TargetCount <= 0) or (Video^.Object_^.Layer-Layer <= TargetCount) then
      Result := Candidate;
    Exit;
  end;
end;

function CameraDirection(Video: PFILTER_PROC_VIDEO; Camera: OBJECT_HANDLE;
  Frame: Double; out Axis: TVec): Boolean;
var
  Edit: PEDIT_SECTION;
  Eye, Target: TVec;
  TargetLayer: Integer;
  Raw: PAnsiChar;
  TargetObject: OBJECT_HANDLE;
  Output: TOBJECT_IMAGE_PARAM;
begin
  Result := False;
  Edit := Video^.Edit;
  if (Camera = nil) or (Edit = nil) or not Assigned(Edit^.GetObjectTrackValue) then Exit;
  if not (Edit^.GetObjectTrackValue(Camera,CameraEffect,'X',Frame,@Eye.X) and
    Edit^.GetObjectTrackValue(Camera,CameraEffect,'Y',Frame,@Eye.Y) and
    Edit^.GetObjectTrackValue(Camera,CameraEffect,'Z',Frame,@Eye.Z) and
    Edit^.GetObjectTrackValue(Camera,CameraEffect,'目標X',Frame,@Target.X) and
    Edit^.GetObjectTrackValue(Camera,CameraEffect,'目標Y',Frame,@Target.Y) and
    Edit^.GetObjectTrackValue(Camera,CameraEffect,'目標Z',Frame,@Target.Z)) then Exit;
  if Assigned(Edit^.GetObjectItemValue) and Assigned(Video^.GetImageObject) and
    Assigned(Video^.GetOutputImageParam) then
  begin
    Raw := Edit^.GetObjectItemValue(Camera,CameraEffect,'目標レイヤー');
    if Raw <> nil then
    begin
      TargetLayer := StrToIntDef(string(AnsiString(Raw)),0);
      if TargetLayer > 0 then
      begin
        TargetObject := Video^.GetImageObject(TargetLayer-1,0);
        if (TargetObject <> nil) and (TargetObject <> Video^.Object_^.Handle) and
          Video^.GetOutputImageParam(TargetObject,0,@Output,SizeOf(Output)) then
          Target := Target+V(Output.X,Output.Y,Output.Z);
      end;
    end;
  end;
  if IsNan(Dot(Eye,Eye)+Dot(Target,Target)) or IsInfinite(Dot(Eye,Eye)+Dot(Target,Target)) then Exit;
  if Dot(Target-Eye,Target-Eye) < 1E-12 then Exit;
  Axis := UnitVector(Target-Eye);
  Result := True;
end;

function BasisDepth(const Axis: TVec; const Params: TOBJECT_IMAGE_PARAM): TVec;
var A: TVec;
begin
  A := RotateZ(Axis,-DegToRad(Params.RZ));
  A := RotateY(A,-DegToRad(Params.RY));
  A := RotateX(A,-DegToRad(Params.RX));
  Result := V(A.X*Params.SX,A.Y*Params.SY,A.Z*Params.SZ);
end;

procedure DrawView(Video: PFILTER_PROC_VIDEO; HasCameraAPI: Boolean;
  Seconds: Double; out Axis: TVec; out CameraDepth: Boolean);
type
  TMatrix = array[0..3,0..3] of Single;
  PMatrix = ^TMatrix;
var
  Camera: OBJECT_HANDLE;
  CameraMode: Integer;
  Frame: Double;
  Output: TOBJECT_IMAGE_PARAM;
  GroupData: array[0..SizeOf(TMatrix)+14] of Byte;
  Group: PMatrix;
  A: TVec;
begin
  Axis := V(0,0,1);
  Camera := nil;
  Frame := Video^.Object_^.FrameS+Video^.Object_^.Frame;
  if (Video^.Scene <> nil) and (Video^.Scene^.Rate > 0) and (Video^.Scene^.Scale > 0) then
    Frame := Video^.Object_^.FrameS+Seconds*Video^.Scene^.Rate/Video^.Scene^.Scale;
  CameraDepth := False;
  if HasCameraAPI and Assigned(Video^.GetCameraMode) then
  begin
    CameraMode := Video^.GetCameraMode();
    CameraDepth := CameraMode <> CAMERA_MODE_OFF;
    if (CameraMode = CAMERA_MODE_ON) and Assigned(Video^.GetCameraControlObject) then
      Camera := Video^.GetCameraControlObject();
  end else
  begin
    Camera := FindLegacyCamera(Video,Video^.Object_^.FrameS+Video^.Object_^.Frame);
    CameraDepth := Camera <> nil;
  end;
  CameraDirection(Video,Camera,Frame,Axis);

  // XMMATRIX の ABI は 16 バイト境界を要求する。
  Group := PMatrix((NativeUInt(@GroupData[0])+15) and not NativeUInt(15));
  if Assigned(Video^.GetGroupMatrix) and Video^.GetGroupMatrix(Group) then
  begin
    A := Axis;
    Axis := V(Group^[0,0]*A.X+Group^[0,1]*A.Y+Group^[0,2]*A.Z,
      Group^[1,0]*A.X+Group^[1,1]*A.Y+Group^[1,2]*A.Z,
      Group^[2,0]*A.X+Group^[2,1]*A.Y+Group^[2,2]*A.Z);
  end;
  if Assigned(Video^.GetOutputImageParam) and
    Video^.GetOutputImageParam(nil,0,@Output,SizeOf(Output)) then
  begin
    Axis := BasisDepth(Axis,Output);
    CameraDepth := CameraDepth and (Output.Alpha >= 1);
  end;
  // param は標準描画に対する相対変換。実際の頂点は変更せず、整列軸にだけ反映する。
  if Video^.Param <> nil then
  begin
    Axis := BasisDepth(Axis,Video^.Param^);
    CameraDepth := CameraDepth and (Video^.Param^.Alpha >= 1);
  end;
  Axis := UnitVector(Axis);
  if IsNan(Dot(Axis,Axis)) or (Dot(Axis,Axis) < 0.1) then Axis := V(0,0,1);
end;

function CompareOrder(const A, B: TDrawOrder): Integer;
begin
  if A.Pass <> B.Pass then Exit(Ord(A.Pass)-Ord(B.Pass));
  if A.Pass <> dpassOpaque then
  begin
    if A.PaperOrder <> B.PaperOrder then Exit(Integer(A.PaperOrder)-B.PaperOrder);
    if A.Depth > B.Depth then Exit(-1);
    if A.Depth < B.Depth then Exit(1);
  end;
  if A.Textured <> B.Textured then Exit(Ord(A.Textured)-Ord(B.Textured));
  if A.Finish <> B.Finish then Exit(Integer(A.Finish)-B.Finish);
  Result := A.Face-B.Face;
end;

constructor TGiftRenderer.Create;
begin
  inherited;
  FMesh := TGiftMesh.Create;
  FCompare := TComparer<TDrawOrder>.Construct(CompareOrder);
end;

destructor TGiftRenderer.Destroy;
begin
  FMesh.Free;
  inherited;
end;

procedure TGiftRenderer.BuildPackage(const S: TGiftSettings; Opening: Double);
begin
  if FHasPackage and (FPackageProgress = Opening) and (FPackage.Style = S.Style) and
    (FPackage.Width = S.Width) and (FPackage.Height = S.Height) and (FPackage.Depth = S.Depth) and
    (FPackage.Color1 = S.Color1) and (FPackage.Color2 = S.Color2) and (FPackage.Opacity = S.Opacity) then
  begin
    FMesh.Truncate(FPackageCount);
    Exit;
  end;
  FHasPackage := False;
  FMesh.Start(V(S.Width*0.5,S.Height*0.5,S.Depth*0.5));
  case S.Style of
    gsRibbonBox, gsPaperBox, gsChest, gsFlapBox, gsBurstBox:
      BuildBoxPackage(FMesh,S,Opening,FPaperFaces);
    gsPaperBag: BuildPaperBag(FMesh,S,Opening);
    gsBasket: BuildBasket(FMesh,S,Opening);
  else
    BuildWrapPackage(FMesh,S,Opening);
  end;
  FPackage := S;
  FPackage.FileName := '';
  FPackageProgress := Opening;
  FPackageCount := FMesh.Faces.Count;
  FHasPackage := True;
end;

procedure TGiftRenderer.AddImage(Video: PFILTER_PROC_VIDEO; const S: TGiftSettings;
  out Resource: string);
const
  ImageFit: array[TGiftStyle,0..1] of Double = (
    (0.78,0.73),(0.74,0.73),(0.65,0.57),(0.75,0.53),(0.72,0.72),
    (0.76,0.73),(0.38,0.49),(0.68,0.74),(0.70,0.70),(0.70,0.70),
    (0.68,0.54),(0.37,0.53),(0.63,0.62),(0.62,0.64));
var
  Width, Height: Integer;
  Factor, X, Y, CenterX: Double;
begin
  Resource := '';
  if (S.FileName = '') or not Assigned(Video^.GetImageResourceSize) then Exit;
  Resource := 'image:'+S.FileName;
  Width := 0;
  Height := 0;
  if not Video^.GetImageResourceSize(PWideChar(Resource),@Width,@Height) or
    (Width < 1) or (Height < 1) then
  begin
    Resource := '';
    Exit;
  end;
  Factor := Min(S.Width*ImageFit[S.Style,0]/Width,S.Height*ImageFit[S.Style,1]/Height);
  X := Width*Factor/S.Width;
  Y := Height*Factor/S.Height;
  CenterX := 0;
  if S.Style = gsStocking then CenterX := -0.12;
  FMesh.Quad(V(CenterX-X,-Y,0),V(CenterX-X,Y,0),V(CenterX+X,Y,0),
    V(CenterX+X,-Y,0),Paint($FFFFFF),True);
end;

procedure TGiftRenderer.DrawFaces(Video: PFILTER_PROC_VIDEO; const Resource: string;
  const Axis: TVec; const S: TGiftSettings; EffectStart: Integer; UseOpaquePass: Boolean);
var
  FirstFace, Count, I, J, Start, Used, PlaneCount: Integer;
  Entry: TDrawOrder;
  Face: TFace;
  P, N, Center, EffectOffset: TVec;
  R, G, B, Alpha, Lighting: Double;
  Transforms: array[TDrawPart] of TDrawTransform;
  Transform: ^TDrawTransform;
  Planes: TPaperPlanes;
  Vertex: PVertexColor;
  BackLight, AdditiveEffect: Boolean;
begin
  FirstFace := 0;
  if S.PackageScale = 0 then FirstFace := FPackageCount;
  Count := FMesh.Faces.Count-FirstFace;
  if Count = 0 then Exit;
  if Length(FOrder) < Count then
  begin
    SetLength(FOrder,Max(2048,2*Count));
    SetLength(FColor,Length(FOrder)*4);
    SetLength(FLight,Length(FOrder)*4);
    SetLength(FTexture,Length(FOrder)*4);
  end;
  // 包装と演出の変換は、それぞれ出力座標の軸に沿って適用する。
  Transforms[dpImage] := Default(TDrawTransform);
  Transforms[dpPackage] := DrawTransform(V(S.PackageX,S.PackageY,S.PackageZ),S.PackageScale);
  BackLight := S.Effect in [geRays,geInnerGlow];
  AdditiveEffect := BackLight or (S.Effect = geFireworks);
  EffectOffset := V(S.EffectX,S.EffectY,S.EffectZ);
  // 光の面を画像から視線の奥へ離し、カメラの深度でも画像と重ねられるようにする。
  if BackLight then EffectOffset := EffectOffset+Axis*(S.Depth*0.16*S.EffectScale);
  Transforms[dpEffect] := DrawTransform(EffectOffset,S.EffectScale);
  // ホスト深度を使えない場合は、箱の大きな面が包装紙の柄を上書きしないようにする。
  PlaneCount := 0;
  if not UseOpaquePass and (S.Style = gsPaperBox) and (S.PackageScale > 0) and
    (S.Opacity > 0) then
    PlaneCount := BuildPaperPlanes(FMesh,FPaperFaces,Axis,Transforms[dpPackage],Planes);
  for I := FirstFace to FMesh.Faces.Count-1 do
  begin
    Face := FMesh.Faces[I];
    Entry.Face := I;
    if I < FPackageCount then Entry.Part := dpPackage
    else if I >= EffectStart then Entry.Part := dpEffect
    else Entry.Part := dpImage;
    Entry.Textured := Face.Textured;
    Entry.Emissive := (Entry.Part = dpEffect) and AdditiveEffect;
    Entry.Finish := Face.Paint.Finish;
    Entry.Pass := dpassSorted;
    Entry.PaperOrder := 0;
    Entry.Depth := 0;
    if UseOpaquePass and (not Face.Textured) and (Face.Paint.Alpha >= 1) and
      (Face.Paint.Finish <> 3) then Entry.Pass := dpassOpaque
    else
    begin
      if Entry.Emissive and BackLight then Entry.Pass := dpassBackLight;
      Center := ModelToHost((Face.P[0]+Face.P[1]+Face.P[2]+Face.P[3])*0.25);
      Transform := @Transforms[Entry.Part];
      if Transform^.Active then
        Center := Center*Transform^.Scale+Transform^.Offset;
      Entry.Depth := Dot(Axis,Center);
      if PlaneCount > 0 then Entry.PaperOrder := PaperOrder(Center,Planes,PlaneCount);
    end;
    FOrder[I-FirstFace] := Entry;
  end;
  // 透過面と画像をまとめて奥から送出する。不透明面は先にホストに深度を確保させる。
  TArray.Sort<TDrawOrder>(FOrder,FCompare,0,Count);
  R := 0;
  G := 0;
  B := 0;
  Start := 0;
  while Start < Count do
  begin
    Entry := FOrder[Start];
    if Assigned(Video^.SetMaterialShine) then Video^.SetMaterialShine(Shine[Entry.Finish]);
    Used := 0;
    I := Start;
    while (I < Count) and (FOrder[I].Pass = Entry.Pass) and
      (FOrder[I].Textured = Entry.Textured) and (FOrder[I].Finish = Entry.Finish) and
      (FOrder[I].Emissive = Entry.Emissive) do
    begin
      Face := FMesh.Faces[FOrder[I].Face];
      Transform := @Transforms[FOrder[I].Part];
      if not Entry.Textured then
      begin
        N := ModelToHost(Face.Normal);
        if Dot(N,Axis) > 0 then N := N*(-1);
        if Entry.Finish = 3 then Lighting := Face.Paint.Tone
        else
          Lighting := Face.Paint.Tone*(0.57+0.38*Max(0.0,Dot(N,V(-0.41,-0.58,-0.70)))+
            0.13*Max(0.0,Dot(N,V(0.80,0.16,-0.31))));
        R := Min(1.0,((Face.Paint.Color shr 16) and 255)*Lighting/255);
        G := Min(1.0,((Face.Paint.Color shr 8) and 255)*Lighting/255);
        B := Min(1.0,(Face.Paint.Color and 255)*Lighting/255);
      end;
      for J := 0 to 3 do
      begin
        P := ModelToHost(Face.P[J]);
        if Transform^.Active then P := P*Transform^.Scale+Transform^.Offset;
        if Entry.Textured then
        begin
          FTexture[Used].X := P.X;
          FTexture[Used].Y := P.Y;
          FTexture[Used].Z := P.Z;
          FTexture[Used].U := UV[J,0];
          FTexture[Used].V := UV[J,1];
          FTexture[Used].A := 1;
        end else
        begin
          Alpha := Face.Paint.Alpha*Face.Weight[J];
          if Entry.Emissive then Vertex := @FLight[Used]
          else
          begin
            Vertex := PVertexColor(@FColor[Used]);
            FColor[Used].NX := N.X;
            FColor[Used].NY := N.Y;
            FColor[Used].NZ := N.Z;
          end;
          Vertex^.X := P.X;
          Vertex^.Y := P.Y;
          Vertex^.Z := P.Z;
          Vertex^.R := R*Alpha;
          Vertex^.G := G*Alpha;
          Vertex^.B := B*Alpha;
          Vertex^.A := Alpha;
        end;
        Inc(Used);
      end;
      Inc(I);
    end;
    if Entry.Textured then
      Video^.DrawPoly(VERTEX_QUAD_TEXTURE,@FTexture[0],Used,PWideChar(Resource))
    else if Entry.Emissive then
    begin
      if Assigned(Video^.SetBlendMode) then Video^.SetBlendMode(BLEND_ADD);
      try
        Video^.DrawPoly(VERTEX_QUAD_COLOR,@FLight[0],Used,nil);
      finally
        if Assigned(Video^.SetBlendMode) then Video^.SetBlendMode(BLEND_NONE);
      end;
    end
    else
      Video^.DrawPoly(VERTEX_QUAD_COLOR_NORM,@FColor[0],Used,nil);
    Start := I;
  end;
end;

procedure TGiftRenderer.Draw(Video: PFILTER_PROC_VIDEO; const S: TGiftSettings;
  Seconds: Double; HasCameraAPI: Boolean);
var
  Time: TGiftTime;
  Axis: TVec;
  Resource: string;
  CameraDepth: Boolean;
  EffectStart: Integer;
begin
  if not Assigned(Video^.DrawPoly) or not Assigned(Video^.SetImageData) then Exit;
  Time := EvaluateGiftTime(S,Seconds);
  BuildPackage(S,Time.Opening);
  Video^.SetImageData(@WhitePixel,1,1);
  AddImage(Video,S,Resource);
  EffectStart := FMesh.Faces.Count;
  if S.EffectScale > 0 then BuildGiftEffect(FMesh,S,Time);
  DrawView(Video,HasCameraAPI,Seconds,Axis,CameraDepth);
  if Assigned(Video^.SetCullingState) then Video^.SetCullingState(False);
  if Assigned(Video^.SetSamplerMode) then Video^.SetSamplerMode(SAMPLER_CLAMP);
  try
    DrawFaces(Video,Resource,Axis,S,EffectStart,CameraDepth);
  finally
    if Assigned(Video^.SetMaterialShine) then Video^.SetMaterialShine(0);
    if Assigned(Video^.SetSamplerMode) then Video^.SetSamplerMode(0);
  end;
  if Assigned(Video^.SetDefaultAnchor) then
    Video^.SetDefaultAnchor(Round(S.Width),Round(S.Height));
end;

end.
