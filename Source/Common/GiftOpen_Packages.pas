unit GiftOpen_Packages;

// 直方体の箱、紙袋、バスケットの成形と開封を担当する。
interface

uses GiftOpen_Settings, GiftOpen_Mesh;

type
  TPose = record
    Pivot, Shift, Angle: TVec;
    function Apply(const Point: TVec): TVec;
  end;

function Pose(const Pivot, Shift, Angles: TVec): TPose;
procedure Panel(Mesh: TGiftMesh; const T: TPose; const A, B, C, D, Width: TVec;
  const Outer, Inner: TPaint);
procedure BuildBoxPackage(Mesh: TGiftMesh; const S: TGiftSettings; P: Double);
procedure BuildPaperBag(Mesh: TGiftMesh; const S: TGiftSettings; P: Double);
procedure BuildBasket(Mesh: TGiftMesh; const S: TGiftSettings; P: Double);
procedure Bow(Mesh: TGiftMesh; const At: TVec; Size, Open: Double; const Trim: TPaint);

implementation

uses System.Math;

const Signs: array[0..1] of Integer = (-1,1);

function Pose(const Pivot, Shift, Angles: TVec): TPose;
begin
  Result.Pivot := Pivot;
  Result.Shift := Shift;
  Result.Angle := Angles;
end;

function TPose.Apply(const Point: TVec): TVec;
begin
  Result := Point-Pivot;
  if Angle.X <> 0 then Result := RotateX(Result,Angle.X);
  if Angle.Y <> 0 then Result := RotateY(Result,Angle.Y);
  if Angle.Z <> 0 then Result := RotateZ(Result,Angle.Z);
  Result := Result+Pivot+Shift;
end;

procedure Panel(Mesh: TGiftMesh; const T: TPose; const A, B, C, D, Width: TVec;
  const Outer, Inner: TPaint);
begin
  Mesh.Plate(T.Apply(A),T.Apply(B),T.Apply(C),T.Apply(D),T.Apply(A+Width)-T.Apply(A),Outer,Inner);
end;

procedure Floor(Mesh: TGiftMesh; const T: TPose; Radius, Y, Thickness: Double;
  const Outer, Inner: TPaint);
begin
  Panel(Mesh,T,V(-Radius,Y,-Radius),V(Radius,Y,-Radius),V(Radius,Y,Radius),
    V(-Radius,Y,Radius),V(0,-Thickness,0),Outer,Inner);
end;

procedure Walls(Mesh: TGiftMesh; const T: TPose; Radius, Top, Bottom, Thickness: Double;
  const Outer, Inner: TPaint);
var
  Side: Integer;
  Angle: Double;
begin
  for Side := 0 to 3 do
  begin
    Angle := Side*Pi/2;
    // 箱の面を回転してからアニメーションの支点に合わせる。
    Panel(Mesh,T,RotateY(V(-Radius,Top,-Radius),Angle),RotateY(V(-Radius,Bottom,-Radius),Angle),
      RotateY(V(Radius,Bottom,-Radius),Angle),RotateY(V(Radius,Top,-Radius),Angle),
      RotateY(V(0,0,Thickness),Angle),Outer,Inner);
  end;
end;

procedure Bow(Mesh: TGiftMesh; const At: TVec; Size, Open: Double; const Trim: TPaint);
var
  I, Side: Integer;
  A, Loose, L, Height: Double;
  Center, Axis: TVec;
  Loop: array[0..16] of TVec;
  Tail: array[0..5] of TVec;
begin
  for Side in Signs do
  begin
    Loose := Open*(0.72+0.12*Side);
    Center := At+V(Side*Loose*1.55, -Loose*0.30, -Loose*0.10);
    Axis := V(0,0,Size*Mix(0.27,0.16,Open));
    for I := 0 to High(Loop) do
    begin
      A := I/High(Loop);
      L := Sin(Pi*A)*Mix(1.32,0.33,Open) + A*Open*1.25;
      Height := Sin(2*Pi*A)*0.19 - Sin(Pi*A)*0.40;
      Loop[I] := Center + V(Side*Size*L, Size*Height, Size*(0.45*A-0.12));
    end;
    Mesh.Strip(Loop,Axis,Size*0.055,Trim);
    for I := 0 to High(Tail) do
    begin
      A := I/High(Tail);
      Tail[I] := Center + V(Side*Size*A*(0.95+Open*0.85),
        Size*(0.10*A+0.10*Sin(2*Pi*A)+0.33*Open*A), -Size*A*0.88);
    end;
    Mesh.Strip(Tail, V(0,0,Size*0.17),Size*0.039,Shade(Trim,0.92));
  end;
  if Open < 1 then
    Mesh.Box(At+V(-Size*0.20,-Size*0.14,-Size*0.25),
      At+V(Size*0.20,Size*0.07,Size*0.25),Trim);
