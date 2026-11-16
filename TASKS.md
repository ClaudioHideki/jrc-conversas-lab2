<!-- jrc-operational-init:v1 -->
# Backlog operacional — JRC Conversas LAB2 — Grupo JRC

## Em progresso (WIP)

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
