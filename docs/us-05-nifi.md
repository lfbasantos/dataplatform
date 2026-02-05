# US-05: Implantar Apache NiFi (Ingestão)

**Data:** 2026-02-05  
**Status:** ✅ Concluído

## Contexto

Implementação do Apache NiFi como ferramenta de ingestão de dados na Open Data Platform. NiFi fornece interface visual para criação de pipelines ETL (flow-based programming), permitindo processar e rotear dados entre diferentes sistemas. Primeira integração: ingestão de arquivos CSV locais para bucket `landing` do MinIO.

---

## Requisitos Funcionais Cobertos

- **FR17:** Sistema possui Apache NiFi para orquestração de ingestão de dados ✅
- **FR18:** NiFi expõe interface web HTTPS (porta 8443) ✅
- **FR19:** NiFi integrado com MinIO via protocolo S3 ✅
- **FR20:** Pipeline de ingestão: arquivos locais → MinIO landing bucket ✅
- **FR21:** Credenciais de acesso configuradas (Single User mode) ✅
- **FR22:** NiFi deployado com suporte a GitHub Codespaces (proxy) ✅

---

## Roteiro de Implementação

### 1. Criar Script Parametrizável de Deploy

Criado script [src/nifi/start-nifi.sh](../src/nifi/start-nifi.sh) com detecção automática de ambiente GitHub Codespaces:

```bash
#!/bin/bash

# Parâmetros padrão
NIFI_USER=${NIFI_USER:-"admin"}
NIFI_PASSWORD=${NIFI_PASSWORD:-"adminadmin123"}

# Detecção de ambiente Codespaces
if [ -n "$CODESPACE_NAME" ]; then
    echo "GitHub Codespaces detectado: $CODESPACE_NAME"
    PROXY_HOST="${CODESPACE_NAME}-8443.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
    echo "Configurando proxy: $PROXY_HOST"
else
    echo "Ambiente local/VM - usando localhost"
    PROXY_HOST="localhost:8443"
fi

echo "Iniciando NiFi..."
docker run -d \
  --name nifi \
  -p 8443:8443 \
  -e SINGLE_USER_CREDENTIALS_USERNAME="$NIFI_USER" \
  -e SINGLE_USER_CREDENTIALS_PASSWORD="$NIFI_PASSWORD" \
  -e NIFI_WEB_HTTPS_PORT=8443 \
  -e NIFI_WEB_PROXY_HOST="$PROXY_HOST" \
  --link minio:minio \
  --link schema-registry:schema-registry \
  apache/nifi:1.25.0

echo "NiFi iniciado. Aguarde ~2 minutos para o serviço ficar disponível."
echo "Credenciais: $NIFI_USER / $NIFI_PASSWORD"
```

**Torne o script executável:**

```bash
chmod +x src/nifi/start-nifi.sh
```

---

### 2. Executar Container NiFi

```bash
./src/nifi/start-nifi.sh
```

**Output esperado:**
```
Ambiente local/VM - usando localhost
Iniciando NiFi...
858aaea541ff2d3fa9c5a6b3c2c4e8f9d1b7a6c5e3f2d1a9b8c7e6f5d4c3b2a1
NiFi iniciado. Aguarde ~2 minutos para o serviço ficar disponível.
Credenciais: admin / adminadmin123
```

**Verificar inicialização:**

```bash
docker logs -f nifi
```

Aguarde a mensagem:
```
NiFi has started. The UI is available at the following URLs:
https://858aaea541ff:8443/nifi
```

---

### 3. Acessar Interface Web

- **URL:** `https://localhost:8443/nifi` (local) ou via port forwarding do Codespaces
- **Credenciais:**
  - Username: `admin`
  - Password: `adminadmin123`

> ⚠️ **Certificado SSL:** Browser mostrará aviso de certificado autoassinado (normal). Clique em "Avançado" → "Prosseguir para o site".

---

### 4. Criar Dados de Teste

Arquivo de exemplo [src/nifi/bilhetagem-sample.csv](../src/nifi/bilhetagem-sample.csv) com 10 transações de bilhetagem:

```csv
card_id,line_id,timestamp,stop_id,fare_type
7891234567890123,101,2026-01-15 08:23:45,1001,regular
8901234567890124,202,2026-01-15 08:45:12,2003,student
9012345678901235,303,2026-01-15 09:12:33,3005,senior
1234567890123456,101,2026-01-15 09:34:21,1007,regular
2345678901234567,404,2026-01-15 10:01:55,4002,regular
3456789012345678,202,2026-01-15 10:23:47,2011,student
4567890123456789,505,2026-01-15 11:05:18,5003,regular
5678901234567890,303,2026-01-15 11:47:29,3009,senior
6789012345678901,101,2026-01-15 12:15:56,1015,regular
7890123456789012,606,2026-01-15 13:22:34,6001,student
```

**Características:**
- 10 registros (497 bytes)
- Campos: `card_id`, `line_id`, `timestamp`, `stop_id`, `fare_type`
- Formato: CSV com header

---

### 5. Copiar Arquivo para Container

```bash
docker cp src/nifi/bilhetagem-sample.csv nifi:/tmp/
```

