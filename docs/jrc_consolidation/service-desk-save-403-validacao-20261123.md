# Service Desk — diagnóstico e correção local do 403 ao salvar

Data: 2026-11-23. Branch local: `codex/service-desk-save-403-20261123`.
Base: `b6cfb57`. Sem push, merge, imagem publicada ou deploy nesta tarefa.

## Causa comprovada

`TicketsController#create` autoriza a unidade e a criação e chama
`CreateTicketWorkflowService#call` → `CreateTicketService#call`.
O serviço cria a identidade interna quando ausente, monta e autoriza o ticket,
salva dentro da transação e chama `IntakeRuleApplication#record_sla!`.

Na base investigada, a linha **28** desse último método exige
`context.capability?(:sla_snapshots_record)`. Isso confunde a aplicação automática
de uma regra publicada com a permissão de fornecer condições manuais de SLA.
Agentes com criação autorizada, mas sem essa permissão manual, recebem
`Pundit::NotAuthorizedError`. A transação desfaz o ticket e o contato recém-criado;
`RequestExceptionHandler` encaminha a exceção a
`OperationsController#render_unauthorized`, que responde 403 `forbidden`.

A reprodução isolada pela API, antes da mudança no backend, falhou nos dois
cenários esperados como 201: destinatário padrão e seleção explícita.
Um TracePoint de teste registrou somente classe/localização da exceção:
`/app/app/services/jrc_service_desk/intake_rule_application.rb:28`.
Não houve rastreamento de payloads, conteúdo ou credenciais produtivas.

O diagnóstico de produção fornecido pelo operador confirma serviço 35 aberto,
ativo na conta/unidade corretas, sem fila/responsável próprios e sem restrições
comerciais; regra de seleção de SLA ativa e ausência de captura NICO publicada.
A política aplicável é a versão 5, modo `calendar_snapshot`, com relógios de
primeira resposta e resolução. As verificações iniciais de identidade, criação,
unidade, destinatário e supervisão já haviam sido aprovadas pelo operador.
O banco produtivo não foi copiado nem alterado.

## Correção

- A aplicação automática permanece dentro da criação autorizada e bloqueada por
  unidade. Usa exclusivamente o snapshot da regra publicada, com digest,
  referências, calendário e política de ciclo de vida verificados.
- `SlaSnapshotWriter` compartilha a persistência do snapshot, marcos e evento
  de auditoria. Conserva digest, versão e prevenção de repetição. Não cria endpoint
  ou opção de payload capaz de ignorar autorização.
- A gravação manual mantém `RecordSlaSnapshotService#authorize!`, o endpoint e
  `SlaSnapshotPolicy#create?`, inclusive `sla_snapshots_record`.
- O frontend trata 403 de escrita como recusa da operação e preserva o formulário
  e seu contexto. Não confirma sucesso nem executa leitura de sucesso após recusa.
  401 continua invalidando a sessão; leituras negadas continuam limpando dados.
- O formulário interno conserva a intenção e a chave de idempotência na recusa;
  protege o rascunho de edição conflitante e permite repetir a mesma tentativa.
  Validação 422 continua permitindo corrigir a intenção. Submissões simultâneas
  do mesmo formulário enviam somente uma requisição.
- A confirmação do destinatário explícito deixa de impor a fila legada, pois
  a pessoa pode ter outro destino autorizado na mesma unidade. A leitura ainda
  confere conta, unidade, destinatário e campos realmente persistidos.
- A mensagem de recusa reutiliza uma tradução existente, sem chave bruta ou
  mensagem de bloqueio geral do módulo.

## Arquivos alterados

Backend:

- `app/services/jrc_service_desk/create_ticket_service.rb`
- `app/services/jrc_service_desk/internal_intake.rb`
- `app/services/jrc_service_desk/intake_rule_application.rb`
- `app/services/jrc_service_desk/record_sla_snapshot_service.rb`
- `app/services/jrc_service_desk/sla_snapshot_writer.rb` (novo)

Frontend:

- `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/operationalSession.js`
- `app/javascript/dashboard/routes/dashboard/serviceDesk/components/InternalTicketForm.vue`
- `app/javascript/dashboard/routes/dashboard/serviceDesk/components/WriteFeedback.vue`

Testes:

- `spec/services/jrc_service_desk/internal_intake_integration_spec.rb`
- `app/javascript/dashboard/routes/dashboard/serviceDesk/helpers/spec/createAuthorization.spec.js` (novo)
- `app/javascript/dashboard/routes/dashboard/serviceDesk/components/spec/IntakeAndArchive.spec.js`
- `app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/cp4Cases.js`

Documentação:

- Este relatório.
- `docs/adr/0009-sla-publicado-na-criacao-autorizada.md` (novo).
- `docs/adr/README.md`, `TASKS.md` e `ROADMAP.md`.

## Validação

Ambiente descartável: Ruby 3.4.12, dependências do Gemfile.lock,
PostgreSQL 16/pgvector e Redis 7. Rede Docker interna, sem portas públicas,
sem volumes ou credenciais de produção. Fonte de testes copiada para disco Linux
para evitar o custo de leitura do volume Windows; condições de teste sintéticas.

- RED do backend: 2 exemplos falharam com 403, ambos na linha comprovada, antes
  da correção. A permissão manual ausente foi afirmada explicitamente.
- Primeiro GREEN da abertura interna: 16 exemplos, zero falhas.
- Frontend ampliado final: 93 arquivos, **1.153 testes aprovados**, zero falhas.
- Conferência final das alterações de feedback/contrato: 4 arquivos,
  **74 testes aprovados**, zero falhas. Inclui formulário montado, cliente HTTP
  real com resposta simulada 403, serviço 35, rascunho preservado, mensagem real
  traduzida e repetição com a mesma chave.
- Suíte Rails ampliada: **1.068 exemplos**, zero pendências; 1.067 aprovados
  inicialmente e uma expectativa incorreta no teste novo de equipe incompatível.
  O contrato nativo responde 404 quando `TeamMember.take!` não encontra o vínculo,
  em vez do 403 esperado pelo teste. Nenhuma autorização do produto foi alterada
  para satisfazer esse caso.
- Depois de corrigir somente a expectativa para 404: **19 exemplos de abertura
  aprovados**, zero falhas e zero pendências, incluindo os cinco cenários novos.
  Os outros 1.049 exemplos da suíte ampliada não foram modificados nem repetidos.
- Concorrência: **22 exemplos aprovados**, zero falhas e zero pendências,
  com conexões PostgreSQL independentes. Para respeitar os guards existentes,
  a execução final usou um banco vazio explicitamente permitido e ambos os
  opt-ins; as listas de segurança e os guards não foram alterados.
- Cobertura final por união dos resultados: **1.090 cenários Rails distintos
  aprovados**. O histórico acima diferencia a execução ampliada inicial da
  revalidação direcionada; não representa uma segunda execução integral.
- Lint: comparação com a base, sem novos alertas Ruby `Lint/` ou `Security/`.
  Sem erros ou avisos ESLint novos nas linhas alteradas. Existem convenções de
  formatação/métricas na base e nos testes; isso não deve
  ser confundido com uma execução integral de RuboCop sem avisos.
- `git diff --check` aprovado. Hashes dos serviços alterados e do teste de
  abertura conferidos entre a árvore local e a fonte executada no disco Linux,
  normalizando apenas CRLF/LF. Nenhuma diferença de conteúdo funcional.

Os testes novos cobrem agente comum, ausência do contato, destinatário padrão
diferente do solicitante, seleção explícita, replay com um snapshot/ciclo,
negação manual de snapshot pela API e serviço, papel sem criação, unidade não
autorizada, serviço de outra conta e equipe padrão incompatível.

## Ajuste final — escolha livre de responsável elegível

Após o pedido adicional, foram reproduzidas duas limitações na implementação:
uma fila padrão de serviço inativa era buscada antes de aplicar o destino válido
da pessoa selecionada; a seleção interna não conferia a autenticação nativa ativa
do destinatário, embora conferisse seu vínculo operacional.

