library SYNC_GiftOpen;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only

// プレゼント開封の AviUtl2 DLL 境界。登録と終了の入口を公開する。
// Delphi 例外は C コールバックの外へ漏らさない。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  GiftOpen_Settings in 'Source\Common\GiftOpen_Settings.pas',
  GiftOpen_Mesh in 'Source\Common\GiftOpen_Mesh.pas',
  GiftOpen_Packages in 'Source\Common\GiftOpen_Packages.pas',
  GiftOpen_Wraps in 'Source\Common\GiftOpen_Wraps.pas',
  GiftOpen_Effects in 'Source\Common\GiftOpen_Effects.pas',
  GiftOpen_Renderer in 'Source\Common\GiftOpen_Renderer.pas',
  SYNC_GiftOpen_Plugin in 'Source\Plugin\Filter\SYNC_GiftOpen_Plugin.pas';

{$R *.res}

// ホストのバージョンを確認し、DLL 所有の登録テーブルを初期化する。
// 非対応バージョンと初期化失敗は 0 を返す。
function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    if Version < GIFTOPEN_REQUIRED_VERSION then Exit;
    InitializeGiftOpen(Version);
    Result := 1;
  except
    // 初期化失敗は戻り値でホストへ伝える。
  end;
end;

// 描画資源はホストのfunc_destroyでエフェクトごとに解放する。
procedure UninitializePlugin; cdecl;
begin
end;

// 公式 SDK 形式の最低対応バージョン番号を返す。
function RequiredVersion: Cardinal; cdecl;
begin
  Result := GIFTOPEN_REQUIRED_VERSION;
end;

// DLL 所有の登録テーブルを返す。取得失敗時は nil を返す。
function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetGiftOpenTable;
  except
    // 登録失敗時はテーブルを返さずホスト側へ判断を委ねる。
  end;
end;

exports
  RequiredVersion name 'RequiredVersion',
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