end;

procedure BoxRibbon(Mesh: TGiftMesh; const T: TPose; Top, Bottom, Extent, Width: Double;
  TurnQuarter: Boolean; const Material: TPaint);
var
  Point: array[0..4] of TVec;
  Across: TVec;
  I: Integer;
begin
  Point[0] := V(0,Bottom,-Extent);
  Point[1] := V(0,Top+0.018,-Extent);
  Point[2] := V(0,Top,-Extent+0.018);
  Point[3] := V(0,Top,Extent-0.018);
  Point[4] := V(0,Top+0.018,Extent);
  Across := V(Width,0,0);
  if TurnQuarter then
  begin
    for I := 0 to High(Point) do Point[I] := RotateY(Point[I],Pi/2);
    Across := V(0,0,Width);
  end;
  for I := 0 to High(Point) do Point[I] := T.Apply(Point[I]);
  Mesh.Strip(Point,T.Apply(Across)-T.Apply(V(0,0,0)),0.013,Material);
  Mesh.Strip([T.Apply(V(0,Bottom,0)+RotateY(V(0,0,Extent),Ord(TurnQuarter)*Pi/2)),
    Point[4]],T.Apply(Across)-T.Apply(V(0,0,0)),0.013,Material);
end;

procedure PrintedPaper(Mesh: TGiftMesh; const Body, Print: TPaint; P: Double);
const Bands = 4;
var
  Side, Row, Col: Integer;
  T: TPose;
  A, B, C, D, N, W, S, E, Shift: TVec;
  Material: TPaint;
  Folio, Angle, X, Y: Double;

  function PointAt(U, H: Double): TVec;
  var Q, Inset: Double;
  begin
    Q := (H+0.96)/1.88;
    Inset := 0.028*Folio*Q;
    Result := T.Apply(RotateY(V(X+Inset+U*(2.08/Bands-2*Inset),H,
      Mix(-1.04,-1.055,Q)),Angle));
  end;

begin
  for Side := 0 to 3 do
  begin
    Angle := Side*Pi/2;
    Folio := Phase(P,0.04+Side*0.045,0.83+Side*0.04);
    Shift := RotateY(V(0.23*Folio,-0.10*Folio,-2.6*Folio),Angle);
    T := Pose(RotateY(V(0,0.93,-1.04),Angle),Shift,
      V(Cos(Angle)*0.98*Folio,0.54*Folio,-Sin(Angle)*0.98*Folio));
    for Col := 0 to Bands-1 do
    begin
      X := -1.04+Col*2.08/Bands;
      Material := Shade(Body,0.95+0.03*Col);
      for Row := 0 to 3 do
      begin
        Y := -0.725+Row*0.47;
        A := PointAt(0,Y-0.235);
        B := PointAt(0,Y+0.235);
        C := PointAt(1,Y+0.235);
        D := PointAt(1,Y-0.235);
        N := PointAt(0.50,Y-0.09);
        W := PointAt(0.24,Y);
        S := PointAt(0.50,Y+0.09);
        E := PointAt(0.76,Y);
        // 模様を紙の同じ面に組み込み、透過時も二重に合成しない。
        Mesh.Tri(A,B,W,Material);
        Mesh.Tri(B,C,S,Material);
        Mesh.Tri(C,D,E,Material);
        Mesh.Tri(D,A,N,Material);
        Mesh.Tri(A,W,N,Material);
        Mesh.Tri(B,S,W,Material);
        Mesh.Tri(C,E,S,Material);
        Mesh.Tri(D,N,E,Material);
        Mesh.Quad(N,W,S,E,Print);
      end;
    end;
  end;
end;

