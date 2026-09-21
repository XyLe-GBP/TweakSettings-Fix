# TweakSettings 1.0.9 互換性修正

対象は iOS 17.3 / arm64e / Dopamine / ElleKit / rootless です。ビルドの最低OSは iOS 15.0、deb のアーキテクチャは `iphoneos-arm64`、アプリとヘルパーには `arm64` と `arm64e` の両方を含めます。

この文書の「確認済み」はソース検査・Mac上のテスト・生成物の検査を指します。脱獄済みiOS 17.3実機での動作確認は未実施です。特に Preferences.framework は非公開APIなので、ビルド成功だけでは実行時の互換性を証明できません。

## 1.0.9 起動クラッシュへの修正

1.0.8について、iPhone 15 Pro Max / iOS 17.3 / Dopamine 3.0.9でアイコンを押した直後に終了するとの実機報告を受けました。

前回の変更で `PSListController` のテーブル取得を `self.table` から `self.tableView` へ変更したことが誤りでした。iOS 17のランタイム定義には `-table` があり、引数なしの `-tableView` はありません。起動時の `TSRootListController.viewDidLoad` がこの未実装セレクタを呼んでいました。検索・長押しにも同じ変更があったため、全箇所を `table` に戻しました。

ローカルヘッダーにあった不正確な `tableView` 宣言も削除しました。これにより同じ呼び出しを再び書いた場合はコンパイル段階で検出できます。1.0.8と区別できるよう、パッケージとアプリのバージョンを1.0.9へ更新しています。

この不具合はソースと[実機から抽出されたiOS 17のPSListController定義](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/Preferences.framework/PSListController.h)の照合で確認しました。ユーザーのクラッシュログはまだ取得できていないため、今回のクラッシュ原因がこの1件だけであることや、1.0.9が対象実機で起動することは未確認です。先のビルド・静的解析では、この誤ったローカル宣言による問題を検出できていませんでした。

## 調査範囲

アプリの全 `.m` / `.h` / prefix header、Cヘルパー、Xcodeプロジェクト、Makefile、ビルドスクリプト、Debianメタデータとインストールスクリプト、entitlements、Info.plist、ローカライズ、同梱Preferencesヘッダー／リンク用スタブを確認しました。画像・アセット定義・起動画面のリソースはビルドと構文検査で確認しています。既存の過去リリースdebは変更していません。

## 主な修正

| 対象 | 問題と修正 |
| --- | --- |
| ビルド | Xcode 11/12やSDK 14.4への固定、グローバルなxcode-select変更を廃止。選択中のXcodeと最新SDKを利用。rootlessと現行arm64e ABIを前提に統一。 |
| パス | アプリの単純な `/var/jb` 文字列追加をlibrootへ変更。Dopamineのpreboot実体パスを解決。AppleのシステムPreferenceBundleパスはrootless変換しない。 |
| 起動 | UIApplicationとdelegateを同じクラスで生成していた構成を通常のdelegate構成へ変更。libprefsのロード失敗をログに記録。 |
| 設定一覧 | entry/filter/名前/アイコンの型検査、CFVersion範囲の境界確認、欠落IDの補完を追加。dpkgのファイル名による判定を実行時のメソッド確認へ変更。fallback parserのNULL呼び出しとbundle-controller配列の保持漏れを修正。 |
| 検索 | 非同期検索の古い結果が新しい検索・更新結果を上書きする競合を解消。更新後の検索条件を再適用。 |
| URL / Spotlight | Spotlight IDを実際の `tweaks:root=...` URLへ変更。各IDを個別にエンコードし、ID内の `/`・日本語・`%`などを保持。起動中のURLを保留し、画面遷移の前に保留を解除。検索で隠れた項目も検索対象にする。 |
| ナビゲーション | 空のナビゲーションスタックを作らない。iPadの分割表示と折りたたみでコントローラを移動し、rootControllerの参照を更新。設定バンドルのロード失敗を表示。 |
| アクション | 非公開NSTaskと `/bin/sh -c` を使わず、許可した引数だけでヘルパーを直接posix_spawn。パイプは待機前に排出し、出力の保持量を制限。UIスレッドをブロックせず、失敗を表示。 |
| Dopamine | respring / userspace rebootには `/basebin/jbctl` の該当コマンドを使用。注入切替は `.safe_mode` を直接操作してuserspace reboot。Dopamineでldrestartは表示しない。利用できないコマンドも非表示。 |
| ヘルパー | Electra用の未検証dlsym呼び出し、fork失敗／子終了コードの取り扱い不良、旧Substrate/libhookerへの曖昧なfallbackを除去。親実行ファイルを正規化して比較し、所有者・書き込み権限・root資格情報を確認。rootツールに渡す環境を固定。 |
| パッケージ | world-writableなsetuidヘルパーを `root:wheel / 4755` に修正。アプリは0755。uicacheのディレクトリ判定・変数展開ミスを修正し、削除時の登録解除も追加。 |
| 通信・設定 | 更新確認のHTTP/JSON型検査と数値バージョン比較を追加。古い上流版を更新扱いしない。changelogの無限スピナー、セッション寿命、UI以外のスレッドからの変更通知を修正。 |

