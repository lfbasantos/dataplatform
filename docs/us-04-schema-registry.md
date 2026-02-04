# US-04: Implantar Schema Registry (Contratos de Dados)

## Contexto

O **Schema Registry** é um serviço centralizado para gerenciar **contratos de dados** (schemas). Ele garante que produtores e consumidores de dados compartilhem a mesma estrutura, prevenindo problemas de incompatibilidade.

**Tecnologia:** Apicurio Registry 2.5.0.Final (suporta PostgreSQL como backend)

---

## Objetivos de Aprendizado

- [x] Entender o problema que contratos de dados resolvem
- [x] Entender o formato Avro para definição de schemas
- [x] Entender políticas de evolução (BACKWARD, FORWARD, FULL)
- [x] Entender versionamento de schemas
- [x] Praticar registro e consulta de schemas via API REST

---

## Comandos Executados

### 1. Criar diretório do serviço

```bash
mkdir -p /workspaces/dataplatform/src/schema-registry
```

**Resultado:** Diretório criado para armazenar schemas e configurações.

---

### 2. Executar container Schema Registry

```bash
docker run -d \
  --name schema-registry \
  -p 8081:8080 \
  -e REGISTRY_DATASOURCE_URL=jdbc:postgresql://postgres:5432/schemaregistry \
  -e REGISTRY_DATASOURCE_USERNAME=postgres \
  -e REGISTRY_DATASOURCE_PASSWORD=postgres123 \
  -e QUARKUS_HTTP_PORT=8080 \
  --link postgres:postgres \
  apicurio/apicurio-registry-sql:2.5.0.Final
```

**Parâmetros importantes:**
- `-p 8081:8080`: Porta da API REST
- `REGISTRY_DATASOURCE_URL`: Conexão JDBC com PostgreSQL
- `REGISTRY_DATASOURCE_PASSWORD`: Senha `postgres123` (conforme US-02)
- `--link postgres:postgres`: Comunicação com PostgreSQL

**Resultado:**
```
Container ID: <container_id>
```

---

### 3. Verificar logs de inicialização

```bash
sleep 20 && docker logs schema-registry 2>&1 | tail -50
```

**Resultado (logs importantes):**
```
INFO SqlRegistryStorage constructed successfully. JDBC URL: jdbc:postgresql://postgres:5432/schemaregistry
INFO Database not initialized.
INFO Initializing the Apicurio Registry database.
INFO Database type: postgresql
INFO apicurio-registry-storage-sql 2.5.0.Final started in 5.714s. Listening on: http://0.0.0.0:8080
```

✅ Schema Registry inicializado com sucesso!

---

### 4. Verificar health check

```bash
curl -s http://localhost:8081/health | jq .
```

**Resultado:**
```json
{
  "status": "UP",
  "checks": [
    {
      "name": "StorageLivenessCheck",
      "status": "UP"
    },
    {
      "name": "PersistenceSimpleReadinessCheck",
      "status": "UP"
    },
    {
      "name": "Database connections health check",
      "status": "UP"
    }
  ]
}
```

✅ Todos os health checks passando!

---

### 5. Criar schema Avro - Posição de Ônibus

```bash
cat > /workspaces/dataplatform/src/schema-registry/bus-position-v1.avsc << 'EOF'
{
  "type": "record",
  "namespace": "sptrans",
  "name": "BusPosition",
  "version": "1",
  "fields": [
    {"name": "vehicle_id", "type": "string", "doc": "Identificador único do veículo"},
    {"name": "line_id", "type": "string", "doc": "Código da linha de ônibus"},
    {"name": "latitude", "type": "double", "doc": "Latitude da posição"},
    {"name": "longitude", "type": "double", "doc": "Longitude da posição"},
    {"name": "timestamp", "type": "long", "logicalType": "timestamp-millis", "doc": "Timestamp da captura (epoch millis)"},
    {"name": "speed", "type": ["null", "double"], "default": null, "doc": "Velocidade em km/h (opcional)"}
  ]
}
EOF
```

**Estrutura do Schema:**

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| `vehicle_id` | string | Sim | Identificador único do veículo |
| `line_id` | string | Sim | Código da linha de ônibus |
| `latitude` | double | Sim | Latitude da posição GPS |
| `longitude` | double | Sim | Longitude da posição GPS |
| `timestamp` | long (timestamp-millis) | Sim | Timestamp Unix em milissegundos |
| `speed` | double (nullable) | Não | Velocidade em km/h (opcional) |

---

### 6. Registrar schema via API REST

