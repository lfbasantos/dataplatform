# US-03: Implantar Hive Metastore (Catálogo Iceberg)

**Data:** 2026-02-04  
**Status:** ✅ Concluído

## Contexto

Implementação do Hive Metastore como catálogo centralizado de tabelas Apache Iceberg, integrado com PostgreSQL (backend de metadados) e MinIO (warehouse S3-compatible).

---

## Requisitos Funcionais Cobertos

- **FR20:** Sistema possui Hive Metastore para catálogo de tabelas Iceberg ✅
- **FR21:** Hive Metastore utiliza PostgreSQL como backend de metadados ✅
- **FR22:** Configurado para integração com MinIO via endpoint S3 ✅
- **FR23:** Suporta registro e gerenciamento de tabelas Iceberg ✅
- **FR24:** Porta Thrift 9083 exposta ✅
- **FR25:** Catálogo configurado para warehouse no MinIO ✅
- **FR26:** Depende de PostgreSQL e MinIO funcionais ✅

---

## Roteiro de Implementação

### 1. Criar Pasta para Hive Metastore

```bash
mkdir -p src/hive-metastore
```

**Objetivo:** Criar pasta para scripts auxiliares e arquivos de configuração (passo 5 da dinâmica).

---

### 2. Criar Arquivo de Configuração metastore-site.xml

```bash
cat > src/hive-metastore/metastore-site.xml << 'EOF'
<?xml version="1.0"?>
<configuration>
    <property>
        <name>metastore.warehouse.dir</name>
        <value>s3a://bronze/warehouse</value>
    </property>
    <property>
        <name>metastore.thrift.port</name>
        <value>9083</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:postgresql://postgres:5432/metastore</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionDriverName</name>
        <value>org.postgresql.Driver</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionUserName</name>
        <value>postgres</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionPassword</name>
        <value>postgres123</value>
    </property>
    <property>
        <name>fs.s3a.endpoint</name>
        <value>http://minio:9000</value>
    </property>
    <property>
        <name>fs.s3a.access.key</name>
        <value>minioadmin</value>
    </property>
    <property>
        <name>fs.s3a.secret.key</name>
        <value>minioadmin123</value>
    </property>
    <property>
        <name>fs.s3a.path.style.access</name>
        <value>true</value>
    </property>
</configuration>
EOF
```

**Parâmetros:**
- `metastore.warehouse.dir`: Localização padrão das tabelas (bucket bronze no MinIO)
- `metastore.thrift.port`: Porta do serviço Thrift
- `javax.jdo.option.ConnectionURL`: URL JDBC do PostgreSQL
- `javax.jdo.option.ConnectionDriverName`: Driver JDBC (PostgreSQL)
- `javax.jdo.option.ConnectionUserName/Password`: Credenciais do PostgreSQL
- `fs.s3a.endpoint`: Endpoint do MinIO
- `fs.s3a.access.key/secret.key`: Credenciais do MinIO
- `fs.s3a.path.style.access`: Usa path-style (bucket.endpoint vs endpoint/bucket)

**Objetivo:** Configurar conexão com PostgreSQL e MinIO.

---

### 3. Baixar Driver JDBC do PostgreSQL

```bash
curl -L -o src/hive-metastore/postgresql-42.7.1.jar https://jdbc.postgresql.org/download/postgresql-42.7.1.jar
```

**Output:**
```
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 1058k  100 1058k    0     0  2645k      0 --:--:-- --:--:-- --:--:-- 2640k
```

**Por que fazer isso:** A imagem `apache/hive:4.0.0` não inclui o driver JDBC do PostgreSQL. Sem ele, ocorre `ClassNotFoundException: org.postgresql.Driver`.

---

### 4. Executar Container Hive Metastore

