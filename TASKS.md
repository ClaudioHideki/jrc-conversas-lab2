<!-- jrc-operational-init:v1 -->
# Backlog operacional — JRC Conversas LAB2 — Grupo JRC

## Em progresso (WIP)

- [ ] **CHAMADOS-PROJETOS-20261117:** Base na imagem d468beb8. Abertura interna com empresa/unidade e pessoa elegível; agentes habilitados criam projetos respeitando negações explícitas; leitura somente responsável/participante e administradores da conta; encerrados em popup paginado e cartão Resolvidos inclui fechados. 61 testes Vue locais aprovados. Integração Rails/PostgreSQL, regressão ampla e publicação de imagem ainda pendentes. Sem implantação. Decisão: [ADR0004](docs/adr/0004-chamados-destinatarios-projetos-escopo.md).

- [ ] **CLOUD-REPLY-FIXTURE-20261116:** O build `43981129768`, job `133697571732`, SHA `1ea2f455`, encontrou RED de 1/168 exemplos no reply Cloud (`incoming_message_whatsapp_cloud_service_spec.rb:346`). A fixture criava a conversa sem conta explícita, divergindo da caixa/contato, e o clock corretamente escopado por conta recusou a mensagem recebida. Adicionada somente `account: whatsapp_channel.account` nessa conversa, preservando as assertions de conteúdo e referências da resposta e sem alterar a factory global ou o produto. Os 11 exemplos Cloud entram também no gate inicial CSAT/clock/Webhooks, elevando o mínimo de 28 para 39. Artifact RED `14282453508`; aguardar GREEN de CI e nova construção autorizada, pois o build foi interrompido antes de publicar imagem.

- [ ] **RELEASE-LINT-20261116:** SHA `3d30b82f` aprovou o gate curto Rails (28 + 33 + 74 + 6 + 439 + 156 + 38 exemplos) e Broker/Flow (4 + 1.023 + 4 Rails, 164 frontend). O gate Projetos `43976142193`, job `133680673748`, passou 2 + 1.294 + 21 + 2 exemplos Rails e bloqueou no RuboCop `--only Lint`: 1.096 arquivos inspecionados, somente três ocorrências de `Lint/AmbiguousBlockAssociation`, nas assertions de retenção e de pontuação de relacionamento. Adicionados apenas parênteses explícitos para os três argumentos com bloco, sem alterar expectativas, produto ou regras do gate. Artifact RED `14281770697`; aguardar nova CI no SHA corrigido antes de liberar a imagem.

- [ ] **CLOCK-FIXTURES-20261116:** O refresh do relógio preserva a associação compartilhada e atributos pendentes, mantendo a leitura por `account_id` + `conversation_id`. CI `43973873010`, SHA `ddc7bfd8`, aprovou CSAT/clock 8, retenção 33, nativo 74, badges 6, genéricos 439, histórico/mídias/Minhas/outbound 156 e busca 38, todos sem falhas. O gate amplo `43974827085`, job `133675987354`, identificou 20 falhas em 1.023 exemplos: a fixture de `Webhooks::Trigger` criava a conversa em conta diferente da caixa/mensagem. Corrigida somente essa fixture com conta explícita e incluídos seus 20 exemplos no gate curto CSAT/clock, agora mínimo 28. Não alterar a factory global de conversas nem afrouxar o filtro de conta do produto. Concluir CI no SHA corrigido antes de liberar a imagem; nenhuma validação física ou implantação é inferida desses testes.

- [ ] **RETENTION-RELEASE-20261116:** Pedido posterior autoriza concluir testes, imagens, main e deploy Grupo JRC. Consolidou a retirada de filtros de segmento e o popup de propostas; preserva a frente Call Center em WIP fora desta release. ADR0003 protege destruição de histórico antes de efeitos, sem apagar recibos/KEEP. RED inicial:21 exemplos/16 falhas; primeira correção:22 exemplos/1 falha adicional comprovada em AccountDeletionService,21 aprovados incluindo corrida PostgreSQL. Correção final e CI em andamento. Aceite físico WhatsApp continua separado.

