# US-02: Implantar PostgreSQL (Backend de Metadados)

**Data:** 2026-02-04  
**Status:** ✅ Concluído

## Contexto

Implementação do PostgreSQL como backend de metadados centralizado para 5 serviços da plataforma: Hive Metastore, Schema Registry, Apache Airflow, Apache Ranger e Apache Atlas.

---

## Requisitos Funcionais Cobertos

- **FR17:** Sistema possui PostgreSQL como backend de metadados ✅
- **FR18:** PostgreSQL expõe porta padrão (5432) ✅
- **FR19:** PostgreSQL suporta múltiplos databases isolados ✅

---

## Roteiro de Implementação

### 1. Criar Volume Persistente

```bash
docker volume create postgres-data
```

**Output:**
```
postgres-data
```

**Objetivo:** Garantir persistência dos metadados após restart do container (FR03).

---

### 2. Executar Container PostgreSQL

```bash
docker run -d \
  --name postgres \
  -p 5432:5432 \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres123 \
  -e POSTGRES_DB=postgres \
  -v postgres-data:/var/lib/postgresql/data \
  --restart unless-stopped \
  postgres:15
```

**Parâmetros:**
- `-d`: Executa em modo detached (background)
- `--name postgres`: Nome do container
- `-p 5432:5432`: Mapeia porta padrão PostgreSQL (host:container)
- `-e POSTGRES_USER=postgres`: Define usuário root (superuser)
- `-e POSTGRES_PASSWORD=postgres123`: Define senha do superuser
- `-e POSTGRES_DB=postgres`: Cria database padrão `postgres`
- `-v postgres-data:/var/lib/postgresql/data`: Volume persistente
- `--restart unless-stopped`: Reinicia automaticamente
- `postgres:15`: Imagem oficial PostgreSQL versão 15

**Output:**
```
Status: Downloaded newer image for postgres:15
51cd4b07f9066cb6bb9f6201abf959d8c6a335ed42ae30fa8e57a627dd117503
```

---

### 3. Verificar Container Ativo

```bash
docker ps | grep postgres
```

**Output:**
```
51cd4b07f906   postgres:15   "docker-entrypoint.s…"   52 seconds ago   Up 51 seconds   0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp   postgres
```

**Validação:** Container ativo com porta 5432 exposta.

---

### 4. Verificar Logs de Inicialização

```bash
docker logs postgres | tail -20
```

**Output:**
```
server started

/usr/local/bin/docker-entrypoint.sh: ignoring /docker-entrypoint-initdb.d/*

2026-02-04 18:27:35.590 UTC [47] LOG:  received fast shutdown request
waiting for server to shut down....2026-02-04 18:27:35.593 UTC [47] LOG:  aborting any active transactions
2026-02-04 18:27:35.596 UTC [47] LOG:  background worker "logical replication launcher" (PID 53) exited with exit code 1
2026-02-04 18:27:35.596 UTC [48] LOG:  shutting down
2026-02-04 18:27:35.597 UTC [48] LOG:  checkpoint starting: shutdown immediate
2026-02-04 18:27:35.604 UTC [48] LOG:  checkpoint complete: wrote 3 buffers (0.0%); 0 WAL file(s) added, 0 removed, 0 recycled; write=0.002 s, sync=0.001 s, total=0.008 s; sync files=2, longest=0.001 s, average=0.001 s; distance=0 kB, estimate=0 kB
2026-02-04 18:27:35.608 UTC [47] LOG:  database system is shut down
 done
server stopped

PostgreSQL init process complete; ready for start up.
```

**Validação:** PostgreSQL inicializado e pronto para conexões.

---

### 5. Criar Database para Hive Metastore

```bash
docker exec -it postgres psql -U postgres -c "CREATE DATABASE metastore;"
```

**Output:**
```
CREATE DATABASE
```

**Objetivo:** Database isolado para Hive Metastore armazenar metadados de tabelas Iceberg.

---

### 6. Criar Database para Schema Registry

```bash
docker exec -it postgres psql -U postgres -c "CREATE DATABASE schemaregistry;"
```

**Output:**
```
CREATE DATABASE
```

**Objetivo:** Database isolado para Schema Registry armazenar schemas Avro e versionamento.

---

### 7. Criar Database para Airflow

```bash
docker exec -it postgres psql -U postgres -c "CREATE DATABASE airflow;"
```

**Output:**
```
CREATE DATABASE
```

**Objetivo:** Database isolado para Airflow armazenar metadados de DAGs e execuções.

---

### 8. Criar Database para Ranger

```bash
docker exec -it postgres psql -U postgres -c "CREATE DATABASE ranger;"
```

**Output:**
```
CREATE DATABASE
```

**Objetivo:** Database isolado para Ranger armazenar políticas de segurança e auditoria.

---

### 9. Criar Database para Atlas

```bash
docker exec -it postgres psql -U postgres -c "CREATE DATABASE atlas;"
```

**Output:**
```
CREATE DATABASE
```

**Objetivo:** Database isolado para Atlas armazenar governança e linhagem de dados.

---

### 10. Listar Todos os Databases Criados

```bash
docker exec -it postgres psql -U postgres -c "\l"
```

