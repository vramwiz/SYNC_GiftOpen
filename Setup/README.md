# SYNC_GiftOpen の配布 ZIP

`make_release_zip.bat` は検証済みの `SYNC_GiftOpen.auf2` を `SYNC_GiftOpen.zip` へ梱包し、同じ AUF2 の XXH3-128 を `SYNC_GiftOpen.catalog.json` に設定します。

## ZIP の作成

既定では `Win64\Release\SYNC_GiftOpen.auf2` を使用します。ハッシュの計算には [xxHash 公式 Windows 版](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4) の `xxhsum.exe` を使い、`Win64\Dependencies\xxHash-0.8.4` または PATH から探します。

```bat
Setup\make_release_zip.bat
```

AUF2 とハッシュ計算ツールの場所を指定する場合は、`-ReleaseDirectory` と `-XxhsumPath` を渡します。

## ZIP の内容

```text
SYNC_GiftOpen/
  SYNC_GiftOpen.auf2
  README.md
  LICENSE
  THIRD_PARTY_NOTICES.md
  ThirdParty/
    LICENSE.AviUtl2-SDK.txt
```

初回の公開タグは `v1.0.0` です。README のプレビューは同じタグの画像を参照します。GitHub リリースに ZIP とカタログ JSON を添付します。
