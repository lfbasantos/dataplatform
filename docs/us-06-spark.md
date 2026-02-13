# US-06: Implantar Apache Spark (Processamento)

**Data:** 2026-02-13
**Status:** Concluido

## Contexto

Implementacao do Apache Spark como engine de processamento distribuido na Open Data Platform. Spark conecta ao Hive Metastore (catalogo de tabelas) e MinIO (storage S3-compatible) para leitura/escrita de tabelas Apache Iceberg, habilitando a arquitetura Medallion (Landing -> Bronze -> Silver -> Gold).

---

## Requisitos Funcionais Cobertos

- **FR70:** Sistema possui Apache Spark para processamento distribuido
- **FR71:** Spark Master expoe UI web (porta 8082)
- **FR72:** Spark Worker conectado ao Master com recursos configurados
- **FR73:** Spark integrado com MinIO via protocolo S3A
- **FR74:** Spark integrado com Hive Metastore via Thrift
- **FR75:** Spark configurado com catalogo Iceberg
- **FR76:** Spark Extensions habilitadas (MERGE INTO, etc.)
- **FR80:** Leitura de dados do MinIO via Spark
- **FR81:** Escrita de tabelas Iceberg via Spark
- **FR82:** Colunas de metadados de ingestao (`_ingested_at`)
- **FR83:** Colunas de rastreabilidade (`_source_file`)

---

## Roteiro de Implementacao

### 1. Escolha da Imagem Docker

Imagem `bitnami/spark` nao esta mais disponivel no Docker Hub. Utilizada imagem oficial `apache/spark:3.5.3`.

**Caracteristicas da imagem:**
- Spark 3.5.3 com Scala 2.12
- Hadoop 3.3.4 (hadoop-client-api, hadoop-client-runtime)
- Java 11 (OpenJDK)
- Spark home: `/opt/spark`
- Entrypoint: passthrough mode (aceita comandos diretos)

**Verificacao da versao Hadoop:**
```bash
docker run --rm apache/spark:3.5.3 ls /opt/spark/jars/ | grep hadoop-client
```
Output:
```
hadoop-client-api-3.3.4.jar
hadoop-client-runtime-3.3.4.jar
```

> A versao do Hadoop determina quais JARs de hadoop-aws e aws-java-sdk devem ser usados. Versoes incompativeis causam `NoSuchMethodError`.

---

### 2. JARs de Dependencia

Tres JARs necessarios, baixados automaticamente pelo script `start-spark.sh`:

| JAR | Versao | Tamanho | Motivo |
|-----|--------|---------|--------|
| `iceberg-spark-runtime-3.5_2.12` | 1.7.1 | ~41 MB | Suporte ao formato Iceberg |
| `hadoop-aws` | 3.3.4 | ~1 MB | Filesystem S3A para Hadoop |
| `aws-java-sdk-bundle` | 1.12.262 | ~267 MB | AWS SDK (cliente S3) |

**Compatibilidade de versoes:**
- `hadoop-aws` DEVE ser mesma versao do Hadoop na imagem (3.3.4)
- `aws-java-sdk-bundle` DEVE ser a versao que hadoop-aws 3.3.4 foi compilado contra (1.12.262)
- `iceberg-spark-runtime` DEVE ser compativel com Spark 3.5 + Scala 2.12

JARs adicionados ao `.gitignore` (total ~309 MB):
```
src/spark/jars/*.jar
```

---

### 3. Arquivo de Configuracao

Criado [src/spark/spark-defaults.conf](../src/spark/spark-defaults.conf) com:

