unit GiftOpen_Effects;

// 開封後の粒子と光を、固定乱数と経過時間だけから立体ポリゴンにする。
interface

uses GiftOpen_Mesh, GiftOpen_Settings;

procedure BuildGiftEffect(Mesh: TGiftMesh; const S: TGiftSettings; const Time: TGiftTime);

implementation

uses System.Math;

const
  PartyColors: array[0..7] of Cardinal =
    ($FFD15C,$F75F81,$76E6E8,$9F8CFF,$F7F1AF,$8AF4A2,$F78547,$D6EDFF);

function EffectColor(const S: TGiftSettings; I: Integer): Cardinal;
begin
  if not S.AutoColor then Exit(S.EffectColor);
  case S.Effect of
    geHearts: Result := PartyColors[(I mod 2)*5+1];
    gePetals: if I mod 3 = 0 then Result := $FFE5ED else Result := $FF9AB5;
    geRays, geInnerGlow, geSparkles:
      if I mod 3 = 0 then Result := $FFF3CE else Result := S.Color2;
    geBubbles: Result := PartyColors[2+I mod 3];
    geSmoke: if I mod 3 = 0 then Result := $DFD6FF else Result := $F3E2F5;
  else
    if I mod 7 = 0 then Result := S.Color2
    else Result := PartyColors[I mod Length(PartyColors)];
  end;
end;

function Spin(const P, Angles: TVec): TVec;
begin
  Result := RotateZ(RotateY(RotateX(P,Angles.X),Angles.Y),Angles.Z);
end;

procedure SoftDisc(Mesh: TGiftMesh; const Center, U, W: TVec; Size, Aspect: Double;
  const Material: TPaint);
const Sides = 12;
var
  I: Integer;
  A, S, C: Double;
  Prev, Current: TVec;
begin
  Prev := Center+U*Size;
  for I := 1 to Sides do
  begin
    A := 2*Pi*I/Sides;
    SinCos(A,S,C);
    Current := Center+U*(C*Size)+W*(S*Size*Aspect);
    Mesh.SoftTri(Center,Prev,Current,Material,1,0,0);
    Prev := Current;
  end;
end;

procedure ParticleShape(Mesh: TGiftMesh; Effect: TGiftEffect; const Center,
  Angles: TVec; Size: Double; const Material: TPaint);
var
  I, Steps: Integer;
  A, R, S, C, Depth: Double;
  P0, P1, Back, Tip, U, W: TVec;
  Outline: array[0..20] of TVec;