**Output:**
```
                                                   List of databases
      Name      |  Owner   | Encoding |  Collate   |   Ctype    | ICU Locale | Locale Provider |   Access privileges   
----------------+----------+----------+------------+------------+------------+-----------------+-----------------------
 airflow        | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 atlas          | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 metastore      | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 postgres       | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 ranger         | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 schemaregistry | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 template0      | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
                |          |          |            |            |            |                 | postgres=CTc/postgres
 template1      | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
                |          |          |            |            |            |                 | postgres=CTc/postgres
(8 rows)
```

**Validação:** 5 databases criados com sucesso: airflow, atlas, metastore, ranger, schemaregistry.

---

### 11. Testar Persistência (Restart)

#### 11.1. Reiniciar Container

```bash
docker restart postgres
```

**Output:**
```
postgres
```

#### 11.2. Verificar Databases Após Restart

```bash
docker exec -it postgres psql -U postgres -c "\l"
```

**Output:**
```
                                                   List of databases
      Name      |  Owner   | Encoding |  Collate   |   Ctype    | ICU Locale | Locale Provider |   Access privileges   
----------------+----------+----------+------------+------------+------------+-----------------+-----------------------
 airflow        | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 atlas          | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 metastore      | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 postgres       | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 ranger         | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 schemaregistry | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 template0      | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
                |          |          |            |            |            |                 | postgres=CTc/postgres
 template1      | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
                |          |          |            |            |            |                 | postgres=CTc/postgres
(8 rows)
```

**Validação:** ✅ Todos os databases persistiram após restart do container.

---

## Critérios de Aceitação

| Critério | Status |
|----------|--------|
| Container PostgreSQL rodando via docker run | ✅ |
| Conexão funcional via cliente SQL | ✅ |
| Databases criados: metastore, schemaregistry, airflow, ranger, atlas | ✅ |
| Volume persistente configurado | ✅ |
| Dados persistem após restart do container | ✅ |

---

## Acessos

| Serviço | Endpoint | Credenciais |
|---------|----------|-------------|
| PostgreSQL | localhost:5432 | User: `postgres`<br>Password: `postgres123` |

### Como Conectar

**Via psql (dentro do container):**
```bash
docker exec -it postgres psql -U postgres
```

**Via psql (do host - requer psql instalado):**
```bash
psql -h localhost -p 5432 -U postgres -d postgres
```

**String de Conexão JDBC:**
```
jdbc:postgresql://localhost:5432/metastore?user=postgres&password=postgres123
```

---

## Clientes Recomendados

### 1. **pgAdmin** (Recomendado - Interface Gráfica)
- **Plataformas:** Windows, Mac, Linux, Web
- **Licença:** Gratuito (open source)
- **Download:** https://www.pgadmin.org/download/
- **Configuração:** 
  - Host: localhost
  - Port: 5432
  - Username: postgres
  - Password: postgres123

### 2. **DBeaver** (Universal)
- **Plataformas:** Windows, Mac, Linux
- **Licença:** Gratuito (Community Edition)
- **Download:** https://dbeaver.io/download/
- **Suporta:** PostgreSQL, MySQL, Oracle, SQL Server, etc.

### 3. **psql** (CLI nativo)
- Já incluído no container
- Leve e rápido para operações via terminal

---

## Databases e Seus Propósitos

| Database | Serviço | Propósito |
|----------|---------|-----------|
| `metastore` | Hive Metastore | Metadados de tabelas Iceberg (schemas, partições, snapshots) |
| `schemaregistry` | Schema Registry | Schemas Avro registrados e políticas de evolução |
| `airflow` | Apache Airflow | Metadados de DAGs, task instances, logs de execução |
| `ranger` | Apache Ranger | Políticas RBAC, mascaramento de dados, logs de auditoria |
| `atlas` | Apache Atlas | Governança de dados, linhagem, classificações, glossário |

---

## Conceitos Aprendidos

### Por que PostgreSQL para Metadados?

**Metadados ≠ Dados**
- **Dados** (big data): Armazenados no MinIO (data lake) em formato Parquet/Iceberg
- **Metadados** (pequenos): Armazenados no PostgreSQL (banco relacional ACID)

**Razões:**
1. **Consistência ACID:** Transações garantem integridade referencial
2. **Consultas Rápidas:** Índices otimizados para lookup de metadados
3. **Tamanho Reduzido:** Metadados são MB/GB, não TB/PB
4. **Padrão da Indústria:** Hive, Presto, Trino usam RDBMS para metadados

### Isolamento de Databases

Cada serviço tem seu próprio database para:
- **Isolamento de schemas:** Evitar conflitos de nomes de tabelas
- **Segurança:** Permissões granulares por database
- **Backup seletivo:** Restaurar apenas um serviço sem afetar outros
- **Troubleshooting:** Identificar facilmente origem de problemas

### Volume Persistente

`/var/lib/postgresql/data` contém:
- **Dados das tabelas** (arquivos PGDATA)
- **WAL (Write-Ahead Log):** Para recuperação após crash
- **Configurações:** pg_hba.conf, postgresql.conf

---

## Próximos Passos

➡️ **US-03**: Implantar Hive Metastore (Catálogo Iceberg)
- Depende de: PostgreSQL ✅ + MinIO ✅

---

## Referências

- [PostgreSQL Documentation](https://www.postgresql.org/docs/15/index.html)
- [Docker PostgreSQL Official Image](https://hub.docker.com/_/postgres)
- [PostgreSQL CLI (psql) Commands](https://www.postgresql.org/docs/15/app-psql.html)
