# HOYA 360 - Experiência Visual CRM + Contact Center

## Objetivo

Esta entrega transforma a base local da F1 SAC Nacional em uma experiência de demonstração navegável, preservando a implementação funcional existente. O foco é apresentar, com aparência de produto final, as 16 telas conceituais do Contact Center e as 18 telas previstas para o CRM Field.

A entrega não declara integração produtiva com JRC PABX, ERP HOYA, URA, CDR, gravações ou regras oficiais de SLA. As áreas que dependem desses contratos usam dados ilustrativos e pontos de integração preparados para conexão posterior.

## Princípios

- Preservar F0 e F1, sem reconstrução do domínio `JrcContactCenter`.
- Reutilizar o shell, componentes, permissões, feature flags e rotas do JRC Conversas.
- Manter Contact Center e CRM Field como experiências integradas, mas não duplicar CRM, Cadastro Mestre, Agenda, Survey ou Webphone.
- Usar o Cliente/Ótica 360° como ponte entre atendimento e relacionamento comercial.
- Não criar endpoints, tokens, eventos ou capacidades externas não homologadas.
- Manter `jrc_contact_center` desligado por padrão.
- Não alterar migrations, schema, lockfiles ou contratos backend nesta rodada visual.

## Catálogo Contact Center - 16 telas

| # | Tela | Rota visual | Base utilizada |
|---|---|---|---|
| 01 | Cockpit do atendente | `contact-center/operacao` | Cockpit F1, estado do agente, chamadas e contexto |
| 02 | Chamada em atendimento | `contact-center/chamada/:callId?` | `CallWorkspace`, CallSession e ações autorizadas |
| 03 | Pós-atendimento e tabulação | `contact-center/pos-atendimento` | ACW, qualificação e encerramento demonstrativo |
| 04 | Supervisor do SAC | `contact-center/supervisor` | Snapshot, filas, agentes e métricas F1 |
| 05 | Control Desk Nacional | `contact-center/control-desk` | Saúde, eventos, comandos e capacidades |
| 06 | Construtor de URA | `contact-center/ura` | Editor visual demonstrativo; publicação futura |
| 07 | Consulta de pedidos na URA | `contact-center/ura/pedidos` | Jornada ilustrativa; ERP futuro |
| 08 | Gestão dos 20 COEs | `contact-center/coes` | Units, queues e routing rules |
| 09 | Atendimento Financeiro | `contact-center/financeiro` | Unidade/fila/case com proteção de perfil |
| 10 | Cliente e Ótica 360° | `contact-center/cliente-360/:customerId?` | CRM/Cadastro Mestre e timeline unificada |
| 11 | Monitor do JRC PABX | `contact-center/pabx` | Provider capabilities e saúde operacional |
| 12 | Gravações e Qualidade | `contact-center/gravacoes` | Recording metadata e auditoria visual |
| 13 | Relatórios de Operação | `contact-center/relatorios` | Métricas F1 e catálogo executivo |
| 14 | Pesquisa de Satisfação | `contact-center/pesquisas` | Survey/Relationship existente |
| 15 | Segurança e Perfis | `contact-center/seguranca` | RBAC, filas, unidades e capacidades |
| 16 | Painel de Migração | `contact-center/migracao` | Ondas, gates, riscos e rollback |

## Catálogo CRM Field - 18 telas

| # | Tela | Rota visual |
|---|---|---|
| 01 | Meu Dia | `crm/field/meu-dia` |
| 02 | Agenda e Calendário | `crm/field/agenda` |
| 03 | Mapa de Visitas | `crm/field/mapa` |
| 04 | Nova Visita / Check-in | `crm/field/visitas/nova` |
| 05 | Relatório de Visita | `crm/field/visitas/relatorio` |
| 06 | Minha Carteira | `crm/field/carteira` |
| 07 | Cliente 360° | `crm/field/cliente-360` |
| 08 | Oportunidades | `crm/field/oportunidades` |
| 09 | Pedidos e Entregas | `crm/field/pedidos` |
| 10 | Tarefas e Retornos | `crm/field/tarefas` |
| 11 | Ações de Divulgação | `crm/field/divulgacao` |
| 12 | Treinamentos | `crm/field/treinamentos` |
| 13 | Catálogo e Materiais | `crm/field/catalogo` |
| 14 | Telefonia Mobile | `crm/field/telefonia` |
| 15 | Nico Field | `crm/field/nico` |
| 16 | Notificações | `crm/field/notificacoes` |
| 17 | Gestão Regional | `crm/field/gestao-regional` |
| 18 | Relatórios Field | `crm/field/relatorios` |