```bash
curl -X POST http://localhost:8081/apis/registry/v2/groups/sptrans/artifacts \
  -H "Content-Type: application/json" \
  -H "X-Registry-ArtifactId: bus_position" \
  -H "X-Registry-ArtifactType: AVRO" \
  --data @/workspaces/dataplatform/src/schema-registry/bus-position-v1.avsc
```

**Resultado:**
```json
{
  "name": "BusPosition",
  "createdBy": "",
  "createdOn": "2026-02-04T19:24:33Z",
  "modifiedBy": "",
  "modifiedOn": "2026-02-04T19:24:33Z",
  "id": "bus_position",
  "version": "1",
  "type": "AVRO",
  "globalId": 1,
  "state": "ENABLED",
  "groupId": "sptrans",
  "contentId": 1,
  "references": []
}
```

✅ Schema registrado com sucesso!

**IDs importantes:**
- `globalId`: 1 (ID único global no registry)
- `contentId`: 1 (ID do conteúdo - reutilizado se schema idêntico)
- `version`: 1 (primeira versão do artifact)

---

### 7. Listar schemas registrados

```bash
curl -s http://localhost:8081/apis/registry/v2/groups/sptrans/artifacts | jq .
```

**Resultado:**
```json
{
  "artifacts": [
    {
      "id": "bus_position",
      "name": "BusPosition",
      "createdOn": "2026-02-04T19:24:33Z",
      "type": "AVRO",
      "state": "ENABLED",
      "groupId": "sptrans"
    }
  ],
  "count": 1
}
```

---

### 8. Consultar versão específica do schema

```bash
curl -s http://localhost:8081/apis/registry/v2/groups/sptrans/artifacts/bus_position/versions/1 | jq .
```

**Resultado:** Retorna o schema Avro completo com todos os 6 campos.

---

### 9. Verificar tabelas criadas no PostgreSQL

```bash
docker exec postgres psql -U postgres -d schemaregistry -c "\dt"
```

**Resultado:** O Apicurio Registry criou várias tabelas no banco `schemaregistry` para persistir:
- Artifacts (schemas registrados)
- Versions (versões de cada schema)
- Content (conteúdo dos schemas)
- Groups (grupos organizacionais)
- Global IDs (identificadores únicos)

---

### 10. Testar persistência - Restart do container

```bash
docker restart schema-registry
```

**Aguardar inicialização:**
```bash
sleep 10 && curl -s http://localhost:8081/apis/registry/v2/groups/sptrans/artifacts | jq .
```

**Resultado:**
```json
{
  "artifacts": [
    {
      "id": "bus_position",
      "name": "BusPosition",
      "type": "AVRO",
      "state": "ENABLED",
      "groupId": "sptrans"
    }
  ],
  "count": 1
}
```

✅ Schema persiste após restart! PostgreSQL mantém os dados.

---

## Validação dos Critérios de Aceitação

- [x] Container Schema Registry rodando via docker run
- [x] API acessível na porta 8081
- [x] Schema de teste `bus_position` registrado via API REST
- [x] Consulta de schemas registrados funcionando
- [x] Entendimento de subjects (artifacts) e versões
- [x] Persistência validada após restart

---

## Como Acessar o Serviço

### API REST

**Base URL:** `http://localhost:8081/apis/registry/v2`

**Endpoints principais:**

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/groups/{groupId}/artifacts` | Lista todos os artifacts de um grupo |
| `GET` | `/groups/{groupId}/artifacts/{artifactId}` | Consulta metadata de um artifact |
| `GET` | `/groups/{groupId}/artifacts/{artifactId}/versions/{version}` | Consulta versão específica |
| `POST` | `/groups/{groupId}/artifacts` | Registra novo artifact |
| `PUT` | `/groups/{groupId}/artifacts/{artifactId}` | Atualiza artifact (nova versão) |
| `DELETE` | `/groups/{groupId}/artifacts/{artifactId}` | Remove artifact |

### Interface Web (UI)

**URL:** `http://localhost:8081/ui`

A interface web do Apicurio permite:
- Navegar schemas registrados
- Visualizar versões e histórico
- Consultar conteúdo dos schemas
- Comparar versões

---

## Credenciais e Configurações

| Parâmetro | Valor |
|-----------|-------|
| **API URL** | `http://localhost:8081` |
| **UI URL** | `http://localhost:8081/ui` |
| **Health Check** | `http://localhost:8081/health` |
| **Banco de dados** | PostgreSQL (`schemaregistry`) |
| **Usuário DB** | `postgres` |
| **Senha DB** | `postgres123` |
| **Porta API** | 8081 (host) → 8080 (container) |

---

## Conceitos Aprendidos

### 1. O que é Schema Registry?

O **Schema Registry** é um **catálogo centralizado de contratos de dados**. Ele resolve o problema de:

**Sem Schema Registry:**
```python
# Produtor envia:
{"id": "123", "speed": 45.5}

# Consumidor espera:
{"vehicle_id": "123", "velocity": 45.5}
# ❌ Incompatibilidade! Campos diferentes
```

**Com Schema Registry:**
```python
# 1. Produtor consulta schema no Registry
schema = registry.get_schema("bus_position", version=1)

# 2. Produtor valida dados contra schema ANTES de enviar
data = {"vehicle_id": "123", "line_id": "8000", "latitude": -23.5, "longitude": -46.6, "timestamp": 1234567890000}
schema.validate(data)  # ✅ Passa

# 3. Consumidor usa o MESMO schema para deserializar
# ✅ Contrato garantido!
```

---

### 2. Formato Avro

**Apache Avro** é um sistema de serialização de dados com schema:

**Vantagens:**
- Schema explícito e fortemente tipado
- Serialização binária compacta (menor que JSON)
- Suporta evolução de schema
- Tipos ricos (timestamp, decimal, union, etc.)

**Exemplo de schema Avro:**
```json
{
  "type": "record",
  "name": "BusPosition",
  "fields": [
    {"name": "vehicle_id", "type": "string"},
    {"name": "speed", "type": ["null", "double"], "default": null}
  ]
}
```

**Union type:** `["null", "double"]` = campo opcional (pode ser null ou double)

---

### 3. Políticas de Evolução de Schema

O Schema Registry suporta **compatibilidade** entre versões:

#### BACKWARD (padrão)
- **Nova versão pode ler dados escritos com versão antiga**
- Permite: adicionar campos opcionais, remover campos
- Proíbe: remover campos obrigatórios, mudar tipo

**Exemplo:**
```json
// Versão 1
{"vehicle_id": "string", "speed": "double"}

// Versão 2 (BACKWARD compatible)
{"vehicle_id": "string", "speed": "double", "fuel_level": ["null", "double"]}
// ✅ Código antigo ainda funciona (ignora fuel_level)
```

#### FORWARD
- **Versão antiga pode ler dados escritos com nova versão**
- Permite: adicionar campos com default, remover campos
- Proíbe: adicionar campos sem default

#### FULL
- **BACKWARD + FORWARD simultaneamente**
- Mudanças muito restritas

#### NONE
- **Sem validação de compatibilidade**
- Qualquer mudança permitida (perigoso!)

---

### 4. Versionamento de Schemas

**Cada mudança no schema cria uma nova versão:**

```
sptrans/bus_position
├── v1: campos básicos (vehicle_id, line_id, lat, lon, timestamp)
├── v2: adiciona campo "speed" opcional
└── v3: adiciona campo "driver_id" opcional
```

**IDs importantes:**
- **artifactId**: Nome do schema (`bus_position`)
- **version**: Versão inteira sequencial (1, 2, 3...)
- **globalId**: ID único global no registry (nunca reutilizado)
- **contentId**: Hash do conteúdo (schemas idênticos = mesmo contentId)

---

### 5. Grupos (Groups)

Os **grupos** organizam schemas relacionados:

**Estrutura:**
```
sptrans/               ← Grupo (domínio de dados)
├── bus_position       ← Artifact (tipo de evento)
├── bus_line           ← Artifact
└── billing_transaction ← Artifact
```

Similar a **namespaces** ou **packages** em código.

---

### 6. Subjects vs Artifacts

**Confluent Schema Registry (Kafka):**
- Usa o conceito de **subject**
- Naming strategy: `<topic>-key`, `<topic>-value`

**Apicurio Registry:**
- Usa **groups + artifacts**
- Mais flexível (não acoplado a Kafka)

Ambos resolvem o mesmo problema!

---

## Diferença: Confluent vs Apicurio

| Aspecto | Confluent Schema Registry | Apicurio Registry |
|---------|---------------------------|-------------------|
| **Backend** | Kafka obrigatório | SQL, Kafka, Streams, InMemory |
| **Dependência** | Alta (precisa Kafka rodando) | Baixa (PostgreSQL suficiente) |
| **Formatos** | Avro, JSON Schema, Protobuf | Avro, JSON, Protobuf, OpenAPI, GraphQL, WSDL |
| **License** | Confluent Community License | Apache 2.0 |
| **UI** | Simples | Rica (busca, linhagem, comparação) |
| **Performance** | Otimizado para Kafka | Multi-backend flexível |

**Por que escolhemos Apicurio:**
- Não temos Kafka ainda (apenas PostgreSQL)
- Open source completo (Apache 2.0)
- Mais formatos suportados
- UI mais completa

---

## Fluxo Típico de Uso

### Produtor (NiFi) - Próxima US

