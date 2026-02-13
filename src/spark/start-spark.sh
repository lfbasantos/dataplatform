#!/bin/bash
# Script parametrizavel para iniciar Apache Spark (Master + Worker)
# Integrado com MinIO (S3) e Hive Metastore (catalogo Iceberg)

set -e

echo "=== Iniciando Apache Spark ==="

# Detectar ambiente Codespaces
if [ -n "$CODESPACE_NAME" ]; then
    echo "  Detectado ambiente: GitHub Codespaces"
    SPARK_MASTER_UI="https://${CODESPACE_NAME}-8082.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
    SPARK_WORKER_UI="https://${CODESPACE_NAME}-8083.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
else
    echo "  Detectado ambiente: Local/VM"
    SPARK_MASTER_UI="http://localhost:8082"
    SPARK_WORKER_UI="http://localhost:8083"
fi

# Configuracoes parametrizaveis
SPARK_WORKER_MEM="${SPARK_WORKER_MEMORY:-1g}"
SPARK_WORKER_NCORES="${SPARK_WORKER_CORES:-2}"
SPARK_IMAGE="${SPARK_IMAGE:-apache/spark:3.5.3}"

echo ""
echo "=== Configuracoes ==="
echo "  Imagem: $SPARK_IMAGE"
echo "  Worker Memory: $SPARK_WORKER_MEM"
echo "  Worker Cores: $SPARK_WORKER_NCORES"
echo ""

# Diretorio base do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JARS_DIR="$SCRIPT_DIR/jars"

# Verificar e baixar JARs
echo "=== Verificando JARs ==="
mkdir -p "$JARS_DIR"

download_jar() {
    local name="$1"
    local url="$2"
    if [ -f "$JARS_DIR/$name" ]; then
        echo "  OK: $name"
    else
        echo "  Baixando: $name ..."
        curl -L -o "$JARS_DIR/$name" "$url"
        echo "  Baixado: $name"
    fi
}

download_jar "iceberg-spark-runtime-3.5_2.12-1.7.1.jar" \
    "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/1.7.1/iceberg-spark-runtime-3.5_2.12-1.7.1.jar"

download_jar "hadoop-aws-3.3.4.jar" \
    "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar"

download_jar "aws-java-sdk-bundle-1.12.262.jar" \
    "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.262/aws-java-sdk-bundle-1.12.262.jar"

# Verificar spark-defaults.conf
if [ ! -f "$SCRIPT_DIR/spark-defaults.conf" ]; then
    echo "ERRO: Arquivo spark-defaults.conf nao encontrado em $SCRIPT_DIR"
    exit 1
fi

echo ""

# --- SPARK MASTER ---
echo "=== Spark Master ==="

if docker ps -a --format '{{.Names}}' | grep -q '^spark-master$'; then
    echo "  Container 'spark-master' ja existe. Removendo..."
    docker stop spark-master 2>/dev/null || true
    docker rm spark-master 2>/dev/null || true
fi

echo "  Iniciando container spark-master..."
docker run -d \
  --name spark-master \
  --hostname spark-master \
  -p 8082:8080 \
  -p 7077:7077 \
  -e SPARK_MASTER_HOST=spark-master \
  -e SPARK_NO_DAEMONIZE=true \
  -v "$JARS_DIR/iceberg-spark-runtime-3.5_2.12-1.7.1.jar":/opt/spark/jars/iceberg-spark-runtime-3.5_2.12-1.7.1.jar \
  -v "$JARS_DIR/hadoop-aws-3.3.4.jar":/opt/spark/jars/hadoop-aws-3.3.4.jar \
  -v "$JARS_DIR/aws-java-sdk-bundle-1.12.262.jar":/opt/spark/jars/aws-java-sdk-bundle-1.12.262.jar \
  -v "$SCRIPT_DIR/spark-defaults.conf":/opt/spark/conf/spark-defaults.conf \
  --link minio:minio \
  --link hive-metastore:hive-metastore \
  --restart unless-stopped \
  "$SPARK_IMAGE" \
  /opt/spark/bin/spark-class org.apache.spark.deploy.master.Master

echo "  spark-master iniciado."

# Aguardar Master subir
echo "  Aguardando Master inicializar (10s)..."
sleep 10

# --- SPARK WORKER ---
echo ""
echo "=== Spark Worker ==="

if docker ps -a --format '{{.Names}}' | grep -q '^spark-worker$'; then
    echo "  Container 'spark-worker' ja existe. Removendo..."
    docker stop spark-worker 2>/dev/null || true
    docker rm spark-worker 2>/dev/null || true
fi

echo "  Iniciando container spark-worker..."
docker run -d \
  --name spark-worker \
  -p 8083:8081 \
  -e SPARK_NO_DAEMONIZE=true \
  -e SPARK_WORKER_MEMORY="$SPARK_WORKER_MEM" \
  -e SPARK_WORKER_CORES="$SPARK_WORKER_NCORES" \
  -v "$JARS_DIR/iceberg-spark-runtime-3.5_2.12-1.7.1.jar":/opt/spark/jars/iceberg-spark-runtime-3.5_2.12-1.7.1.jar \
  -v "$JARS_DIR/hadoop-aws-3.3.4.jar":/opt/spark/jars/hadoop-aws-3.3.4.jar \
  -v "$JARS_DIR/aws-java-sdk-bundle-1.12.262.jar":/opt/spark/jars/aws-java-sdk-bundle-1.12.262.jar \
  -v "$SCRIPT_DIR/spark-defaults.conf":/opt/spark/conf/spark-defaults.conf \
  --link spark-master:spark-master \
  --link minio:minio \
  --link hive-metastore:hive-metastore \
  --restart unless-stopped \
  "$SPARK_IMAGE" \
  /opt/spark/bin/spark-class org.apache.spark.deploy.worker.Worker spark://spark-master:7077

echo "  spark-worker iniciado."

echo ""
echo "========================================="
echo "  Spark cluster iniciado com sucesso!"
echo "========================================="
echo ""
echo "  Master UI:  $SPARK_MASTER_UI"
echo "  Worker UI:  $SPARK_WORKER_UI"
echo ""
echo "  Para verificar logs:"
echo "    docker logs -f spark-master"
echo "    docker logs -f spark-worker"
echo ""
echo "  Para abrir spark-shell:"
echo "    docker exec -it spark-master /opt/spark/bin/spark-shell"
echo ""
echo "  Para abrir pyspark:"
echo "    docker exec -it spark-master /opt/spark/bin/pyspark"
echo ""
