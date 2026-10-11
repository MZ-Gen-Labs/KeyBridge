# KeyBridge MCP

KeyBridgeの登録情報をAIから参照できる、Mac内で動作するMCPサーバーです。キーの表示名・サービス名・環境変数名・環境・タグ・期限・セット構成・KeyBridgeが保持する適用の記録を返します。APIの呼び出しやAPI提供元の機能一覧の取得は行いません。

キーの値、DopplerのToken、用途メモ、関連URL、ログイン時のプログラムパスはMCPの出力にも共有ファイルにも含めません。名前・サービス名・タグには秘密情報を入力しないでください。用途は表示名やタグに記載できます。

## 使い方

1. KeyBridgeの「設定」で「MCPに説明情報を共有」を有効にする。初期状態は無効です。
2. 「MCP接続設定をコピー」を押す。
3. stdio対応のAIアプリのMCP接続設定に追加する。アプリによって設定形式が異なります。
4. KeyBridgeを起動したまま利用する。

一般的なJSON設定例：

```json
{
  "mcpServers": {
    "keybridge": {
      "command": "/usr/bin/python3",
      "args": ["/Applications/KeyBridge.app/Contents/Resources/keybridge_mcp.py"]
    }
  }
}
```

キーやDopplerのTokenをMCP設定のenvに記載する必要はありません。Python 3を使用します（このMacの /usr/bin/python3 で検証済み）。MacごとにMCPの共有設定を行います。

AIへの指示例：

- 「KeyBridgeでGoogle AI Studioの登録キーを検索し、Pythonから参照する方法を教えて」
- 「使えるキーセットと環境変数名を確認して」
- 「TTSタグのキーを検索して、JavaScriptで環境変数から読むコードを書いて」

## 提供するツール

| ツール | 引数 | 結果 |
| --- | --- | --- |
| keybridge_list_keys | query（省略可） | 表示名・サービス・環境変数・環境・タグの部分一致検索 |
| keybridge_list_sets | なし | セット名、含まれるキーの識別子と環境変数名、Macへの適用の記録 |
| keybridge_get_usage | key_id、language（python / javascript / shell、省略時python） | 実際に登録された変数名を使う参照コードと利用手順 |

`GOOGLE_AI_S_KEY`などの独自名に対応します。SDKが自動認識する変数名とは異なる場合、取得した値をAPIクライアントの認証引数へ渡す必要があります。

適用状態はKeyBridgeが保持する記録です。MCPサーバー自身や呼び出し元AIアプリがその環境変数を継承しているかは検査しません。プログラムで利用するにはセットを適用後、ターミナル・IDE等を再起動するか、KeyBridgeの「キー付きで起動」を使います。

## データと通信

KeyBridgeは共有を有効にした場合だけ、明示的な許可リストの項目を `~/Library/Application Support/KeyBridge/mcp-catalog.json` に書きます。親ディレクトリは0700、ファイルは0600です。Dopplerからの更新、適用・解除、共有設定の変更に合わせて更新します。共有を無効にするとファイルを削除し、次のMCP呼び出しから参照できなくなります。既にAIへ渡した説明情報は回収できません。

サーバーはこの説明情報ファイルを各呼び出し時に読みます。更新時刻が3分以上前なら、古い情報を返さずKeyBridgeの起動・更新を案内します。Doppler切断時にも共有ファイルを削除します。MCPサーバーにネットワーク・Keychain・環境変数の秘密値の取得・プログラム実行機能はありません。

MCPサーバーはstdioのJSON-RPCを使い、HTTPポートは開きません。MCPの2025-11-25のinitialize方式に対応し、2025-06-18、2025-03-26、2024-11-05とのネゴシエーションを提供します。2026-07-28の新方式専用クライアントは対象外です。接続したAIアプリは説明情報をモデルに送信する場合があるため、共有先のAIアプリの設定を確認してください。

## 検証

Swift側で秘密値・用途メモ・URLの除外、期限判定、適用値更新判定、ファイル権限、無効化を検証。Python側で初期化・ツール一覧・検索・独自環境変数名の参照例・秘密値の除外・無効化・古い情報の拒否・不正入力・実際のstdioサブプロセスを検証。

```sh
./scripts/test.sh
```
