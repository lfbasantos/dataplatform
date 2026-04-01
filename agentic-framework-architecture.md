Framework de Engenharia de Dados Orientada a Agentes (ADE)
Documento de Arquitetura e Constituição do Sistema

1. Visão Geral e Objetivo
Este documento define as diretrizes, a arquitetura e os padrões de operação para um Multi-Agent System (MAS) aplicado à Engenharia de Dados. O objetivo deste framework é fazer a transição de pipelines puramente imperativos para Pipelines Declarativos e Baseados em Intenção, utilizando inteligência artificial para design, revisão e qualidade de código, mantendo a execução orquestrada sob rígidos Guardiões Determinísticos (Deterministic Guardrails).

A arquitetura resolve o gargalo de desenvolvimento e manutenção de catálogos de dados extensos, delegando a criação e o self-healing (auto-cura) a agentes LLM, enquanto a execução rotineira e o consumo computacional permanecem ancorados em orquestradores tradicionais open-source.

2. Glossário e Conceitos-Chave (Rastreabilidade de Mercado)
Para alinhamento com iniciativas de mercado e literatura de LLM Ops, adotamos a seguinte nomenclatura:

ADE (Agentic Data Engineering): Paradigma onde agentes de IA autônomos gerenciam o ciclo de vida dos dados (ingestão, transformação, modelagem), guiados por metadados e intenções declarativas (YAML), em vez de scripts manuais.

MAS (Multi-Agent System): Sistema composto por múltiplos agentes de IA interagindo entre si. Neste framework, aplicamos o princípio de Segregation of Duties (Segregação de Funções) entre agentes de criação, revisão e qualidade.

Tiered LLM Architecture (Arquitetura LLM em Camadas): Estratégia de otimização de custos e latência que utiliza Modelos de Fronteira (Frontier Models, ex: Claude 3.5 Sonnet/Opus, GPT-4o) para tarefas complexas de raciocínio, e Modelos Locais/Menores (SLMs - Small Language Models, ex: Llama 3 8B via Ollama) para roteamento e monitoramento contínuo.

Deterministic Guardrails (Guardiões Determinísticos): Ferramentas clássicas de validação (ex: sqlfluff, testes de Data Quality, Profilers) que atuam como juízes absolutos sobre o código gerado pela IA. Os agentes iteram com base nos erros dessas ferramentas, eliminando a subjetividade da IA.

DaC (Documentation-as-Code) para Gerenciamento de Estado: Abordagem onde o "estado" e a "memória" dos agentes (que são stateless por natureza) são armazenados em arquivos Markdown (.md). Inspiração direta no "Padrão Amnesia", garantindo que humanos e máquinas compartilhem o mesmo contexto auditável.

Circuit Breaker (Disjuntor): Padrão de confiabilidade que interrompe processos em loop. No contexto de IA, é o mecanismo que impede o esgotamento de tokens ou o estouro de janelas de tempo (SLAs) em caso de falhas contínuas de raciocínio.

3. Topologia do Sistema
A arquitetura integra componentes tradicionais de engenharia de dados com o ecossistema de agentes.

3.1. Camada de Integração e Orquestração
N Fontes de Dados: APIs, Bancos Relacionais, Sistemas IoT, Mensageria.

Data Lake / Data Warehouse: O destino final para armazenamento e processamento distribuído.

Orquestrador (O "Motor"): Ferramenta open-source (ex: Apache Airflow, Dagster). Ele executa DAGs compiladas e aciona o Agente Monitor via logs ou webhooks. Ele não "pensa", apenas executa e reporta.

Repositório Git (A "Memória de Longo Prazo"): Armazena configurações (.yaml), regras de guardrails, estado de execução (.md) e os artefatos finais de código (SQL/Python).

3.2. Camada de Agentes (MAS)
Agent Monitor (O Roteador): SLM local (via Ollama). Lê logs do orquestrador, classifica erros de acordo com o catálogo (Runbook) e despacha a tarefa.

Agent-Job (O Construtor): Modelo de Fronteira. Lê as especificações em YAML e os esquemas de origem/destino, e escreve o código de transformação e extração.

Agent-Review (O Revisor de Sintaxe e Performance): Avalia o código do Agent-Job estritamente contra as regras do linter (ex: sqlfluff) e regras de complexidade pré-definidas.

Agent-Quality (O Revisor de Dados): Executa testes de perfilamento (profiling) nos dados gerados em sandbox comparando origem e destino para aprovar a fidelidade da carga.

4. Fluxos de Operação (Diagramas)
4.1. Fluxo de Desenvolvimento e Deploy (CI/CD Guiado por IA)
Este fluxo ocorre na criação de um novo pipeline ou na refatoração de um existente.

