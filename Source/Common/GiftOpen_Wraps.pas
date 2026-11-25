unit GiftOpen_Wraps;

// 袋、布、フィルム、球殻など、曲面と折り目を持つ包装を成形する。
interface

uses GiftOpen_Settings, GiftOpen_Mesh;

// P は 0 の閉状態から 1 の開封完了までの割合。画像面を動かさない。
procedure BuildWrapPackage(Mesh: TGiftMesh; const S: TGiftSettings; P: Double);

implementation

uses System.Math, GiftOpen_Packages;

const Signs: array[0..1] of Integer = (-1,1);

type
  TWrapAxis = (waY, waX);

function OnAxis(const Point: TVec; Axis: TWrapAxis): TVec;
begin
  if Axis = waX then Result := V(Point.Y,-Point.X,Point.Z)
  else Result := Point;
end;

procedure Skin(Mesh: TGiftMesh; const Rings: array of TRing; const T: TPose;
  StartAngle, Sweep, Fold: Double; Count: Integer; const Body, Lining: TPaint;
  Axis: TWrapAxis = waY; Thickness: Double = 0);
var
  I, J: Integer;
  A, B, Ripple: Double;
  Outer, Inner: TPaint;
  P, Q, R, S: TVec;
  TopIn, BottomIn: TRing;
begin
  for I := 0 to High(Rings)-1 do
  begin
    TopIn := Rings[I];
    BottomIn := Rings[I+1];
    TopIn.RX := Max(0.0,TopIn.RX-Thickness);
    TopIn.RZ := Max(0.0,TopIn.RZ-Thickness);
    BottomIn.RX := Max(0.0,BottomIn.RX-Thickness);
    BottomIn.RZ := Max(0.0,BottomIn.RZ-Thickness);
    for J := 0 to Count-1 do
    begin
      A := StartAngle+Sweep*J/Count;
      B := StartAngle+Sweep*(J+1)/Count;
      Ripple := 1 - Fold*0.92*Cos((A+B)*4);
      Outer := Shade(Body,Ripple);
      P := T.Apply(OnAxis(RingPoint(Rings[I],A,Fold),Axis));
      Q := T.Apply(OnAxis(RingPoint(Rings[I+1],A,Fold),Axis));
      R := T.Apply(OnAxis(RingPoint(Rings[I+1],B,Fold),Axis));
      S := T.Apply(OnAxis(RingPoint(Rings[I],B,Fold),Axis));
      Mesh.Quad(P,Q,R,S,Outer);
      if Thickness > 0 then
      begin
        Mesh.Quad(
          T.Apply(OnAxis(RingPoint(TopIn,B,Fold),Axis)),
          T.Apply(OnAxis(RingPoint(BottomIn,B,Fold),Axis)),
          T.Apply(OnAxis(RingPoint(BottomIn,A,Fold),Axis)),
          T.Apply(OnAxis(RingPoint(TopIn,A,Fold),Axis)),Lining);
        Inner := Shade(Lining,1.12);
        if I = 0 then Mesh.Quad(P,S,T.Apply(OnAxis(RingPoint(TopIn,B,Fold),Axis)),
          T.Apply(OnAxis(RingPoint(TopIn,A,Fold),Axis)),Inner);
        if I = High(Rings)-1 then Mesh.Quad(R,Q,T.Apply(OnAxis(RingPoint(BottomIn,A,Fold),Axis)),
          T.Apply(OnAxis(RingPoint(BottomIn,B,Fold),Axis)),Inner);
        if (Sweep < 2*Pi-0.001) and (J=0) then
          Mesh.Quad(Q,P,T.Apply(OnAxis(RingPoint(TopIn,A,Fold),Axis)),
            T.Apply(OnAxis(RingPoint(BottomIn,A,Fold),Axis)),Inner);
        if (Sweep < 2*Pi-0.001) and (J=Count-1) then
          Mesh.Quad(S,R,T.Apply(OnAxis(RingPoint(BottomIn,B,Fold),Axis)),
            T.Apply(OnAxis(RingPoint(TopIn,B,Fold),Axis)),Inner);
      end;
    end;
  end;
end;