## Sistema visual

A camada visual usa componentes compartilhados para evitar telas desconexas:

- `VisualShowcasePage`: hero, ações, métricas, jornada, conteúdo, tendências, marcos e timeline.
- `VisualMetricCard`: indicadores compactos com tendência e status.
- `VisualSectionCard`: seções consistentes com título, descrição e ícone.
- `VisualStatusBadge`: estados operacionais e de integração.
- `VisualTimeline`: histórico unificado de CRM e atendimento.
- `VisualProgress`: indicadores e metas.
- `VisualMiniBars`: tendências demonstrativas sem dependência de biblioteca adicional.

O Contact Center usa navegação secundária por Atendimento, Operação, Telefonia e Gestão. O CRM Field usa Minha rotina, Clientes e negócios, Divulgação e suporte e Gestão.

## Ponte Cliente/Ótica 360°

As duas experiências possuem ações cruzadas:

- Contact Center -> CRM Field Cliente 360° / Minha Carteira.
- CRM Field -> Contact Center Cliente 360° / Cockpit.

A ponte é visual nesta rodada e foi construída sem duplicar empresa, contato, pedido ou histórico. A fonte definitiva continua sendo o Cadastro Mestre/CRM, com referências do ERP adicionadas futuramente.

## Dados nativos e demonstrativos

### Nativos da F1

- Estados do agente e elegibilidade.
- Unidades, filas e memberships.
- CallSession, CallLeg e jornada registrada.
- Ocorrências e callbacks.
- Integração com Minha Agenda.
- Supervisor, eventos, comandos e métricas disponíveis.
- Permissões e Survey/Relationship existentes.

### Demonstrativos até contrato externo

- Árvore/publicação real de URA.
- Pedidos e financeiro do ERP HOYA.
- Os 20 COEs e DDD oficiais.
- Telefonia, transferência, CDR e gravações reais.
- DIDs, 0800 e thresholds oficiais.
- SLA contratual e contingência real.
- Nico Voice e WhatsApp corporativo.

Os catálogos visuais ficam isolados dos adapters produtivos. A troca futura deve ocorrer na camada de provider/service, e não por reconstrução das telas.

## Pontos de integração futura

- `JrcContactCenter::Providers::JrcPabxAdapter` para telefonia e capacidades.
- Event inbox/reconciler para webhooks canônicos.
- Commands para ações assíncronas confirmadas pelo PABX.
- Gateway ERP para pedidos, montagem, entrega e financeiro.
- Recording links para URLs temporárias e autorizadas.
- Survey/Relationship para NPS/CSAT.
- Cadastro Mestre/CRM para óticas, contatos, carteira e timeline.

## Segurança e escopo

- Todas as rotas permanecem account-scoped.
- Perfis e feature flags existentes continuam sendo verificados.
- Nenhum dado real, token, senha, gravação ou endpoint externo foi incluído.
- A interface não afirma que uma operação externa foi concluída sem confirmação do backend/provider.
- Service Desk continua fora do fluxo de ocorrência do Contact Center.

## Validação necessária no Git/Codex

Este snapshot não inclui dependências instaladas. Antes de commit/push, executar no ambiente nativo do repositório:

1. `pnpm eslint` nos arquivos do delta.
2. Vitest dos catálogos, rotas, layouts e regressões Webphone/F1.
3. Rails specs dirigidos F1, caso qualquer contrato compartilhado seja afetado.
4. `assets:precompile`/build de produção.
5. Renderização em navegador nas larguras desktop, notebook e tablet.
6. Conferência de feature flags e permissões em duas Accounts.

Não fazer commit, push, imagem ou deploy sem autorização específica.