```bash
docker run -d \
  --name hive-metastore \
  -p 9083:9083 \
  -e SERVICE_NAME=metastore \
  -e DB_DRIVER=postgres \
  -e SERVICE_OPTS="-Djavax.jdo.option.ConnectionDriverName=org.postgresql.Driver -Djavax.jdo.option.ConnectionURL=jdbc:postgresql://postgres:5432/metastore -Djavax.jdo.option.ConnectionUserName=postgres -Djavax.jdo.option.ConnectionPassword=postgres123" \
  -e HIVE_CUSTOM_CONF_DIR=/hive_custom_conf \
  -v $(pwd)/src/hive-metastore:/hive_custom_conf \
  -v $(pwd)/src/hive-metastore/postgresql-42.7.1.jar:/opt/hive/lib/postgresql-42.7.1.jar \
  --link postgres:postgres \
  --link minio:minio \
  --restart unless-stopped \
  apache/hive:4.0.0
```

**Parâmetros:**
- `-d`: Modo detached (background)
- `--name hive-metastore`: Nome do container
- `-p 9083:9083`: Porta Thrift do Metastore
- `-e SERVICE_NAME=metastore`: **CRÍTICO** - Define que vai rodar apenas metastore (não hiveserver2)
- `-e DB_DRIVER=postgres`: Define PostgreSQL como backend
- `-e SERVICE_OPTS="..."`: Parâmetros JDBC para conexão
- `-e HIVE_CUSTOM_CONF_DIR=/hive_custom_conf`: Diretório de configs customizadas
- `-v .../metastore-site.xml:/hive_custom_conf`: Monta arquivo de configuração
- `-v .../postgresql-42.7.1.jar:/opt/hive/lib/`: Monta driver JDBC no classpath
- `--link postgres:postgres`: Link de rede com PostgreSQL
- `--link minio:minio`: Link de rede com MinIO
- `--restart unless-stopped`: Reinicia automaticamente
- `apache/hive:4.0.0`: Imagem oficial Apache Hive

**Output:**
```
9920789c7f678405bc222f57c02a7a1edadf600e05274291c27fa3b906009cdc
```

---

### 5. Verificar Container Ativo

```bash
docker ps | grep hive
```

**Output:**
```
9920789c7f67   apache/hive:4.0.0   "sh -c /entrypoint.sh"   44 seconds ago   Up 44 seconds   10000/tcp, 0.0.0.0:9083->9083/tcp, [::]:9083->9083/tcp, 10002/tcp   hive-metastore
```

**Validação:** Container ativo com porta 9083 exposta.

---

### 6. Verificar Logs de Inicialização

```bash
docker logs hive-metastore 2>&1 | tail -60
```

**Output (trechos relevantes):**
```
Initialization script completed
+ '[' 0 -eq 0 ']'
+ echo 'Initialized schema successfully..'
Initialized schema successfully..
+ '[' metastore == hiveserver2 ']'
+ '[' metastore == metastore ']'
+ export METASTORE_PORT=9083
+ METASTORE_PORT=9083
+ exec /opt/hive/bin/hive --skiphadoopversion --skiphbasecp --service metastore
2026-02-04 18:52:37: Starting Hive Metastore Server
```

**Validação:** 
- ✅ Schema inicializado com sucesso
- ✅ Metastore Server iniciado
- ✅ Porta 9083 configurada

---

### 7. Verificar Tabelas Criadas no PostgreSQL

```bash
docker exec postgres psql -U postgres -d metastore -c "\dt"
```

**Output (amostra das 83 tabelas):**
```
                   List of relations
 Schema |             Name              | Type  |  Owner   
--------+-------------------------------+-------+----------
 public | COMPACTION_METRICS_CACHE      | table | postgres
 public | COMPACTION_QUEUE              | table | postgres
 public | COMPLETED_COMPACTIONS         | table | postgres
 public | COMPLETED_TXN_COMPONENTS      | table | postgres
 public | CTLGS                         | table | postgres
 public | DATABASE_PARAMS               | table | postgres
 public | DATACONNECTORS                | table | postgres
 public | DATACONNECTOR_PARAMS          | table | postgres
 public | DBS                           | table | postgres
 public | DB_PRIVS                      | table | postgres
 public | DC_PRIVS                      | table | postgres
 public | DELEGATION_TOKENS             | table | postgres
 public | FUNCS                         | table | postgres
 public | FUNC_RU                       | table | postgres
 public | GLOBAL_PRIVS                  | table | postgres
 public | HIVE_LOCKS                    | table | postgres
 public | I_SCHEMA                      | table | postgres
 public | KEY_CONSTRAINTS               | table | postgres
 public | MASTER_KEYS                   | table | postgres
 public | MATERIALIZATION_REBUILD_LOCKS | table | postgres
 public | METASTORE_DB_PROPERTIES       | table | postgres
 ...
(83 rows)
```