procedure Drawstring(Mesh: TGiftMesh; const Body, Trim: TPaint; P: Double);
var
  Mouth, Gather, Drop, Loose, Top, A: Double;
  I, Side: Integer;
  T: TPose;
  Neck: array[0..24] of TVec;
  Tail: array[0..5] of TVec;
  R0, R1, R2, R3, R4, R5, R6: TRing;
begin
  Loose := Phase(P,0,0.50);
  Drop := Phase(P,0.36,1);
  Gather := Phase(P,0.12,0.67);
  Top := -1+1.64*Drop;
  Mouth := Mix(0.18,0.88,Gather);
  T := Default(TPose);
  R0 := Ring(Top,Mouth+0.11,Mouth+0.11);
  R1 := Ring(Top+0.16-0.10*Drop,Mouth,Mouth);
  R2 := Ring(Mix(-0.57,0.78,Drop),0.72,0.58);
  R3 := Ring(Mix(-0.08,0.92,Drop),0.96,0.87);
  R4 := Ring(Mix(0.58,1.19,Drop),0.99,0.94);
  R5 := Ring(Mix(0.90,1.47,Drop),0.81,0.80);
  R6 := Ring(R5.Y+0.06,0,0);
  Skin(Mesh,[R0,R1,R2,R3,R4,R5,R6],T,0,2*Pi,0.09,32,Body,Shade(Body,0.73),waY,0.029);
  if P <= 0.20 then
    Skin(Mesh,[Ring(Top+0.075,0,0),Ring(Top+0.09,Mouth+0.045,Mouth+0.045)],
      T,0,2*Pi,0.09,32,Shade(Body,0.71),Body);
  for I := 0 to High(Neck) do
  begin
    A := (I/High(Neck)*2*Pi)*(1-0.22*Loose)+0.33*Loose;
    Neck[I] := RingPoint(Ring(R1.Y,Mouth+0.032,Mouth+0.028),A,0.09);
  end;
  Mesh.Cord(Neck,0.026,Trim);
  for Side in Signs do
  begin
    for I := 0 to High(Tail) do
    begin
      A := I/High(Tail);
      Tail[I] := V(Side*(0.03+0.54*A+0.49*Loose*A),R1.Y+0.24*A+0.08*Sin(A*Pi),
        -Mouth-0.09-0.23*A);
    end;
    Mesh.Cord(Tail,0.025,Trim);
  end;
  if Loose < 1 then Bow(Mesh,V(0,R1.Y-0.03,-Mouth-0.10),0.22,Loose,Trim);
end;

procedure Candy(Mesh: TGiftMesh; const Body, Trim: TPaint; P: Double);
var
  I, Side: Integer;
  Q, A, Tail: Double;
  T: TPose;
  Tie: array[0..20] of TVec;
  Inner, EndColor: TPaint;
begin
  Inner := Shade(Body,0.71);
  for I := 0 to 3 do
  begin
    A := I*Pi/2;
    Q := Phase(P,0.18+0.06*I,1);
    T := Pose(V(0,0,0),V(0.14*Sin(A)*Q,2.38*Cos(A+Pi/4)*Q,
      2.28*Sin(A+Pi/4)*Q),V(0.98*Q,-0.54*Q,0.46*Q));
    if I mod 2 = 0 then EndColor := Body else EndColor := Shade(Body,1.25);
    Skin(Mesh,[Ring(-0.65,0.08,0.13),Ring(-0.52,0.65,0.72),Ring(-0.30,0.88,0.91),
      Ring(0.25,0.88,0.91),Ring(0.52,0.64,0.71),Ring(0.65,0.08,0.13)],
      T,A,Pi/2,0.065,8,EndColor,Inner,waX,0.021);
  end;
  for Side in Signs do
  begin
    Tail := Phase(P,0,0.76);
    T := Pose(V(Side*0.65,0,0),V(Side*1.67*Tail,0.41*Tail,0.51*Tail),
      V(Side*2.0*Tail,0,Side*1.05*Tail));
    Skin(Mesh,[Ring(Side*0.57,0.17,0.18),Ring(Side*0.68,0.12,0.14),
      Ring(Side*0.85,0.40,0.49),Ring(Side*1.04,0.51,0.60)],
      T,0,2*Pi,0.16,32,Body,Inner,waX,0.018);
    Skin(Mesh,[Ring(Side*0.66,0,0),Ring(Side*0.66,0.17,0.18)],
      T,0,2*Pi,0.065,32,Body,Inner,waX);
    for I := 0 to High(Tie) do
    begin
      A := I*2*Pi/High(Tie);
      Tie[I] := T.Apply(OnAxis(RingPoint(Ring(Side*0.664,0.143,0.162),A),waX));
    end;
    Mesh.Cord(Tie,0.023,Trim);
  end;
