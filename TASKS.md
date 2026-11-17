<!-- jrc-operational-init:v1 -->
# Backlog operacional — JRC Conversas LAB2 — Grupo JRC

## Em progresso (WIP)

- [ ] **CALL-CENTER-REVIEW-0-2-20261116:** Revisão funcional dos quinze cards e popups nativos, com matriz das 23 figuras em `docs/jrc_contact_center/stages_0_2_review_20261116.json`. Base 1834971c preservada. Incremento 6f9e06ae aprovado na CI 43952085591: 415 Rails, 178 Vue e 52 Chrome, build/probe aprovados. Validado: recarga transacional do perfil antes do GrantGuard, auditoria de capacidades CC e criação/revisão/negação do popup. Validada na CI 43956197984 / d648747d: autorização corporativa da escrita direta em perfis globais CC, 420 Rails, 178 Vue e 52 Chrome. Backend de elegibilidade aprovado no SHA 395cdfb2: 424 Rails e 178 Vue. CI 43962051059 ficou em 49/52 Chrome por corrida do filtro após salvar; correção da ordem do evento e dois testes Vue adicionais em revisão, mantendo 52/52 como gate obrigatório. Próximo checkpoint exige 52 Chrome, preservando os 44 existentes. Herança de equipe, revisão otimista e demais lacunas 0–2 continuam abertas em docs/adr/20261116-call-center-role-update-and-gaps.md.

- [ ] **CALL-CENTER-0-2-20261116:** Implementação isolada e correção dos gates, sem operações reais do PABX. Checkpoints e resultados em `docs/jrc_contact_center/lint_correction_checkpoint_20261116.json`; homologação operacional e contratos externos continuam separados dos testes sintéticos.

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

- [x] **BOOTSTRAP-01:** Identidade, stack, natureza Brownfield e fontes locais registradas.
- [x] **BOOTSTRAP-02:** Estrutura INIT, domínio, arquitetura e ADR organizados sem apagar conteúdo anterior.

## Como manter

Uma tarefa deve registrar problema, escopo, critério de aceite, evidência/arquivo e limite. Só mover para Concluído com a prova correspondente; não converter publicação de imagem em aceite operacional.


## Respostas rápidas e catálogo de aprovações — 2026-11-15 [WIP]

- Melhorar o atendimento nativo: acesso junto à assinatura, prévia contextual, um anexo e envio explicitamente confirmado, com intenção persistida para retry sem duplicação.
- Traduzir a Central em pt_BR e abrir configurações/edição em Dialog nativo; importar somente rascunhos inativos autorizados, com dry-run, escopo, diff, revisão de identidades e auditoria.
- Base funcional publicada preservada: `55da80eb1254aee54ee0f1fb5c42f2be46a98737`; main e ambientes existentes não são alterados.
- Evidências e limitações: `docs/adr/20261115-respostas-rapidas-catalogo-aprovacoes.md`. CI dirigida e homologação Chrome devem ser provadas sobre o SHA final. Sem publicação de imagem ou deploy nesta tarefa.

## CALL-CENTER-PART1-20261117 [WIP]

Continuidade da Parte 1 autorizada em 17/11, preservando fc0bf6ce e o workspace b77ffe55 com três arquivos pendentes intactos. Primeiro incremento: revisão esperada no editor nativo de perfis, contrato aditivo sem migration e sem concessões implícitas; decisão e testes em docs/adr/20261117-call-center-role-revision.md. Os sete Rails, cinco Vue e quatro Chrome adicionais ainda exigem execução no novo SHA. Preservar 52 Chrome e exigir 56 no gate. A main observada em 89779191 não foi integrada. Herança, elegibilidade, auditoria por unidade e etapas 3–8 permanecem abertas; nenhuma homologação externa, imagem, merge ou deploy nesta tarefa.

CI 44078910273/e217b41a preservada: 428 Rails, uma falha de preparação/escopo do contador de auditoria, Ruby sem novas infrações. Correção limitada ao novo spec: autenticação preparada antes do contador e contagem por perfil auditado. Produto não alterado. Artefato e hash registrados no ADR; Vue e 56 Chrome ainda não comprovados para este incremento.

- [x] **CC-ROLE-REVISION-20261117:** 80632726, CI 44080303193: 431 Rails, 185 Vue e 56 Chrome aprovados, com 52 capturas verificadas.
- [ ] **CC-CONFIG-AUDIT-20261117:** trilha transacional em armazenamento nativo, consulta/detalhe/exportação com escopos atuais e históricos, proteção da consulta genérica e revalidação de vínculos sob locks. Backend e 30 exemplos novos + dois de concorrência aguardam CI; frontend dedicado e homologação ampliada são o próximo incremento. Sem migration, grant, produção ou PABX real.

- WIP auditoria F14: backend 67a85761 com 467 Rails e 185 Vue aprovados; lint falhou com 15 infrações novas. Incremento corrige-as e prepara interface/detalhes/histórico/exportação e oito novos cenários Chrome reais. Homologação no novo SHA ainda pendente.

- Auditoria: corrigido filtro numérico identificado pelo Vue; espera do SHA-256 e fixture de leitor ajustadas. Próximo SHA exige 196 Vue e 64 Chrome, sem reaproveitar homologação inexistente.

- Auditoria administrativa: 196 Vue no b726ef8d; corrigidas sete infrações ESLint e uma Ruby, sem exclusões. Aguardando nova CI e 64 cenários Chrome reais.

- Corrigido o fechamento do popup de auditoria: footer explícito no chamador, sem alterar Dialog compartilhado. Nova regressão Vue; Chrome continua exigindo 64/64.

- Auditoria funcional 1877e145: 467 Rails, 197 Vue, 64 Chrome; 64 hashes de capturas verificados. Contraste de valores no popup escuro identificado e corrigido no próximo incremento, ainda sem aceite visual final.
- WIP revisão esperada em unidades/filas/vínculos: 26 exemplos Rails, 12 Vue e quatro Chrome preparados, sem migrations/grants. Gate do novo SHA exige 493 Rails/209 Vue/68 Chrome esperados. Herança/elegibilidade e etapas 3–8 permanecem abertas.

- Revisão de cadastros: corrigida preparação de microssegundos; cenário de conta passa a provar rejeição/rollback pelas FKs nativas já existentes, sem introduzir purga. 487 exemplos no primeiro gate com duas falhas de preparação/assunção; nova validação pendente.

- cfcae689: 493 Rails e 209 Vue aprovados. Removida somente linha em branco extra apontada pelo lint. Nova CI deve concluir build/68 Chrome e conferir contraste; etapas continuam abertas.

- Checkpoint 3c5054ac validado: 493 Rails, 209 Vue, 68 Chrome, 72 capturas/hash e contraste corrigido. Sem conclusão integral das etapas.
- Novo incremento: preservar custom_role_id omitido no PATCH nativo de agentes; seis cenários API e duas suítes nativas de agentes adicionados à CI. Explicit clear/fallback, herança e elegibilidade continuam pendentes.

- [ ] **CALL-CENTER-ROLE-FALLBACK-20261117:** Proteger retirada explícita/exclusão de perfil e promoção/criação nativa pela alçada efetiva. ADR em docs/adr/20261117-call-center-native-role-fallback.md; novos cenários preparados, validação nativa do próximo SHA pendente. Base a3355707 aprovada: 525 Rails, 209 Vue, 68 Chrome, 72 capturas verificadas. Herança/elegibilidade continuam abertas.