```properties
# MinIO / S3A
spark.hadoop.fs.s3a.endpoint                    http://minio:9000
spark.hadoop.fs.s3a.access.key                  minioadmin
spark.hadoop.fs.s3a.secret.key                  minioadmin123
spark.hadoop.fs.s3a.path.style.access           true
spark.hadoop.fs.s3a.impl                        org.apache.hadoop.fs.s3a.S3AFileSystem
spark.hadoop.fs.s3a.connection.ssl.enabled      false

# Iceberg Catalogs
spark.sql.catalog.spark_catalog                 org.apache.iceberg.spark.SparkSessionCatalog
spark.sql.catalog.spark_catalog.type            hive
spark.sql.catalog.spark_catalog.uri             thrift://hive-metastore:9083

spark.sql.catalog.iceberg                       org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.iceberg.type                  hive
spark.sql.catalog.iceberg.uri                   thrift://hive-metastore:9083
spark.sql.catalog.iceberg.warehouse             s3a://bronze/warehouse

# Iceberg Extensions
spark.sql.extensions                            org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions

# Hive Metastore
spark.hive.metastore.uris                       thrift://hive-metastore:9083
spark.sql.catalogImplementation                 hive
spark.sql.warehouse.dir                         s3a://bronze/warehouse
```

**Estrategia de dois catalogos:**
- `spark_catalog` (SparkSessionCatalog): catalogo padrao, permite misturar tabelas Iceberg e nao-Iceberg
- `iceberg` (SparkCatalog): catalogo dedicado para operacoes explicitas Iceberg (acesso via `iceberg.database.table`)

---

### 4. Script de Deploy

Criado [src/spark/start-spark.sh](../src/spark/start-spark.sh) com:

- Deteccao automatica de GitHub Codespaces
- Download automatico de JARs faltantes do Maven Central
- Remocao de containers existentes (idempotente)
- Deploy do Master e Worker com `--restart unless-stopped`

**Executar:**
```bash
chmod +x src/spark/start-spark.sh
./src/spark/start-spark.sh
```

**Output esperado:**
```
=== Iniciando Apache Spark ===
  Detectado ambiente: GitHub Codespaces
=== Verificando JARs ===
  OK: iceberg-spark-runtime-3.5_2.12-1.7.1.jar
  OK: hadoop-aws-3.3.4.jar
  OK: aws-java-sdk-bundle-1.12.262.jar
=== Spark Master ===
  Iniciando container spark-master...
  spark-master iniciado.
  Aguardando Master inicializar (10s)...
=== Spark Worker ===
  Iniciando container spark-worker...
  spark-worker iniciado.
=========================================
  Spark cluster iniciado com sucesso!
=========================================
```

---

### 5. Docker Run - Detalhes

**Spark Master:**
```bash
docker run -d \
  --name spark-master \
  --hostname spark-master \
  -p 8082:8080 \
  -p 7077:7077 \
  -e SPARK_MASTER_HOST=spark-master \
  -e SPARK_NO_DAEMONIZE=true \
  -v jars/iceberg-spark-runtime-3.5_2.12-1.7.1.jar:/opt/spark/jars/... \
  -v jars/hadoop-aws-3.3.4.jar:/opt/spark/jars/... \
  -v jars/aws-java-sdk-bundle-1.12.262.jar:/opt/spark/jars/... \
  -v spark-defaults.conf:/opt/spark/conf/spark-defaults.conf \
  --link minio:minio \
  --link hive-metastore:hive-metastore \
  --restart unless-stopped \
  apache/spark:3.5.3 \
  /opt/spark/bin/spark-class org.apache.spark.deploy.master.Master
```

**Spark Worker:**
```bash
docker run -d \
  --name spark-worker \
  -p 8083:8081 \
  -e SPARK_NO_DAEMONIZE=true \
  -e SPARK_WORKER_MEMORY=1g \
  -e SPARK_WORKER_CORES=2 \
  -v (mesmos JARs e config do Master) \
  --link spark-master:spark-master \
  --link minio:minio \
  --link hive-metastore:hive-metastore \
  --restart unless-stopped \
  apache/spark:3.5.3 \
  /opt/spark/bin/spark-class org.apache.spark.deploy.worker.Worker spark://spark-master:7077
```

> `--hostname spark-master` e obrigatorio no Master. Sem ele, o Spark nao consegue resolver o proprio hostname e falha com `UnresolvedAddressException`.

---

### 6. Validacao

#### 6.1 Verificar Containers

```bash
docker ps | grep spark
```