end;

procedure Cloth(Mesh: TGiftMesh; const Body, Trim: TPaint; P: Double);
var
  Side, Row: Integer;
  A, Q, U, B, X0, X1, Y0, Y1, Z0, Z1: Double;
  T: TPose;
  Inner, Face: TPaint;
  LeftA, RightA, LeftB, RightB: TVec;
begin
  Inner := Shade(Body,0.70);
  Q := Phase(P,0.23,1);
  T := Pose(V(0,0,0),V(0,0.35*Q,0),V(0,0,0));
  Panel(Mesh,T,V(-0.93,0.94,-0.93),V(0.93,0.94,-0.93),V(0.93,0.94,0.93),
    V(-0.93,0.94,0.93),V(0,-0.04,0),Body,Inner);
  for Side := 0 to 3 do
  begin
    A := Side*Pi/2;
    Q := Phase(P,0.13+0.075*Side,0.86+Side*0.04);
    T := Pose(RotateY(V(0,0.92,-0.93),A),RotateY(V(0,0.25*Q,-0.43*Q),A),
      V(-Cos(A)*Q*1.67,0,Sin(A)*Q*1.67));
    for Row := 0 to 11 do
    begin
      U := Row/12;
      B := (Row+1)/12;
      X0 := 0.93*(1-Power(U,4));
      X1 := 0.93*(1-Power(B,4));
      Y0 := Mix(0.94,-1.01,U)-Sin(Pi*U)*0.29;
      Y1 := Mix(0.94,-1.01,B)-Sin(Pi*B)*0.29;
      Z0 := -0.93+Power(U,3)*0.93;
      Z1 := -0.93+Power(B,3)*0.93;
      LeftA := RotateY(V(-X0,Y0,Z0-X0*0.025),A);
      RightA := RotateY(V(X0,Y0,Z0+X0*0.025),A);
      LeftB := RotateY(V(-X1,Y1,Z1-X1*0.025),A);
      RightB := RotateY(V(X1,Y1,Z1+X1*0.025),A);
      Face := Shade(Body,0.92+0.15*Sin(U*Pi*3+Side*0.4));
      if Row mod 5 = 1 then Face := Paint(Trim.Color,Body.Alpha,Body.Finish);
      Mesh.Quad(T.Apply(LeftB),T.Apply(LeftA),T.Apply(RightA),T.Apply(RightB),Face);
      Mesh.Quad(T.Apply(RightB+V(0,0.023,0)),T.Apply(RightA+V(0,0.023,0)),
        T.Apply(LeftA+V(0,0.023,0)),T.Apply(LeftB+V(0,0.023,0)),Inner);
      Mesh.Quad(T.Apply(LeftA),T.Apply(LeftB),T.Apply(LeftB+V(0,0.023,0)),
        T.Apply(LeftA+V(0,0.023,0)),Face);
      Mesh.Quad(T.Apply(RightB),T.Apply(RightA),T.Apply(RightA+V(0,0.023,0)),
        T.Apply(RightB+V(0,0.023,0)),Face);
    end;
  end;
  Q := Phase(P,0,0.48);
  if P < 1 then
    Bow(Mesh,V(0.40*Q,-1.09-0.58*Q,0),0.28,Q,Trim);
end;

procedure DirectWrap(Mesh: TGiftMesh; Style: TGiftStyle; const Body, Trim: TPaint; P: Double);
var
  Side, Band, I: Integer;
  A, Y, Q, Spread, Height, Width, X, Z, U: Double;
  T: TPose;
  Origin, Across, Delta, A0, A1, B0, B1, Ridge: TVec;
  Path: array[0..5] of TVec;
  Material, Inner, Highlight: TPaint;
