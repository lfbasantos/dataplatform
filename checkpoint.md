# Checkpoint - US-06: Apache Spark

**Data:** 2026-02-12
**Branch:** main

---

## Passos Concluidos

### 1. Verificacao da imagem Docker
- `bitnami/spark` nao esta mais disponivel no Docker Hub
- Imagem escolhida: `apache/spark:3.5.3` (Hadoop 3.3.4, Spark home: `/opt/spark`)

### 2. Arquivos criados
- `src/spark/spark-defaults.conf` — configuracao S3A + Iceberg + Hive Metastore
- `src/spark/start-spark.sh` — script idempotente de deploy (Master + Worker)
- `src/spark/jars/` — diretorio para JARs (baixados automaticamente pelo script)
- `.gitignore` — adicionado `src/spark/jars/*.jar`

### 3. JARs baixados (pelo script, ~309 MB total)
- `iceberg-spark-runtime-3.5_2.12-1.7.1.jar`
- `hadoop-aws-3.3.4.jar`
- `aws-java-sdk-bundle-1.12.262.jar`

### 4. Containers Spark subindo
- Corrigido bug: adicionado `--hostname spark-master` no docker run (resolvia `UnresolvedAddressException`)
- `spark-master` UP (portas 8082, 7077)
- `spark-worker` UP (porta 8083, 1g RAM, 2 cores)

### 5. Fix no Hive Metastore (US-03)
- Problema: `ClassNotFoundException: S3AFileSystem` ao criar databases
- Causa: JARs `hadoop-aws` e `aws-java-sdk-bundle` estavam em `/opt/hadoop/share/hadoop/tools/lib/` mas NAO no classpath do Hive (`/opt/hive/lib/`)
- Fix aplicado:
  ```bash
  docker exec --user root hive-metastore cp /opt/hadoop/share/hadoop/tools/lib/hadoop-aws-3.3.6.jar /opt/hive/lib/
  docker exec --user root hive-metastore cp /opt/hadoop/share/hadoop/tools/lib/aws-java-sdk-bundle-1.12.367.jar /opt/hive/lib/
  docker restart hive-metastore
  ```
- **ATENCAO:** esse fix nao e persistente! Ao recriar o container hive-metastore, precisa reaplicar.

### 6. Validacoes concluidas
- `SHOW DATABASES` — OK (retornou `default`)
- `CREATE DATABASE bronze` — OK (retornou `bronze, default`)

---

## Passos Pendentes

### 7. Testar leitura CSV do MinIO
```bash
docker exec spark-master /opt/spark/bin/spark-sql --conf spark.ui.enabled=false \
  -e "SELECT * FROM csv.\`s3a://landing/bilhetagem-sample.csv\` LIMIT 5;"
```

### 8. Testar criacao de tabela Iceberg
- Ler CSV do landing como DataFrame
- Adicionar colunas `_ingested_at` e `_source_file`
- Criar tabela `iceberg.bronze.bilhetagem`
- Verificar dados no MinIO (`mc ls local/bronze/warehouse/`)

### 9. Criar documentacao `docs/us-06-spark.md`
- Seguir padrao de `docs/us-05-nifi.md`

### 10. Commit git
- `feat: US-06 concluida - Apache Spark processamento`

---

## Comandos para Retomar

Ao reabrir o Codespace:

```bash
# 1. Verificar containers
docker ps -a

# 2. Se hive-metastore perdeu o fix dos JARs (recriado):
docker exec --user root hive-metastore cp /opt/hadoop/share/hadoop/tools/lib/hadoop-aws-3.3.6.jar /opt/hive/lib/
docker exec --user root hive-metastore cp /opt/hadoop/share/hadoop/tools/lib/aws-java-sdk-bundle-1.12.367.jar /opt/hive/lib/
docker restart hive-metastore

# 3. Se spark-master ou spark-worker estiverem parados:
docker start spark-master spark-worker

# 4. Se precisar recriar os containers Spark do zero:
./src/spark/start-spark.sh
```
