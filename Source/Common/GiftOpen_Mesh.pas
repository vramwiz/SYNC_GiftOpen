unit GiftOpen_Mesh;

// 立体の包装と演出で使う面・押し出し・曲面を生成する。
// 形状は半幅・半高・半奥行きを1とする座標で記述する。Yの正方向は下。
interface

uses System.Generics.Collections;

type
  TVec = record
    X, Y, Z: Double;
    class operator Add(const A, B: TVec): TVec;
    class operator Subtract(const A, B: TVec): TVec;
    class operator Multiply(const A: TVec; B: Double): TVec;
  end;

  TPaint = record
    Color: Cardinal;
    Alpha, Tone: Single;
    Finish: Byte; // 0: 紙、1: 布・塗装、2: 金属・フィルム、3: 発光
  end;

  TFace = record
    P: array[0..3] of TVec;
    Normal: TVec;
    Weight: array[0..3] of Single;
    Paint: TPaint;
    Textured: Boolean;
  end;

  TRing = record
    Y, RX, RZ, X, Z: Double;
  end;

  TGiftMesh = class
  private
    FScale: TVec;
    FFaces: TList<TFace>;
    function Position(const Point: TVec): TVec;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const Dimensions: TVec);
    procedure Truncate(Count: Integer);
    procedure Quad(const A, B, C, D: TVec; const Material: TPaint; Textured: Boolean = False);
    procedure Tri(const A, B, C: TVec; const Material: TPaint);
    procedure SoftTri(const A, B, C: TVec; const Material: TPaint; WeightA, WeightB, WeightC: Single);
    procedure Plate(const A, B, C, D, Thickness: TVec; const Outer, Inner: TPaint);
    procedure Box(const Lo, Hi: TVec; const Material: TPaint);
    procedure Strip(const Path: array of TVec; const Across: TVec;
      Thickness: Double; const Material: TPaint);
    procedure Cord(const Path: array of TVec; Radius: Double; const Material: TPaint);
    property Faces: TList<TFace> read FFaces;
  end;

function V(X, Y, Z: Double): TVec;
function Dot(const A, B: TVec): Double;
function Cross(const A, B: TVec): TVec;
function UnitVector(const A: TVec): TVec;
function RotateX(const A: TVec; Angle: Double): TVec;
function RotateY(const A: TVec; Angle: Double): TVec;
function RotateZ(const A: TVec; Angle: Double): TVec;
function Paint(Color: Cardinal; Alpha: Double = 1; Finish: Byte = 0): TPaint;
function Shade(const Material: TPaint; Tone: Double): TPaint;
function Ring(Y, RX, RZ: Double; X: Double = 0; Z: Double = 0): TRing;
function RingPoint(const R: TRing; Angle: Double; Fold: Double = 0): TVec;

implementation

uses System.Math;

function V(X, Y, Z: Double): TVec;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
end;

class operator TVec.Add(const A, B: TVec): TVec;
begin
  Result := V(A.X+B.X, A.Y+B.Y, A.Z+B.Z);
end;

class operator TVec.Subtract(const A, B: TVec): TVec;
begin
  Result := V(A.X-B.X, A.Y-B.Y, A.Z-B.Z);
end;

class operator TVec.Multiply(const A: TVec; B: Double): TVec;
begin
  Result := V(A.X*B, A.Y*B, A.Z*B);
end;

function Dot(const A, B: TVec): Double;
begin
  Result := A.X*B.X + A.Y*B.Y + A.Z*B.Z;
end;

function Cross(const A, B: TVec): TVec;
begin
  Result := V(A.Y*B.Z-A.Z*B.Y, A.Z*B.X-A.X*B.Z, A.X*B.Y-A.Y*B.X);
end;

function UnitVector(const A: TVec): TVec;
var
  Len: Double;
begin
  Len := Sqrt(Dot(A,A));
  if Len < 1E-9 then Exit(V(0,0,0));
  Result := A * (1/Len);
end;

function RotateX(const A: TVec; Angle: Double): TVec;
var S, C: Double;
begin
  SinCos(Angle,S,C);
  Result := V(A.X,A.Y*C-A.Z*S,A.Y*S+A.Z*C);