begin
  Inner := Shade(Body,0.69);
  if Style = gsDirectRibbon then
  begin
    // 五本の幅広い帯を重ね、ほどける順に閉じた巻き取りから開いた弧へ移す。
    for Band := 0 to 4 do
    begin
      Y := -0.78 + Band*0.39;
      Q := Phase(P,0.07+Band*0.08,0.73+Band*0.065);
      if Q >= 1 then Continue;
      for Side := 0 to 3 do
      begin
        A := Side*Pi/2;
        T := Pose(V(0,Y,0),RotateY(V(0,0.09*Band*Q,-1.9*Q),A),V(0,0,0));
        for I := 0 to High(Path) do
        begin
          U := I/High(Path);
          X := Mix(-0.90,0.90,U) + Q*0.45*Sin(A+U*Pi);
          Z := -0.90 + Q*0.48*Sin(2*Pi*U);
          Path[I] := T.Apply(RotateY(V(X,Y+Q*0.26*Sin(Pi*U),Z),A));
        end;
        Mesh.Strip(Path,V(0,0.199*(1-Phase(Q,0.82,1)),0),0.035,
          Shade(Body,0.88+0.16*(Band mod 2)));
      end;
    end;
    for Band in Signs do
    begin
      Q := Phase(P,0.10,0.70);
      T := Pose(V(0,0,0),V(0,Band*2.01*Q,0),V(0,0,Band*1.38*Q));
      Panel(Mesh,T,V(-0.90,Band*0.975,-0.90),V(0.90,Band*0.975,-0.90),
        V(0.90,Band*0.975,0.90),V(-0.90,Band*0.975,0.90),V(0,-Band*0.045,0),Body,Inner);
    end;
    Q := Phase(P,0,0.49);
    if P < 1 then Bow(Mesh,V(0,-0.79-1.20*Q,-0.995),0.37,Q,Trim);
    Exit;
  end;

  // 紙とフィルムで同じ閉形状を使い、紙は鋭い裂け目、フィルムは柔らかい折り目を作る。
  for Side := 0 to 5 do
  begin
    A := Side*Pi/2;
    Origin := RotateY(V(0,0,-0.88),A);
    Across := RotateY(V(1,0,0),A);
    Delta := V(0,1,0);
    Width := 0.92;
    Height := 0.94;
    if Side >= 4 then
    begin
      Origin := V(0,(Side*2-9)*0.94,0);
      Across := V(1,0,0);
      Delta := V(0,0,1);
      Height := 0.88;
    end;
    for Band in Signs do
    begin
      Q := Phase(P,0.05+0.048*Side,0.83+0.032*Side);
      Spread := Band*Q;
      T := Pose(Origin,Origin*(2.12*Q)+Across*(1.18*Spread),
        V(0.47*Q,0.63*Spread,0.83*Spread));
      for I := 0 to 7 do
      begin
        U := -1+I*0.25;
        Y := Height*U;
        X := 0.085*(2*GiftRandom(I,Side)-1)*Sin((U+1)*Pi*0.5);
        U := U+0.25;
        Z := 0.085*(2*GiftRandom(I+1,Side)-1)*Sin((U+1)*Pi*0.5);
        Material := Shade(Body,0.89+0.18*GiftRandom(I+1,Side+2));
        if Style = gsFilm then Material := Shade(Body,0.96+0.35*GiftRandom(I,Side));
        if (Style = gsDirectPaper) and (I mod 3 = 0) then
          Material := Shade(Paint(Trim.Color,Body.Alpha,Body.Finish),0.94);
        A0 := Origin+Across*(Band*Width)+Delta*Y;
        A1 := Origin+Across*(Band*Width)+Delta*(Height*U);
        B1 := Origin+Across*(Z+Band*0.12*Q)+Delta*(Height*U);
        B0 := Origin+Across*(X+Band*0.12*Q)+Delta*Y;
        if Style = gsFilm then
        begin
          Ridge := (A0+A1+B1+B0)*0.25 + Origin*(0.015+0.12*GiftRandom(Side*8+I,Band+2));
          Highlight := Shade(Material,1.14);
          if (I mod 4 = 1) and (Band = 1) then
            Highlight := Shade(Paint(Trim.Color,Body.Alpha,Body.Finish),0.82);
          Mesh.Tri(T.Apply(A0),T.Apply(A1),T.Apply(Ridge),Material);
          Mesh.Tri(T.Apply(A1),T.Apply(B1),T.Apply(Ridge),Highlight);
          Mesh.Tri(T.Apply(B1),T.Apply(B0),T.Apply(Ridge),Material);
          Mesh.Tri(T.Apply(B0),T.Apply(A0),T.Apply(Ridge),Shade(Material,0.88));
        end else Panel(Mesh,T,A0,A1,B1,B0,Origin*(-0.022),Material,Inner);
      end;
    end;
  end;
