# Voz V4 — diagnóstico e correções

## Baseline verificado

Repositório correto `ClaudioHideki/jrc-conversas-lab2`. O Rails produtivo consultado por `cat /app/.git_sha` retornou `0163e1ee324e0f0de46ed6dc0b869afb3dbc9895`; esta leitura não prova o SHA do Sidekiq nem o estado atual após mudanças externas. Main `a92f9bf8...` é ancestral. Checkpoint local preexistente em `docs/release-integrada-jrc/CONTINUE-AQUI.md` preservado e excluído dos commits desta entrega.

DOCX lido integralmente: `JRC_Conversas_Tela_Agente_Voz_Especificacao_DEV_v4 (2).docx`, SHA-256 `7f2264acb6aa6bd8d60c0503b58b5c239b9f303889cf0b088792c085e13bc93c`. Capa V3/conteúdo V4: consideradas as 21 seções. As quatro capturas produtivas citadas no prompt não foram recebidas como arquivos independentes; duas figuras do DOCX foram inspecionadas. Não foram fabricadas capturas “antes”.

| Defeito reproduzido | Correção | Evidência |
|---|---|---|
| Falha da consulta opcional de cliente/agente impedia mostrar a chamada autorizada | CallWorkspace mantém registro, separa indisponibilidade do cliente e permite notas autorizadas | Vitest RED/GREEN de CallWorkspace |
| Consulta não oferecia correlação exata e contexto detalhado scoped | Filtro provider/external_session_id, projeção por contato vinculado/telefone único e resolver com controle de geração | RSpec e useActiveVoiceContext.spec |
| Controles locais se misturavam à conversa selecionada | GlobalVoiceBar no Dashboard usa singleton SIP; atendimento selecionado permanece independente | E2E A na ligação/B no WhatsApp e specs de shell |
| Locale PT-BR não carregava diretamente catálogo Contact Center | Registro explícito do catálogo existente em português; teste de locale | voiceV4Locale.spec e ausência de chaves cruas no E2E |
| Pausa operacional não atualizava elegibilidade nativa | Transação atualiza AccountUser.availability somente nas transições locais autorizadas | CI RED 42629305380: 2 falhas; correção Rails aprovada posteriormente |
| Notas sobrescritas não tinham histórico consultável | Revisões transacionais, lock_version, paginação e RBAC; sem revisão duplicada para texto inalterado | CI RED 42637693973: 104 exemplos/3 falhas; writer testa rollback e readonly |
| Projeção de perfil view-only incluía notas operacionais | Remoção de attendance_observations sem operate? | Spec de API direta e histórico negado |
| Inbox WhatsApp anterior fazia reaparecer botão Encerrar no cabeçalho de Voz | Regra WhatsApp exige que a seleção não esteja em Voz | header-duplicate-red.json → green.json |
| Rascunho tardio da sessão não aparecia sem remount | Store reativo por identidade; promoção sem apagar edição local | late-draft-red.json → green.json |
| Popup podia desaparecer enquanto originate ainda aguardava | Escape, X e clique fora bloqueados durante busy; falha mantém formulário | Achado P2 da revisão independente; review-red.json → green.json |
| Hold/transferência pendente bloqueava o único Encerrar | Encerramento tem guarda própria contra duplo clique, independente de pending dos outros comandos | Promise SIP diferida no teste; review-red.json → green.json |

## Marca da conexão WhatsApp

Broker: base mais recente `56f9e772c9331710bed65d1d46a4f925f3d3d86d`, branch `codex/broker-device-name-20261109`, commit `d1ae9563167f45dad2157794bbd13e0c9c70889e`. Compose passa `CONFIG_SESSION_PHONE_CLIENT` com padrão **Broker JRC** e `CONFIG_SESSION_PHONE_NAME` com padrão **Chrome**; ambos configuráveis. Preservadas alterações Branef/URA da base e o outro checkout Broker com trabalho local.

É configuração suportada pela engine, não remoção/substituição da Evolution. O efeito visual depende de novo pareamento e do WhatsApp; não foi desconectado nem pareado número real para renomear aparelhos antigos. Não há necessidade técnica de reconstruir API/web/engine por essa mudança isolada de Compose.

## Limites abertos

Não foi comprovada a correspondência do Call-ID do PABX real; conferência, gravação em tempo real, atribuição/adiamento de atendimento de Voz e diagnóstico financeiro/jurídico de serviço continuam com aceites pendentes. Ausência de PABX autorizado bloqueia homologação física; não impede testes Rails/componentes e não justifica declarar implementação funcional completa.
