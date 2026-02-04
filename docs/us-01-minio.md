# US-01: Implantar MinIO (Object Store)

**Data:** 2026-02-04  
**Status:** ✅ Concluído

## Contexto

Implementação do primeiro serviço da plataforma Open Data Platform: MinIO como Object Store S3-compatible, base para a arquitetura Medallion (landing → bronze → silver → gold).

---

## Requisitos Funcionais Cobertos

- **FR10:** Sistema possui MinIO como Object Store S3-compatible ✅
- **FR11:** MinIO expõe endpoint S3 (porta 9000) e console (porta 9001) ✅
- **FR12:** Buckets criados: landing, bronze, silver, gold ✅
- **FR13:** Credenciais configuráveis via variáveis de ambiente ✅
- **FR14:** Buckets suportam operações S3 (PUT, GET, DELETE) ✅
- **FR15:** Acesso via protocolo S3 (s3a://) ✅
- **FR16:** MinIO implantado como primeiro serviço (sem dependências) ✅

---

## Roteiro de Implementação

### 1. Criar Volume Persistente

```bash
docker volume create minio-data
```

**Output:**
```
minio-data
```

**Objetivo:** Garantir persistência dos dados após restart do container (FR03).

---

### 2. Executar Container MinIO

```bash
docker run -d \
  --name minio \
  -p 9000:9000 \
  -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin123 \
  -v minio-data:/data \
  --restart unless-stopped \
  quay.io/minio/minio:latest server /data --console-address ":9001"
```

**Parâmetros:**
- `-d`: Executa em modo detached (background)
- `--name minio`: Nome do container
- `-p 9000:9000`: Porta da API S3
- `-p 9001:9001`: Porta do console web
- `-e MINIO_ROOT_USER`: Usuário root (access key)
- `-e MINIO_ROOT_PASSWORD`: Senha root (secret key)
- `-v minio-data:/data`: Volume persistente
- `--restart unless-stopped`: Reinicia automaticamente após reboot
- `server /data --console-address ":9001"`: Comando de inicialização

---

### 3. Verificar Container Ativo

```bash
docker ps | grep minio
```

**Output:**
```
845d8dde21fd   quay.io/minio/minio:latest   "/usr/bin/docker-ent…"   32 seconds ago   Up 32 seconds   0.0.0.0:9000-9001->9000-9001/tcp, [::]:9000-9001->9000-9001/tcp   minio
```

**Validação:** Container ativo com portas 9000-9001 expostas.

---

### 4. Verificar Logs de Inicialização

```bash
docker logs minio | tail -20
```

**Output:**
```
INFO: Formatting 1st pool, 1 set(s), 1 drives per set.
INFO: WARNING: Host local has more than 0 drives of set. A host failure will result in data becoming unavailable.
MinIO Object Storage Server
Copyright: 2015-2026 MinIO, Inc.
License: GNU AGPLv3 - https://www.gnu.org/licenses/agpl-3.0.html
Version: RELEASE.2025-09-07T16-13-09Z (go1.24.6 linux/amd64)

API: http://172.17.0.2:9000  http://127.0.0.1:9000 
WebUI: http://172.17.0.2:9001 http://127.0.0.1:9001  

Docs: https://docs.min.io
```

**Validação:** MinIO iniciado corretamente, API e WebUI acessíveis.

---

### 5. Configurar MinIO Client (mc)

```bash
docker exec -it minio mc alias set local http://localhost:9000 minioadmin minioadmin123
```

**Output:**
```
mc: Configuration written to `/tmp/.mc/config.json`. Please update your access credentials.
mc: Successfully created `/tmp/.mc/share`.
mc: Initialized share uploads `/tmp/.mc/share/uploads.json` file.
mc: Initialized share downloads `/tmp/.mc/share/downloads.json` file.
Added `local` successfully.
```

**Objetivo:** Configurar alias para operações S3 via CLI.

---

### 6. Criar Buckets da Arquitetura Medallion

#### 6.1. Bucket Landing

```bash
docker exec -it minio mc mb local/landing
```

**Output:**
```
Bucket created successfully `local/landing`.
```

#### 6.2. Bucket Bronze

```bash
docker exec -it minio mc mb local/bronze
```

**Output:**
```
Bucket created successfully `local/bronze`.
```

#### 6.3. Bucket Silver

```bash
docker exec -it minio mc mb local/silver
```

**Output:**
```
Bucket created successfully `local/silver`.
```

#### 6.4. Bucket Gold

```bash
docker exec -it minio mc mb local/gold
```

**Output:**
```
Bucket created successfully `local/gold`.
```

---

### 7. Listar Todos os Buckets

```bash
docker exec -it minio mc ls local/
```

**Output:**
```
[2026-02-04 18:07:02 UTC]     0B bronze/
[2026-02-04 18:07:42 UTC]     0B gold/
[2026-02-04 18:03:50 UTC]     0B landing/
[2026-02-04 18:07:20 UTC]     0B silver/
```

**Validação:** 4 buckets criados com sucesso.

---

### 8. Testar Operações S3 (CRUD)

#### 8.1. Criar Arquivo de Teste (Host)

```bash
echo "Hello MinIO - Open Data Platform" > tmp/teste-minio.txt
```

#### 8.2. Copiar Arquivo para Container

```bash
docker cp tmp/teste-minio.txt minio:/tmp/teste-minio.txt
```

**Output:**
```
Successfully copied 2.05kB to minio:/tmp/teste-minio.txt
```

#### 8.3. Upload para Bucket (PUT)

```bash
docker exec -it minio mc cp /tmp/teste-minio.txt local/landing/
```

**Output:**
```
/tmp/teste-minio.txt:  33 B / 33 B ┃▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓┃ 3.72 KiB/s 0s
```

**Validação:** Upload realizado via protocolo S3.

#### 8.4. Listar Conteúdo do Bucket (LIST)

```bash
docker exec -it minio mc ls local/landing/
```

**Output:**
```
[2026-02-04 18:12:50 UTC]    33B STANDARD teste-minio.txt
```

**Validação:** Arquivo presente no bucket.

#### 8.5. Download do Bucket (GET)

```bash
docker exec -it minio mc cp local/landing/teste-minio.txt /tmp/teste-download.txt
```

**Output:**
```
http://localhost:9000/landing/teste-minio.txt:  33 B / 33 B ┃▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓┃ 6.10 KiB/s 0s
```

#### 8.6. Verificar Integridade

```bash
docker exec -it minio cat /tmp/teste-download.txt
```

**Output:**
```
Hello MinIO - Open Data Platform
```

**Validação:** Conteúdo íntegro, download funcionando.

#### 8.7. Remover Arquivo (DELETE)

```bash
docker exec -it minio mc rm local/landing/teste-minio.txt
```

**Output:**
```
Removed `local/landing/teste-minio.txt`.
```

#### 8.8. Confirmar Remoção

```bash
docker exec -it minio mc ls local/landing/
```

**Output:** (vazio)

**Validação:** DELETE funcionando corretamente.

---

### 9. Testar Persistência (Restart)

#### 9.1. Reiniciar Container

```bash
docker restart minio
```

#### 9.2. Verificar Buckets Após Restart

```bash
docker exec -it minio mc ls local/
```

**Output:**
```
[2026-02-04 18:07:02 UTC]     0B bronze/
[2026-02-04 18:07:42 UTC]     0B gold/
[2026-02-04 18:03:50 UTC]     0B landing/
[2026-02-04 18:07:20 UTC]     0B silver/
```

**Validação:** ✅ Todos os buckets persistiram após restart do container.

---

## Critérios de Aceitação

| Critério | Status |
|----------|--------|
| Container MinIO rodando via docker run | ✅ |
| Console acessível na porta 9001 | ✅ |
| Buckets criados: landing, bronze, silver, gold | ✅ |
| Upload de arquivo de teste via CLI | ✅ |
| Download de arquivo via CLI MinIO Client (mc) | ✅ |
| Entendimento de credenciais (access key, secret key) | ✅ |
| Persistência após restart | ✅ |

---

## Acessos

| Serviço | Endpoint | Credenciais |
|---------|----------|-------------|
| API S3 | http://localhost:9000 | Access: `minioadmin`<br>Secret: `minioadmin123` |
| Console Web | http://localhost:9001 | User: `minioadmin`<br>Pass: `minioadmin123` |

---

## Conceitos Aprendidos

### Object Storage vs File System

- **File System**: Hierarquia de diretórios e arquivos (árvore)
- **Object Storage**: Flat namespace com buckets e objetos identificados por keys
- **Vantagens**: Escalabilidade horizontal, durabilidade, API HTTP/REST

### Protocolo S3

- **Bucket**: Container lógico para objetos (equivalente a "pasta raiz")
- **Object**: Arquivo armazenado com key única
- **Key**: Identificador do objeto (pode simular hierarquia com `/`)
- **Operações**: PUT (upload), GET (download), LIST, DELETE

### MinIO vs AWS S3

| Aspecto | MinIO | AWS S3 |
|---------|-------|--------|
| Deployment | On-premises / Self-hosted | Cloud (AWS) |
| API | S3-compatible (100%) | Nativo S3 |
| Custo | Gratuito (open source) | Pay-as-you-go |
| Uso | Dev/Test, Private Cloud | Produção Cloud |

### Arquitetura Medallion

- **Landing**: Dados brutos (raw) da ingestão
- **Bronze**: Dados validados em formato estruturado (Parquet)
- **Silver**: Dados limpos, enriquecidos, com qualidade
- **Gold**: Dados agregados, otimizados para consumo (BI)

---

## Próximos Passos

➡️ **US-02**: Implantar PostgreSQL (Backend de Metadados)

---

## Referências

- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [MinIO Client (mc) Guide](https://min.io/docs/minio/linux/reference/minio-mc.html)
- [S3 API Reference](https://docs.aws.amazon.com/AmazonS3/latest/API/Welcome.html)
- [Medallion Architecture](https://www.databricks.com/glossary/medallion-architecture)