Output esperado:
```
spark-worker    Up X minutes    0.0.0.0:8083->8081/tcp
spark-master    Up X minutes    0.0.0.0:8082->8080/tcp, 0.0.0.0:7077->7077/tcp
```

#### 6.2 Verificar Logs

```bash
docker logs spark-master 2>&1 | tail -5
```
Procure por: `Master: I have been elected leader! New state: ALIVE`

```bash
docker logs spark-worker 2>&1 | tail -5
```
Procure por: `Registering worker ... with 2 cores, 1024.0 MiB RAM`

#### 6.3 Abrir spark-shell

```bash
docker exec -it spark-master /opt/spark/bin/spark-shell
```

#### 6.4 Testar Hive Metastore

```scala
spark.sql("SHOW DATABASES").show()
```
Output esperado:
```
+---------+
|namespace|
+---------+
|   bronze|
|  default|
+---------+
```

#### 6.5 Testar Leitura S3 (MinIO)

```scala
val df = spark.read.option("header","true").csv("s3a://landing/bilhetagem-sample.csv")
df.show()
```
Output esperado: 10 registros de bilhetagem.

#### 6.6 Criar Tabela Iceberg

```scala
import org.apache.spark.sql.functions._

val billing = spark.read
  .option("header","true")
  .option("inferSchema","true")
  .csv("s3a://landing/bilhetagem-sample.csv")

val billingWithMeta = billing
  .withColumn("_ingested_at", current_timestamp())
  .withColumn("_source_file", lit("bilhetagem-sample.csv"))

billingWithMeta.writeTo("iceberg.bronze.bilhetagem")
  .tableProperty("format-version", "2")
  .createOrReplace()
```

#### 6.7 Verificar Tabela

```scala
spark.sql("SELECT * FROM iceberg.bronze.bilhetagem").show()
```
Output esperado: 10 registros com colunas `_ingested_at` e `_source_file`.

---

## Arquitetura

```
┌─────────────────┐     ┌─────────────────┐
│  SPARK MASTER   │     │  SPARK WORKER   │
│  :8082 (UI)     │◄────│  :8083 (UI)     │
│  :7077 (cluster)│     │  1g RAM/2 cores │
└────┬───────┬────┘     └────┬───────┬────┘
     │       │               │       │
     ▼       ▼               ▼       ▼
┌─────────┐ ┌──────────────┐
│  MINIO  │ │HIVE METASTORE│
│  :9000  │ │    :9083     │
└─────────┘ └──────┬───────┘
                   │
            ┌──────▼───────┐
            │  POSTGRESQL  │
            │    :5432     │
            └──────────────┘
```

**Fluxo de dados:**
1. NiFi ingere CSV para `s3a://landing/` (US-05)
2. Spark le do landing via S3A
3. Spark transforma e adiciona metadados
4. Spark escreve tabela Iceberg em `s3a://bronze/warehouse/`
5. Metadados registrados no Hive Metastore (PostgreSQL)

---

## Troubleshooting

### Problema 1: UnresolvedAddressException no Master

**Sintoma:**
```
ERROR SparkUncaughtExceptionHandler: Uncaught exception
java.nio.channels.UnresolvedAddressException
```

**Causa:** Container nao consegue resolver o hostname `spark-master`.

**Solucao:** Adicionar `--hostname spark-master` ao `docker run` do Master.

---

### Problema 2: ClassNotFoundException S3AFileSystem no CREATE DATABASE

**Sintoma:**
```
MetaException: java.lang.ClassNotFoundException:
Class org.apache.hadoop.fs.s3a.S3AFileSystem not found
```

**Causa:** Hive Metastore nao tem `hadoop-aws` no classpath. Os JARs existem em `/opt/hadoop/share/hadoop/tools/lib/` mas nao em `/opt/hive/lib/`.

**Solucao:**
```bash
docker exec --user root hive-metastore \
  cp /opt/hadoop/share/hadoop/tools/lib/hadoop-aws-3.3.6.jar /opt/hive/lib/
docker exec --user root hive-metastore \
  cp /opt/hadoop/share/hadoop/tools/lib/aws-java-sdk-bundle-1.12.367.jar /opt/hive/lib/
docker restart hive-metastore
```