begin
  U := Spin(V(1,0,0),Angles);
  W := Spin(V(0,1,0),Angles);
  Back := Spin(V(0,0,Size*0.135),Angles);
  case Effect of
    geConfetti:
      Mesh.Plate(Center-U*Size-W*(Size*0.49),Center-U*Size+W*(Size*0.49),
        Center+U*Size+W*(Size*0.49),Center+U*Size-W*(Size*0.49),Back*0.52,
        Material,Shade(Material,0.85));
    geStars, geSparkles, geHearts, gePetals:
      begin
        case Effect of
          geStars: Steps := 10;
          geSparkles: Steps := 8;
          geHearts: Steps := 20;
        else
          Steps := 12;
        end;
        for I := 0 to Steps-1 do
        begin
          A := 2*Pi*I/Steps;
          SinCos(A,S,C);
          case Effect of
            geHearts:
              Outline[I] := Center+Spin(V(Size*S*S*S,
                -Size*(13*C-5*Cos(2*A)-2*Cos(3*A)-Cos(4*A))/16,0),Angles);
            gePetals:
              begin
                R := 0.82+0.18*Cos(2*A)+0.07*Cos(3*A);
                Outline[I] := Center+Spin(V(Size*S*R*0.58,-Size*C*R,
                  Size*0.34*Abs(S)),Angles);
              end;
          else
            R := 1;
            if I mod 2 <> 0 then
              if Effect = geStars then R := 0.45 else R := 0.20;
            Outline[I] := Center+U*(R*S*Size)-W*(R*C*Size);
          end;
        end;
        for I := 0 to Steps-1 do
        begin
          P0 := Outline[I];
          P1 := Outline[(I+1) mod Steps];
          if Effect = geSparkles then
            Mesh.SoftTri(Center-Back*1.3,P0,P1,Material,1,0.24,0.24)
          else
          begin
            Depth := 0.72+0.21*((I mod 3)/2);
            Mesh.Tri(Center-Back,P0,P1,Shade(Material,Depth+0.16));
            Mesh.Tri(Center+Back,P1,P0,Shade(Material,Depth));
          end;
        end;
      end;
    geSmoke:
      begin
        SoftDisc(Mesh,Center,U,W,Size,0.76,Material);
        SoftDisc(Mesh,Center+W*(Size*0.25),U,Spin(V(0,0,1),Angles),Size*0.83,0.83,Shade(Material,0.94));
      end;
    geBubbles:
      begin
        // 輪郭の干渉色と小さな反射を、回転する薄い輪で表現する。
        for I := 0 to 15 do
        begin
          A := I*Pi/8;
          P0 := Center+U*(Size*Cos(A))+W*(Size*Sin(A));
          A := (I+1)*Pi/8;
          P1 := Center+U*(Size*Cos(A))+W*(Size*Sin(A));
          Mesh.SoftTri(P0,P1,Center+(P0-Center)*0.76,Material,0.82,0.67,0);
          Mesh.SoftTri(P1,Center+(P1-Center)*0.76,Center+(P0-Center)*0.76,Material,0.67,0,0);
        end;
        Tip := Center - U*(0.41*Size) - W*(0.48*Size);
        SoftDisc(Mesh,Tip,U,W,Size*0.21,0.55,Paint($FFFFFF,Material.Alpha,3));
      end;
  end;
end;

procedure Streamers(Mesh: TGiftMesh; const S: TGiftSettings; Progress: Double);
var
  I, J, Count: Integer;
  Start, Q, A, Speed, Lift, Head, Tail, T, Ripple, Width, Fade: Double;
  Direction, Side, Across: TVec;
  Path: array[0..14] of TVec;
begin
  Count := Max(1,Round(18*S.Amount));
  for I := 0 to Count-1 do
  begin
    Start := 0;
    if I > 0 then Start := 0.19*GiftRandom(I,2);
    Q := (Progress-Start)/(1-Start);
    if Q < 0 then Continue;
    A := 2*Pi*(I+0.7*GiftRandom(I,1))/Count;
    Speed := S.Range*(1.2+1.48*GiftRandom(I,3));
    Lift := S.Range*(2.8+1.46*GiftRandom(I,5));
    Direction := V(Cos(A),0,0.65*Sin(A));
    Side := V(-Sin(A),0,0.65*Cos(A));
    Width := 0.016+0.018*GiftRandom(I,4);
    Across := UnitVector(Cross(Direction,V(0,-0.85,0.4)))*Width;
    Head := Q+0.012;
    // 先端が飛んだ軌道を帯が追い、伸び切った後は末端も飛び出す。
    Tail := Max(0.0,Head-0.43);
    for J := 0 to High(Path) do
    begin
      T := Mix(Tail,Head,J/High(Path));
      Ripple := 0.10*Sin(39*T+A)*Smooth(T/0.23);
      Path[J] := V(0,-0.10-Lift*T+3.05*S.Range*Sqr(T),0.16)+
        Direction*(Speed*(1-Exp(-1.6*T)))+Side*Ripple;
    end;
    Fade := 1-Smooth((Q-0.57)/0.43);
    Mesh.Strip(Path,Across,0.009,Paint(EffectColor(S,I),Fade,0));
  end;
end;

procedure LightBurst(Mesh: TGiftMesh; const S: TGiftSettings; Progress: Double);
var
  I, Count: Integer;
  Angle, Radius, Width, Length, Fade: Double;
  Root, Dir, Across, Core, Tip: TVec;
  Material: TPaint;
  Rising: Boolean;