end;

function RotateY(const A: TVec; Angle: Double): TVec;
var S, C: Double;
begin
  SinCos(Angle,S,C);
  Result := V(A.X*C+A.Z*S,A.Y,-A.X*S+A.Z*C);
end;

function RotateZ(const A: TVec; Angle: Double): TVec;
var S, C: Double;
begin
  SinCos(Angle,S,C);
  Result := V(A.X*C-A.Y*S,A.X*S+A.Y*C,A.Z);
end;

function Paint(Color: Cardinal; Alpha: Double; Finish: Byte): TPaint;
begin
  Result.Color := Color;
  Result.Alpha := Alpha;
  Result.Tone := 1;
  Result.Finish := Finish;
end;

function Shade(const Material: TPaint; Tone: Double): TPaint;
begin
  Result := Material;
  Result.Tone := Material.Tone*Tone;
end;

function Ring(Y, RX, RZ, X, Z: Double): TRing;
begin
  Result.Y := Y;
  Result.RX := RX;
  Result.RZ := RZ;
  Result.X := X;
  Result.Z := Z;
end;

function RingPoint(const R: TRing; Angle, Fold: Double): TVec;
var S, C, Wrinkle: Double;
begin
  SinCos(Angle,S,C);
  Wrinkle := 1 + Fold*Cos(Angle*8) + Fold*0.32*Sin(Angle*13);
  Result := V(R.X+R.RX*C*Wrinkle,R.Y,R.Z+R.RZ*S*Wrinkle);
end;

constructor TGiftMesh.Create;
begin
  inherited;
  FFaces := TList<TFace>.Create;
  FFaces.Capacity := 2048;
end;

destructor TGiftMesh.Destroy;
begin
  FFaces.Free;
  inherited;
end;

procedure TGiftMesh.Start(const Dimensions: TVec);
begin
  FScale := Dimensions;
  FFaces.Clear;
end;

procedure TGiftMesh.Truncate(Count: Integer);
begin
  FFaces.Count := Count;
end;

function TGiftMesh.Position(const Point: TVec): TVec;
begin
  Result := V(Point.X*FScale.X,Point.Y*FScale.Y,Point.Z*FScale.Z);
end;

procedure TGiftMesh.Quad(const A, B, C, D: TVec; const Material: TPaint; Textured: Boolean);
var
  Face: TFace;
begin
  if Material.Alpha <= 0 then Exit;
  Face.P[0] := Position(A);
  Face.P[1] := Position(B);
  Face.P[2] := Position(C);
  Face.P[3] := Position(D);
  Face.Normal := UnitVector(Cross(Face.P[1]-Face.P[0],Face.P[2]-Face.P[0]) +
    Cross(Face.P[2]-Face.P[0],Face.P[3]-Face.P[0]));
  if Dot(Face.Normal,Face.Normal) = 0 then Exit;
  Face.Weight[0] := 1;
  Face.Weight[1] := 1;
  Face.Weight[2] := 1;
  Face.Weight[3] := 1;
  Face.Paint := Material;
  Face.Textured := Textured;
  FFaces.Add(Face);
end;

procedure TGiftMesh.Tri(const A, B, C: TVec; const Material: TPaint);
begin
  Quad(A,B,C,C,Material);
end;

procedure TGiftMesh.SoftTri(const A, B, C: TVec; const Material: TPaint;
  WeightA, WeightB, WeightC: Single);
var Index: Integer; Face: TFace;
begin
  Index := FFaces.Count;
  Tri(A,B,C,Material);
  if FFaces.Count = Index then Exit;
  Face := FFaces[Index];
  Face.Weight[0] := WeightA;
  Face.Weight[1] := WeightB;
  Face.Weight[2] := WeightC;
  Face.Weight[3] := WeightC;
  FFaces[Index] := Face;
end;