- [ ] **WHATSAPP-RELIABILITY-20261116:** Candidata de estados outbound honestos e recibo LIVE imutável, mídia em custódia privada, reuso estrito LIVE/V2 e clocks separados para cronologia/não lidas. Desenho: [ADR0002](docs/adr/0002-recibo-live-custodia-broker.md); execução: [plano local](docs/jrc_consolidation/live_ingress_receipt_plan_20261116.md). Usuário autorizou branch de testes no GitHub Actions; CI e E2E sintético em fechamento, sem merge/imagens/deploy/envio físico. Helper e componente de publicação passaram 10/10 localmente; runtime Rails3.4.12 e build elegível devem ser verificados na CI. Lifecycle hard delete permanece gate de release; a autoridade de bots legados não foi removida por suposição.
- [ ] **PROPOSTA-POPUP-20261116:** Detalhes comerciais em popup nativo, com X/Esc/fundo e preservação do rascunho. 46 testes locais aprovados; concluir CI e imagem. Escopo: [ADR](docs/adr/20261116-proposta-popup.md).

Publicação encerrada; as pendências operacionais continuam em A fazer. Consulte os recibos e limites em CONTINUE-AQUI.md.

Nenhuma execução funcional é iniciada por este bootstrap. As frentes já em andamento permanecem nos planos/checkpoints existentes.

## A fazer (To Do)

- [ ] **WHATSAPP-OPS-20261115:** Reconciliar autoridade legada por conversa,acesso ao storage e escopo dos grupos antes de novos testes físicos/replay. Não modificar permissões ou eliminar registros por suposição.

- [ ] **DOC-01:** Revisar os termos de [glossary.md](docs/domain/glossary.md) com o responsável pelo domínio.
- [ ] **DOC-02:** Conferir [system-overview.md](docs/architecture/system-overview.md) e as versões com o ambiente efetivo quando houver acesso autorizado.
- [ ] **OPS-01:** Reconciliar conversas por caixa e a política de acesso Minhas/compartilhadas/exclusivas.
- [ ] **OPS-02:** Manter homologação de voz, histórico e mídias distinta de teste sintético e de publicação.

## Concluído (Done)

- [x] **QUICK-REPLIES-RELEASE-20261115:** Produto `5c3fb7f` corrigido, testado e implantado no Grupo JRC: CI 49/49, 404 Rails/504 Vue dirigidos, 13 Chrome e dois E2Es privados; API e Rails/Sidekiq conferidos. Aceite operacional WhatsApp/storage é parcial e a validação física foi adiada pelo usuário. Evidências: `docs/jrc_consolidation/quick_replies_whatsapp_release_20261115.md`.
- [x] **RELEASE-20261114:** Base produtiva `55da80eb` preservada e consolidada na release `5c3fb7f`; imagem, versão, migrations e saúde verificadas em 15/11. Homologação física continua separada.
- [x] **GATES-20261114:** Matriz nativa `43770789984` terminou com 49/49 jobs aprovados, incluindo os gates e o upgrade populado. Nenhuma migration do produto foi modificada neste incremento.
- [x] **REMOVER-FILTRO-SEGMENTO-20261116:** Painel retirado das oito superfícies; imagem do produto `c8efa1d68e1b5706e47cd022fa8e31df1e156e6c` publicada e verificada por digest. CI `43941168985`: três jobs aprovados, 2.752 testes Vue e 168 Rails aprovados, smokes antes/depois da publicação. Implantação não realizada. Referência e limites: [ADR](docs/adr/20261116-remocao-filtro-segmento.md).

- [x] **BOOTSTRAP-01:** Identidade, stack, natureza Brownfield e fontes locais registradas.
- [x] **BOOTSTRAP-02:** Estrutura INIT, domínio, arquitetura e ADR organizados sem apagar conteúdo anterior.

## Como manter

Uma tarefa deve registrar problema, escopo, critério de aceite, evidência/arquivo e limite. Só mover para Concluído com a prova correspondente; não converter publicação de imagem em aceite operacional.


## Respostas rápidas e catálogo de aprovações — 2026-11-15 [WIP]

- Melhorar o atendimento nativo: acesso junto à assinatura, prévia contextual, um anexo e envio explicitamente confirmado, com intenção persistida para retry sem duplicação.
- Traduzir a Central em pt_BR e abrir configurações/edição em Dialog nativo; importar somente rascunhos inativos autorizados, com dry-run, escopo, diff, revisão de identidades e auditoria.
- Base funcional publicada preservada: `55da80eb1254aee54ee0f1fb5c42f2be46a98737`; main e ambientes existentes não são alterados.
- Evidências e limitações: `docs/adr/20261115-respostas-rapidas-catalogo-aprovacoes.md`. CI dirigida e homologação Chrome devem ser provadas sobre o SHA final. Sem publicação de imagem ou deploy nesta tarefa.