Antes do ajuste, os seis novos cenários tiveram duas falhas. A criação com fila
padrão inativa recebeu 404 e o destinatário com autenticação inativa apareceu na
lista. As outras quatro verificações já passaram, confirmando a independência
do responsável padrão e as restrições de conta/vínculo.

`CreateTicketService#catalogue_references` agora dispensa a fila padrão do serviço
somente na abertura interna, pois seu destino é resolvido por `InternalIntake`.
`InternalIntake.recipient_allowed?` também exige a autenticação nativa ativa do
destinatário, relida do banco. Não há whitelisting de usuários nem novos grants.

Revalidação da versão com este ajuste:

- **176 testes Rails aprovados**, zero falhas e zero pendências, abrangendo criação,
  catálogo, todos os testes da pasta de políticas, guards de comandos, feature gate,
  regras publicadas, operações HTTP, integração e encerramento/SLA.
- Nesses testes, **25 exemplos de abertura interna**, incluindo seis novos:
  outra equipe/fila com padrão inativo e configuração legada ausente, incluindo
  replay preservando o mesmo ID e o destinatário; padrão de serviço/legado desabilitado;
  fila de serviço de outra equipe; autenticação inativa; vínculo inativo; e
  destinatário de outra conta. Não há substituição silenciosa pelo padrão.
- **87 testes Vue aprovados**, zero falhas, em seis arquivos. O teste adicional
  recusa a confirmação se a leitura do servidor substituir a pessoa escolhida
  pelo padrão. Também são revalidados rascunho após 403, destinatários sem triagem
  legada, prevenção de duplicidade, recibo e navegação.
- Os números da suíte ampla anterior acima documentam o incremento de SLA/403.
  Os 176/87 são a revalidação direcionada posterior às duas alterações adicionais;
  não representam uma segunda execução de toda a suíte ampla.

| Requisito | Resultado no código local |
| --- | --- |
| Escolher qualquer destinatário elegível da unidade | Lista e execução usam o vínculo operacional ativo, a autenticação e as políticas do destino; não limitam à pessoa padrão. |
| Ajustar fila/equipe automaticamente | Usa destino compatível com a pessoa; comprovado com outra equipe e fila explícitas. |
| Dispensar administração e edição manual de SLA | Agente comum cria e recebe SLA publicado; gravação manual permanece protegida. |
| Não depender de triagem/padrões inválidos | Padrão inativo, responsável desabilitado e ausência de configuração legada não bloqueiam a escolha válida. |
| Preservar os dados após erro | Recusa de escrita é local, com rascunho e chave de tentativa mantidos. |
| Manter o responsável escolhido | Atribuição persistida exata, replay com o mesmo chamado e confirmação recusada em caso de substituição. |
| Isolar conta/unidade e excluir inativos | Destinos fora do escopo, sem vínculo ativo, sem autorização manual ou com autenticação inativa são recusados. |
| Preservar demais operações | Não há alteração de Pundit, roles, memberships ou supervisão; fluxo de catálogo não interno conserva seus padrões. |

## Riscos e homologação

- A mudança aplica SLA publicado também a criações autorizadas de agentes que
  antes eram recusadas indevidamente. Não altera metas nem regras publicadas.
- Configuração inválida de calendário/ciclo de vida continua bloqueando a
  aplicação; não se fabrica cumprimento de SLA nem se desativa a medição.
- Um 2xx sem leitura confirmada continua pendente, preservando a proteção contra
  repetição indevida. Uma recusa de escrita não equivale a sessão expirada.
- Não foram alterados papéis, memberships, permissões globais, supervisão,
  isolamento, Pundit ou visibilidade de outros chamados.
- A árvore Enterprise foi conferida; não há override correspondente dos serviços
  alterados. Os 41 testes da pasta de políticas nativas passaram na validação
  ampliada, junto de 61 exemplos de modelos, 459 da pasta de serviços e 507
  da pasta de requests; a revalidação de abertura está discriminada acima.
- O aceite operacional do usuário em produção depende de homologação e publicação
  posteriores, mediante autorização. Nenhum chamado produtivo foi criado como teste.
