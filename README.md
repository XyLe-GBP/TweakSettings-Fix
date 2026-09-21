# TweakSettings

Tweak の設定をまとめて開ける専用アプリです。
[CreatureSurvive/TweakSettings](https://github.com/CreatureSurvive/TweakSettings) をもとに、iOS 17 の rootless 環境向けに修正しています。

![preview](Resources/icon_large.png)

## 動作確認済みの環境

**バージョン 1.0.9** は、以下の実機環境で動作確認済みです。インストール後、ホーム画面から正常に起動することを確認しています。

| 項目 | 環境 |
| --- | --- |
| 端末 | iPhone 15 Pro Max |
| iOS | 17.3 |
| アーキテクチャ | arm64e |
| 脱獄 | Dopamine 3.0.9 |
| Tweak 注入 | ElleKit |
| 構成 | rootless |

起動時のクラッシュを修正したほか、設定一覧や検索、rootless のパス処理、再起動などの操作を見直しています。詳しい変更内容は [互換性と修正内容](docs/COMPATIBILITY.md) を参照してください。

## ビルドとインストール

macOS、Xcode、libroot を含む Theos、ldid、Python 3 が必要です。使用する Xcode を `xcode-select` で選択してから実行してください。

```sh
export THEOS=/path/to/theos
./Tests/run.sh
./build.sh
python3 Tests/validate_package.py
```

生成されるパッケージ:

```text
Releases/com.creaturecoding.tweaksettings_1.0.9_iphoneos-arm64.deb
```

アプリとヘルパーには `arm64` と `arm64e` の両方を含みます。ビルド上の最低 OS バージョンは iOS 15.0 です。

生成した `.deb` を脱獄済み端末に転送し、Sileo などのパッケージマネージャーでインストールしてください。各 Tweak とその依存ライブラリも、使用する iOS と rootless に対応している必要があります。

## オリジナルの作者

Dana Buehre (CreatureSurvive)
[cs@creaturecoding.com](mailto:cs@creaturecoding.com)

© Dana Buehre (CreatureSurvive) 2021
