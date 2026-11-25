# SYNC_GiftOpen の作業規則

- 作業開始時に `note.md` を読む。仕様は `docs/SPECIFICATION.md`、操作は `README.md` を参照する。
- 本番は `SYNC_GiftOpen.dproj` と `SYNC_GiftOpen.auf2` の1つ。検査用 EXE から同じ AUF2 を読み込む。
- Delphi 37.0 の `rsvars.bat` を読み込んで Win64 Debug / Release をビルドする。警告・エラーと AUF2 の更新を確認する。
- ビルド構成、ビルドイベント、デバッガー設定は継承元に合わせる。出力フォルダーは GiftOpen 専用。IDE と AviUtl2 の起動・操作はユーザーの明示依頼がある場合に行う。
- ユニット追加時は `.dpr` の `in` と `.dproj` の `DCCReference` を両方更新する。日本語を含む `.pas`、`.dpr`、`.ps1` は UTF-8 BOM 付き、CRLF とする。
- ユニット先頭に責務を記載する。ホスト所有のポインターはコールバック内で使い、Delphi 例外は DLL 境界から漏らさない。SDK の型や配置を変更する場合はヘッダーと照合する。
- コピー元のプロジェクト、ユーザーの AUP2、他のプラグインを変更しない。`Setup` の ZIP とカタログは GiftOpen の配布用。カタログのバージョンとハッシュは公開資産に対応させる。