procedure ChestLid(Mesh: TGiftMesh; const T: TPose; const Wood, Lining, Metal: TPaint);
const Divisions = 14;
var I, Side: Integer; A, B, Y0, Y1, Z0, Z1, X: Double;
begin
  for I := 0 to Divisions-1 do
  begin
    A := I*Pi/Divisions;
    B := (I+1)*Pi/Divisions;
    Y0 := -0.60-0.43*Sin(A);
    Y1 := -0.60-0.43*Sin(B);
    Z0 := -Cos(A);
    Z1 := -Cos(B);
    Panel(Mesh,T,V(-1,Y0,Z0),V(1,Y0,Z0),V(1,Y1,Z1),V(-1,Y1,Z1),
      V(0,0.045,0),Shade(Wood,0.92+0.06*(I mod 3)),Lining);
    for Side in Signs do
    begin
      X := Side*0.78;
      Panel(Mesh,T,V(X-0.065,Y0-0.012,Z0),V(X+0.065,Y0-0.012,Z0),
        V(X+0.065,Y1-0.012,Z1),V(X-0.065,Y1-0.012,Z1),
        V(0,0.018,0),Metal,Shade(Metal,0.82));
      Mesh.Quad(T.Apply(V(Side,-0.60,Z0)),T.Apply(V(Side,Y0,Z0)),
        T.Apply(V(Side,Y1,Z1)),T.Apply(V(Side,-0.60,Z1)),Wood);
    end;
  end;
  Panel(Mesh,T,V(-0.13,-0.55,-1.035),V(-0.13,-0.30,-1.035),
    V(0.13,-0.30,-1.035),V(0.13,-0.55,-1.035),V(0,0,0.09),Metal,Shade(Metal,0.70));
  Mesh.Quad(T.Apply(V(-0.038,-0.420,-1.038)),T.Apply(V(-0.026,-0.352,-1.038)),
    T.Apply(V(0.026,-0.352,-1.038)),T.Apply(V(0.038,-0.420,-1.038)),Paint($372512));
end;

procedure FoldingBox(Mesh: TGiftMesh; const Body, Lining: TPaint; P: Double);
var
  Side: Integer;
  W, F, A: Double;
  T, Base: TPose;
  LowL, LowR, TopR, TopL, HingeL, HingeR, Edge: TVec;
begin
  Base := Pose(V(0,0,0),V(0,0.20*P,0),V(0,0,0));
  Floor(Mesh,Base,0.96,0.97,0.07,Body,Lining);
  for Side := 0 to 3 do
  begin
    A := Side*Pi/2;
    W := Phase(P,0.16+0.04*Side,0.94+0.02*Side);
    F := Phase(P,0,0.56);
    T := Pose(RotateY(V(0,0.92,-0.96),A),Base.Shift,
      V(-Cos(A)*W*Pi*0.50,0,Sin(A)*W*Pi*0.50));
    LowL := RotateY(V(-0.96,0.92,-0.96),A);
    LowR := RotateY(V(0.96,0.92,-0.96),A);
    TopR := RotateY(V(0.96,-0.88,-0.96),A);
    TopL := RotateY(V(-0.96,-0.88,-0.96),A);
    Edge := RotateY(V(0,0,0.04),A);
    Panel(Mesh,T,TopL,LowL,LowR,TopR,Edge,Body,Lining);
    // 各壁に取り付けた四枚の三角形が、重ならずに上面を閉じる。
    HingeL := T.Apply(TopL);
    HingeR := T.Apply(TopR);
    Edge := T.Apply(RotateY(V(0,-0.88-0.96*Sin(F*1.53),-0.96+0.96*Cos(F*1.53)),A));
    Mesh.Tri(HingeL,HingeR,Edge,Body);
    Mesh.Tri(HingeL+V(0,0.026,0),Edge+V(0,0.026,0),HingeR+V(0,0.026,0),Lining);
    Mesh.Quad(HingeL,Edge,Edge+V(0,0.026,0),HingeL+V(0,0.026,0),Lining);
    Mesh.Quad(Edge,HingeR,HingeR+V(0,0.026,0),Edge+V(0,0.026,0),Lining);
  end;
end;

procedure BurstBox(Mesh: TGiftMesh; const Body, Inner, Trim: TPaint; P: Double);
var
  Side, I: Integer;
  A, Q, Gap, X, Y: Double;
  Outs, Rise, Shift: TVec;
  T: TPose;
  Corner: array[0..3] of TVec;
  Center, B, C, Thick: TVec;
