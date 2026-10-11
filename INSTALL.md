# KeyBridgeをMacへインストール

この版はApple Silicon（Mシリーズ）のMac、macOS 14以降用です。

1. KeyBridge-0.2.1-arm64.dmgをダブルクリックします。
2. KeyBridgeをApplicationsへドラッグします。
3. Finderの「アプリケーション」からKeyBridgeをダブルクリックします。
4. メニューバー右側に鍵と橋のアイコンが表示されます。アイコンから管理画面を開けます。

管理画面を閉じてもKeyBridgeは常駐します。終了するにはアイコンのメニューから「終了（適用は維持）」を選択します。

## 今のデータを引き継ぐ

登録キー・説明情報・セットは今のDoppler Project / Configをそのまま使います。Tokenと適用状態はMacのキーチェーン、このMacの設定は同じアプリ識別子 dev.keybridge.app の設定に保存されています。アプリの移動で再登録やデータ移行は不要です。更新・移動後にキーチェーン認証を求められた場合は、Macのログインキーチェーンのパスワードを入力してください。

開発フォルダの旧版とインストール版を同時に起動しないでください。今後は /Applications/KeyBridge.app を起動します。

ログイン後の自動適用が有効な場合、インストール版の起動時にログイン項目を新しい場所へ登録し直します。システム設定に承認要求が出た場合は許可してください。

MCP接続設定のサーバーパスは次になります。既にAIアプリへ設定済みの場合は、KeyBridgeの「MCP接続設定をコピー」で新しい設定を取得してください。

/Applications/KeyBridge.app/Contents/Resources/keybridge_mcp.py

## 配布範囲

この版はローカル開発用のアドホック署名で、Appleの公証はありません。このMacでのインストールと動作確認用です。他のMacへ一般配布する場合は、Developer ID署名と公証を行う必要があります。インストール用DMGにはAPIキーやDoppler Token、個人の設定は含みません。


## アプリ一覧の重複整理（0.2.1）

通常のMacアプリとしてアプリ一覧・Dockに表示される設定です。メニューバー常駐は維持し、管理画面を閉じても終了しません。開発用ビルドは `dist.noindex/KeyBridge.app` に生成して、Spotlightの検索対象から分離します。普段は `/Applications/KeyBridge.app` を起動してください。