> **ATENCAO:** Esse fix nao e persistente. Ao recriar o container do Hive Metastore, precisa reaplicar.

---

### Problema 3: Worker nao conecta ao Master

**Causa:** Worker iniciou antes do Master estar pronto.

**Solucao:** O script inclui `sleep 10` entre Master e Worker. Se persistir, reinicie o Worker:
```bash
docker restart spark-worker
```

---

### Problema 4: Erro de conexao com MinIO (Connection Refused)

**Causa:** Container MinIO nao esta rodando ou `--link minio:minio` ausente.

**Validacao:**
```bash
docker exec spark-master ping -c 3 minio
```

---

## Conceitos Aprendidos

### Arquitetura Master/Worker
- **Master:** gerencia recursos e agenda jobs. Nao processa dados.
- **Worker:** executa tasks. Acessa dados diretamente (S3, HMS).
- Worker precisa de `--link` para MinIO e HMS porque os executors rodam nele.

### Catalogo Iceberg
- **SparkSessionCatalog:** catalogo padrao, permite misturar tabelas Iceberg e nao-Iceberg
- **SparkCatalog:** catalogo dedicado, acesso via `iceberg.database.table`
- Metadados armazenados no Hive Metastore (PostgreSQL)
- Dados armazenados no MinIO (S3A)

### Format Version 2
- Iceberg v2 habilita row-level deletes, updates e merge operations
- Suporte a equality e position deletes
- Necessario para `MERGE INTO` e `DELETE FROM`

---

## Acessos

| Servico | URL | Credenciais |
|---------|-----|-------------|
| Spark Master UI | http://localhost:8082 | - |
| Spark Worker UI | http://localhost:8083 | - |
| spark-shell | `docker exec -it spark-master /opt/spark/bin/spark-shell` | - |
| pyspark | `docker exec -it spark-master /opt/spark/bin/pyspark` | - |
| spark-sql | `docker exec -it spark-master /opt/spark/bin/spark-sql` | - |

---

## Limitacoes Conhecidas

### Fix HMS nao persistente
O fix de copiar JARs S3A para `/opt/hive/lib/` nao sobrevive a recriacao do container. Sera resolvido na US-13 (Docker Compose) com volume ou Dockerfile customizado.

### Modo Local no spark-shell
O `spark-shell` roda em modo `local[*]` por padrao (nao conecta ao cluster Master/Worker). Para submeter jobs ao cluster, usar `spark-submit --master spark://spark-master:7077`.

---

## Proximos Passos

- [ ] **US-07:** Configurar Great Expectations para validacao de qualidade
- [ ] **US-08:** Implantar HiveServer2 para consultas SQL
- [ ] **Melhoria:** Persistir fix do HMS em Dockerfile ou entrypoint customizado
- [ ] **Melhoria:** Criar job Spark automatizado (Landing -> Bronze)

---

## Validacao Final

- [x] Container Spark Master rodando via docker run
- [x] Container Spark Worker rodando e conectado ao Master (2 cores, 1 GB)
- [x] UI Master acessivel na porta 8082
- [x] spark-shell conectando ao Hive Metastore (`SHOW DATABASES`)
- [x] Leitura de arquivo do MinIO via Spark (10 registros CSV)
- [x] Escrita de tabela Iceberg via Spark (`iceberg.bronze.bilhetagem`)
- [x] Colunas de metadados `_ingested_at` e `_source_file` presentes
- [x] Documentacao completa criada
- [x] Script parametrizavel versionado no git

**Resumo Executivo:**
Apache Spark 3.5.3 operacional com cluster Master/Worker. Integracoes com MinIO (S3A) e Hive Metastore (Thrift) validadas. Tabela Iceberg v2 criada com sucesso no catalogo `iceberg.bronze.bilhetagem` com 10 registros e metadados de ingestao. Imagem `bitnami/spark` substituida por `apache/spark` oficial (bitnami indisponivel no Docker Hub).
