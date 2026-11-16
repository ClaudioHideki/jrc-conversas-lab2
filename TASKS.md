<!-- jrc-operational-init:v1 -->
# Backlog operacional — JRC Conversas LAB2 — Grupo JRC

## Em progresso (WIP)

- [ ] **QUICK-REPLIES-RELEASE-20261115:** Correções de anexo/revisão, seleção de catálogo e limite nativo implementadas e revisadas; 504 testes Vue e 15 negativas do contrato passaram. Concluir Rails/Chrome/E2E/CI/imagem e aplicação autorizada no Grupo JRC antes de marcar a release concluída. Plano e evidências: `docs/jrc_consolidation/quick_replies_whatsapp_release_20261115.md`.

- [ ] **RELEASE-20261114:** Promover a consolidação de histórico/runtime/aprovações após CI e imagem do SHA exato; verificar versão, migrations e saúde no Grupo JRC. Código e testes locais registrados em CONTINUE-AQUI.md; implantação ainda não comprovada.
- [ ] **GATES-20261114:** Confirmar na CI nativa os manifestos reconciliados e o upgrade populado de Backoffice com workflow legado. Provas locais: 15 testes Python e 52 Node; Ruby/PostgreSQL ainda dependem do runner. Nenhuma migration do produto foi modificada.

Nenhuma execução funcional é iniciada por este bootstrap. As frentes já em andamento permanecem nos planos/checkpoints existentes.

## A fazer (To Do)

- [ ] **DOC-01:** Revisar os termos de [glossary.md](docs/domain/glossary.md) com o responsável pelo domínio.
- [ ] **DOC-02:** Conferir [system-overview.md](docs/architecture/system-overview.md) e as versões com o ambiente efetivo quando houver acesso autorizado.
- [ ] **OPS-01:** Reconciliar conversas por caixa e a política de acesso Minhas/compartilhadas/exclusivas.
- [ ] **OPS-02:** Manter homologação de voz, histórico e mídias distinta de teste sintético e de publicação.

## Concluído (Done)

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