begin
  Rising := S.Effect = geInnerGlow;
  Fade := (0.5+0.5*Smooth(Progress/0.18))*(1-Smooth((Progress-0.50)/0.50))*
    (0.40+0.60*Min(1.0,S.Amount));
  Radius := (1.08+1.84*Smooth(Progress))*S.Range;
  Root := V(0,0,0);
  if Rising then
  begin
    Root := V(0,0.36,0);
    Count := Max(2,Round(13*S.Amount));
    SoftDisc(Mesh,Root+V(0,-0.20*Radius,0),V(1,0,0),V(0,1,0),0.53*Radius,1.55,
      Paint(EffectColor(S,0),0.47*Fade,3));
  end else
  begin
    Count := Max(3,Round(19*S.Amount));
    SoftDisc(Mesh,Root,V(1,0,0),V(0,1,0),0.61*Radius,1,
      Paint(EffectColor(S,0),0.34*Fade,3));
  end;
  for I := 0 to Count-1 do
  begin
    Angle := (I+GiftRandom(I,4)*0.65)*2*Pi/Count+0.31*Progress;
    if Rising then Angle := -Pi/2+((I+0.7*GiftRandom(I,4))/Count-0.5)*2.32;
    Dir := V(Cos(Angle),Sin(Angle),0);
    Length := Radius*(0.62+0.38*GiftRandom(I,2));
    Width := Length*(0.071+0.081*GiftRandom(I,5));
    Across := V(-Dir.Y,Dir.X,0)*Width;
    Core := Root+Dir*(Length*0.46);
    Tip := Root+Dir*Length;
    Material := Paint(EffectColor(S,I),Fade*(0.33+0.34*GiftRandom(I,1)),3);
    Mesh.SoftTri(Root,Core-Across,Core,Material,0.18,0,1);
    Mesh.SoftTri(Root,Core,Core+Across,Material,0.18,1,0);
    Mesh.SoftTri(Core,Core-Across,Tip,Material,1,0,0);
    Mesh.SoftTri(Core,Tip,Core+Across,Material,1,0,0);
  end;
end;

procedure Fireworks(Mesh: TGiftMesh; const S: TGiftSettings; const Time: TGiftTime);
var
  Burst, I, Count: Integer;
  P, Stagger, A, Radius, Z, Fade, Distance: Double;
  Origin, Dir, Head, Tail, Across: TVec;
  Material, Spark: TPaint;
begin
  Count := Max(3,Round(38*S.Amount));
  for Burst := 0 to 2 do
  begin
    Stagger := Burst*0.16;
    P := (Time.EffectProgress-Stagger)/(1-Stagger);
    if P < 0 then Continue;
    Origin := V((1-Burst)*1.22*S.Range,(-0.63-0.56*GiftRandom(Burst,8))*S.Range,0.10+0.22*Burst);
    Radius := (0.21+1.62*(1-Sqr(1-P)))*S.Range;
    for I := 0 to Count-1 do
    begin
      A := 2*Pi*(I+0.30*GiftRandom(I,Burst))/Count;
      Z := 2*GiftRandom(I,8+Burst)-1;
      Dir := V(Cos(A)*Sqrt(1-Z*Z),Sin(A)*Sqrt(1-Z*Z),Z);
      Distance := Radius*(0.69+0.31*GiftRandom(I,11));
      Head := Origin+Dir*Distance+V(0,0.64*S.Range*Sqr(P),0);
      Tail := Head-Dir*Min(Distance,S.Range*(0.18+0.47*(1-P)));
      Across := UnitVector(Cross(Dir,V(0,0,1)))*(0.025+0.024*(1-P));
      Fade := (1-Smooth((P-0.60)/0.40))*(0.88+0.12*Sin(I+P*31));
      Material := Paint(EffectColor(S,Burst*2+1),Fade,3);
      Mesh.SoftTri(Tail,Head-Across,Head,Material,0,0,1);
      Mesh.SoftTri(Tail,Head,Head+Across,Material,0,1,0);
      if I mod 2 = 0 then
      begin
        Spark := Material;
        if S.AutoColor then Spark.Color := $FFEDC8;
        ParticleShape(Mesh,geSparkles,Head,V(0,0,A),0.057+0.033*(1-P),Spark);
      end;
    end;
  end;