Snippet de código
sequenceDiagram
    participant Engenheiro
    participant Git_Repo
    participant Agent_Job
    participant Agent_Review
    participant Agent_Quality
    
    Engenheiro->>Git_Repo: Submete YAML (Origem, Destino, Regras)
    Git_Repo->>Agent_Job: Webhook Aciona Criação
    Agent_Job->>Agent_Job: Analisa Metadados e Escreve tasks.md
    Agent_Job->>Agent_Job: Gera Código (SQL/Python)
    Agent_Job->>Agent_Review: Submete Código
    
    loop Até passar no Linting (Max Retries)
        Agent_Review->>Agent_Review: Roda Guardrails (ex: sqlfluff)
        alt Erro
            Agent_Review-->>Agent_Job: Retorna String de Erro
            Agent_Job->>Agent_Job: Corrige Código
        end
    end
    
    Agent_Review->>Agent_Quality: Passa para Teste de Dados
    
    loop Até passar no Profiling (Max Retries)
        Agent_Quality->>Agent_Quality: Roda Testes de Qualidade (Sandbox)
        alt Divergência
            Agent_Quality-->>Agent_Job: Retorna Relatório de Profiling
            Agent_Job->>Agent_Job: Ajusta Lógica de Negócio
        end
    end
    
    Agent_Quality->>Git_Repo: Abre Pull Request (Código + Profiling_Report.md)
    Git_Repo->>Engenheiro: Notifica para Validação Final
    Engenheiro->>Git_Repo: Approve & Merge -> Orquestrador assume
4.2. Fluxo de Resiliência (Self-Healing & Circuit Breaker)
Este fluxo é ativado quando o Orquestrador falha durante a carga de produção.

Snippet de código
graph TD
    A[Falha no Orquestrador] --> B(Geração de Log de Erro)
    B --> C{Agent Monitor analisa Erro}
    
    C -- Erro Catalogado (Runbook) --> D[Despacha para Agent-Job iniciar Correção]
    D --> E{Validação Review/Quality}
    E -- Passou --> F[Abre Pull Request para Retomar Pipeline]
    E -- Falhou sucessivamente --> G(Dispara Circuit Breaker: Limite de Iterações)
    
    C -- Erro Desconhecido/Anomalia de Negócio --> H(Dispara Circuit Breaker: SLA/Timeout)
    
    G --> I[Atualiza tasks.md com STATUS_LOCKED]
    H --> I
    I --> J[Notifica Analista via PagerDuty/Slack]
    
    J --> K((Intervenção do Analista - HUMAN OVERRIDE))
    K --> L[Git Commit no tasks.md]
    L --> M[Webhook Acorda Agente para Retomar Execução]
5. A Constituição do Sistema (System Prompt & Regras de Estado)
Todos os agentes de criação (Job, Review, Quality) devem operar sob um System Prompt base que imponha o "Padrão Amnesia" e o uso estrito do Documentation-as-Code.

Diretrizes de Comportamento do Agente:
Você não possui memória de longo prazo nativa. Seu estado atual, progresso e contexto residem integralmente no arquivo tasks.md da branch atual.

Antes de gerar qualquer código, você deve obrigatoriamente criar ou atualizar três arquivos:

contexto.md: A interpretação do problema e metadados lidos.

plano.md: A estratégia passo a passo (Plan-and-Solve).

tasks.md: O checklist de execução.

Subserviência aos Guardiões: Você não deve contestar o Agent-Review ou os relatórios de Profiling. O output dessas ferramentas é a verdade absoluta. Adapte o seu código até que os erros desapareçam.

Sintaxe de Gerenciamento de Estado (Obrigatório em tasks.md):
Os agentes devem utilizar e respeitar as seguintes tipagens de blocos para controle de fluxo:

[STATUS: PENDING | RUNNING | DONE]: Usado pela IA para marcar o progresso de cada tarefa.

[STATUS: CIRCUIT_BREAKER_TRIGGERED]: Inserido pela IA quando o limite de iterações ou timeout for atingido. A IA deve parar de processar imediatamente após inserir esta flag.

[HUMAN_OVERRIDE: INITIATED] ... [HUMAN_OVERRIDE: END]: Bloco de preenchimento exclusivo humano.

Regra Suprema de Retomada:
Se ao inicializar, o agente encontrar a tag [HUMAN_OVERRIDE: INITIATED] no arquivo tasks.md, ele deve:

Interromper qualquer raciocínio prévio sobre aquela tarefa.

Assumir as instruções contidas dentro do bloco como diretrizes absolutas e incontestáveis.

Retomar a execução exatamente a partir do ponto instruído pelo humano.