procedure TGiftMesh.Plate(const A, B, C, D, Thickness: TVec; const Outer, Inner: TPaint);
var A2, B2, C2, D2: TVec;
begin
  A2 := A+Thickness;
  B2 := B+Thickness;
  C2 := C+Thickness;
  D2 := D+Thickness;
  Quad(A,B,C,D,Outer);
  Quad(D2,C2,B2,A2,Inner);
  Quad(A,A2,B2,B,Inner);
  Quad(B,B2,C2,C,Inner);
  Quad(C,C2,D2,D,Inner);
  Quad(D,D2,A2,A,Inner);
end;

procedure TGiftMesh.Box(const Lo, Hi: TVec; const Material: TPaint);
begin
  Plate(V(Lo.X,Lo.Y,Lo.Z),V(Lo.X,Hi.Y,Lo.Z),V(Hi.X,Hi.Y,Lo.Z),
    V(Hi.X,Lo.Y,Lo.Z),V(0,0,Hi.Z-Lo.Z),Material,Material);
end;

procedure TGiftMesh.Strip(const Path: array of TVec; const Across: TVec;
  Thickness: Double; const Material: TPaint);
var
  I: Integer;
  A, B, EdgeA, EdgeB, FromPoint, ToPoint: TVec;
begin
  if (Length(Path) < 2) or (Material.Alpha <= 0) then Exit;
  A := Path[0]-Across;
  B := Path[0]+Across;
  EdgeA := UnitVector(Cross(Across,Path[1]-Path[0]))*Thickness;
  Quad(B,A,A+EdgeA,B+EdgeA,Shade(Material,0.88));
  for I := 1 to High(Path) do
  begin
    FromPoint := Path[I-1];
    ToPoint := Path[I];
    if I < High(Path) then ToPoint := Path[I+1];
    EdgeB := UnitVector(Cross(Across,ToPoint-FromPoint))*Thickness;
    Quad(A,B,Path[I]+Across,Path[I]-Across,Material);
    Quad(B+EdgeA,A+EdgeA,Path[I]-Across+EdgeB,Path[I]+Across+EdgeB,Shade(Material,0.86));
    Quad(A,Path[I]-Across,Path[I]-Across+EdgeB,A+EdgeA,Shade(Material,1.16));
    Quad(B+EdgeA,Path[I]+Across+EdgeB,Path[I]+Across,B,Shade(Material,1.07));
    A := Path[I]-Across;
    B := Path[I]+Across;
    EdgeA := EdgeB;
  end;
  Quad(A,B,B+EdgeA,A+EdgeA,Shade(Material,0.88));
end;

procedure TGiftMesh.Cord(const Path: array of TVec; Radius: Double; const Material: TPaint);
const Sides = 7;
var
  I, J, Next: Integer;
  Axis, U, W, Ref, A, B: TVec;
  Prev, Curr: array[0..Sides-1] of TVec;
  S, C: Double;
begin
  if (Length(Path) < 2) or (Material.Alpha <= 0) then Exit;
  Ref := V(0,0,1);
  if Abs(Dot(UnitVector(Path[High(Path)]-Path[0]),Ref)) > 0.85 then Ref := V(0,1,0);
  for I := 0 to High(Path) do
  begin
    A := Path[Max(0,I-1)];
    B := Path[Min(High(Path),I+1)];
    Axis := UnitVector(B-A);
    U := UnitVector(Cross(Axis,Ref));
    if Dot(U,U) < 0.01 then U := UnitVector(Cross(Axis,V(1,0,0)));
    W := Cross(Axis,U);
    for J := 0 to Sides-1 do
    begin
      SinCos(J*2*Pi/Sides,S,C);
      Curr[J] := Path[I] + U*(Radius*C) + W*(Radius*S);
    end;
    if I > 0 then
      for J := 0 to Sides-1 do
      begin
        Next := (J+1) mod Sides;
        Quad(Prev[Next],Prev[J],Curr[J],Curr[Next],Material);
      end;
    if (I = 0) or (I = High(Path)) then
      for J := 0 to Sides-1 do
      begin
        Next := (J+1) mod Sides;
        if I = 0 then Tri(Path[I],Curr[Next],Curr[J],Material)
        else Tri(Path[I],Curr[J],Curr[Next],Material);
      end;
    Prev := Curr;
  end;
end;

end.
