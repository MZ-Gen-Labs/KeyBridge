# KeyBridge

KeyBridgeは、MacでAPIキーを管理し、プログラムへ環境変数として渡すアプリです。メニューバーから管理画面を開き、用途ごとにキーをセットへまとめられます。Dopplerを保管先として使い、複数のMacで登録情報を共有します。

## 機能

- キーの表示名、サービス、環境変数名、用途メモ、環境、タグ、関連URL、有効期限を管理。
- 用途別のキーセットを作成し、このMacへ適用するセットを切り替え。
- 選んだプログラムだけへ環境変数を渡して起動。
- ログイン時のセット適用と、指定プログラムの起動。
- Touch IDまたはログインパスワードでキーの表示・コピーを確認。
- 秘密値を返さず、キーの説明情報と参照コードをAIへ提供するMCPサーバー。

Gemini・ElevenLabsのテンプレートを用意しています。その他のサービスや独自の環境変数名も登録できます。

## 必要な環境

- macOS 14以降。
- ビルドにはXcodeのSwift開発環境（Swift tools 5.10以降）。
- MCPにはPython 3。現在の接続設定とテストは `/usr/bin/python3` を使用します。
- 通常モードで使うにはDopplerのProject、Config、Config限定Service Token。

SwiftUI、AppKit、SecurityなどmacOS標準機能とPython標準ライブラリを使い、外部ライブラリには依存しません。現在の実機検証はApple Siliconで行っています。

## ビルド・インストール

```sh
./scripts/build-app.sh
./scripts/package-app.sh
```

開発用アプリは `dist.noindex/KeyBridge.app`、インストール用DMGは `dist/` に生成されます。DMGを開き、KeyBridgeをApplicationsへドラッグしてください。普段は `/Applications/KeyBridge.app` から起動します。管理画面を閉じてもメニューバーに常駐します。

生成するアプリはローカルのアドホック署名です。公証済み配布版ではありません。インストール手順は [INSTALL.md](INSTALL.md) を参照してください。

デモモードを開く場合：

```sh
open -n dist.noindex/KeyBridge.app --args --demo
```

デモは架空データをメモリ内で扱います。実際のDoppler、Macの環境変数、ログイン項目を変更しません。

## Dopplerを接続する

1. KeyBridge専用のProjectとConfigをDopplerで用意します。
2. 対象Configの読み書きが可能なService Tokenを発行します。
3. KeyBridgeの「設定」にProject、Config、Tokenを入力して「保存して接続」を押します。
4. 「キー」でAPIキーを登録します。
5. 「セット」で必要なキーをまとめ、「適用」でセットを選びます。

TokenとAPIキーはアプリの入力欄に直接入力してください。ソース、設定例、Git、チャットへ貼り付ける必要はありません。

登録だけでは環境変数を変更しません。適用後にターミナル・IDE等を再起動してください。キーを編集した場合も「再適用」が必要です。

## プログラムから参照する

独自の名前も使用できます。たとえば環境変数名を `MY_SERVICE_API_KEY` として登録した場合：

```python
import os

api_key = os.environ["MY_SERVICE_API_KEY"]
# 利用するAPIクライアントの認証引数へapi_keyを渡す。
```

値をログやコマンド引数に出力しないでください。SDKが自動認識する変数名と異なる場合は、読み取った値を認証引数に明示的に渡します。

## 保存先とGitの範囲

| 情報 | 保存先 |
| --- | --- |
| 登録キー・説明情報・セット | Dopplerの専用Secret |
| Doppler Token・適用前後の復元情報 | Macのローカルキーチェーン |
| 接続先・起動先・自動適用等の設定 | MacのUserDefaults |
| MCP用の説明情報（共有を有効にした場合） | ユーザーのApplication Support内 |
| ソース・仕様・人工データのテスト・アイコン | Git |

このリポジトリに実際の秘密値や利用者設定は含めません。アプリを更新しても、既存のキーチェーンとDopplerの登録情報を使います。iCloud同期は実装していません。

KeyBridgeはDopplerの専用Secretにバージョン付きBase64 JSONを保管します。Base64は暗号化ではなく、DopplerのSecret保管とHTTPSによって保護します。通常の `doppler run` でこのレコードを直接APIキーとして使うことはできません。

## 制約

Macへ広く適用する場合、公開の `launchctl setenv` を使うため、処理中の短い間は値がプロセス引数に現れます。対象を限定する場合は「キー付きで起動」を使ってください。

起動済みプロセスへ後から値を反映したり、渡した値を回収したりすることはできません。解除はKeyBridgeが管理する値を適用前へ戻しますが、他のツールが変更した値は上書きせず競合として停止します。

途中失敗は復元を試みますが、強制終了中の完全な復旧は保証しません。Dopplerへの保存前に競合を確認しますが、複数のMacから同じレコードへ同時に書き込む場合の原子的な更新は保証しません。

有効期限は交換管理用です。期限切れキーの新規適用は止めますが、API提供元のキーを自動失効させません。

MCPが返す情報と接続方法は [MCP.md](MCP.md)、詳細な仕様は [SPEC.md](SPEC.md) を参照してください。

## 検証

```sh
./scripts/test.sh
```

キー・セットの検証、人工データによるAPI通信、環境適用の切り替え・復元・競合、MCP通信と秘密値の除外をテストします。既定のテストは実キーやDopplerアカウントを使いません。検証範囲は [VALIDATION.md](VALIDATION.md) を参照してください。