begin
  T := Pose(V(0,0,0),V(0,1.08*Smooth(P),0),V(0,0,0));
  Floor(Mesh,T,1,1,0.07,Body,Inner);
  for Side := 0 to 4 do
  begin
    A := Side*Pi/2;
    Outs := V(Sin(A),0,-Cos(A));
    if Side = 4 then Outs := V(0,-1,0);
    Corner[0] := V(-1,-0.94,-1);
    Corner[1] := V(-1,0.95,-1);
    Corner[2] := V(1,0.95,-1);
    Corner[3] := V(1,-0.94,-1);
    Center := V(0.15,-0.07,-1);
    if Side = 4 then
    begin
      Corner[0] := V(-1,-0.94,1);
      Corner[1] := V(-1,-0.94,-1);
      Corner[2] := V(1,-0.94,-1);
      Corner[3] := V(1,-0.94,1);
      Center := V(0.15,-0.94,-0.07);
    end else
    begin
      for I := 0 to 3 do Corner[I] := RotateY(Corner[I],A);
      Center := RotateY(Center,A);
    end;
    for I := 0 to 3 do
    begin
      Q := Phase(P,0.12+I*0.04,0.93);
      Gap := 1-Q*0.88;
      X := (GiftRandom(4*Side+I,3)-0.5)*1.65;
      Y := (GiftRandom(4*Side+I,5)-0.5)*1.25;
      Rise := V(X*Q,-0.94*Sin(Pi*Q)+Y*Q,0);
      Shift := Outs*(2.9*Q)+Rise;
      T := Pose(Center,Shift,V((0.8+Y)*Q,0.7*X*Q,1.5*X*Q));
      B := T.Apply(Center+(Corner[I]-Center)*Gap);
      C := T.Apply(Center+(Corner[(I+1) mod 4]-Center)*Gap);
      Thick := Outs*(-0.04*Gap);
      Mesh.Tri(T.Apply(Center),B,C,Shade(Body,1+0.08*(I mod 3)));
      Mesh.Tri(C+Thick,B+Thick,T.Apply(Center)+Thick,Inner);
      if Q > 0 then
      begin
        Mesh.Quad(T.Apply(Center),B,B+Thick,T.Apply(Center)+Thick,Inner);
        Mesh.Quad(B,C,C+Thick,B+Thick,Inner);
        Mesh.Quad(C,T.Apply(Center),T.Apply(Center)+Thick,C+Thick,Trim);
      end;
    end;
  end;
end;

procedure BuildBoxPackage(Mesh: TGiftMesh; const S: TGiftSettings; P: Double);
var
  Body, Interior, Trim, Paper, Pattern: TPaint;
  Base, Lid, Bands: TPose;
  Lift, Loose, Fall, Rim, WallTop, Y: Double;
  Side, I: Integer;
