二サーバー構成での運用検討
============================

概要
----

本メモは、単一ホストで WEKO3 を運用したときに発生しやすい実行時メモリ圧迫を緩和するため、
アプリ系をサーバ1、PostgreSQL と Elasticsearch をサーバ2へ分離する二サーバー構成の実現性と
処理効率を整理したものである。

検討対象は実行時の構成であり、Docker イメージの build 時メモリ不足は別件とする。
分離対象は PostgreSQL と Elasticsearch のみであり、Redis、RabbitMQ、ファイル保存領域は
サーバ1に残す前提で評価する。

本メモでは次の 2 パターンを分けて扱う。

* 同一拠点内の二サーバー構成: 同一 LAN または同等の低遅延 private network 上で server1 と server2 を接続する。
* 別拠点間の二サーバー構成: server1 と server2 が別の場所にあり、VPN や専用線を含む広域ネットワーク越しに通信する。

結論
----

同一拠点内の二サーバー構成は、WEKO3 の現行アーキテクチャでも十分に現実的であり、
単一ホストの実行時メモリ圧迫が主問題である場合は有力な選択肢である。

一方で、別拠点間で server1 と server2 を分ける構成は、現行設定の変更も視野に入れてよいとしても、
標準構成の延長としては現実的とは言いにくい。成立し得るのは、少なくとも次の条件を満たす場合に限られる。

* server1 と server2 の間が安定した private network で結ばれ、遅延と packet loss が十分小さい。
* PostgreSQL 接続設定、Elasticsearch 接続設定、deploy 手順の見直しを行う。
* Elasticsearch の TLS/認証や非標準ポート対応に必要なコード修正を受け入れる。
* 広域ネットワーク障害時に DB/検索系が全面的に影響を受けることを許容できる。

同一拠点内の二サーバー構成を推しやすい条件は次のとおりである。

* 単一ホストの実行時メモリ圧迫が主問題である。
* 二台が同一 LAN 上にあり、サーバ間遅延が低く安定している。
* PostgreSQL と Elasticsearch へのアクセスを標準ポートのまま private network と firewall で保護できる。
* 単一ホスト時より運用監視と障害切り分けが複雑になることを受け入れられる。

逆に、次の条件では二サーバー化自体を推奨しにくい。

* サーバ間ネットワークが不安定、または遠距離配置になる。
* 非標準ポート、Elasticsearch の TLS/認証、Redis/RabbitMQ の外出しまで一度に進めたい。
* 追加される障害点、監視項目、復旧手順を運用側で吸収しにくい。

現行構成の前提
--------------

現行の ``docker-compose2.yml`` と ``scripts/instance.cfg`` から見ると、WEKO3 のアプリケーション自体は
環境変数で PostgreSQL と Elasticsearch の接続先を決める構造になっている。

* ``web`` は ``INVENIO_POSTGRESQL_HOST=postgresql``、``INVENIO_ELASTICSEARCH_HOST=elasticsearch`` を受け取る。
* ``worker`` も同じ値を受け取り、``scheduler`` は ``worker`` の設定を継承する。
* ``scripts/instance.cfg`` では ``SQLALCHEMY_DATABASE_URI`` が ``INVENIO_POSTGRESQL_HOST`` を使って生成される。
* 同じく ``SEARCH_ELASTIC_HOSTS`` は ``INVENIO_ELASTICSEARCH_HOST`` を使う。

ただし、現行の Compose 定義は接続先ホスト名を外から差し込む形ではなく、ローカル service 名
``postgresql`` と ``elasticsearch`` をそのまま埋め込んでいる。したがって、二サーバー構成で使うには
アプリケーションコードの変更までは不要だが、少なくとも deployment 用の Compose override か
``docker-compose2.yml`` の運用向け差し替えが必要になる。

また、現行設定には次の制約がある。

* PostgreSQL 接続は ``5432`` 固定で生成される。
* Redis は ``6379`` 固定で URL が生成される。
* RabbitMQ は ``5672`` 固定で URL が生成される。
* Elasticsearch は ``SEARCH_ELASTIC_HOSTS`` にホスト名を渡す形で、標準的な HTTP 接続前提である。
* DB engine option は ``pool_pre_ping`` を有効にし、Compose 側では ``INVENIO_DB_POOL_CLASS=NullPool`` が設定されている。
* Elasticsearch client 設定は ``timeout=60``、``max_retries=5`` である。
* bulk index 用 timeout は ``INDEXER_BULK_REQUEST_TIMEOUT=600`` である。

ローカル同居前提のリソース設定も確認できる。

* PostgreSQL は ``postgres:12`` を使用している。
* Elasticsearch は ``docker.elastic.co/elasticsearch/elasticsearch:6.8.23`` をベースに single-node 構成で動作する。
* Elasticsearch コンテナは ``ES_JAVA_OPTS=-Xms512m -Xmx512m`` を使う。
* ``install.sh`` は初期起動時に ``postgresql redis elasticsearch rabbitmq`` をまとめて起動する。

