# Tweak Settings
A dedicated settings app for tweak preferences

![preview](Resources/icon_large.png)

## Rootless compatibility build (1.0.9)

対象: **iOS 17.3 / arm64e / Dopamine / ElleKit / rootless**。
アプリとヘルパーはarm64＋arm64e、最低OSはiOS 15.0です。

ビルド・回帰テスト・deb検査を行っています。**iOS 17.3実機での動作確認は未実施**です。
変更内容・既知の制限・実機確認手順は [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) を参照してください。

macOS、選択済みのXcode、最新のTheos（librootを含む）、ldidが必要です。

```sh
export THEOS=/path/to/theos
./Tests/run.sh
./build.sh
python3 Tests/validate_package.py
```

生成物: `Releases/com.creaturecoding.tweaksettings_1.0.9_iphoneos-arm64.deb`

脱獄済み端末へ転送し、Sileoなどのパッケージマネージャーでインストールしてください。
設定を表示する各Tweakと依存ライブラリにも、対象OS・rootlessへの対応が必要です。

# Author

Dana Buehre (CreatureSurvive)
[cs@creaturecoding.com](mailto:cs@creaturecoding.com)

© Dana Buehre (CreatureSurvive) 2021
