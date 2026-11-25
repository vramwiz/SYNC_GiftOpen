# ライセンスと共通基盤の由来

プレゼント開封（SYNC_GiftOpen）。Copyright (c) 2026 VRAMの魔術師。

本体は GNU General Public License v3.0（GPL-3.0-only）で、全文は [LICENSE](LICENSE) にあります。Delphi RTL を使用します。

- AviUtl ExEdit2 Plugin SDK の定義は Copyright (c) 2025 Kenkun、MIT ライセンスです。Delphi 側の SDK 型は `Source/Lib/AviUtl2FilterTypes.pas`、ライセンス全文は [ThirdParty/LICENSE.AviUtl2-SDK.txt](ThirdParty/LICENSE.AviUtl2-SDK.txt) にあります。
- SYNC_WeatherFX から Delphi のプロジェクト構成とビルドイベント、SDK 定義、登録ヘルパーを継承しました。登録ヘルパーの共通基盤は SYNC_AquaFX、SYNC_ParticleFX、SYNC_Mine を経て Syncroh2 / SYNC_Lyrics に由来します。
- SYNC_PianoRoll のメディアオブジェクト登録と `DrawPoly` による立体描画手順を参照しました。