このため、二サーバー構成にする場合は、接続先の差し替えだけでなく、ローカル PostgreSQL と
Elasticsearch を不用意に起動しないデプロイ手順を用意する必要がある。

さらに、別拠点間構成まで視野に入れると、設定変更やコード修正の必要箇所も見えてくる。

* PostgreSQL は host だけが環境変数化されており、port は ``5432`` 固定である。
* Elasticsearch は ``SEARCH_ELASTIC_HOSTS`` を host 名として扱う前提が強い。
* ``weko_admin.utils.elasticsearch_reindex()`` は ``http://<host>:9200/`` を直組みしている。
* ``docker-compose2.yml`` では ``INVENIO_DB_POOL_CLASS=NullPool`` が設定されているが、実装上は ``QueuePool`` を利用できる。

そのため、別拠点間構成を本気で採用するなら、単に host を差し替えるだけでは足りず、
接続 URL と接続プール戦略まで含めて見直す必要がある。

変更を視野に入れた場合の論点
----------------------------

別拠点間の二サーバー構成を検討する場合、少なくとも次の変更候補を持つことになる。

.. list-table::
   :header-rows: 1

   * - 項目
     - 現行状態
     - 別拠点で必要になりやすい見直し
   * - PostgreSQL 接続
     - host のみ環境変数化、port は ``5432`` 固定
     - port 可変化、必要なら ``SQLALCHEMY_DATABASE_URI`` 全体を環境変数で差し替える
   * - DB connection pool
     - Compose では ``NullPool``
     - ``QueuePool`` 利用と pool size / recycle の調整を検討する
   * - Elasticsearch 接続
     - host 名 + HTTP + ``9200`` 前提が強い
     - URL 化、TLS/認証対応、管理系ユーティリティの修正を行う
   * - install / deploy
     - ローカル DB/ES 起動前提
     - 外部 DB/ES 用の compose override か別 deployment 定義を用意する
   * - 監視
     - 単一ホスト中心
     - 回線遅延、packet loss、VPN/専用線の健全性も監視対象に加える

ここで重要なのは、別拠点間で現実性を上げる変更は「設定値の差し替え」だけでなく、
アプリケーションが暗黙に持っているローカル HTTP / 標準ポート前提を減らす方向になる点である。

提案トポロジ
------------

.. code-block:: text

   +------------------------------------+
   | Server 1: Application              |
   |------------------------------------|
   | nginx                              |
   | web (uWSGI)                        |
   | worker (Celery)                    |
   | scheduler (Celery Beat)            |
   | Redis                              |
   | RabbitMQ                           |
   | local file storage (/var/tmp etc.) |
   +-------------------+----------------+
                       |
                       | private network
                       | PostgreSQL 5432
                       | Elasticsearch 9200
                       v
   +------------------------------------+
   | Server 2: Data / Search            |
   |------------------------------------|
   | PostgreSQL 12                      |
   | Elasticsearch 6.8.23               |
   +------------------------------------+

同一拠点内での配置意図を表で整理すると次のとおりである。

.. list-table::
   :header-rows: 1

   * - コンポーネント
     - 配置先
     - 理由
   * - ``nginx`` / ``web``
     - サーバ1
     - ユーザ通信の入口であり、静的ファイル・アプリケーション本体と同居させるため
   * - ``worker`` / ``scheduler``
     - サーバ1
     - RabbitMQ とローカルファイルへのアクセスが多く、アプリ側に残した方が単純なため
   * - Redis / RabbitMQ
     - サーバ1
     - 今回の分離対象外であり、現行設定でもローカル同居前提が強いため
   * - PostgreSQL
     - サーバ2
     - メモリ消費とディスク I/O をアプリ系から切り離すため
   * - Elasticsearch
     - サーバ2
     - JVM heap と index I/O をアプリ系から切り離すため

別拠点間で無理に分ける場合のイメージは次のとおりである。

.. code-block:: text

   +------------------------------------+
   | Site A / Server 1                  |
   |------------------------------------|
   | nginx / web / worker / scheduler   |
   | Redis / RabbitMQ / local files     |
   +-------------------+----------------+
                       |
                       | VPN / dedicated line
                       | WAN latency, packet loss, outage risk
                       v
   +------------------------------------+
   | Site B / Server 2                  |
   |------------------------------------|
   | PostgreSQL / Elasticsearch         |
   +------------------------------------+

この構成では、メモリや I/O の分離効果は得られるが、WEKO の主要 read/write path が WAN 依存になる。
したがって、同一拠点内の二サーバー構成とは別物として判断する必要がある。

実現性評価
----------