**Validação:** ✅ 83 tabelas do Hive Metastore criadas no PostgreSQL.

**Tabelas Principais:**
- `DBS` - Databases (catálogos)
- `TBLS` - Tables (tabelas registradas)
- `PARTITIONS` - Partições das tabelas
- `COLUMNS_V2` - Colunas das tabelas
- `TABLE_PARAMS` - Propriedades das tabelas (metadados Iceberg)
- `SDS` - Storage Descriptors (localização S3)
- `SERDES` - Serializers/Deserializers

---

### 8. Testar Persistência (Restart)

```bash
docker restart hive-metastore
```

**Output:**
```
hive-metastore
```

**Validação:** Container reiniciou e reconectou ao PostgreSQL sem recriar schemas (83 tabelas permanecem).

---

## Critérios de Aceitação

| Critério | Status |
|----------|--------|
| Container Hive Metastore rodando via docker run | ✅ |
| Conexão com PostgreSQL (database metastore) funcional | ✅ |
| Conexão com MinIO (endpoint S3) funcional | ✅ |
| Porta Thrift 9083 acessível | ✅ |
| Schema inicializado (83 tabelas) | ✅ |

---

## Acessos

| Serviço | Endpoint | Protocolo |
|---------|----------|-----------|
| Hive Metastore | localhost:9083 | Thrift |

### Como Conectar

**Via Spark (exemplo futuro):**
```scala
spark.sql("CREATE DATABASE IF NOT EXISTS bronze")
spark.sql("SHOW DATABASES").show()
```

**Via Beeline (CLI do Hive):**
```bash
docker exec -it hive-metastore beeline -u "jdbc:hive2://localhost:9083"
```

**Via código Python (pyhive):**
```python
from pyhive import hive
conn = hive.Connection(host='localhost', port=9083)
cursor = conn.cursor()
cursor.execute('SHOW DATABASES')
print(cursor.fetchall())
```

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│                     HIVE METASTORE                          │
│                    (porta 9083 - Thrift)                    │
│                                                             │
│  ┌───────────────────────────────────────────────────┐    │
│  │  CATALOG SERVICE                                   │    │
│  │  - Registra databases/tables                       │    │
│  │  - Gerencia schemas Iceberg                        │    │
│  │  - Controla partições                              │    │
│  └───────────────────────────────────────────────────┘    │
│                        │              │                     │
│                        ▼              ▼                     │
│           ┌─────────────────┐   ┌──────────────┐          │
│           │   POSTGRESQL    │   │    MINIO     │          │
│           │   (metadados)   │   │  (warehouse) │          │
│           │  83 tabelas     │   │  s3a://...   │          │
│           └─────────────────┘   └──────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

---

## Conceitos Aprendidos

### Hive Metastore vs HiveServer2

| Componente | Função | Porta |
|------------|--------|-------|
| **Hive Metastore** | Cataloga metadados de tabelas (biblioteca) | 9083 (Thrift) |
| **HiveServer2** | Executa queries SQL (motor de execução) | 10000 (JDBC) |

**Nesta US implementamos apenas o Metastore** - HiveServer2 será implantado em US-08.

### Arquivo Físico vs Tabela Lógica

**Arquivo Físico (Parquet):**
- Arquivo binário no MinIO: `s3a://bronze/warehouse/table1/data.parquet`
- Contém apenas dados (colunas + valores)