begin
  Body := Paint(S.Color1,S.Opacity,1);
  Interior := Shade(Body,0.68);
  Trim := Paint(S.Color2,1,2);
  if S.Style = gsFlapBox then
  begin
    FoldingBox(Mesh,Body,Paint(S.Color2,S.Opacity,1),P);
    Exit;
  end;
  if S.Style = gsBurstBox then
  begin
    BurstBox(Mesh,Body,Interior,Trim,P);
    Exit;
  end;
  Lift := Phase(P,0.19,1);
  Fall := Phase(P,0.26,1);
  WallTop := -0.85;
  Rim := 1.03;
  if S.Style = gsChest then
  begin
    WallTop := -0.60;
    Fall := 0.95*Phase(P,0.22,1);
  end;
  Base := Pose(V(0,0,0),V(0,1.68*Fall,0),V(0,0,0));
  Floor(Mesh,Base,1,1,0.07,Body,Interior);
  if S.Style = gsChest then
  begin
    // 板目は表面の色で表現し、板の継ぎ目に隙間を作らない。
    Walls(Mesh,Base,1,WallTop,0.94,0.065,Body,Interior);
    for Side in Signs do
    begin
      Panel(Mesh,Base,V(Side*0.79-0.06,-0.60,-1.012),V(Side*0.79-0.06,0.96,-1.012),
        V(Side*0.79+0.06,0.96,-1.012),V(Side*0.79+0.06,-0.60,-1.012),
        V(0,0,0.034),Trim,Shade(Trim,0.78));
      for I := 0 to 3 do
      begin
        Y := -0.48+I*0.42;
        Mesh.Box(Base.Apply(V(Side*0.79-0.019,Y,-1.038)),
          Base.Apply(V(Side*0.79+0.019,Y+0.034,-1.012)),Shade(Trim,1.24));
        if Body.Alpha >= 0.999 then
          Mesh.Quad(Base.Apply(V(-1,Y+0.14,-1.004)),Base.Apply(V(-1,Y+0.153,-1.004)),
            Base.Apply(V(1,Y+0.153,-1.004)),Base.Apply(V(1,Y+0.14,-1.004)),Shade(Body,0.66));
      end;
    end;
    Lid := Pose(V(0,-0.60,1),Base.Shift,V(-1.92*Lift,0,0));
    ChestLid(Mesh,Lid,Body,Interior,Trim);
    Exit;
  end;
  Walls(Mesh,Base,1,WallTop,0.94,0.06,Body,Interior);
  Lid := Pose(V(0,-0.90,0),V(1.55*Lift,-1.42*Lift,0.52*Lift),
    V(-0.58*Lift,0.45*Lift,0.63*Lift));
  Floor(Mesh,Lid,Rim,-0.93,0.075,Interior,Shade(Body,1.12));
  Walls(Mesh,Lid,Rim,-0.95,-0.81,0.054,Shade(Body,1.14),Interior);
  if S.Style = gsPaperBox then
  begin
    Paper := Paint(S.Color1,S.Opacity,0);
    Pattern := Paint(S.Color2,S.Opacity,0);
    PrintedPaper(Mesh,Paper,Pattern,P);
  end else
  begin
    Loose := Phase(P,0,0.48);
    if Loose < 1 then
    begin
      Bands := Pose(V(0,-1.02,0), V(-1.50*Loose,-0.50*Loose,0.22*Loose),
        V(0,0.68*Loose,0.60*Loose));
      BoxRibbon(Mesh,Bands,-1.025,0.99,1.055,0.16*(1-Phase(Loose,0.72,1)),False,Trim);
      BoxRibbon(Mesh,Bands,-1.045,0.99,1.055,0.15*(1-Phase(Loose,0.72,1)),True,Shade(Trim,1.10));
    end;
    if P < 1 then Bow(Mesh,V(-0.92*Loose,-1.055-1.50*Lift,0.22*Lift),0.47*(1-Phase(P,0.67,1)),Loose,Trim);
  end;
end;

procedure BuildPaperBag(Mesh: TGiftMesh; const S: TGiftSettings; P: Double);
var
  Body, Inner, HandleColor: TPaint;
  T: TPose;
  Mouth, Top, Bottom, Drop, A, Side: Double;
  I, Sign: Integer;
  Handle: array[0..12] of TVec;
  F0, F1, B0, B1, C0, C1: TVec;
begin
  Body := Paint(S.Color1,S.Opacity);
  Inner := Shade(Body,0.78);
  HandleColor := Paint(S.Color2,1,1);
  Drop := Phase(P,0.28,1);
  Mouth := 0.075+0.81*Phase(P,0.07,0.62);
  Top := -0.92+1.49*Drop;
  Bottom := 0.98+0.46*Drop;
  T := Pose(V(0,0,0),V(0,0,0),V(0,0,0));
  Panel(Mesh,T,V(-0.87,Bottom,-0.91),V(0.87,Bottom,-0.91),V(0.87,Bottom,0.91),
    V(-0.87,Bottom,0.91),V(0,-0.05,0),Body,Inner);
  for Sign in Signs do
  begin
    Side := Sign;
    Panel(Mesh,T,V(-0.95,Top,Side*Mouth),V(-0.87,Bottom,Side*0.91),
      V(0.87,Bottom,Side*0.91),V(0.95,Top,Side*Mouth),
      V(0,0,-Side*0.017),Body,Inner);
    F0 := V(Side*0.95,Top,-Mouth);
    F1 := V(Side*0.87,Bottom,-0.91);
    B0 := V(Side*0.95,Top,Mouth);
    B1 := V(Side*0.87,Bottom,0.91);
    C0 := V(Side*(0.70+0.24*Drop),Top,0);
    C1 := V(Side*0.87,Bottom,0);
    Panel(Mesh,T,F0,F1,C1,C0,V(-Side*0.014,0,0),Shade(Body,0.90),Inner);
    Panel(Mesh,T,C0,C1,B1,B0,V(-Side*0.014,0,0),Shade(Body,1.16),Inner);
    for I := 0 to High(Handle) do
    begin
      A := I*Pi/High(Handle);
      Handle[I] := V(-0.40*Cos(A),Top+0.085-(0.47-0.30*Drop)*Sin(A),
        Side*(Mouth+0.035+0.28*Drop*Sin(A)));
    end;
    Mesh.Cord(Handle,0.028,HandleColor);
  end;
  if P < 0.30 then
    Panel(Mesh,T,V(-0.94,Top,-Mouth),V(0.94,Top,-Mouth),V(0.94,Top,Mouth),
      V(-0.94,Top,Mouth),V(0,0.02,0),
      Shade(Body,1.10),Inner);
