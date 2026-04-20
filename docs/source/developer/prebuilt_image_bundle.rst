Prebuilt Image Bundle
=====================

``docker compose build`` が難しい小メモリ環境向けに、事前ビルド済み Docker イメージを tar bundle として配布できます。

作成手順
--------

高メモリなビルド機でリポジトリ直下から次を実行します。

.. code-block:: console

   chmod +x scripts/package-prebuilt-images.sh
   ./scripts/package-prebuilt-images.sh

生成物は ``dist/prebuilt-images/<git-sha>/`` に出力されます。

- ``app.tar``
- ``elasticsearch.tar``
- ``nginx.tar``
- ``images.env``
- ``SHA256SUMS``

``images.env`` には bundle が対象とする commit と image 名が入っています。

利用手順
--------

1. 高メモリなビルド機で生成した ``dist/prebuilt-images/<git-sha>/`` を、そのまま低メモリ端末へ転送します。
2. 低メモリ端末では、bundle を作成した commit と同じ commit を checkout します。
3. リポジトリ直下で次を実行します。

.. code-block:: console

   ./install.sh --image-bundle dist/prebuilt-images/<git-sha>

このモードでは ``docker load`` で bundle を読み込んだあと、ローカル build を行わずに通常の bootstrap と起動処理へ進みます。

注意事項
--------

- ``--image-bundle`` と ``--pull-images`` は同時に使えません。
- Compose project 名は ``WEKO_DOCKER_PROJECT`` で固定できます。既存の別スタックと衝突しない名前を指定してください。
- bundle の commit と現在の checkout が一致しない場合、``install.sh`` はエラー終了します。
- bundle の arch とホスト arch が一致しない場合、``install.sh`` はエラー終了します。
- prebuilt asset を優先するため、bundle 利用時は bootstrap 中の asset rebuild を既定で省略します。再生成が必要な場合だけ ``--rebuild-assets`` を付けてください。