**Validar cópia:**

```bash
docker exec nifi ls -lh /tmp/bilhetagem-sample.csv
```

**Output:**
```
-rw-rw-rw- 1 nifi nifi 497 Feb 4 20:04 /tmp/bilhetagem-sample.csv
```

---

### 6. Criar Flow de Ingestão no NiFi

#### 6.1. Adicionar Processor GetFile

1. Arraste o ícone **Processor** para o canvas
2. Busque por **GetFile** e adicione
3. Botão direito no processor → **Configure**
4. Aba **PROPERTIES:**
   - **Input Directory:** `/tmp`
   - **File Filter:** `bilhetagem-sample.csv`
   - **Keep Source File:** `false` (deleta após ler)
   - **Minimum File Age:** `0 sec`
   - **Polling Interval:** `10 sec`
5. Aba **SCHEDULING:** Run Schedule = `10 sec`
6. Aba **SETTINGS → AUTO-TERMINATED RELATIONSHIPS:** marque `failure`
7. Clique **APPLY**

---

#### 6.2. Adicionar Processor PutS3Object

1. Arraste outro **Processor** para o canvas
2. Busque por **PutS3Object** e adicione
3. Botão direito no processor → **Configure**
4. Aba **PROPERTIES:**

| Propriedade | Valor | Observação |
|-------------|-------|------------|
| **Object Key** | `${filename}` | Usa nome original do arquivo |
| **Bucket** | `landing` | Bucket criado no MinIO (US-01) |
| **Access Key ID** | `minioadmin` | Credencial MinIO |
| **Secret Access Key** | `minioadmin123` | Credencial MinIO |
| **Endpoint Override URL** | `http://minio:9000` | Endpoint MinIO (docker link) |
| **Region** | `us-east-1` | Região fictícia (obrigatória) |
| **Signer Override** | **(VAZIO)** | ⚠️ **CRÍTICO:** Deixe vazio! |
| **Use Path Style Access** | `true` | ⚠️ **OBRIGATÓRIO para MinIO** |

5. Aba **SETTINGS → AUTO-TERMINATED RELATIONSHIPS:** marque `success` e `failure`
6. Clique **APPLY**

---

#### 6.3. Conectar Processors

1. Arraste seta do **GetFile** para **PutS3Object**
2. Marque relationship **success**
3. Clique **ADD**

---

#### 6.4. Iniciar Flow

1. Clique botão direito no canvas (fundo branco) → **Start**
2. Ou selecione ambos processors (Shift+Click) → botão **Play** na toolbar

---

### 7. Validar Ingestão

#### 7.1. Verificar Logs do NiFi

```bash
docker logs nifi 2>&1 | grep -E "GetFile|PutS3Object" | tail -20
```

Procure por mensagens de sucesso (ausência de erros).

---

#### 7.2. Verificar Arquivo no MinIO

```bash
docker exec minio mc ls local/landing/
```

**Output esperado:**
```
[2026-02-05 18:54:03 UTC]   497B STANDARD bilhetagem-sample.csv
```

✅ **Sucesso:** Arquivo de 497 bytes ingerido no bucket `landing`.

---

#### 7.3. Validar pela UI do MinIO

1. Acesse `http://localhost:9001` (ou port forwarding Codespaces)
2. Login: `minioadmin` / `minioadmin123`
3. Menu **Object Browser** → bucket `landing`
4. Confirme presença do arquivo `bilhetagem-sample.csv`

---

## Arquitetura do Flow

```
┌─────────────────┐
│   GetFile       │
│  /tmp/*.csv     │
└────────┬────────┘
         │ success
         ▼
┌─────────────────┐
│  PutS3Object    │
│  bucket:landing │
│  endpoint:minio │
└─────────────────┘
```

**FlowFile Lifecycle:**
1. GetFile detecta arquivo em `/tmp/`
2. Lê conteúdo para FlowFile (objeto interno do NiFi)
3. Deleta arquivo original (Keep Source File=false)
4. FlowFile roteado via relationship `success`
5. PutS3Object recebe FlowFile
6. Escreve conteúdo no MinIO bucket `landing`
7. FlowFile descartado (auto-terminated success)

---

## Troubleshooting

### Problema 1: SignatureDoesNotMatch Error

**Sintoma:**
```
PutS3Object[id=...] Failed to put Object: 
The request signature we calculated does not match the signature you provided
```

**Causa:** 
Propriedade **Signer Override** configurada com `AWSS3V4SignerType` (incompatível com MinIO).

**Solução:**
Deixar **Signer Override VAZIO** (blank/empty) no PutS3Object processor.

---

### Problema 2: Access Denied (403)

**Causa:** Credenciais incorretas ou bucket não existe.

**Validação:**

```bash
# Verificar buckets no MinIO
docker exec minio mc ls local/

# Recriar bucket landing se necessário
docker exec minio mc mb local/landing
```

---

### Problema 3: NiFi UI Inacessível em Codespaces

**Causa:** Variável `NIFI_WEB_PROXY_HOST` não configurada.

**Validação:**

```bash
docker exec nifi env | grep NIFI_WEB_PROXY_HOST
```