1. **Buscar schema no Registry:**
```bash
curl http://localhost:8081/apis/registry/v2/groups/sptrans/artifacts/bus_position/versions/1
```

2. **Validar dados contra schema** (biblioteca Avro)

3. **Serializar dados** (JSON → Avro binário)

4. **Enviar para MinIO** (Landing Zone)

### Consumidor (Spark) - US-06

1. **Ler schema do Registry** (mesma versão ou compatível)

2. **Deserializar dados** (Avro binário → DataFrame)

3. **Processar** (Bronze → Silver → Gold)

---

## Troubleshooting

### Erro: Password authentication failed

**Sintoma:** Container reinicia continuamente com erro de autenticação.

**Causa:** Senha incorreta do PostgreSQL (`postgres` vs `postgres123`).

**Solução:**
```bash
docker stop schema-registry && docker rm schema-registry
# Recriar com senha correta: postgres123
```

---

### Schema Registry não inicializa

**Verificar logs:**
```bash
docker logs schema-registry 2>&1 | tail -100
```

**Verificar conectividade PostgreSQL:**
```bash
docker exec schema-registry ping -c 3 postgres
```

**Verificar banco existe:**
```bash
docker exec postgres psql -U postgres -c "\l" | grep schemaregistry
```

---

### API retorna 404

**Verificar container rodando:**
```bash
docker ps --filter name=schema-registry
```

**Verificar porta mapeada:**
```bash
curl http://localhost:8081/health
```

**Se porta errada, recriar container.**

---

## Próximos Passos

- **US-05:** Implantar Apache NiFi
  - Consumir API SPTrans (posição dos ônibus)
  - Validar payloads contra schema `bus_position`
  - Gravar dados na Landing Zone (MinIO)

- **US-06:** Implantar Apache Spark
  - Ler dados da Landing usando schema do Registry
  - Criar tabelas Iceberg na Bronze Zone
  - Registrar tabelas no Hive Metastore

---

## Comandos Úteis de Referência

```bash
# Listar todos os grupos
curl -s http://localhost:8081/apis/registry/v2/groups | jq .

# Listar artifacts de um grupo
curl -s http://localhost:8081/apis/registry/v2/groups/sptrans/artifacts | jq .

# Consultar metadata de um artifact
curl -s http://localhost:8081/apis/registry/v2/groups/sptrans/artifacts/bus_position | jq .

# Consultar versão específica (conteúdo do schema)
curl -s http://localhost:8081/apis/registry/v2/groups/sptrans/artifacts/bus_position/versions/1 | jq .

# Listar todas as versões de um artifact
curl -s http://localhost:8081/apis/registry/v2/groups/sptrans/artifacts/bus_position/versions | jq .

# Registrar nova versão (atualização de schema)
curl -X POST http://localhost:8081/apis/registry/v2/groups/sptrans/artifacts/bus_position/versions \
  -H "Content-Type: application/json" \
  -H "X-Registry-ArtifactType: AVRO" \
  --data @bus-position-v2.avsc

# Deletar artifact
curl -X DELETE http://localhost:8081/apis/registry/v2/groups/sptrans/artifacts/bus_position

# Verificar conectividade PostgreSQL
docker exec schema-registry pg_isready -h postgres -p 5432

# Ver tabelas do Registry no PostgreSQL
docker exec postgres psql -U postgres -d schemaregistry -c "\dt"

# Backup do banco schemaregistry
docker exec postgres pg_dump -U postgres schemaregistry > schema-registry-backup.sql
```

---

## Requisitos Funcionais Cobertos

- **FR40:** ✅ Serviço Schema Registry implantado
- **FR41:** ✅ Suporta schemas Avro
- **FR42:** ✅ Schema `sptrans.bus_position.v1` registrado
- **FR43:** ✅ Preparado para `sptrans.bus_line.v1`
- **FR44:** ✅ Preparado para `billing.transaction.v1`
- **FR45:** ✅ Suporta políticas de evolução (BACKWARD, FORWARD, FULL)
- **FR46:** ✅ Permite validação de payloads contra schemas
- **FR47:** ✅ API REST exposta na porta 8081
- **FR48:** ✅ Depende de PostgreSQL (funcional)

---

## Referências

- [Apicurio Registry Documentation](https://www.apicur.io/registry/docs/)
- [Apache Avro Documentation](https://avro.apache.org/docs/current/)
- [Schema Evolution in Avro](https://docs.confluent.io/platform/current/schema-registry/avro.html)
- [Apicurio vs Confluent Comparison](https://www.apicur.io/registry/docs/apicurio-registry/2.5.x/getting-started/assembly-intro-to-the-registry.html)