同一拠点内でそのまま成立しやすい範囲
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

次の範囲であれば、二サーバー構成は比較的実現しやすい。

* PostgreSQL と Elasticsearch の接続先ホストだけを server2 側へ向ける。
* PostgreSQL は ``5432``、Elasticsearch は ``9200`` を使う。
* server2 側は private network 内でのみ到達可能にし、firewall で接続元を server1 に限定する。
* PostgreSQL 12 系、Elasticsearch 6.8 系を維持して互換性リスクを増やさない。

この条件なら、WEKO アプリケーションの Python コード自体には手を入れずに進められる可能性が高い。
必要になるのは deployment 設定の切り替えであり、現実的には ``docker-compose2.yml`` を直接使うのではなく、
接続先 environment と起動対象 service を上書きする compose override を用意する方法が安全である。

設定変更やコード修正が必要な範囲
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

次の項目は現行構成のままでは吸収できないため、別途対応が必要である。

* PostgreSQL を非標準ポートで公開する。
* Redis や RabbitMQ も別サーバへ出す。
* Elasticsearch に TLS/認証を付ける。
* server2 側の PostgreSQL / Elasticsearch を高可用構成へ拡張する。

理由は次のとおりである。

* ``scripts/instance.cfg`` は PostgreSQL ``5432``、Redis ``6379``、RabbitMQ ``5672`` を固定で埋め込む。
* ``SEARCH_ELASTIC_HOSTS`` はホスト名中心の設定であり、証明書、scheme、認証情報をまとめて切り替える前提になっていない。
* ``weko_admin.utils.elasticsearch_reindex()`` は ``http://<host>:9200/`` を前提にしている。
* ``install.sh`` はローカル PostgreSQL / Elasticsearch の起動を前提にしている。

したがって、同一拠点内の二サーバー構成は「標準ポート・private network・最小変更」の範囲で採用するのが最も現実的である。

別拠点間の実現性
^^^^^^^^^^^^^^^^

別拠点間で server1 と server2 を分けることは、技術的には不可能ではないが、現実性は低い。
特に WEKO3 のようにアプリケーションと DB/検索基盤が高頻度に往復する構成では、広域ネットワークに
よる遅延・瞬断・帯域制約がそのままユーザ応答とバッチ処理時間に跳ね返る。

別拠点間構成が現実的になるのは、せいぜい次の条件を満たす場合である。

* site 間 latency が小さく、ピーク時でも安定している。
* PostgreSQL / Elasticsearch を public exposure せずに private network で閉じられる。
* DB 接続プールや ES 接続方式の見直しを含む設定変更、必要ならコード修正を行える。
* WAN 障害時に WEKO が実質停止に近い状態になることを業務として許容できる。

通常のインターネット VPN 越しや、回線品質が読めない拠点間接続では、メモリ分離の利点より
通信依存リスクの方が大きくなりやすい。

処理経路と性能影響
------------------

主な処理経路
^^^^^^^^^^^^

二サーバー化した場合の主要経路は次のようになる。

* 検索系: ``web -> Elasticsearch``
* 更新系: ``web -> PostgreSQL commit -> RabbitMQ -> worker -> Elasticsearch``
* 定期処理: ``scheduler/worker -> PostgreSQL`` または ``scheduler/worker -> Elasticsearch``

期待できる効果
^^^^^^^^^^^^^^

* PostgreSQL の shared buffer や OS page cache、Elasticsearch の JVM heap が server1 から外れるため、アプリ系のメモリ圧迫を下げやすい。
* DB と ES のディスク I/O を server1 から切り離せるため、nginx / web / worker と競合しにくくなる。
* 再索引、集計、重い検索などの影響範囲を server2 側へ寄せられる。
* DB/検索基盤のバックアップや監視をアプリ系と分けて整理しやすくなる。

増えるコスト
^^^^^^^^^^^^

* すべての DB クエリと検索がネットワーク越しになる。
* DB は ``NullPool`` 前提のため、接続再利用が効きにくく、接続確立や往復遅延の影響を受けやすい。
* bulk index や再索引では ``worker -> Elasticsearch`` の転送時間が伸びやすい。
* 障害点が server1 と server2 に分かれ、切り分けと復旧手順が増える。

別拠点間の場合は、上記に加えて次の影響が強くなる。

* DB トランザクションの commit 待ちが WAN latency に直結する。
* 検索画面や詳細画面の応答時間が、単純な CPU/メモリ性能ではなく回線品質に支配されやすい。
* 再索引や一括更新では、アプリ負荷よりも回線帯域と packet loss が wall clock time を左右しやすい。
* WAN 障害が DB/ES 障害とほぼ同義になり、切り分けが難しくなる。

比較表
^^^^^^