end;

procedure BuildBasket(Mesh: TGiftMesh; const S: TGiftSettings; P: Double);
const WickerRows = 11;
var
  Body, Inner, Trim: TPaint;
  Top, Bottom, A, B, Y, Z, Lower, Split: Double;
  Side, Row, Col, Sign, I: Integer;
  Base, Lid: TPose;
  Handle: array[0..20] of TVec;
  Horizontal: array[0..24] of TVec;
  Upright: array[0..WickerRows] of TVec;
begin
  Body := Paint(S.Color1,S.Opacity,1);
  Inner := Shade(Body,0.62);
  Trim := Paint(S.Color2,1,1);
  Lower := Phase(P,0.18,1);
  Split := Phase(P,0.05,0.90);
  Base := Pose(V(0,0,0),V(0,1.48*Lower,0),V(0,0,0));
  Top := -0.64;
  Bottom := 0.97;
  Floor(Mesh,Base,0.91,Bottom,0.08,Body,Inner);
  Walls(Mesh,Base,0.94,Top,Bottom-0.04,0.045,Inner,Shade(Body,0.85));
  for Side := 0 to 3 do
  begin
    A := Side*Pi/2;
    for Row := 0 to WickerRows-1 do
    begin
      Y := Mix(Top+0.04,Bottom-0.09,(Row+0.5)/WickerRows);
      for Col := 0 to High(Horizontal) do
      begin
        B := Mix(-0.96,0.96,Col/High(Horizontal));
        Z := -0.989-0.038*Cos((Col*0.5+Row)*Pi);
        Horizontal[Col] := Base.Apply(RotateY(V(B,Y,Z),A));
      end;
      Mesh.Strip(Horizontal,V(0,0.047,0),0.031,Shade(Body,0.90+0.24*GiftRandom(Row,Side)));
    end;
    for Col := 0 to 12 do
    begin
      B := Mix(-0.96,0.96,Col/12);
      for Row := 0 to High(Upright) do
      begin
        Y := Mix(Top,Bottom,Row/High(Upright));
        Z := -0.997-0.013*Cos((Row+Col)*Pi);
        Upright[Row] := Base.Apply(RotateY(V(B,Y,Z),A));
      end;
      Mesh.Strip(Upright,RotateY(V(0.018,0,0),A),0.034,Shade(Body,0.71+0.24*GiftRandom(Col,Side)));
    end;
  end;
  Walls(Mesh,Base,1,Top-0.055,Top+0.035,0.085,Trim,Shade(Trim,0.79));
  for Sign in Signs do
  begin
    Lid := Pose(V(Sign*0.96,Top,0),V(Sign*1.00*Split,-0.43*Split,0.43*Split),
      V(0,0,-Sign*1.60*Split));
    Panel(Mesh,Lid,V(Min(0,Sign),-0.89,-1),V(Max(0,Sign),-0.89,-1),
      V(Max(0,Sign),-0.89,1),V(Min(0,Sign),-0.89,1),V(0,0.27,0),Body,Inner);
    for I := 0 to High(Handle) do
    begin
      A := Pi*I/High(Handle);
      Handle[I] := Base.Apply(V(Sign*Cos(A)*0.98,Top+0.10-0.74*Sin(A),
        Sign*0.50 + Sign*0.37*Lower*Sin(A)))+V(0,0.22*Lower,0.40*Lower);
    end;
    Mesh.Cord(Handle,0.038,Trim);
  end;
end;

end.
