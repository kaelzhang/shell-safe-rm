# safe-rm（セーフ・アールエム）

```
 _______  _______  _______  _______         ______    __   __
|       ||   _   ||       ||       |       |    _ |  |  |_|  |
|  _____||  |_|  ||    ___||    ___| ____  |   | ||  |       |
| |_____ |       ||   |___ |   |___ |____| |   |_||_ |       |
|_____  ||       ||    ___||    ___|       |    __  ||       |
 _____| ||   _   ||   |    |   |___        |   |  | || ||_|| |
|_______||__| |__||___|    |_______|       |___|  |_||_|   |_|
```

[Safe-rm](https://github.com/kaelzhang/shell-safe-rm) は、Unix の [`rm`](https://man7.org/linux/man-pages/man1/rm.1.html) コマンドの**ほぼ全ての機能**を備えた、より安全な置き換えツールです。

## 概要

- MacOS・Linux 両対応、テストカバレッジも充実
- `safe-rm` で削除したファイルやディレクトリは、システムの「ゴミ箱」へ移動されます（完全削除されません）
  - MacOS では AppleScript を利用し、ゴミ箱から「元に戻す」機能もサポート
  - Linux でも重複ファイルの扱いなど、OSのゴミ箱仕様に準拠
- オリジナルの `rm` コマンドと**ほぼ同じオプション**が利用可能
- 独自の設定ファイルによるカスタマイズが可能

## 主な対応オプション

| オプション | 概要 | 説明 |
| ------ | ----- | ------------ |
| `-i`, `--interactive` | 対話的 | 各ファイル削除前に確認 |
| `-I`, `--interactive=once` | 簡易対話 | 3つ以上や再帰削除時のみ一度だけ確認 |
| `-f`, `--force` | 強制 | 存在しないファイルも含め、確認なしで削除 |
| `-r`, `-R`, `--recursive`, `--Recursive` | 再帰 | ディレクトリごと削除 |
| `-v`, `--verbose` | 詳細表示 | 削除対象を詳細に表示 |
| `-d`, '--directory' | 空ディレクトリ削除 | 空ディレクトリのみ削除 |
| `--` | オプション終了 | ファイル名が `-` で始まる場合などに使用 |

短縮オプションの組み合わせも可能です（例: `-rf`, `-riv` など）

## インストール方法

### 一時的な利用

`~/.bashrc` などにエイリアスを追加します。

```sh
alias rm='/path/to/bin/rm.sh'
```

`/path/to` には、`shell-safe-rm` をクローンしたパスを指定してください。

### 永続的なインストール（推奨）

Node.js（npm）がインストールされている場合：

```sh
npm i -g safe-rm
```

ソースコードから直接インストールする場合：

```sh
# Node.js 環境がある場合
npm link

# Node.js や npm がない場合
make && sudo make install

# make コマンドがない場合
sudo sh install.sh
```

インストール後、`~/.bashrc` などに以下を追加してください：

```sh
alias rm='safe-rm'
```

## アンインストール

エイリアス設定を削除した上で、以下のいずれかでアンインストールできます：

```sh
npm uninstall -g safe-rm
```

または

```sh
make && sudo make uninstall
```

または

```sh
sudo sh uninstall.sh
```

## 設定ファイルによるカスタマイズ

ホームディレクトリの `~/.safe-rm/config` で、以下のようなカスタマイズが可能です：
- ゴミ箱ディレクトリの指定
- ゴミ箱内のファイルを完全削除するかどうか
- MacOS で AppleScript の利用を禁止

サンプル設定ファイルは [こちら](./.safe-rm/config) を参照してください。

```sh
# サンプルコピー
cp -r ./.safe-rm ~/
```

カスタム設定ファイルを使いたい場合：

```sh
alias="SAFE_RM_CONFIG=/path/to/safe-rm.conf /path/to/shell-safe-rm/bin/rm.sh"
```

npm でインストールした場合：

```sh
alias="SAFE_RM_CONFIG=/path/to/safe-rm.conf safe-rm"
```

### MacOS で「元に戻す」機能を無効化

`~/.safe-rm/config` に以下を記載：

```sh
export SAFE_RM_USE_APPLESCRIPT=no
```

### ゴミ箱ディレクトリの変更

```sh
export SAFE_RM_TRASH=/path/to/trash
```

### ゴミ箱内のファイルを完全削除

```sh
export SAFE_RM_PERM_DEL_FILES_IN_TRASH=yes
```

## 削除保護機能

特定のファイルやディレクトリを誤って削除しないよう、`~/.safe-rm/` 配下に `.gitignore` ファイルを作成し、保護したいパスを記載できます。

例：

```
/path/to/be/protected
```

この場合、以下のコマンドはエラーになります：

```sh
$ safe-rm /path/to/be/protected
$ safe-rm /path/to/be/protected/foo
$ safe-rm -rf /path/to/be/protected/bar
```

ただし、パフォーマンスの都合上、

```sh
$ safe-rm -rf /path/to
```

のように親ディレクトリごと削除した場合は保護されません。

> 注意：
> - `.gitignore` を利用するには `git` のインストールが必要です
> - パターンはルートディレクトリ（`/`）基準です
> - `/` のみを記載すると全てが保護されてしまうので注意

---

[AppleScript]: https://en.wikipedia.org/wiki/AppleScript 