.. list-table::
   :header-rows: 1

   * - 観点
     - 単一サーバー
     - 二サーバー
     - コメント
   * - 実行時メモリ
     - DB/ES とアプリが競合する
     - server1 の圧迫を下げやすい
     - 今回の主目的に最も効きやすい
   * - ディスク I/O
     - DB/ES/アプリ/ファイルが同居する
     - DB/ES の I/O を分離できる
     - 検索・集計・再索引の干渉を減らしやすい
   * - 検索応答
     - ローカル呼び出し
     - ``web -> ES`` の往復遅延が追加される
     - 低遅延 LAN なら許容しやすいが、遠距離配置は不利
   * - DB 応答
     - ローカル呼び出し
     - ``web/worker -> DB`` の往復遅延が追加される
     - ``NullPool`` のため接続確立コストに敏感になりやすい
   * - bulk 更新 / 再索引
     - ローカル ES へ投入
     - ``worker -> ES`` がネットワーク越しになる
     - wall clock time は伸びやすい
   * - 障害点
     - 1台に集中する
     - server1 / server2 の双方を監視する
     - 原因切り分けは複雑になる
   * - 保守性
     - 構成は単純
     - 役割分離しやすい
     - 運用手順の整備が前提になる

別拠点間まで含めて比較すると、次の整理になる。

.. list-table::
   :header-rows: 1

   * - 観点
     - 同一拠点内の二サーバー
     - 別拠点間の二サーバー
     - 判断
   * - メモリ/I/O 分離
     - 効果が出やすい
     - 効果自体は同じ
     - どちらも利点はある
   * - 通信遅延
     - 低い前提を置きやすい
     - アプリ応答へ直接影響しやすい
     - 別拠点は不利
   * - 障害耐性
     - サーバ障害中心で考えればよい
     - 回線障害も major incident になる
     - 別拠点は不利
   * - 実装変更量
     - deploy 差分中心
     - 設定変更と一部コード修正が必要
     - 別拠点は不利
   * - 現実性
     - 高い
     - 低い
     - 別拠点は限定条件付き

推奨条件
--------

次の条件では二サーバー構成を推奨しやすい。

* 単一ホストで swap、OOM、または顕著なメモリ逼迫が起きている。
* DB と ES のメモリ消費がボトルネックであり、アプリケーションコードの最適化だけでは改善しにくい。
* server1 と server2 を同一拠点の低遅延ネットワークで接続できる。
* PostgreSQL / Elasticsearch の監視、バックアップ、障害対応を分けて運用したい。

別拠点間でも推奨し得る例外的な条件を挙げるなら、専用線や高品質 VPN を前提にした private network を確保でき、
かつ DB/ES 接続方式の見直しを実施できる場合に限られる。

非推奨条件
----------

次の条件では二サーバー構成は推奨しにくい。

* server 間回線が不安定で、遅延や packet loss が無視できない。
* 拠点間やインターネット越しのように、DB/ES を遠距離配置する。
* 非標準ポートや TLS/認証を含む大きな接続要件変更を、設定変更だけで済ませたい。
* Redis / RabbitMQ / ファイル領域まで同時に分離したい。

特に、単に「サーバを別の場所に置けるから」という理由だけで DB/ES を遠隔配置するのは避けた方がよい。

導入前チェック項目
------------------

採否判断の前に、少なくとも次を計測・整理しておくべきである。

#. server1 のピーク時 CPU、メモリ、swap、ディスク I/O。
#. PostgreSQL 接続遅延と主要クエリの応答時間。
#. Elasticsearch の検索応答時間、GC、indexing 時間、merge 負荷。
#. 登録、更新、著者一括更新、再索引など ES 反映を伴う処理の所要時間。
#. Celery queue の滞留数と処理完了までの時間。
#. server2 停止時にユーザ操作と定期処理がどこまで止まるか。
#. 障害時の一次切り分け担当、復旧手順、バックアップ復元手順。
#. 別拠点間の場合は、round-trip latency、packet loss、帯域、VPN/専用線の failover 挙動。

導入判断は、次の観点で Go / No-Go を決めるのがよい。

* Go: server1 のメモリ圧迫が改善し、主要操作の応答時間悪化が許容範囲に収まり、障害時運用も整理できる。
* No-Go: メモリ改善よりも通信遅延と運用複雑化の影響が大きい、または server2 障害時の受容が難しい。

補足
----

この検討は PostgreSQL と Elasticsearch の分離に絞ったものであり、WEKO の公開 API やデータモデルを変更するものではない。
将来的に二サーバー構成を安定運用するなら、次の追補検討余地がある。

* DB connection pool の見直し
* PostgreSQL / Redis / RabbitMQ の port 可変化
* Elasticsearch endpoint の URL 化と TLS/認証対応
* ``weko_admin.utils.elasticsearch_reindex()`` の HTTP 直組み解消
* install 手順の外部 DB/ES 対応