Deve retornar: `NIFI_WEB_PROXY_HOST=<codespace>-8443.app.github.dev`

**Solução:** Remover container e usar [start-nifi.sh](../src/nifi/start-nifi.sh) que configura automaticamente.

---

### Problema 4: GetFile Não Detecta Arquivo

**Causas possíveis:**
- Arquivo não está em `/tmp/` do container (verificar com `docker exec nifi ls /tmp/`)
- File Filter incorreto (verificar nome exato do arquivo)
- Minimum File Age > 0 (arquivo muito recente)

**Solução:**
```bash
# Recopiar arquivo
docker cp src/nifi/bilhetagem-sample.csv nifi:/tmp/

# Verificar permissões
docker exec nifi ls -lh /tmp/bilhetagem-sample.csv
```

---

## Conceitos NiFi

### FlowFiles
Objetos internos que carregam dados através do pipeline. Contêm:
- **Content:** payload (bytes do arquivo)
- **Attributes:** metadados (filename, path, size, etc.)

### Processors
Componentes que processam FlowFiles (ler, transformar, escrever, rotear).

### Relationships
Conexões entre processors baseadas em resultado (success, failure, etc.).

### Process Groups
Containers organizacionais para agrupar múltiplos flows relacionados dentro do mesmo canvas. Útil para organizar pipelines complexos.

---

## Organização de Múltiplos Pipelines

**Pergunta Frequente:** "Como criar outro flow?"

**Resposta:** NiFi não tem "flows" separados. Use **Process Groups** para organizar:

1. Arraste ícone **Process Group** para o canvas
2. Nomeie (ex: "Ingestão Landing")
3. Mova processors existentes para dentro do grupo (arrastar)
4. Crie novos Process Groups para outros pipelines (ex: "Bronze Processing")

**Hierarquia Sugerida:**

```
Root Canvas
├── Process Group: Ingestão Landing
│   ├── GetFile → PutS3Object (bilhetagem)
│   └── GetFile → PutS3Object (outros CSVs)
├── Process Group: Bronze Processing
│   └── FetchS3 → ConvertRecord → PutParquet
└── Process Group: Silver Processing
    └── QueryDatabaseTable → MergeRecord → PutS3
```

---

## Limitações Conhecidas

### ⚠️ Persistência de Flow (TODO US-06)

**Problema:** Flow atual armazenado em `/opt/nifi/nifi-current/conf/flow.xml.gz` dentro do container **SEM volume persistente**.

**Impacto:** Flow perdido ao recriar container (`docker rm nifi`).

**Workaround Temporário:**
```bash
# Backup manual do flow
docker cp nifi:/opt/nifi/nifi-current/conf/flow.xml.gz ./backup-flow.xml.gz

# Restaurar após recriar container
docker cp ./backup-flow.xml.gz nifi:/opt/nifi/nifi-current/conf/flow.xml.gz
docker restart nifi
```

**Solução Definitiva (planejada para US-06):**
Adicionar volume mapping ao script de deploy:
```bash
docker volume create nifi-data
docker run -d \
  --name nifi \
  -v nifi-data:/opt/nifi/nifi-current/conf \
  # ... outras opções ...
  apache/nifi:1.25.0
```

---

## Próximos Passos

- [ ] **US-06:** Adicionar volume persistence para NiFi
- [ ] **US-07:** Criar múltiplos flows organizados em Process Groups
- [ ] **US-08:** Integrar NiFi com Schema Registry (validação de schemas)
- [ ] **US-09:** Pipeline bronze: conversão CSV → Parquet
- [ ] **US-10:** Configurar NiFi Registry para versionamento de flows

---

## Referências

- [Apache NiFi Documentation](https://nifi.apache.org/docs.html)
- [NiFi Expression Language Guide](https://nifi.apache.org/docs/nifi-docs/html/expression-language-guide.html)
- [MinIO S3 Compatibility](https://min.io/docs/minio/linux/integrations/aws-cli-with-minio.html)
- [NiFi PutS3Object Processor](https://nifi.apache.org/docs/nifi-docs/components/org.apache.nifi/nifi-aws-nar/1.25.0/org.apache.nifi.processors.aws.s3.PutS3Object/)

---

## Validação Final

✅ **US-05 Concluída - Checklist:**

- [x] Container NiFi deployado e acessível via HTTPS (porta 8443)
- [x] Proxy configurado para GitHub Codespaces
- [x] Credenciais Single User funcionando (admin/adminadmin123)
- [x] Flow criado: GetFile → PutS3Object
- [x] Integração MinIO via S3 protocol funcionando
- [x] Arquivo teste (497 bytes) ingerido com sucesso no bucket landing
- [x] Signer Override configurado corretamente (VAZIO)
- [x] Path Style Access habilitado (true)
- [x] Documentação completa criada
- [x] Script parametrizável versionado no git

**Resumo Executivo:**  
Apache NiFi operacional com pipeline de ingestão CSV → MinIO. Flow testado e validado (497 bytes no bucket landing). Documentação troubleshooting incluída. Persistência de volumes planejada para próxima iteração.
