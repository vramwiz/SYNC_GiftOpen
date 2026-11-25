# SYNC_GiftOpen 作業ノート

## 構成

- プロジェクトは `SYNC_GiftOpen.dproj`。AviUtl2 の「メディアオブジェクトを追加」から「プレゼント開封」を配置する。グループは SYNC。
- SYNC_WeatherFX の Delphi プロジェクト構成・SDK 定義・登録処理・ライセンスを継承。新しいプロジェクト GUID、ソース参照、出力先を設定した。
- `Setup` は SYNC_WeatherFX から継承し、初回正式版 v1.0.0 に合わせて GiftOpen 向けに更新した。バッチはプロジェクト内の Release AUF2 を優先参照先にし、配布 ZIP と実物の XXH3-128 を持つカタログを生成する。
- AviUtl2 SDK は 2.1.15 と 2.1.17 のヘッダーを照合した。Delphi の実行時判定で 2.1.16 から登録でき、2.1.17 のカメラ照会関数は対応版で使う。[AviUtl ExEdit2 Plugin SDK](https://spring-fragrance.mints.ne.jp/aviutl/)

## ビルド

Delphi 37.0 / Win64。プロジェクトルートの PowerShell で実行する。

```powershell
New-Item -ItemType Directory -Force 'C:\ProgramData\aviutl2\Plugin\SYNC_GiftOpen' | Out-Null
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_GiftOpen.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_GiftOpen.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64'
```

- Win64 Debug / Release のコンパイラ設定、DLL を AUF2 に変換するビルド後イベント、デバッガーホストは WeatherFX の設定を使用する。
- 最終出力は両構成共通の `C:\ProgramData\aviutl2\Plugin\SYNC_GiftOpen\SYNC_GiftOpen.auf2`。最後に実行した構成で上書きされる。DCU は構成ごとに `Win64\Debug\DCU` と `Win64\Release\DCU` に出力する。
- AviUtl2 の起動中に AUF2 が使用中の場合は、MSBuild 実行時に `/p:DCC_ExeOutput=.\Win64\Debug\` または `/p:DCC_ExeOutput=.\Win64\Release\` を加えると、プロジェクト内に検査用の AUF2 を出力できる。
- ソース追加時は `.dpr` の `in` と `.dproj` の `DCCReference` を両方更新する。日本語を含む Pascal・PowerShell ソースは UTF-8 BOM と CRLF を使う。
- コンパイル、IDE 読み込み、AviUtl2 上の表示は別々に確認する。通常のビルドでは IDE と AviUtl2 を起動しない。

## 描画と時間

- `GiftOpen_Settings` はトラック値の範囲と秒単位の時間評価。`GiftOpen_Mesh` は立体面と材質。`GiftOpen_Packages` と `GiftOpen_Wraps` は包装の形状と開封。`GiftOpen_Effects` は固定乱数を用いた演出。
- `SYNC_GiftOpen_Plugin` は SDK 登録とインスタンスの寿命を管理。`GiftOpen_Renderer` は PianoRoll と同様に最小の白画像を登録し、`DrawPoly` にローカル頂点を送る。ブレンドや深度を担う Direct3D デバイスは AviUtl2 が所有する。
- 画像は `image:` リソースを使い、アスペクト比を維持して各包装に収める。閉・開の前後で画像頂点は共通。パスが空か読めないときは包装と演出を描画する。
- 包装と演出の相対 XYZ と拡大率を、それぞれの出力頂点と透過面の整列に適用する。画像はオブジェクト内の元の座標を使う。
- 画像の設定項目は「画像ファイル」。
- 包装メッシュと描画バッファはエフェクトインスタンスごとに再利用する。ホストのテクスチャ、カメラ、編集のポインターはコールバックの間だけ使用する。
- カメラ制御ではホストの深度を使用する。透過ポリゴンと画像の描画順は、取得できるカメラの視線方向、グループ行列、標準描画の回転・拡大から補う。カメラ制御の対象外では通常視点から奥行き順に送る。編集用視点やカメラスクリプトの最終視点は SDK コールバックで取得できる範囲に制約がある。
- 「包装紙付きプレゼント箱」はホストの深度を使わないとき、包装紙の面を基準に奥から並べる。箱の大きな面が手前の柄を上書きするのを防ぐ。
- 包装スタイルは14種類。バスケットは上部が開いており、開封時間に合わせて持ち手と一緒に下がる。
- 紙テープは飛んだ軌道を帯が追う。放射光と光の噴出はプレゼント画像の背後に描き、花火とともに光源の影響を受けない頂点色で加算合成する。

## 検査

コンパイルログは `Win64\BuildLogs`。本番 AUF2 を `Win64\Verification\GiftOpen_HostCheck.exe` へ渡し、AviUtl2 を代行するコールバックで検査する。Debug / Release のそれぞれで、登録と初期値、全包装と演出、画像の前後関係、シーク再現性、透過、0 秒動作、カメラ ABI の分岐を確認する。
包装・演出それぞれの変換、Z 移動による描画順、包装紙の柄の描画順、画像設定の登録と画像頂点の独立性も同じ検査で確認する。
紙テープの伸びとフェード、放射光と光の噴出の画像との前後関係、花火の終盤の明るさと加算合成も確認する。

```powershell
dcc64 -B '-EWin64\Verification' '-NUWin64\Verification' 'Tests\GiftOpen_HostCheck.dpr'
.\Win64\Verification\GiftOpen_HostCheck.exe 'C:\ProgramData\aviutl2\Plugin\SYNC_GiftOpen\SYNC_GiftOpen.auf2'
```

`Win64\Verification\GeometryPreview.png` は実際の送出頂点を検査用ラスタライザーで描いた画像。ホスト内の描画・光源・透過合成の目視確認は未実施。
