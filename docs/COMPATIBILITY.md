# TweakSettings 1.0.9 の互換性と修正内容

## 動作確認済みの環境

以下の実機環境で、インストール後にホーム画面から正常に起動することを確認しています。

| 項目 | 環境 |
| --- | --- |
| 端末 | iPhone 15 Pro Max |
| iOS | 17.3 |
| アーキテクチャ | arm64e |
| 脱獄 | Dopamine 3.0.9 |
| Tweak 注入 | ElleKit |
| 構成 | rootless |

パッケージのアーキテクチャは `iphoneos-arm64` です。アプリとヘルパーには `arm64` と `arm64e` を含み、ビルド上の最低 OS バージョンは iOS 15.0 に設定しています。

## 起動時のクラッシュ修正

アイコンを押した直後にアプリが終了する問題を修正しました。

原因となっていたのは、`PSListController` に対する `tableView` の呼び出しです。iOS 17 の `PSListController` では、テーブルの取得に `table` を使います。起動時の初期化に加え、検索や長押し処理でも呼び出しを `self.table` に統一しました。

同梱ヘッダーからも誤った `tableView` 宣言を削除し、`table` を読み取り専用として宣言しています。修正内容は [iOS 17 のランタイムヘッダー](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/Preferences.framework/PSListController.h) と照合しました。

## その他の修正

アプリとヘルパーのソースに加え、ビルド設定、インストール・削除スクリプト、権限設定、ローカライズ、同梱の Preferences ヘッダーとリンク用スタブを見直しています。

### rootless 対応とビルド

- Xcode と SDK のバージョン固定を外し、選択中の Xcode を使うようにしました。ビルドスクリプトから `xcode-select` の設定を変更する処理も削除しています。
- rootless と現在の arm64e ABI に合わせてビルド設定を統一しました。
- 脱獄環境のパスは libroot で解決します。Apple のシステム設定バンドルには rootless のパス変換を適用しません。
- `UIApplication` とアプリのデリゲートを分離し、libprefs の読み込みに失敗した場合はログを残すようにしました。

### 設定一覧・検索・画面遷移

- 設定データの型、CFVersion の範囲、項目 ID をチェックし、不正なデータで処理が止まる問題を修正しました。設定を読み込む処理の関数ポインタと、コントローラの保持方法も見直しています。
- 非同期検索で古い結果が新しい結果を上書きする問題を修正しました。一覧を更新した後も検索条件を維持します。
- URL と Spotlight から設定を開く処理を修正しました。ID に日本語や `/`、`%` が含まれる場合も扱えます。起動中に受け取った URL は初期化後に処理し、検索で非表示になっている項目も開けるようにしました。
- 空のナビゲーションスタックができる問題と、iPad の分割表示を切り替えた際のコントローラ管理を修正しました。設定バンドルの読み込みに失敗した場合はエラーを表示します。

### 再起動などの操作とヘルパー

- シェル経由のコマンド実行をやめ、決められた引数でヘルパーを直接起動するようにしました。処理中も画面操作を妨げず、失敗した場合はエラーを表示します。
- Dopamine の respring と userspace reboot には `jbctl` を使います。Tweak 注入の切り替えは `.safe_mode` を変更してから userspace reboot を実行します。
- Dopamine では ldrestart を表示しません。環境に必要なコマンドがない操作も非表示にしています。
- ヘルパーは呼び出し元のパス、所有者、書き込み権限、実行時の資格情報を確認します。子プロセスの起動失敗と終了コードの扱いも修正しました。

### パッケージ・更新確認

- ヘルパーの所有者と権限を `root:wheel`、`4755` に修正しました。アプリの実行ファイルは `0755` です。
- インストール時のアイコン登録処理を修正し、削除時の登録解除も追加しました。
- 更新確認で HTTP レスポンスと JSON の形式を確認するようにしました。バージョンは数値で比較し、古い上流版を更新として案内しません。
- 変更履歴の読み込みに失敗した際、読み込み表示が消えない問題を修正しました。通信セッションと設定変更通知の処理も見直しています。

## ビルドとテスト

macOS 上で次のコマンドを実行します。Xcode、libroot を含む Theos、ldid、Python 3 が必要です。

```sh
export THEOS=/path/to/theos
./Tests/run.sh
./build.sh
python3 Tests/validate_package.py
```

自動テストでは、URL の生成と解析、設定のフィルタ処理、ヘルパーの引数・権限チェックを確認しています。ヘルパーの OS 操作にはモックを使い、Dopamine 向けのコマンド選択や注入マーカーの扱いをテストします。テストから実際の再起動は行いません。

パッケージの検査では、rootless の配置、所有者と権限、バージョン、リソース、両アーキテクチャ、最低 OS バージョン、ldid の署名ハッシュを確認します。ビルド後は同梱スクリプトでパッケージ内の数値 UID/GID を `0/0` に揃えます。

1.0.9 は iPhoneOS 26.2 SDK、deployment target 15.0 で両アーキテクチャの Archive に成功しています。アプリの Xcode 静的解析は警告なしで完了し、回帰テスト、リソースの構文検査、生成した `.deb` の検査も通過しています。

## 使用上の注意

各 Tweak の設定バンドルと、Cephei などの依存ライブラリは、使用する iOS と rootless に対応したものをインストールしてください。rootful 専用や旧 arm64e ABI のバンドル、バンドル内部で起きるクラッシュは、このアプリの修正だけでは解消できません。

通常の Reboot を実行すると脱獄状態が解除されるため、再脱獄が必要です。また、Tweak 注入の切り替え後に userspace reboot が失敗した場合も、注入マーカーの変更は残ります。

## 参考資料

- [Dopamine](https://github.com/opa334/Dopamine)
- [Dopamine の環境管理](https://github.com/opa334/Dopamine/blob/3.x/Application/Dopamine/Jailbreak/DOEnvironmentManager.m)
- [Dopamine の jbctl](https://github.com/opa334/Dopamine/blob/3.x/BaseBin/jbctl/src/main.m)
- [Theos の rootless 対応](https://theos.dev/docs/rootless)
- [PreferenceLoader の libprefs](https://github.com/rpetrich/PreferenceLoader/blob/master/prefs.xm)
- [ElleKit](https://github.com/tealbathingsuit/ellekit)