## 自動検証

```sh
export THEOS=/path/to/theos
./Tests/run.sh
./build.sh
python3 Tests/validate_package.py
```

- Foundationで実際のURL生成／解析とフィルタ関数を実行。Unicode・予約文字の往復、未知スキーム、空ID、不正データ、CFVersionの下限／上限を確認。
- 本番ヘルパーのソースをOS呼び出しのモックとともにコンパイル。未知操作、シェル文字列、親プロセス偽装、書き換え可能なアプリ、非root実行、資格情報設定失敗を拒否することを確認。
- モックでDopamineのコマンド選択、セーフモードのシグナル、注入マーカーの作成／削除／書き込み失敗／シンボリックリンク拒否を確認。テストから実際の再起動コマンドを実行しない。
- plist / strings / asset JSON / storyboard XMLとshell scriptの構文を確認。
- 実際のdebを読み、rootless配置・root所有・4755/0755・バージョン・ローカライズ・起動画面・アイコン・Mach-O両アーキテクチャ・最低OS・ldidのコードページ／entitlementsハッシュを検査。これは脱獄環境用の署名検査であり、Apple証明書の信頼検証ではない。

今回の検証結果：iPhoneOS 26.2 SDK／deployment target 15.0でarm64・arm64eのArchiveが成功。アプリ全実装ファイルのXcode静的解析は警告なし。上記回帰テストと最終debの検査も成功。Theos付属dm.plで残るホストの数値UID/GIDは、パッケージ生成後に同梱スクリプトで0/0へ正規化している。

## 実機で残る確認

1. 脱獄済みの対象端末に新しいdebをパッケージマネージャーでインストールし、ホーム画面から起動する。
2. 通常のPreferenceBundle、Cepheiなどの依存ライブラリを持つバンドル、plistだけの設定を開き、値の保存を確認する。それぞれの依存パッケージもrootless/iOS 17対応版が必要。
3. 検索入力・キャンセル・プル更新を繰り返す。画面を切り替えた後も一覧と選択が一致することを確認する。
4. `tweaks:root=<ID>` とSpotlightから、起動前／起動後／検索中それぞれで正しい項目を開けることを確認する。iPadでは縦横回転、分割表示、戻る操作も確認する。
5. UICache、respring、セーフモード、userspace rebootを個別に確認する。注入切替は常に確認ダイアログを出し、再起動後にDopamineで設定を確認する。通常のRebootでは脱獄状態が解除されるため、再脱獄が必要。
6. ネットワークを切って更新／changelog画面にエラーが表示されることを確認する。
7. アップグレード／削除後のアイコン登録とファイル権限を確認する。

任意の他社バンドル内で発生するネイティブクラッシュ、旧arm64e ABIやrootful専用バンドル、非対応の依存ライブラリはホストアプリ側だけでは修復できません。Objective-C例外は一部の読み込み境界で処理していますが、SIGSEGV等を回復するものではありません。注入マーカーの変更後に再起動の実行が失敗した場合、エラーを表示しますがマーカー状態は変更済みです。

## 参照した一次資料

2026-09-21に確認。

- [Dopamine公式の対応範囲](https://github.com/opa334/Dopamine)：現行3.xのREADMEはarm64eのiOS 15.0–17.3.1を記載。古いDopamine 2.xの対応範囲とは異なる。
- [Dopamineの環境管理](https://github.com/opa334/Dopamine/blob/3.x/Application/Dopamine/Jailbreak/DOEnvironmentManager.m)：注入マーカーとjbctlを使う操作を確認。
- [Dopamine jbctl](https://github.com/opa334/Dopamine/blob/3.x/BaseBin/jbctl/src/main.m)：`respring` / `reboot_userspace`の実装を確認。
- [Theos rootless](https://theos.dev/docs/rootless)：libroot、パッケージアーキテクチャ、arm64e ABI、rpathの扱いを確認。
- [PreferenceLoader libprefs](https://github.com/rpetrich/PreferenceLoader/blob/master/prefs.xm)：CFVersionフィルタと設定生成処理を照合。
- [ElleKit](https://github.com/tealbathingsuit/ellekit)：注入・フックの実装元。このアプリ自体には新しいフックを追加していない。