end;

procedure BuildGiftEffect(Mesh: TGiftMesh; const S: TGiftSettings; const Time: TGiftTime);
var
  I, Count, Density: Integer;
  Q, Age, Start, A, Speed, Size, Fade, Drag, Rise, Z: Double;
  Origin, Angles: TVec;
  Material: TPaint;
begin
  if not Time.EffectActive then Exit;
  case S.Effect of
    geStreamers: begin Streamers(Mesh,S,Time.EffectProgress); Exit; end;
    geRays, geInnerGlow: begin LightBurst(Mesh,S,Time.EffectProgress); Exit; end;
    geFireworks: begin Fireworks(Mesh,S,Time); Exit; end;
  end;
  case S.Effect of
    geConfetti: Density := 65;
    geSparkles: Density := 39;
    geSmoke, geBubbles: Density := 17;
  else
    Density := 31;
  end;
  Count := Max(1,Round(Density*S.Amount));
  for I := 0 to Count-1 do
  begin
    Start := 0;
    if I > 0 then Start := 0.17*GiftRandom(I,2);
    Q := (Time.EffectProgress-Start)/(1-Start);
    if (Q < 0) or (Q >= 1) then Continue;
    Age := Time.EffectAge-Start*S.EffectSeconds;
    A := 2*Pi*GiftRandom(I,1);
    Speed := S.Range*(0.63 + 1.16*GiftRandom(I,3));
    Drag := 1-Exp(-3.0*(Q+0.006));
    Z := Sin(A)*Speed*Drag*1.30 + 0.19;
    Rise := -Speed*(1.48*Q-0.88*Q*Q)-0.12;
    Fade := 1-Smooth((Q-0.60)/0.40);
    Size := 0.032+0.058*GiftRandom(I,4);
    Angles := V(GiftRandom(I,5)*6+Age*3.8,GiftRandom(I,6)*6+Age*5.3,A+Age*6.8);
    Origin := V(Cos(A)*Speed*Drag,Rise,Z);
    case S.Effect of
      geConfetti:
        Origin.Y := Origin.Y + 0.89*Q*Q + 0.13*Sin(A+4*Q);
      geStars, geHearts, gePetals:
        begin
          Size := Size*1.52;
          Angles.X := 0.54*Sin(A+Age*3.0);
          Angles.Y := 0.64*Cos(A+Age*3.5);
          Angles.Z := 0.70*Sin(A+Age*2.4);
          if S.Effect = gePetals then Origin.Y := Origin.Y+0.84*Q*Q;
        end;
      geSparkles:
        begin
          Size := Size*(0.45+1.05*Sqr(Sin(4*Pi*Q+A)));
          Fade := Fade*Abs(Sin(6*Pi*Q+A));
        end;
      geSmoke, geBubbles:
        begin
          Origin := V(Origin.X*0.61+0.14*Sin(A+Age*2.1),-Speed*Q*0.91-0.04,Origin.Z*0.62);
          Angles := V(0.16*Sin(A+Age),0.43*Sin(A+Age*2.6),A+Age);
          if S.Effect = geSmoke then
          begin
            Size := Size*(2.2+4.3*Q);
            Fade := Fade*0.43;
          end else Size := Size*(1.3+0.46*Q);
        end;
    end;
    Material := Paint(EffectColor(S,I),Fade,Ord(S.Effect in [geSparkles, geSmoke, geBubbles])*3);
    ParticleShape(Mesh,S.Effect,Origin,Angles,Size,Material);
  end;
end;

end.