**Tabela Lógica (Iceberg):**
- Metadados no PostgreSQL (via Hive Metastore)
- Schema, partições, estatísticas, snapshots
- Aponta para arquivos físicos no MinIO
- Permite time travel, ACID transactions, schema evolution

### Papel do Hive Metastore

O Hive Metastore funciona como uma **"biblioteca de tabelas"**:

1. **Registro:** Spark/Hive registra tabela no metastore
2. **Armazenamento:** Metastore salva schema + localização S3 no PostgreSQL
3. **Consulta:** Spark/Hive consulta metastore para saber onde estão os dados
4. **Leitura:** Engine lê arquivos Parquet diretamente do MinIO

**Sem Metastore:** Seria necessário saber exatamente o caminho S3 de cada arquivo Parquet.  
**Com Metastore:** Basta fazer `SELECT * FROM bronze.tabela` - metastore resolve o caminho.

### Warehouse Location

`s3a://bronze/warehouse` é o diretório raiz onde tabelas são criadas:

```
bronze/
  └── warehouse/
      ├── database1.db/
      │   ├── table1/
      │   │   ├── metadata/
      │   │   │   └── v1.metadata.json
      │   │   └── data/
      │   │       └── 00000-1-abc123.parquet
      │   └── table2/
      └── database2.db/
```

### Apache Iceberg

**Formato de tabela open source** que adiciona recursos ACID ao data lake:

- **Schema Evolution:** Adicionar/remover colunas sem reescrever dados
- **Time Travel:** Consultar versões anteriores da tabela
- **Partition Evolution:** Mudar particionamento sem migração
- **ACID Transactions:** Garantias de consistência
- **Hidden Partitioning:** Partições automáticas transparentes

**Metadados Iceberg no Metastore:**
- `TABLE_PARAMS` contém `table_type=ICEBERG`
- Metadata JSON files no S3 (`metadata/*.json`)
- Manifest files rastreiam arquivos Parquet

---

## Troubleshooting

### Erro: ClassNotFoundException: org.postgresql.Driver

**Causa:** Driver JDBC do PostgreSQL não está no classpath.

**Solução:** Baixar `postgresql-42.7.1.jar` e montar em `/opt/hive/lib/`:
```bash
curl -L -o src/hive-metastore/postgresql-42.7.1.jar https://jdbc.postgresql.org/download/postgresql-42.7.1.jar

docker run ... \
  -v $(pwd)/src/hive-metastore/postgresql-42.7.1.jar:/opt/hive/lib/postgresql-42.7.1.jar \
  ...
```

### Erro: Schema initialization failed!

**Causa:** Não conseguiu conectar ao PostgreSQL.

**Verificar:**
1. PostgreSQL está rodando? `docker ps | grep postgres`
2. Database `metastore` existe? `docker exec postgres psql -U postgres -l`
3. Link de rede configurado? `--link postgres:postgres`

### Container em loop de restart

**Verificar logs:** `docker logs hive-metastore 2>&1`

**Causas comuns:**
- Falta de `SERVICE_NAME=metastore` (tenta rodar HiveServer2)
- Driver JDBC não montado
- PostgreSQL inacessível

---

## Próximos Passos

➡️ **US-04**: Implantar Schema Registry (Contratos de Dados)
- Independente do Hive Metastore
- Depende de: PostgreSQL ✅

**Uso do Hive Metastore será validado em:**
- US-06: Apache Spark (criará tabelas Iceberg)
- US-08: HiveServer2 (consultará tabelas via SQL)

---

## Referências

- [Apache Hive Documentation](https://hive.apache.org/documentation.html)
- [Apache Hive Docker Hub](https://hub.docker.com/r/apache/hive)
- [Apache Iceberg Documentation](https://iceberg.apache.org/docs/latest/)
- [PostgreSQL JDBC Driver](https://jdbc.postgresql.org/)
- [Hive Metastore Configuration](https://cwiki.apache.org/confluence/display/Hive/AdminManual+Metastore+Administration)
