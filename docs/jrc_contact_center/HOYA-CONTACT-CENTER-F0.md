# JRC Contact Center - F0 Fundacao

## Estado deste candidato

Este pacote implementa somente a fundacao tecnica do dominio `JrcContactCenter` sobre a base HOYA recebida em 14/10/2026.
A feature flag `jrc_contact_center` nasce desligada por padrao. Nenhum endpoint real do JRC PABX, ERP, URA, 0800, DDD/COE ou Meta foi inventado ou ativado.

Base congelada usada nesta rodada:

- ZIP: `JRCConversa-HOYA-codex-hoya-inicial-20261013.zip`
- SHA-256: `35b66f3c4f297e2299609fd78fb7d65dd4fd76717506df663673618ecf8346fc`
- Arquivos regulares na base: 11.121
- Manifesto local da base: SHA-256 `c395d7b75bb153bb3e34f2752ce9ac9dda47d569986543183d019fdce1fbb5ca`
- Referencia de importacao JRC registrada em `HOYA-SETUP.md`: `e8e70d14246e18dc8f84e354f66a4b1ff548e7ad`
- Base SHA do repositorio HOYA registrada em `HOYA-SETUP.md`: `f22a5e6866ecc0ac7bdad24e94cb711607429f62`

## Fronteira arquitetural

- JRC PABX: motor de telefonia, SIP/WebRTC, URA, ACD/filas, transferencias, gravacoes e contingencia quando os contratos forem homologados.
- JRC Conversas / JrcContactCenter: experiencia do agente, CRM/contexto, escopo de acesso, ocorrencias, callback, supervisao, auditoria e relatorios.
- ERP: permanece fonte externa dos dados operacionais autorizados. A F0 nao grava nem consulta ERP real.
- Service Desk: permanece independente. Ocorrencias do Contact Center usam `JrcContactCenter::Case`, sem criar tickets do Service Desk.

## Entregas F0

### Dominio e banco

Migration aditiva `20261014100000_create_jrc_contact_center_foundation.rb` com estruturas account-scoped para:

- unidades e filas;
- vinculos agente-fila;
- CallSession e CallLeg;
- eventos de URA e estados do agente;
- qualificacao pos-chamada;
- ocorrencias e timeline;
- regras de roteamento versionadas;
- fallback;
- callbacks;
- inbox duravel de eventos;
- comandos assincronos;
- metadados de gravacao;
- fatos diarios reconciliaveis para relatorios.

As referencias multitenant usam `account_id` e chaves estrangeiras compostas quando aplicavel.

### Seguranca e escopo

Permissoes novas de papel customizado:

- `jrc_contact_center_view`
- `jrc_contact_center_operate`
- `jrc_contact_center_supervise`
- `jrc_contact_center_configure`
- `jrc_contact_center_reports`

Agentes comuns enxergam filas explicitamente vinculadas e registros pertencentes ao seu escopo. Supervisao/configuracao recebem escopo ampliado conforme permissao. IDs de fila, unidade, usuario e destino de roteamento sao validados dentro da conta antes de escrita.

### Integracao de telefonia

`JrcContactCenter::Providers::JrcPabxAdapter` existe como contrato de capabilities, mas as capacidades externas permanecem `pending_contract`.
O codigo legado Hodu nao e promovido automaticamente a contrato JRC PABX e nenhum DTMF legado foi copiado como regra nova.

A inbox de eventos implementa idempotencia por conta/provedor/evento, digest de payload e estado de processamento. O reconciliador preserva uma unica CallSession e impede regressao simples de chamada terminal quando eventos de ciclo chegam fora de ordem.

### Frontend

Rotas account-scoped adicionadas sob `/accounts/:accountId/contact-center`:

- Operacao / Cockpit;
- Supervisor;
- Control Desk;
- Ocorrencias;
- Relatorios;
- Configuracoes.

A navegacao aparece somente quando a feature flag e o perfil permitem. O Cockpit informa explicitamente que o contrato externo ainda esta pendente.

### Minha Agenda

Callbacks do Contact Center sao projetados de forma somente-leitura na `Minha Agenda`, sem duplicar o registro de origem. O item abre o Cockpit do Contact Center no callback correspondente.

## Deliberadamente fora da F0

Nao fazem parte deste candidato:

- ativacao de numero 0800/DID;
- arvore real da URA e audios;
- tabela real DDD -> COE ou overrides;
- regras reais de fallback COE -> SAC;
- chamadas reais pelo JRC PABX;
- transferencia real, CDR ou download de gravacao;
- endpoints ou credenciais ERP;
- escrita em ERP;
- coexistencia dos WhatsApps corporativos;
- Nico Voice;
- deploy, commit, push ou geracao de imagem.

Esses itens dependem dos contratos e dados homologados do projeto e devem entrar nas fases posteriores.

## Validacao que deve ser executada no Codex/Git HOYA

Antes de commit/push/imagem:

1. Confirmar branch, HEAD e `git status` do repositorio HOYA real.
2. Comparar o HEAD atual com o ZIP-base e com este delta; nao usar reset/checkout destrutivo.
3. Confirmar que migrations historicas nao foram modificadas e que a nova migration e aditiva.
4. Rodar a nova migration em PostgreSQL descartavel; rollback e reaplicacao.
5. Rodar specs do Contact Center e regressao dirigida de Agenda, CRM, Cadastro Mestre, Ligacoes, Service Desk, Projetos, Relacionamento e Nico.
6. Rodar RuboCop/ESLint/Vitest conforme o runtime oficial do repositorio.
7. Rodar build de producao com Ruby 3.4.4, Node 24.13.0 e pnpm 10.2.0 definidos pela base.
8. Validar visualmente as rotas do Contact Center com a flag ligada apenas na conta de teste.
9. Confirmar isolamento entre dois tenants e entre duas filas/COEs antes de habilitar piloto.
10. Somente depois de aceite gerar commit/push e a imagem do repositorio HOYA.

## Limitacao desta execucao local

O ambiente de trabalho usado para montar o candidato nao possui o runtime completo bloqueado da aplicacao: Ruby local 3.3.8, Node 22.16.0, sem `bundle`/`pnpm` instalados a partir do lockfile e sem rede para buscar dependencias. Foram executadas validacoes estaticas locais; migration, RSpec, Vitest, ESLint, RuboCop e build de producao precisam ser confirmados no ambiente Codex/Git HOYA antes de qualquer imagem.