end;

procedure Stocking(Mesh: TGiftMesh; const Body, Trim: TPaint; P: Double);
var
  Drop, Mouth, Top, A: Double;
  I: Integer;
  T: TPose;
  Loop: array[0..11] of TVec;
  R0, R1, R2, R3, R4, R5: TRing;
begin
  Drop := Phase(P,0.20,1);
  Mouth := Phase(P,0.06,0.53);
  Top := -0.94+0.66*Drop;
  T := Pose(V(0,0.65,0),V(-1.42*Drop,0.78*Drop,0.28*Drop),V(0.34*Drop,0,-0.72*Drop));
  R0 := Ring(Top,0.63+0.10*Mouth,0.52+0.22*Mouth,-0.12);
  R1 := Ring(Top+0.22,0.56+0.05*Mouth,0.47+0.14*Mouth,-0.12);
  R2 := Ring(0.14,0.55,0.55,-0.12);
  R3 := Ring(0.55,0.79,0.70,0.17);
  R4 := Ring(0.88,0.86,0.63,0.13);
  R5 := Ring(0.98,0,0,0.16);
  Skin(Mesh,[R0,R1,R2,R3,R4,R5],T,0,2*Pi,0.041,28,Body,Shade(Body,0.65),waY,0.037);
  Skin(Mesh,[Ring(Top-0.045,R0.RX+0.042,R0.RZ+0.063,-0.12),
    Ring(Top+0.065,R0.RX+0.053,R0.RZ+0.071,-0.12),
    Ring(Top+0.21,R1.RX+0.057,R1.RZ+0.069,-0.12)],
    T,0,2*Pi,0.035,28,Trim,Shade(Trim,0.86),waY,0.05);
  if P < 0.23 then
    Skin(Mesh,[R0,Ring(Top+0.035,0,0,-0.12)],T,0,2*Pi,0.041,28,Shade(Body,0.76),Body);
  for I := 0 to High(Loop) do
  begin
    A := I*Pi/High(Loop);
    Loop[I] := T.Apply(V(-0.67-0.13*Sin(A),Top-0.28*Sin(A),0.11*Cos(A)));
  end;
  Mesh.Cord(Loop,0.023,Trim);
end;

procedure Globe(Mesh: TGiftMesh; Style: TGiftStyle; const Body, Second, Trim: TPaint; P: Double);
var
  I, J, Sign, Pieces: Integer;
  A, Theta, Q, Shrink, Radius, Sweep, Trans: Double;
  Rings: array[0..12] of TRing;
  T: TPose;
  Piece: TPaint;
  Pivot, Shift, Angles: TVec;
  Tail: array[0..10] of TVec;
begin
  case Style of
    gsCapsule, gsKusudama: Pieces := 2;
  else
    Pieces := 8;
  end;
  for I := 0 to Pieces-1 do
  begin
    A := I*2*Pi/Pieces;
    Sweep := 2*Pi/Pieces;
    Sign := 2*(I mod 2)-1;
    Q := Phase(P,0.08+0.014*I,0.94+0.007*I);
    Piece := Body;
    Shrink := 1;
    case Style of
      gsCapsule:
        begin
          // 二つの半球は同じ赤道から上下へ分離する。
          A := 0;
          Sweep := 2*Pi;
          Pivot := V(0,0,0);
          Shift := V(Sign*1.32*Q,Sign*1.92*Q,0.48*Q);
          Angles := V(Sign*0.26*Q,0,-Sign*0.72*Q);
          if Sign = 1 then Piece := Second;
        end;
      gsKusudama:
        begin
          A := -Pi/2+I*Pi;
          Pivot := V(0,-0.95,0);
          Shift := V(-Sign*0.22*Q,-1.27*Q,0.72*Q);
          Angles := V(0.13*Q,0,Sign*1.35*Q);
          if I = 1 then Piece := Shade(Body,0.86);
        end;
    else
      begin
        Pivot := V(0,0,0);
        Shift := V(2.2*Q*Cos(A+0.28),(-0.65+1.55*GiftRandom(I,0))*Q,
          2.3*Q*Sin(A+0.28));
        Angles := V(2.5*Q,-2.3*Q,1.7*Q);
        Shrink := 1-Q;
        Piece := Shade(Body,0.88+0.24*GiftRandom(I,1));
      end;
    end;
    T := Pose(Pivot,Shift,Angles);
    for J := 0 to High(Rings) do
    begin
      Theta := Pi*J/High(Rings);
      if Style = gsCapsule then Theta := Theta*0.5;
      Radius := Sin(Theta)*Shrink;
      Trans := -Cos(Theta)*Shrink;
      if (Style = gsCapsule) and (Sign = 1) then Trans := -Trans;
      if Style = gsBalloon then Radius := Radius*(0.89-0.16*Trans);
      Rings[J] := Ring(Trans,Radius,Radius);
    end;
    Skin(Mesh,Rings,T,A,Sweep,0,Max(4,36 div Pieces)*Ord(Style <> gsCapsule)+
      36*Ord(Style=gsCapsule),Piece,Shade(Piece,0.71),waY,0.026);
    if Style = gsCapsule then
      Skin(Mesh,[Ring(Sign*0.017,1.005,1.005),Ring(Sign*0.059,1.008,1.008)],
        T,0,2*Pi,0,36,Shade(Piece,1.30),Piece,waY,0.025);
    if Style = gsKusudama then
      Skin(Mesh,[Ring(-0.035,1.012,1.012),Ring(0.038,1.012,1.012)],
        T,A,Sweep,0,18,Paint(Trim.Color,Body.Alpha,2),Shade(Body,0.81),waY,0.016);
    if Style = gsKusudama then
    begin
      for J := 0 to High(Tail) do
      begin
        Theta := J/High(Tail);
        Tail[J] := T.Apply(V(-Sign*(0.18+0.15*Theta),0.54+Theta*(0.24+0.95*Q),
          -0.71-0.16*Sin(Theta*2*Pi)));
      end;
      Mesh.Strip(Tail,V(0.074,0,0),0.013,Trim);
    end;
  end;
  if Style in [gsBalloon,gsKusudama] then
  begin
    Q := Phase(P,0.09,0.85);
    T := Pose(V(0,0.96,0),V(1.32*Q,1.22*Q,0.26*Q),V(0,0,1.74*Q));
    if Style = gsBalloon then
      Skin(Mesh,[Ring(0.925,0.04,0.04),Ring(1.08,0.10,0.09),Ring(1.11,0.10,0.09)],
        T,0,2*Pi,0,14,Body,Body,waY,0.012);
    for J := 0 to High(Tail) do
    begin
      Theta := J/High(Tail);
      Tail[J] := T.Apply(V(0.20*Sin(Theta*2.2*Pi)*Theta,1.07+0.67*Theta,-0.05*Theta));
    end;
    Mesh.Cord(Tail,0.019,Trim);
  end;
end;

procedure BuildWrapPackage(Mesh: TGiftMesh; const S: TGiftSettings; P: Double);
var
  Body, Trim: TPaint;
begin
  Body := Paint(S.Color1,S.Opacity,1);
  Trim := Paint(S.Color2,1,1);
  case S.Style of
    gsDrawstring: Drawstring(Mesh,Body,Trim,P);
    gsCandy: Candy(Mesh,Shade(Body,1.04),Trim,P);
    gsFuroshiki: Cloth(Mesh,Body,Trim,P);
    gsDirectRibbon, gsDirectPaper: DirectWrap(Mesh,S.Style,Body,Trim,P);
    gsFilm: DirectWrap(Mesh,S.Style,Paint(S.Color1,S.Opacity,2),Trim,P);
    gsStocking: Stocking(Mesh,Body,Trim,P);
    gsCapsule, gsBalloon, gsKusudama: Globe(Mesh,S.Style,Paint(S.Color1,S.Opacity,2),
      Paint(S.Color2,S.Opacity,2),Trim,P);
  end;
end;

end.
