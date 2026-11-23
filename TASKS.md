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

- [x] **CALL-CENTER-ROLE-FALLBACK-20261117:** Checkpoint 30fbf0b1, CI 44140644967: 546 Rails (540 + 6 concorrência), 209 Vue, 68 Chrome, zero falhas/pendências e 72 hashes de capturas conferidos. Preservado o sucesso parcial nativo de convites.
- [ ] **CALL-CENTER-ACCESS-INHERITANCE-20261117:** Configuração CC ligada a AccountUser/Team, novos usuários pendentes, união de fontes e bloqueios individuais prioritários. Backend/API, constraints e testes preparados; execução do novo SHA e interface ainda pendentes. Migration aditiva 20261117190000, sem alteração de migrations/SQLs históricos.

- [ ] **CALL-CENTER-ACCESS-UI-20261117:** Backend 548f66ac aprovou 590 Rails e 209 Vue; gate final bloqueado por duas infrações de lint, corrigidas sem supressão. Popup nativo de usuários/equipes com origens, revisão, filtros e paginação implementado; onze cenários Vue e doze Chrome adicionais preparados (80 totais). Validação do novo SHA pendente.

- [ ] **CALL-CENTER-FINAL-WRITE-AUTH-20261117:** Recarregar ator e escopo ao concluir a espera por locks de unidade/fila; duas novas provas HTTP reais de revogação, oito cenários concorrentes esperados. CI do próximo SHA obrigatória. A interface 8498ebf5 aprovou 590 Rails e 220 Vue, com lint Ruby limpo; ajustes de formatação frontend verificados por equivalência canônica, sem alterar conteúdo. Chrome 80 ainda pendente.

- [ ] **CALL-CENTER-DEPENDENCY-GRANTS-20261117:** Comparar chaves concedidas e efeitos por destinatário ao trocar perfil, editar equipe ou incluir membro. Seis regressões preparadas para capacidades latentes sem Visualizar. Sem novas capacidades. Base 8850187c: 592 Rails, 220 Vue e lint Ruby limpo; frontend e Chrome exigem nova execução após correção dos quatro diagnósticos.

- [ ] **CALL-CENTER-QUEUE-ELIGIBILITY-20261117:** Vínculo de fila exige elegibilidade explícita no servidor, sem confundir presença com autorização. Revogação entre abertura e salvamento conserva rascunho; desativação permanece permitida. Seis API, um Vue e quatro Chrome preparados (84 totais), validação do próximo SHA pendente. Dump migrado não substituiu schema histórico com divergências de outros módulos.

- [ ] **CALL-CENTER-GLOBAL-ACW-SCOPE-20261117:** Revalidar autorização dentro do lock da conta e impedir que escopo de unidade escreva política global. Três novos API, dois HTTP concorrentes com espera PostgreSQL comprovada, um Vue e extensão dos quatro cenários Chrome corporativos preparados. Sem valores de negócio novos; aguardam o próximo SHA.

- 48c2a9a4 / CI 44159560428: 598 Rails, 220 Vue, frontend e Ruby aprovados. Chrome: 68 anteriores aprovados e 12 novos com timeout por controles fora do viewport. Causa confirmada no relatório e capturas; contained aplicado no chamador, sem modificar Dialog compartilhado. Próximo SHA exige 84 Chrome completos.

- f8e603ae / CI 44166469596 bloqueou antes dos testes por CRLF nas cópias temporárias enviadas pela API Git. Correção restrita a LF; auxiliar externo passa a recusar CR antes do upload. Nenhum gate suprimido. Novo SHA deve executar todas as validações previstas.

- 7b9c7ff7 / CI 44167331338: 609 Rails (599 + 10 concorrentes), 222 Vue e migrations aprovados, zero falhas/pendências/erros externos. Quatro apontamentos de lint corrigidos: dois ternários, complexidade da validação de vínculo e Rails/exclude?. Chrome não executado nesse SHA; próximo gate continua exigindo 84 cenários.

- [ ] **CALL-CENTER-NATIVE-PABX-NAV-20261117:** Reusar ramal_settings / SipSettingsPage / PabxSettingsPanel com capability derivada do Super Admin administrativo. Dois API e dois Vue Router preparados, sem endpoints novos ou chamadas ao provedor. Conexão/CDR não equivale a publicação de filas/URA; homologação externa permanece pendente.

- 63a06c07 / CI 44169070593: 609 Rails, 222 Vue, migrations e ambos os lints aprovados. Chrome 80/84: os 12 casos de herança/usuário/conflito agora passaram. Quatro casos novos pararam em option disabled dentro de label. Playwright 1.59.1 segue label.control; corrigida associação acessível for/id, preservando toBeDisabled e todas as provas posteriores. Não reduzir a cobertura; próxima CI obrigatória.

- 7211bf19 / CI 44172675890: 611 Rails (601 + 10 concorrentes), 224 Vue, migrations e lint aprovados. Chrome 80/84; corrigida associação acessível da Fila sem alterar asserções. Oito novos casos preparados para navegação SIP/PABX nativa e negação por rota forçada, com perfil real e ator SuperAdmin exclusivamente sintético. Próximo gate exige 92 cenários; nenhuma operação externa.

- [ ] **CALL-CENTER-RECIPIENT-SCOPE-20261117:** Revalidar cobertura corporativa do destinatário ao gravar vínculo de fila, sem transferir GROUP do ator. Oito API, um HTTP concorrente com espera de lock, um Vue e extensão dos quatro Chrome preparados. Sem novas migrations, concessões reais ou operações externas; execução do próximo SHA pendente.

- [x] **CALL-CENTER-DD8ECE07-VALIDATION:** CI 44177839950 aprovada: 611 Rails, 224 Vue, 92 Chrome, zero falhas/pendências/erros e 100 hashes de capturas conferidos. Navegação SIP/PABX nativa e negação por rota forçada comprovadas sem escritas ou chamadas ao provedor. Cobertura corporativa do destinatário é incremento posterior ainda não validado. As 23 figuras permanecem parcialmente atendidas, com lacunas expressas.

- [ ] **CALL-CENTER-PERMISSION-ORIGINS-20261117:** Identificar perfil/equipes reais por capacidade herdada no detalhe autorizado e popup, sem alterar listagem, grants ou elegibilidade. Três Rails, um Vue e extensão dos quatro Chrome preparados; evidência nativa do próximo SHA obrigatória.

- f21f65ba / CI 44181012669: 620 Rails (609 + 11 concorrentes), 225 Vue, zero falhas/pendências/erros. Única infração nova: alinhamento de parâmetros no spec de cobertura, corrigido sem alterar asserções. Chrome bloqueado pelo lint nesse SHA; nova validação obrigatória inclui origens nominais preparadas.

- [ ] **CALL-CENTER-OPERATOR-FRESH-AUTH-20261117:** Revalidar estado local dentro dos locks de conta/vínculo; impedir que confirmação do PABX substitua elegibilidade/autorização atual. Cinco serviços e três HTTP concorrentes preparados; preservar idempotência, ACW e eventos de origem. Sem novo comando PABX. Nova CI obrigatória, sem atribuir evidência antiga ao incremento.

- 81c91a4c / CI 44182927869: 623 Rails (612 + 11 concorrentes), 226 Vue, zero falhas/pendências/erros. Uma complexidade ABC 27,75/26 na resposta de permissões foi corrigida extraindo a parte específica do usuário, sem mudar o contrato. Chrome não executado nesse SHA; novo gate inclui a proteção da disponibilidade preparada.

- 0fd871ce / CI 44185417916: 631 Rails (617 + 14 concorrentes), 226 Vue e migrations aprovados, zero falhas/pendências/erros. Corrigido um alinhamento na nova chamada do helper de corrida; nenhuma alteração funcional ou de asserção. Próximo SHA precisa concluir lint/build e os 92 Chrome, incluindo as novas provas de origem e cobertura corporativa.

- 042a0fd5 / CI 44187779842: 631 Rails, 226 Vue, migrations, lints e build aprovados. Seed do Chrome falhou aleatoriamente por senha sem dígito; diagnóstico/stack preservados por hash. Helper exclusivamente sintético garante classes obrigatórias sem reduzir entropia; uma regressão usa a validação real de User e reproduz a rejeição antiga. Nova CI obrigatória, sem enfraquecer senha, fixture ou cenários.

- a7c89170 / CI 44190646298: 632 Rails e 226 Vue aprovados, incluindo reprodução da senha inválida e correção pelo validador real. Alinhado o namespace do auxiliar ao domínio e caminho do spec, sem supressão. Auditoria identificou consumidor pendente: JSON autenticado/menu/rotas ainda não refletem fontes efetivas CC; tratar antes do próximo refinamento PABX.

- [x] **CC-AUTH-PROFILE-20261117:** Normalização somente das capacidades CC no perfil autenticado e navegação com a política efetiva, preservando as demais permissões. Nove casos HTTP, sete Vue e quatro Chrome adicionais preparados; validação do próximo SHA pendente. Base 7011dac7 aprovada: 632 Rails, 226 Vue, 92 Chrome e 108 capturas verificadas (CI 44194721033). ADR em docs/adr/20261117-call-center-authenticated-permissions.md.

- [x] **CC-NATIVE-PABX-TABS-20261117:** Reuso do formulário técnico existente em três abas, teclado, rascunho preservado, descarte explícito e bloqueio de gravação após falha no GET inicial. Fronteira por conta/usuário/perfil na rota nativa; entrada por autoridade CC efetiva preserva SuperAdmin/403 no backend. Onze testes Vue e quatro Chrome ampliados preparados; validação do próximo SHA pendente. Não implementa codec/URA/publicação/ACK do fornecedor.
- [x] **CC-OBSERVED-SUPERVISOR-20261117:** Cabeçalho nativo usa somente contagens locais do snapshot autorizado; remove atores/percentuais ilustrativos desse fluxo, distingue zero de leitura ausente e descarta dados em erro/troca de conta. Seis Vue e quatro Chrome ampliados preparados. Catálogo demonstrativo dos outros chamadores preservado. SLA/taxa oficial não inventados; validação do próximo SHA pendente.

Aceite incremental **cf040419 / CI 44203813534**: 641 Rails, 250 Vue, 96 Chrome, zero falhas/pendências/erros externos aos exemplos; lint, migrations, schema reload, assets e bootstrap aprovados. 120 capturas verificadas por SHA-256. Atualiza os estados preparados acima, sem declarar conclusão das 23 figuras ou homologação PABX.

- [ ] **CC-LOCAL-IVR-DRAFTS-20261117:** Núcleo local de esquema/grafo/simulação DTMF preparado, com reautorização por uso e referências nativas. Testes Rails ainda pendentes; persistência, revisões imutáveis, API e editor ainda não implementados. Proposta em docs/adr/20261117-call-center-local-ivr-drafts.md; nenhuma publicação PABX ou formato de fornecedor presumido.


- [x] **CC-LOCAL-IVR-ENGINE-20261117:** 7ab118ba / CI 44214303140: 686 Rails (45 do núcleo local), 250 Vue e 96 Chrome aprovados; 120 capturas verificadas por SHA-256. Grafo e simulação locais não publicam no PABX e ainda não constituem editor disponível ao usuário.
- [ ] **CC-LOCAL-IVR-LEDGER-20261117:** Preparados identidade/revisões imutáveis, migration aditiva exata, escopo histórico/atual e escrita transacional com revisão/UUID/auditoria nativa. Novos testes reais de SQL, ciclo de conta, upgrade e recarga ainda dependem da CI do próximo SHA. Sem API/editor novos; concorrência HTTP, paginação e homologação da URA permanecem pendentes. Nenhuma migration executada localmente ou em produção.

- Persistência 207bc523 / CI 44216984172 bloqueada: 14/15 exemplos no schema recarregado; preservada a rejeição nativa de exclusão de Account antes de Unit. Teste separado de ordem atômica, correções de lint sem supressão e migration atual somente formatada com SQL normalizado idêntico. Novo hash exato 67424d81…; revalidação obrigatória. API/editor ainda em preparação isolada, sem aceite.

- Persistência 868ecad5: 16/16 no schema recarregado; 729/730 principais. Corrigido somente matcher da mensagem decorada por Rails e quatro diagnósticos de lint; validação do autor extraída preservando SQL montado, novo hash exato eaeb4147658fd8e5c9bf25272c34bf5ed3113cf603856854906620f128d92e91. Próxima CI obrigatória.


- [x] **CC-LOCAL-IVR-LEDGER-VALIDATED-20261118:** 6a8b9c72 / CI 44220513593: 744 Rails únicos (730 + 14), 16 reexecuções do ledger após schema reload, 250 Vue, 96 Chrome e 120 capturas/hash. Migrations, lints, assets e bootstrap aprovados; artefato 14390294705 / 90e947cc7bdfa34bf80e08460f1ad1508cd10c22f838481394e95554794d79d6.
- [ ] **CC-LOCAL-IVR-API-EDITOR-20261118:** API/editor/importação/exportação/histórico/simulação preparados, reutilizando escopos e auditoria nativos. Três corridas HTTP reais e 12 Chrome adicionais preparados; gate exigirá 108/108 preservando os 96 anteriores. Execução nativa do próximo SHA pendente. Sem publicação PABX, Docker, produção ou concessões reais. Figuras/etapas permanecem abertas onde faltam critérios.

- API/editor 804413ec / CI 44230570088: 779 Rails únicos, 16 reexecuções do ledger, 290 Vue e frontend lint aprovados. Lint Ruby apontou 29 infrações; correções mínimas preparadas sem supressões e com criação validada em exemplo próprio. 108 Chrome continuam pendentes; próximo SHA exige nova validação integral do workflow setorial.

- [ ] **CC-SUPERVISOR-OBSERVATION-20261118:** Serialização de polling, descarte de unidades após erro e fronteira de ator/perfil preparados; quatro Vue e quatro novos Chrome nativos, em contas sintéticas exclusivas. Gate exigirá 112 cenários sem remover os 108. Validação do novo SHA pendente; ADR registrado.

- Chrome 4d06013f / CI 44233151968: 780 Rails únicos, 16 reexecuções, 290 Vue, lints/assets/bootstrap aprovados; 100/108 Chrome. Corrigidos labels DTMF/destinos e histórico substituído por replace; três Vue de regressão preparados. Mapa/importação/restauração e supervisor ampliam o próximo gate para 112 Chrome e 300 Vue esperados, ainda não aprovados.

- 31d57172 / CI 44236825274: 780 Rails únicos, 16 reexecuções e 300 Vue aprovados; três infrações Ruby remanescentes corrigidas sem supressão. Novo gate deve validar 112 Chrome, também descartando simulação quando o DTMF muda.

- 71841f76 / CI 44239525292: 780 Rails únicos, 16 reexecuções, 300 Vue e ambos os lints aprovados; Chrome 100/112. Corrigir observação da origem 5386/proxy5387 e esperar a transição CSS nativa de 250 ms, preservando critérios e registrando metadados sem conteúdo. Correção corporativa por equipe segue separada e não deve entrar neste checkpoint de QA.

- [ ] **CC-CURRENT-TEAM-CORPORATE-SOURCES-20261118:** Consulta compartilhada revalida membership e TeamScope nativos; fontes diretas preservadas. Reinclusão com fonte corporativa ativa exige GROUP administrativo, sem grants automáticos; remoções/no-op preservados. Escopos e memberships serializados no lock da conta e reautorizados após espera. Trinta e dois exemplos Rails novos, regressões de CRM/Aprovações e extensão dos quatro Chrome corporativos preparados; execução do novo SHA pendente. ADR registrado. Sem migration ou configuração de usuários reais.

- [x] **CC-LOCAL-IVR-API-EDITOR-ACCEPTANCE-20261118:** 417bb868 / CI 44243460813: 780 Rails únicos, 16 reexecuções do ledger após schema reload, 300 Vue e 112 Chrome, zero falhas/pendências/ignorados/flaky/erros externos. 140 hashes de capturas verificados; quatro capturas do editor revisadas visualmente em 1440/390 px, claro/escuro. Artefato 14401817176 / 7c94a08d69d4da3c1eb243c365afaa68c6e4969df6fa1bb09e08bb14befb6167. Editor/mapa locais não são publicação no PABX nem conclusão das 23 figuras. A correção corporativa posterior ainda exige CI própria.

- 77be76ae / CI 44246410692: 820 Rails principais, sete falhas após os HTTP esperados; 16 do ledger no schema recarregado aprovados. Corrigidas consultas de associação em memória nos testes e onze infrações de lint sem exclusões. Concluídos também seletores atuais de Aprovações/Operadora/link da Central, checagem da empresa atual da unidade e reautorização das observações após locks. Próximo gate exige os 47 exemplos novos preparados desde 417bb868, regressões nativas e os mesmos 112 Chrome. Não atribuir aprovação do SHA anterior ao incremento.

- 6c728416 / CI 44250259196: 845 Rails principais, uma falha de preparo ao tentar substituir emissor imutável; 16 do ledger na recarga aprovados. Preservada a proibição nativa e corrigidos os dois caminhos de specs sem exclusões, duplicações ou perda de histórico. Os 47 exemplos novos continuam exigindo o próximo gate, inclusive as seis corridas novas ainda não executadas. A atividade recente da Central é WIP separado.

- 6ab822a0 / CI 44253568507: 845/845 Rails principais, lint sem novas infrações, 22/23 concorrentes e 16/16 na recarga. Uma escrita de fila não aguardou o mutex Account esperado; corrigida a transação externa em ConfigurationWrite (duas linhas), preservando locks de registro/pais, reautorização e revisão. Diagnóstico de timeout sem conteúdo acrescentado; novo gate obrigatório. Atividade recente permanece WIP separado.


- **CC-CURRENT-SOURCE-ACCOUNT-LOCK-20261118:** 03de3a8f / CI 44255888203: 845 principais, 23 concorrentes e 16 reexecuções do ledger aprovados, zero novas infrações Ruby. Revogação durante espera real em Account negou a gravação na fila. Suíte adicional corporativa: 82/84, sem pendências/erros externos. Preparadas dependência explícita Poppler e prova independente de cada FK de conta, sem alterar produto/migrations nem retirar asserções. Exigir 85 corporativos e todos os gates no próximo SHA. Artefato 14407681498, SHA-256 41e7e059d1b26c17685b05cebb0637efe03eca4e1c33b55ac8645d1212a084cf. Vue/112 Chrome ainda pendentes; atividade recente fora deste checkpoint de QA.


- [x] **CC-CURRENT-TEAM-SOURCES-ACCEPTANCE-20261118:** ac85d6eb / CI 44260446025 aprovada: 845 principais + 23 concorrentes + 85 corporativos = 953 Rails únicos, mais 16 reexecuções de recarga; 300 Vue, 112 Chrome e bootstrap real dos 15 cards. Migrations/SQL/lints/assets aprovados; zero falhas/pendências/skips/flaky/erros externos. 144 capturas verificadas por hash. Artefato 14410325587, SHA-256 05357d9e829154191bce2b8c335513f1512c4e2795767ab45acfcdb93c898ca0. Não é conclusão integral das figuras/equipes/PABX.
- [ ] **CC-RECENT-ACTIVITY-LOCAL-IVR-NAVIGATION-20261118:** Atividade recente real, detalhe/histórico nativos e fronteira completa de acesso reaproveitada do Cadastro Mestre; 15 Vue novos preparados, sem mocks tratados como homologação. Corrigida descoberta da URA local para configurar sem publicar, preservando publicador e todas as restrições de backend; 5 Rails preparados. Doze cenários Chrome existentes ampliados, mantendo os 112. Nenhum resultado novo alegado; validar novo SHA, temas, celular e capturas antes do aceite. Não há novo endpoint, migration, cadastro paralelo ou comando ao fornecedor.

- [ ] **CC-EMPTY-PAGINATION-20261118:** Revisão de quatro capturas reais de ac85d6eb (equipe retirada, desktop/celular/claro/escuro) confirmou dados removidos, mas encontrou o rótulo incoerente Página 1 de 0 na lista de URA e no seletor. Corrigir o estado vazio sem inventar páginas/resultados nem mudar a autorização. Tratar depois do incremento de atividade/navegação; os registros e APIs já permanecem protegidos.

- **CC-RECENT-ACTIVITY-QA-20261118:** 699f2c7b / CI 44266430730: 850 principais + 23 concorrentes + 85 corporativos = 958 Rails únicos, 16 reexecuções na recarga e 315 Vue aprovados; zero novas infrações Ruby. Chrome 108/112: quatro falhas idênticas de seletor amplo que passou a encontrar dois headers, sem falha de backend/atividade/URA nesses cenários. Seletor agora exige exatamente o header direto da Central, preservando a asserção de CSS. Estados vazios da URA/seletor não exibem página 1 de 0 nem conservam páginas após erro; dois Vue novos e quatro Chrome existentes ampliados. Exigir CI própria antes do aceite. Artefato 14412328122 / 8640861f913b9cbd774e5409a7ed46212e99e70fbf0ee28c258d6ee24fac6b90. Auditoria global ACW permanece incremento separado ainda não testado.

- [ ] **CC-ACW-NATIVE-CONFIGURATION-AUDIT-20261118:** Auditoria da política global no mesmo lock/transação Account, somente campos efetivos, false preservado, no-op sem duplicação e rollback se falhar. Reuso do escopo/lista/detalhe/histórico nativos, incluindo proteção do endpoint genérico para cobertura restrita. Dez Rails e quatro Vue novos preparados; cinco testes de valores isolados antigos preservados e execução explícita no runner. Quatro Chrome existentes ampliados, sem reduzir os 112. Lint sem novos avisos. Exigir novo SHA/CI; não atribuir aceite do checkpoint anterior nem declarar revisão otimista global/precedência/23 figuras concluídas.

- **CC-RECENT-ACTIVITY-COMPLETE-SELECTOR-20261118:** 2c6971b8 / CI 44272597974: 958 Rails únicos + 16 reexecuções, 317 Vue, migrations/lints/assets/bootstrap aprovados. Chrome 108/112: quatro leituras evaluate ainda usavam o seletor amplo, linha 711. Ambas foram corrigidas para o mesmo header direto, mantendo as três verificações de CSS e os temas. A primeira correção foi incompleta; não declarar aceite desse SHA. Artefato 14415097723 / e8f84090258dfe6aac95dc95661746a934a22ff3b557ea58c6b7d4f72c445e73. Exigir o próximo gate completo, junto ao incremento separado de auditoria ACW. A preparação do Cliente 360º não entra neste checkpoint.

- **CC-ACW-AUDIT-NATIVE-QA-20261118:** 5dfa484c / CI 44278344086: 860 principais + 23 concorrentes + 85 corporativos = 968 Rails únicos e 16 reexecuções na recarga aprovados, incluindo os dez cenários novos de auditoria ACW; compatibilidade isolada legada aprovada e 321 Vue aprovados. Cinco infrações somente de indentação no novo spec bloquearam Chrome. Corrigidas sem mudar asserções ou configurar exclusões. Artefato 14416927294 / 8ae636ff667c272a948006d88770cd8cf2bcd39c43ed40a8d9212362fade8fb5. Exigir gate final do próximo SHA. A integração do Cliente 360º permanece WIP separado e fora deste checkpoint de QA.

- [ ] **CC-LINKED-NATIVE-CUSTOMER-MASTER-20261118:** Entrada do Contato 360º nativo só para vínculo explícito autorizado por ContactDirectory, sem concessão por telefone ou por direitos CC. Popup/campos/APIs nativos, atualização/fechamento com leitura nova sem perder rascunho e invalidação por navegação. Chamada selecionada não duplica demonstração. Cinco Rails, dezesseis Vue e quatro Chrome novos preparados (116 obrigatórios, mantendo os 112). Fixture nativo com operador agent sem administrar/configurar, isolamento por empresa/unidade/conta, retirada de permissão e cores/capturas reais. Ainda sem execução/homologação deste incremento; figura 21 e correlação legada permanecem parciais.

- [x] **CC-ACW-RECENT-EMPTY-STATES-ACCEPTANCE-20261118:** 0519ee64 / CI 44284092413 integralmente aprovada: 968 Rails únicos, 16 reexecuções na recarga, cinco isolados legados, 321 Vue, 112 Chrome, zero falhas/pendências/skips/flaky/erros externos e nenhum novo apontamento de lint. Artefato 14421025672 / 4b752c36e8642c4b1725941ab378ff7fccae4247eba653b6172e15f14fc645c2. 160 capturas verificadas por hash, oito efetivamente revisadas nos quatro projetos. Atividade/detalhe/histórico nativos, navegação URA local, auditoria ACW e estados vazios aprovados incrementalmente; revisão global/precedência ACW e as 23 figuras continuam abertas. Cliente 360º é incremento posterior e exige CI própria.

- **CC-LINKED-MASTER-QA-20261118:** 39121ea2 / CI 44292035221: 865 principais + 23 concorrentes + 85 corporativos = 973 Rails únicos e 16 reexecuções do ledger aprovados. Vue 336/337: o teste do diálogo compartilhado exigia um atributo HTML do stub que não corresponde ao contrato de prop; corrigido para conferir contactId diretamente no componente nativo, mantendo identidade e navegação. Duas infrações Ruby no seed sintético: guardas passam à lista explícita all? preservando as seis condições, e expressão aritmética ganha parênteses. Nenhuma regra desativada. Artefato 14423108526 / 2b216cb7f937daed74ee1343d74cc8b88b17dbc0a9ab4029c65b6c90f925807d. Assets/Chrome não executados; exigir novo gate 337 Vue e 116 Chrome. Revisão ACW é WIP posterior, excluído deste checkpoint.

- [ ] **CC-GLOBAL-ACW-EXPECTED-REVISION-20261118:** Revisão por conta e estado efetivo dentro do lock Account, comparação nativa 409/428, no-store e dois clientes com rascunho/comparação/confirmação. Dez Rails, uma corrida PostgreSQL real e doze Vue preparados; quatro Chrome em fragmento separado, mantendo os 116 anteriores quando aplicados. Zero novos avisos no lint direcionado. Não executado nativamente; manter separado do SHA 39121ea2. Omissão legada preservada e documentada, token não concede acesso. Precedência/formulários/PABX e as 23 figuras permanecem abertos.

- **CC-LINKED-MASTER-NATIVE-AND-VISUAL-QA-20261118:** 65ecefbe / CI 44295927524: 973 Rails únicos, 16 reexecuções, 337 Vue, 116 Chrome, lints/migrations/assets/bootstrap aprovados. Artefato 14424903824 / c65d38a4a3ead9d412fa8a3aa1987b63df1633f6cd50c0c8d16a8bd31d478c8d; 164 hashes conferidos. Quatro capturas revisadas mostram carregamento após salvar; não são aceite do layout final. QA agora espera o Cargo persistido, captura visão geral/formulário e traduz o status pelo mapa nativo, com um Vue adicional. Próximo incremento completo de revisão ACW adiciona dez Rails, uma corrida, doze Vue e quatro Chrome: exigir 350 Vue e 120 Chrome no novo SHA, sem reduzir os 116. Figuras/etapas continuam parciais.

- [x] **CC-GLOBAL-ACW-REVISION-NATIVE-20261118:** 7c4e408c / CI 44302097163 aprovado: 875 principais + 24 concorrentes + 85 corporativos = 984 Rails únicos; 16 reexecuções na recarga, 350 Vue e 120 Chrome, zero falhas/pendências/erros externos. Artefato 14428461439 / e6b1079a60e7f05cc3fd507404dabc876a6ff1ab1638cc05179f000f9f3bbfcd, 180 hashes PNG conferidos. Revisadas 13 imagens completas e sete recortes do topo/formulário; não todas as 180. Rascunho/409/comparação/revisão explícita e bloqueio global por escopo aprovados. Revisão visual encontrou transbordamento interno do cadastro móvel e título escuro sobre gradiente no tema claro; próximos ajustes e nova prova obrigatórios antes do aceite visual. Não conclui as 23 figuras.
- [ ] **CC-OPERATING-WRITE-AUTHORITY-20261118:** Casos e retornos reutilizam o lock Account e constroem autoridade atual após esperar; usuário ativo, feature, perfil, elegibilidade, equipe e cobertura continuam nativos. Caso e evento obrigatório passam a uma transação. Nove cenários API, dez corridas PostgreSQL e duas provas de rollback sem transação externa preparados; ainda não executados. Ajustes responsivos em fieldset/CompanyPicker e contraste de SettingsPage incluem geometria real de todos os controles e estado habilitado antes das capturas. Oito Vue nativos existentes do formulário entram na seleção da CI; sem repetir matriz 36. Vínculos parentais, idempotência de retornos e fluxo em página completa permanecem pendentes, sem simular conclusão.
- **CC-PABX-CONTRACT-DECISION-20261118:** Usuário confirma indisponibilidade do contrato técnico completo. Continuar interfaces, APIs internas, persistência, auditoria, simulações e testes independentes. Comandos, publicação, ACK/capacidades e versão aplicada continuam bloqueados por homologação externa; nenhum endpoint/resposta inventado ou operação real executada.
- **CC-CONCURRENT-MAIN-REVIEW-20261118:** Main avançou de d3d66232 para e6bd4cc9 por 6215fdeb e e6bd4cc9 (CI de LIVE/routing). Quatro caminhos revisados; sobreposição somente no diário TASKS. Nada incorporado nem alterado na main. Nova guarda do procedimento externo exige exatamente e6bd4cc9 antes/depois do checkpoint remoto; evolução concorrente preservada.

- **CC-OPERATING-AUTHORITY-QA-20261118:** 4c72e8d0 / CI 44309567421: 884 principais aprovados; concorrência 34/36, duas falhas nas expectativas de exceção do teste de rollback. O ambiente test.rb mantém show_exceptions=true: não alterar o tratamento global; verificar HTTP 500, que o save! obrigatório foi alcançado e as mesmas provas de estado revertido no banco sem transação externa. Duas infrações Ruby corrigidas na origem (array literal em laço e linha vazia), sem excluir regras. Artefato 14429268864 / e10973945769dbad2ab63e9901d405244a4394da4995ba4bf8fa6ef3e86766af. Gates corporativos/Vue/assets/Chrome não rodaram neste SHA; não reutilizar resultados antigos como próprios.
- [ ] **CC-OPERATING-ORIGIN-VISIBILITY-20261118:** Resolver chamada/caso/unidade explícitos pelos AccessScope existentes, derivar somente unidade/fila omitidas na criação a partir da chamada autorizada e verificar visibilidade nativa antes de confirmar a transação. Não amplia AccessScope nem cria grants. Preparados 17 cenários PostgreSQL em banco exclusivo sem fixtures transacionais e quatro Chrome de criação real, recarga/lista/histórico e origem negada (124 totais exigidos). Seed sintético possui filas e memberships explícitos; cobertura B continua negada independentemente da associação à fila. Contato/empresa diretos, reenvio idempotente de callback e ações em listas permanecem pendentes. Exigir nova CI antes do aceite.
- **CC-PAUSE-CATALOG-DECISION-20261118:** Aprovado pelo usuário: manter motivos livres e eventos legados; exigir catálogo somente depois de ativação explícita por conta. Não ativar em produção nem reinterpretar eventos antigos. Desbloqueia a implementação local futura do catálogo; não é funcionalidade implementada/testada nesta entrada.

- **CC-OPERATING-ORIGIN-QA-20261118:** d20607c1 / CI 44312599937: 884 principais e 52/53 concorrentes aprovados, incluindo os 17 cenários novos de origem e as duas provas concretas de rollback (HTTP 500, save! atingido e estado revertido). Resta expectativa de 401 no caso cuja unidade deixou a cobertura: a nova consulta nativa responde precisamente 404 para ocultar a unidade. Ajustado somente esse par recurso/fonte, conservando zero registros/eventos; não aceitar alternativamente ambos os códigos. Treze apontamentos de alinhamento em nove linhas de spec corrigidos sem mudar dados/asserções. Artefato 14431163646 / a5c40e360b94b2f88821f815667de221f49bdeeb19c5380a325f97b1532274a7. Corporativos/Vue/assets/Chrome ainda não executados neste SHA. Nova CI obrigatória; preparação do catálogo de pausas permanece separada e não aplicada.

- **CC-OPERATING-CHROME-DETECTORS-20261118:** acf83737 / CI 44315748862: 884 principais + 53 concorrentes + 85 corporativos = 1.022 Rails únicos, 16 reexecuções do ledger e 358 Vue aprovados; lint/migrations/assets/bootstrap15 aprovados. Chrome 116/124, oito falhas em dois detectores repetidos nos quatro projetos: título exato existe como h1 e h4; POST da UI usa o proxy Vite 5386, não a origem Rails 5387 usada pela consulta de controle. Traces confirmam quatro POSTs de casos com 201. Corrigir para uma única heading nível1 e origem5386/caminho completo da conta/métodoPOST; manter RGB branco, 201, persistência e negações. Artefato 14434658740 / db45ed3393350b28b2c5d3fa2dcac54e97bba444bee965397c89748df3c12c11 preservado e verificado. Quatro provas de geometria passaram; duas capturas móveis efetivamente revisadas mostram formulário contido nos dois temas, desktops têm bytes idênticos ao layout anteriormente revisado. Popups passarão a capturar o viewport real, conservando contenção. Gate completo ainda bloqueado; exigir nova CI de 124. Catálogo de pausas continua preparado separadamente, sem ativação, aplicação ou testes nativos.

- **CC-LAST-ELIGIBLE-DECISION-20261118:** Usuário aprovou confirmação explícita do gestor, com revisão e auditoria, ao retirar o último agente elegível de uma fila ativa. Não criar aprovação formal obrigatória nem publicar PABX. Implementação e testes ainda pendentes; reutilizar configurações, permissões, revisão e auditoria nativos, sem definir elegibilidade por presença online ou tratar provider_pending como disponibilidade real.


### Call Center — catálogo local de pausas, candidato de 18/11

- Compatibilidade aprovada: legado preservado; exigir catálogo somente após ativação explícita por conta.
- Implementados no candidato: popup nativo, HH:MM, revisão otimista, auditoria atômica, escopos restritivos por unidade/perfil, snapshot histórico e opções operacionais reautorizadas; sem PABX.
- Preparados testes nativos/Vue/Chrome próprios (132 Chrome obrigatórios, mantendo os 124 anteriores). Não aprovados antes da execução sobre o novo SHA.
- ADR: docs/adr/20261118-call-center-local-pause-catalog.md. Figuras 7/8 continuam parciais; regras avançadas e integração externa são pendências explícitas.
- Próximo incremento: último agente elegível — confirmação explícita do gestor, revisão vinculada ao estado e auditoria, sem aprovação formal obrigatória, conforme decisão do usuário.


### Call Center — revisão do último agente elegível, 18/11

- Decisão do usuário: confirmação do gestor com revisão e auditoria; sem aprovação formal obrigatória.
- Incremento temporário implementa proteção no endpoint nativo de participantes, recibo assinado e contextual, confirmação literal, auditoria atômica e popup com impacto. Não testado nativamente ainda.
- Preparados testes Rails/Vue e quatro Chrome adicionais (136 obrigatórios, mantendo os 132 anteriores). Não reusar a aprovação de 5e12db0a como aprovação deste código.
- ADR: docs/adr/20261118-call-center-manager-queue-withdrawal.md. Figura 12 permanece parcial, inclusive retirada indireta via equipe.
- Base anterior validada 5e12db0a: CI44326127674,1022 Rails únicos+16 recargas de schema,358Vue,124Chrome;184 capturas com hash verificado, seleção visual revisada. Catálogo4175aa7b ainda em diagnóstico nativo; não concluído.

- Revisão de consumidores do estado: novos dados de pausa são exclusivos da resposta autenticada do operador; não serão copiados para outro usuário no painel do supervisor. Preparados cinco cenários nativos de privacidade A/B, cobertura Group e perda de unidade.
- QA visual identificado em captura real5e: detalhe de perna connected agora preparado para usar o tradutor nativo existente, com estado da API preservado. Testes próprios ainda pendentes.


### Call Center — QA nativo d3e2179b

- CI44346971047:1093 Rails únicos (948 principais,60 concorrência,85 corporativos),16 recargas de schema e387Vue aprovados, sem falhas/pendências/erros externos.
- Artefato14447323510: SHA-256 f42b0fee0a8f1eedb1f57257984d14c20d1aca93ec572ce3be8ba29d9dbbec1d.
- Gates de assets/Chrome não executados: oito infrações Ruby restantes (complexidade/predicado de escopo e duas linhas físicas de alinhamento). Corrigidas no candidato seguinte, preservando comportamento e asserções; nova validação exigida.
- Matriz por figura reconciliada: catálogo básico, cobertura corporativa e decisão do gestor não permanecem descritos como ausentes/indefinidos. Funcionalidades avançadas e contrato externo continuam pendentes.


### Call Center — QA Chrome266fa5f8 e correção do procedimento

- CI44351000161:1093 Rails únicos,16 recargas,387Vue,lint sem novas infrações,assets/CSS reais ebootstrap15 aprovados. Chrome128/136; zero skips/flaky/erros externos. Não homologado integralmente.
- Artefato14453461748:SHA-256 d3d68fe95587a8c51cc8cbd90e4ab5dce912b0979098518523f42d2ec177e9f5,recuperado e verificado. Quatro capturas efetivamente revisadas: popup de pausas móvel escuro, revisão do gestor móvel clara e desktop escura, operador desktop claro. Hashes na matriz; não representam revisão manual de todas as capturas.
- Duas falhas de procedimento, repetidas nos quatro projetos: seletor amplo de status encontrou o banner pendente e o carregamento do novo catálogo; auditoria foi consultada sem abrir o detalhe nativo. Corrigir seleção pelo texto exato esperado e abrir a única linha do vínculo/operação, conferir resposta pelo ID do evento e depois o popup. Preservar todas as136 verificações, escritas reais, recarga, negações e auditoria. Nenhuma mudança funcional.
- Oito Chrome do catálogo passaram. Retirada do último agente comprovou409 sem gravação, confirmação literal,200/persistência e auditoriaAPI/negação antes do passo de detalhe ausente. Aceite final exige próxima CI no próprioSHA.
- Permanecem parciais as figuras7/8/12; retirada indireta por equipe e capacidades externas não estão homologadas. SemPABX,produção,merge,imagem ou deploy.


### Call Center — justificativa privada de pausa, próximo incremento

- Preparados checkbox opcional por motivo, tipagem/limite1.000, exigência só depois da ativação explícita já aprovada, metadata nativo e projeção privada reautorizada do próprio operador. Nenhuma alteração de banco/grants/PABX.
- Assinatura do catálogo e digest de recibos sem texto preservados; leitura não materializa o novo campo no formato histórico. Valores malformados não viram omissão permissiva.
- Preparados29 Rails novos (19serviço,9API,1concorrência),cinco cenários de privacidade ampliados e cincoVue (incluindo resposta tardia após perda de autoridade). Os oitoChrome existentes do catálogo ganharam persistência e negação da justificativa, preservando136 cenários. Ainda não executados no candidato.
- ADR:docs/adr/20261118-call-center-private-pause-justification.md. CI2bbcab4c em andamento não valida este incremento posterior. Exigir checkpoint e CI próprios após o resultado atual.


### Call Center — aceite do incremento2bbcab4c

- CI44359221023 aprovada no próprio SHA2bbcab4cac5c434b38c1bbea3beaaa44a1c1d738:1093 Rails únicos (948 principais,60 concorrência,85 corporativos),16 recargas de schema,387Vue e136Chrome; zero falhas,pendências,skips,flaky ou erros externos. Lint,migrations,assets/CSS reais ebootstrap15 aprovados.
- Artefato14455379412,32.678.968bytes,SHA-256 df5cbf358d4c4aa12b18dc40ee9d7bb6629358853c31eb168a56b9f74609296f. Download e200 hashes de capturas verificados.
- Quatro capturas do detalhe de auditoria efetivamente revisadas: desktops e celulares,claro/escuro,contidos e legíveis. O novo bloco do gestor aparece após rolagem interna; acrescentada rolagem explícita antes da captura seguinte. Sua confirmação,texto,persistência,negação eAPI passaram nesteSHA.
- Catálogo básico e retirada direta do último agente validados; figuras7/8/12 e conjunto23 não concluídos. Justificativa posterior preparada separadamente e sem evidência nativa herdada.


### Call Center — aviso de duração para o supervisor, próximo incremento

- Preparados sinal derivado do evento autorizado, duração formatada pelo helper nativo e aviso de limite excedido. Nenhum texto privado, catálogo, retorno automático ou ACK PABX. Definição histórica preservada; sem evidência retorna ausência.
- Oito Rails/API,doisVue e quatroChrome novos preparados, com contas próprias adicionais. Gate futuro exige140,preservando136 anteriores. Não executados nem aprovados no candidato.
- ADR:docs/adr/20261118-call-center-supervisor-pause-notice.md. Incremento independente preparado após85fca000; a CI desteSHA não o contém.


### Call Center — QA85fca000 e correção integral do lint

- CI44367512137:1122 Rails únicos (976 principais,61 concorrência,85 corporativos),16 recargas e392Vue aprovados,sem falhas/pendências/erros externos. Assets/Chrome não executados por seis apontamentos Ruby; não homologado integralmente.
- Artefato14461285550,SHA-256 8e777911b1547ea7a7e3a58a4a7f931a081235f8cd8205bfee6f212989f29119 recuperado e verificado.
- Corrigidas as seis causas: espaçamento após guarda,exclude? booleano literal,alinhamento de hash,classe exata no spec e dois exemplos divididos. Todas as verificações preservadas; mais dois exemplos nativos. Spec renomeado para agent_state_manager_pause_justification_spec.rb;19 exemplos preservados,hash antigo fixado no controle de rename e checkpoint85 intacto.
- O incremento de aviso ao supervisor foi concluído na cópia temporária com oitoRails/doisVue/quatroChrome adicionais; gate seguinte exige140 preservando136. Nenhuma mudança no PABX,ativação real,imagem ou deploy. NovaCI própria obrigatória antes do aceite.


### Call Center — cockpit com dados observados, próximo incremento

- Corrigidos na cópia temporária os rótulos das contagens nativas, ausência versus zero e referência ilustrativa do cockpit. Controles reais preservados; catálogo demonstrativo permanece nas suas rotas. TMA,satisfação e população diária não foram inventados.
- Contexto nativo de autenticação reaproveitado do supervisor para limpar dados e rejeitar respostas tardias após conta/usuário/perfil/permissões; atualização negada limpa observações e seleção anteriores. Nenhum comando PABX.
- SeteVue preparados e quatroChrome existentes ampliados,com comparação ao contexto real;140 obrigatórios preservados. Ainda não executados neste candidato. ADR:docs/adr/20261118-call-center-cockpit-observed-metrics.md.
- Correção adicional de fixture do aviso de pausa preparada: ao retirar a única membership visível à UnidadeA,a API corretamente omite o agente; depois a coberturaGroup sintética permite confirmar que a membership remanescente não revela aviso da fila retirada. Nenhuma permissão real alterada. A CI66 em andamento permanece imutável.


### Call Center — diagnóstico66fa4f9a

- CI44374575657:986 principais,985 aprovados e uma falha de fixture;16 recargas aprovadas. Concorrência,corporativos,Vue,assets eChrome não executados. Artefato14463100420,SHA-256 60e22bb6e8e7f5559ab08b741007aa23aead5258d8dcac08f95abdb56e38c3e7 verificado.
- AAPI corretamente omitiu o agente após sua última membership visível àUnidadeA ser retirada. Corrigido o teste para provar essa ausência e depois a visãoGroup sem aviso da fila sem participação atual. Mais asserções,sem aceitar resultados alternativos.
- Quatro convenções corrigidas: classe exata sem segundo argumento descritivo indevido,described_class,prefixo nativo do arquivo e deslocamentos de relógio sempre em blocos.
- Coletor opcional de sugestões tentouESLint sem dependências instaladas após a falhaRails. Condicionado ao pré-requisito real e registrado como não executado quando ausente. Gates obrigatórios preservados; YAML e seis combinações estáticas validadas.
- Cockpit observado e seteVue preparados separadamente; quatroChrome existentes ampliados,140 preservados. NovaCI própria antes do aceite. Sem imagem,deploy,produção ouPABX.


### Incremento ACW por motivo — 18/11/2026

- [x] Decisão confirmada: fila → equipe → geral; bloquear conflitos.
- [x] Motor/snapshots de voz validados em a16e8a49/CI44409349600, dentro do escopo incremental descrito no ADR.
- [x] Popup ACW, persistência, revisão, negação e auditoria:144/144Chrome em a16e8a49, incluindo140 anteriores.
- [ ] Concluir seleção intermediária/persistência do motivo e prévia do relógio, formulários vinculados e automações de encerramento conforme figura 9.
- [ ] Homologação externa PABX permanece bloqueada por contrato indisponível. Nenhuma etapa ou conjunto das 23 figuras é declarado concluído.


### ACW — revisão nativa517549ef

- CI44401274599:1.175 Rails distintos,16 recargas,415Vue,zero falhas/pendências/erros externos nesses gates e zero novas infrações Ruby. Bootstrap15 e assets novos aprovados.
- Chrome140/144; quatro falhas na consulta de histórico semresource_id. Corrigida aURL do teste com sua própria conta sintética; API permanece estrita. Causa confirmada nos quatro relatórios,sem excluir ou reduzir cenários.
- Revisão real de quatroPNG identificou baixo contraste do botãoAdicionar regra no escuro. Cor semântica explícita e asserção de cor computada acrescentadas. Justificativa própria e aviso de duração agora aparecem nas capturasmobile.
- Artefato14476916190 / ca15cf8ca34310540565ccfb1b22c1d6969031edecb9c05caa48f05e5bdb3719 recuperado e verificado. Aceite do novoSHA exige144/144; conjunto23 continua aberto. Roteamento preparado separadamente,sem validação nativa herdada.


### Roteamento local — incremento em preparação

- Reaproveitados RoutingRule, APIs e card Distribuição. Preparados lock/reautorização, revisão canônica, leitura paginada, auditoria atômica e filtro/histórico nativos. Sem cadastro paralelo, migration, grant ou publicação PABX.
- Popup local preparado com criação/edição, pesquisa, paginação/URL, revisão explícita de conflito e referências nativas. Preserva destino legado somente por fila, condições e janelas existentes. Registros publicados não podem ser alterados. Default voiceOnly das URAs preservado; canais nativos continuam aceitos somente no novo contexto de roteamento.
- Sete testes concorrentes/rollback adicionais e regressões HTTP/Vue preparados; quatro Chrome novos elevam o gate de144 para148, sem redução de cobertura. Ainda não executados ou homologados no novoSHA.
- Matriz corrigida para distinguir pausas/justificativa/aviso já validados em98c9d617 das lacunas de aprovação, chamada ativa e fornecedor. Figuras7/8/9/12 permanecem parciais. ADR:docs/adr/20261118-call-center-local-routing-drafts.md.


### Aceite ACW a16e8a49

- CI44409349600:1175 Rails distintos,16 recargas,415Vue,144Chrome,zero falhas/pendências/erros/novas infrações Ruby. DoisPNG efetivamente revisados e208 hashes verificados. Artefato14479548124 / eb514563dfeeefdc48c9a5c3231829986c8963467fe2eb488adc615876d35b3b.
- Cor real do botão:escuro715/claro96 nos quatro projetos; corrigidos contraste e consulta de histórico sem alterar o validador. Aceite restrito ao motor e popupACW. Relógio por seleção intermediária, formulários, automações e fornecedor continuam pendentes.
- Roteamento local posterior continua sem aceite nativo herdado; próximo gate exige148Chrome. Sem imagem,merge,deploy ou produção.


### Roteamento — QAadf4101b

- CI44418507109:1039 Rails principais,1038 aprovados,um fixture sem coberturaGroup inicial;16 recargas aprovadas. AAPI negou corretamente. Preparação corrigida comGroup sintético explícito antes das criações201 e substituição pelaUnidadeA antes das negativasB; nenhuma permissão relaxada. Mais uma regressão impede criação por administrador sem cobertura.
- Corrigidos22 apontamentos Ruby nos dois specs:alinhamento,setup aninhado simplificado,literal fora do loop eexists? nativo. Sem exclusões ou redução de expectativas.
- Artefato14482776042 / 42c22a2edbc5964ec399c9a9e91dddcc75d28d6019b79a4a7fcde5db857c269e verificado. Concorrência,Vue,assets,Chrome não executados nesseSHA. Próximo gate exige148Chrome e todos os critérios anteriores.


### ACW — contexto atual do atendimento, preparação incremental

- Preparados fingerprint nativo de usuário/vínculo/capacidades, descarte de respostas tardias, limpeza de projeção privada após falha de leitura/negação e proteção de início duplicado. Falha ordinária de gravação preserva rascunho; presença não invalida contexto.
- Dezesseis casos novos do hook, três do workspace e três do painel de voz, além dos existentes, preparados. Seus três arquivos passaram a constar explicitamente no gate Vue; nenhum caminho anterior retirado. Seis arquivos sob lint estático por diferença; avisos preexistentes permanecem sem supressão. Situação não verificada bloqueia novas chamadas, preservando rejeição e encerramento existentes.
- ADR:docs/adr/20261118-call-center-acw-current-authority.md. Preparação posterior àCI44423463990; não herda seu aceite. Relógio, persistência intermediária, formulários, automações e homologação visual do workspace completo permanecem pendentes.


### Roteamento — diagnóstico db20cf5c e menor correção

- CI44423463990:1196Rails distintos e16recargas aprovados;Rubylint sem novos apontamentos. Vue436/440; quatro falhas do stubDialog semclose. Corrigido para refletir open/close expostos pelo componente nativo e acrescentada asserção de fechamento por revogação. Nenhuma mudança na autorização nem no fluxo de produção.
- Artefato14483643068 / 93047f2b4d881c6bd2d6c2a89c0eb1455ee981f505845168864d6cc78ce2d29d verificado. Assets eChrome não executados; novo aceite ainda depende daCI do próximoSHA. Incremento ACW de privacidade preparado e identificado separadamente, sem reaproveitar evidência como se já estivesse testado.


### Equipe nativa — identidade de participantes, próximo incremento

- Preparada a mesma conversão de IDs já usada na validação nativa nas duas diferenças de conjuntos de inclusão/remoção. Impede que strings numéricas removam um participante que continua selecionado, preservando seu vínculo e as fontes herdadas. Guards Enterprise e regras de elegibilidade permanecem intactos.
- Seis regressões HTTP preparadas, incluindo herança atual, substituição mista, negação entre contas, CC desabilitado e remoção explícita. Ainda não executadas no candidato; não são prova de conclusão da retirada indireta do último agente.
- ADR:docs/adr/20261118-call-center-native-team-roster-identity.md. A CI090a1dac ativa não contém este incremento posterior. Sem alteração no cadastro de usuário,grants,migrations,PABX ou produção.


### Conferência visual da figura9 — título do popup

- A imagem8 do segundoWord usa configuração de pós-atendimento. A captura validada a16e8a49 ainda dizia Encerramentos—Novo registro, embora edite política existente. Preparado título específico Configurar regras de pós-atendimento, sem alterar campos/ações dos demais recursos ou criar registros paralelos.
- Uma regressãoVue e asserção do cabeçalho nos quatroChromeACW existentes preparadas; conjunto148 preservado. Formulários/obrigatoriedades/automações doWord continuam pendentes, sem controles decorativos anunciados como funcionais.


### Equipe — autenticação atual após espera por mutex

- Preparada recarga do User e verificação nativa de autenticação no guard Enterprise de participantes, após Accountlock e antes de qualquer gravação. Políticas nativas, guard de ativação e isolamento existentes preservados.
- Três testes concorrentes adicionais preparados, mudando confirmed_at apenas depois da autenticação/espera SQL real. O helper conserva seu comportamento anterior por padrão. Ainda não executados; exigem banco descartável explicitamente protegido e novoSHA.


### ACW — projeção auxiliar do operador, acompanhamento preparado

- Preparado descarte de AgentState auxiliar que chegue depois da consultaACW negada e ocultação desse fallback sem revalidação. UmVue adicional preparado; não usa dados privados do fetch anterior para reapresentar estado ou catálogo.
- Continuação posterior a090a1dac; não é aceite herdado nem homologação do workspace completo. Sem alterações no fluxo SIP externo.


### Aceite090a1dac e QA visual posterior

- CI44427479081 aprovada:1196Rails distintos,16recargas,528Vue,148Chrome,zero falhas/pendências/erros externos/novas infraçõesRuby. Bootstrap15 eCSS novos aprovados. Artefato14486734653/e1204b106d64441b3be63d7a6ea7f6bd5b1f03ed8efc6efd3fe93ee766831df5 recuperado e216 capturas verificadas porhash; quatroPNG efetivamente revisados.
- Escopo aceito: roteamento local com criação/edição,consulta,paginação,CAS,revisão,auditoria e negações; ACW atual com regressõesVue do workspace. Não é homologação visual do Hoya completo nemPABX.
- Revisão visual real preparou correção de Critério de roteamento sem mudar Tipo de unidade nas telas nativas, rótuloCC neutro Versão e espera por nomes reais da unidade/fila antes de capturar. QuatroVue adicionais e fortalecimento dos mesmos148Chrome,sem reduzir verificações anteriores. As correções de equipe e projeção auxiliar posteriores continuam exigindoCI própria.


### Gate d14f975a — correção dirigida

CI 44435975247: 1205 exemplos Rails distintos aprovados (1046 principais, 74 de concorrência e 85 corporativos), 16 recargas de schema separadas e 534/534 Vue. Um único novo RSpec/MatchArray bloqueou lint Ruby; assets/probe/148 Chrome não executaram. A correção usa contain_exactly com os mesmos dois IDs esperados, sem alterar a asserção funcional ou desativar regras. Nova CI deve comprovar o SHA corrigido. A prévia indireta de retirada por equipe permanece em preparação separada, sem uso nas APIs.


### Retirada indireta de equipe — em preparação

Prévia pura de composição de membros, serviço único de elegibilidade configurada, recibo explícito vinculado ao gestor e auditoria nativa por fila; reutilização nos três editores existentes. Quatorze arquivos frontend passaram lint dirigido sem erros/avisos novos. Rails/Vue/152Chrome (148 preservados +4novos) ainda precisam executar no novo SHA. Exclusão da entidade Team inteira e hierarquia não são declaradas cobertas. Escopo, testes e limites: docs/adr/20261118-call-center-indirect-team-withdrawal.md.


### ACW — proteção contra leitura antiga do relógio [preparado]

Atualização condicional do relógio sobre a linha ainda pendente e no mesmo escopo; preservar conclusão já gravada, limite atual, identidade e conteúdo manual. Sete cenários PostgreSQL preparados; aguardam execução própria. Não equivale à seleção intermediária do motivo, formulários ou automações por destino. Decisão aprovada de precedência preservada. Detalhes: docs/adr/20261119-call-center-acw-clock-stale-read.md.

- [ ] Call Center 19/11: revalidar CI apos cinco infracoes Ruby, recarga da associacao no teste de projecao e normalizacao de IDs do roster (dois cenarios HTTP). Preservar os 152 cenarios Chrome e validar separadamente a correcao do relogio ACW (sete cenarios nativos). Nenhum aceite integral ou operacao PABX inferida.

- [ ] Call Center 19/11: revalidar o relogio ACW apos falha da fixture (email derivado de display_name com espacos) e trocar update_all por with_lock/reload/update! sem remover validacoes. Preservar 1.102 exemplos principais aprovados, os 16 de schema e toda a cobertura futura de Vue/Chrome ainda bloqueada.

- [ ] Call Center 19/11: relogio validado nativamente em 490cd3a8 (sete casos;1.270 Rails distintos+16schema). Gate global ainda bloqueado: ajustar alinhamento da fixture e instalar Vuex sintetico em dois testes de navegacao PABX. Preservar verificacoes originais e exigir 152 Chrome antes de aceite visual.

- [ ] Call Center 19/11: c0e20792 aprovou 1.270 Rails distintos+16schema+573Vue, lint e build/bootstrap frescos. Chrome148/152: quatro falhas no seletor global do comprovante presente na previa e no dialogo. Restringir ao dialogo acessivel exato, exigir unicidade e visibilidade apos scroll; revalidar152 sem alterar produto ou timeouts.

- [ ] 2026-11-19: validar rascunhos ACW nativos, revisao manual, privacidade e dois novos fluxos Chrome (160 casos totais); overlay preparado, sem resultados atribuidos ao novo codigo. Ver ADR 20261119-call-center-pending-acw-draft.

- [x] 2026-11-19: checkpoint3b9aa6db com 1270Rails distintos +16schema,573Vue,152Chrome,232 capturas verificadas. Auditoria responsiva da retirada pela equipe e relógio comprovados; isto não fecha as23figuras.

- [ ] 2026-11-19: validar protecao de navegacao do rascunho ACW com Dialog/Router nativos, nove casos unitarios e quatro Chrome (164 totais). Preparado apos34f58253; a CI atual nao inclui este incremento.

- [x] 2026-11-19: rascunhos ACW ee689703 validados com1310Rails+16schema,619Vue,160Chrome e240capturas verificadas. Não encerra workspace Hoya completo, templates dinâmicos, automações ou PABX.

- [ ] 2026-11-19: proteger exclusão da entidade Team com revisão assinada própria, autoridade atual/lock, auditoria e FKs preservadas; página nativa mantém confirmação por nome. Preparados HTTP/SQLwait/Vue e168Chrome (164anteriores+4novos), sem aceite nativo ainda. Ver ADR de exclusão da equipe.

- [x] 2026-11-19: a8c6c78d validou navegação ACW e rótulos de conflito:1310Rails+16schema,631Vue,164Chrome,244capturas verificadas; diálogo conferido nos4projetos. Não equivale ao Hoya completo ou às23figuras.

- [ ] 2026-11-19: revalidar exclusão Team após e0b0feac:1168Rails+16schema aprovados;80/82concorrência (duas expectativas de normalização nativa corrigidas) e5infrações Ruby corrigidas sem alterar gates. Vue/Chrome168 ainda pendentes; artefato14510134218 preservado.


### Call Center — 19/11 — bootstrap de Equipes

- [x] acc72d8e:1335Rails distintos+16schema/661Vue, lint e assets novos aprovados; evidência14513102816 verificada.
- [x] Causa pelo source map: ciclo teams.routes → quatro formulários com router global → settings.routes:66.
- [ ] Validar a correção mínima de imports de rota assíncronos, o teste de inicialização e os168Chrome preservados. A homologação integral permanece em a8c6c78d/164Chrome até nova prova.
- [ ] Formulários ACW: seis arquivos de fundação e rascunho SQL separados, sem rotas expostas/migration executada; não incluídos no checkpoint desta correção.


### Call Center — 19/11 — fontes Ubuntu regionais efetivas

- [x] Preservada CI44493933103/79ef66b0:1335Rails+16schema/662Vue, lint aprovado; assets cancelados por45m,0Chrome executados. Artefato14517850671 verificado, sem homologação integral.
- [x] Causa comprovada: mirror+file regional EC2 escapou do normalizador e baixou porHTTP a31,4kB/s; metadata manteve assinaturas. Não afirmar HTTPS efetivo nessa execução.
- [x]24testes leves de fontes e Bash -n aprovados; normalizador exige mirror HTTPS efetivo nas quatro suites antes de gravar. Demais workflows e limite45m preservados.
- [ ] Provar a correção no Linux e todos os gates/168Chrome antes de homologar exclusão da equipe. Última homologação integral continua a8c6c78d.
- [ ]23arquivos de formulários ACW preparados, sem migração/rotas admitidas; revisão de tamanho JSONB, persistência/UI/bindings e respostas privadas ainda pendentes.


### Call Center — 19/11 — equipe inteira homologada e biblioteca ACW

- [x]7d55fe76/CI44505104067:1335Rails distintos+16recarga do schema,662Vue,168Chrome,0falhas/pendências/erros externos/flaky/skips.252capturas verificadas porSHA-256; quatro capturas novas inspecionadas.
- [x] Exclusão nativa de equipe: confirmação por nome,409/revisão explícita do gestor, exclusão200/reload404 e auditoria; permissões e escopos revalidados.
- [x] Corrigido o ciclo de imports das rotas Teams sem trocar componentes/metadados; bootstrap real15cards/0erros. Ubuntu HTTPS efetivo nas quatro suites,24testes e assinaturas APT preservados.
- [ ] Biblioteca interna de formulários ACW preparada com popup, versões, campos nativos, CAS, idempotência, histórico/auditoria e autorização global. Não declarar homologada antes da nova CI.
- [ ] Vínculo imutável regra→versão e respostas operacionais privadas ainda pendentes; nenhuma regra antiga ou snapshot é alterado por cadastrar um formulário.
- [ ] Contrato/ACK/publicação PABX externo pendente.23figuras e etapas0–2não concluídas.

### Biblioteca ACW — primeira execução nativa93ffea06

- [x] CI44514041346 preservada: migration inicial aplicada;38/39exemplos de recarga passaram,1falha de recibo na reexecução;48novas infrações Ruby registradas, sem exclusões de regras.
- [ ] Corrigir as infrações e comparar metadados fresh/reload/RSpec para localizar a divergência do recibo. A verificação permanece obrigatória.
- [ ] Rails principal, concorrência nova, Vue, assets e176Chrome ainda não executados nesta candidata;7d55fe76continua a última homologação integral.

### Call Center — tipos explícitos do CHECK e decisão de pausa

- [x]315ab97a/CI44518350072 isolou a divergência: somente casts do CHECKde status mudam após recarga;38/39exemplos,3infrações Ruby restantes. Artefato14527207589verificado.
- [x] Correção mínima preparada: tipos text explícitos; recibo completo continua obrigatório e teste de alteração real do CHECKfoi adicionado. Metadados não são RSpec;9testes do leitor externo passaram.
- [ ] Provar novamente a instalação/recarga/reexecução, todos os gates e176Chrome na candidata corrigida.
- [x] Decisão de negócio registrada: pausa começa somente após fim da chamada e conclusão do ACW.
- [ ] Proteção nativa adicional e5regressões preparadas; fila persistente de intenção e interface de pausa adiada ainda pendentes. Nenhum comando externo.

### Call Center — biblioteca ACW, correção final de lint

- [x] CI44523670408/304612a4: 1493 exemplos Rails distintos, mais 40 de recarga, e 753 Vue aprovados; zero falhas, pendências e erros externos nos relatórios. As cinco regressões da pausa após ACW passaram.
- [x] Instalação, schema reload e reexecução agora preservam o recibo completo; alteração real do CHECK continua sendo rejeitada.
- [x] Identificadas dez infrações de formatação Vue e quatro Ruby. Correções preservam SQL, verificações e comportamento: espaços/quebras, literal, linha vazia e nome explícito do leitor de metadados conforme a regra própria do projeto. Nenhuma configuração de lint alterada.
- [x] Conferência local direcionada: 18 arquivos frontend sem erros de lint (avisos permanecem); 23 testes da proteção de migrations aprovados. Não equivalem à execução nativa da nova candidata.
- [ ] Revalidar os gates e executar os 176 cenários Chrome; nenhum foi executado em304612a4 por falha de lint.
- [ ] Intenção persistente/interface de pausa adiada e vínculo regra→formulário/respostas privadas continuam pendentes. Etapas0–2 e23figuras permanecem abertas.

### Call Center — observação HTTP da biblioteca no Chrome

- [x] CI44528134759/882ccce6: 1493 Rails distintos +40 de schema,753Vue, lint Ruby/frontend e bootstrap15cards aprovados. Chrome:172casos aprovados,4timeouts do mesmo cenário, zero skips/flaky/erros externos. Artefato14533939230 verificado porSHA-256.
- [x] Causa comprovada no teste: aguardava POST/PATCH na origem Rails5387, mas o navegador chama o proxy Vite5388. As quatro capturas e snapshots mostram a versão salva/recarregada; os cenários pararam na observação HTTP.
- [x] Ajuste mínimo preparado: comparar a URL exata na origem do navegador, preservando método, caminho,20assertivas e duas esperas. Nenhuma alteração no fixture, API, timeout ou produto.
- [ ] Reexecutar os176casos completos e conferir todas as capturas/assertivas de histórico, persistência e escopo antes de homologar a biblioteca.
- [ ] O incremento independente de pausa adiada permanece fora deste checkpoint, sem validação nativa.

Correção da anotação de origem: os quatro arquivos api-origins do artefato882ccce6 comprovam POST201 em127.0.0.1:5386, com Rails direto em5387. A menção anterior a5388 era um erro de anotação, não uma porta usada pelo teste corrigido. A correção91174bbb deriva a origem da página e não contém essa porta fixa.

### Call Center — orçamento global da validação nativa

- [x] CI44536336065/91174bbb preservada:1493Rails distintos+40schema,753Vue,lint,assets e bootstrap15cards aprovados. Artefato14539179428 hashb98328216d8d1c750fc311c07e6a128c4547adaba250fe988087b4f1263c99d4.
- [x] Anotação do GitHub confirma o prazo global45m. Lint Ruby12m10s,assets1m05s;Chrome começou36m45s após o início. O log avançou nos projetos desktop; não há relatórioChrome final. Não contabilizar aprovação dos176casos.
- [x] Correção limitada do prazo global para65m para acomodar quatro projetos completos e variabilidade medida. Preservados os timeouts individuais, guardas de memória/disco, todas as verificações e os176casos. Nenhuma infraestrutura paga ou limite de cobrança alterado.
- [ ] Revalidar a candidata completa; etapas0–2 e23figuras continuam abertas. Pausa adiada é incremento independente, ainda fora deste checkpoint.

### Call Center — intenção privada de pausa após chamada e ACW

- [x] Regra aprovada registrada: preservar a chamada e aguardar a conclusão explícita de todo ACW; vencimento e rascunho não liberam pausa.
- [x] Incremento preparado: intenção própria persistente/imutável, revisão específica, confirmação e retirada explícitas, recibo idempotente, aplicação pelo gerenciador nativo e revalidação de permissões/fila/catálogo. Sem publicação/comando PABX ou ACK fictício.
- [x] Regressões preparadas para pedido atrasado após retirada, concorrência real, revogação, unidades/contas distintas, privacidade, integridade e recarga do schema. Respostas privadas não entram no payload do supervisor nem na lista genérica de auditoria.
- [x] Conferência local leve: dez arquivos frontend (incluindo o TypeScript do Chrome) formatados, nove arquivos JS/Vue sem erros de ESLint; três avisos de chaves dinâmicas preexistentes no Supervisor foram conferidos na base2caaec5d;28 testes da proteção de migrations passaram. Timestamp193000 não colide com os341 arquivos do SHA2caaec5d.
- [ ] Executar a própria CI da intenção persistente: Rails, concorrência, schema, Vue, lint, assets e184Chrome (os176 anteriores mais dois percursos em quatro projetos). Não tratar testes preparados como aprovados.
- [ ] Histórico operacional detalhado, vínculo regra→versão de formulário/respostas privadas e automações por destino continuam pendentes. Nenhuma etapa/figura integral ou integração PABX foi declarada concluída.

### Call Center — biblioteca ACW com evidência nativa2caaec5d

- [x] CI44546602975/2caaec5d:1493Rails distintos+40recarga do schema,753Vue e176Chrome (44por projeto),0falhas/pendências/erros externos/skips/flaky. Lint e assets novos passaram;bootstrap15cards. Artefato14542154788,hashdfe9409d5391eccd330ac4e388a246630b4c3cf49baa7dbaabf587d1c1a56141;264capturas verificadas.
- [x] Biblioteca: criação, edição, versões imutáveis, prévia não persistida, histórico, filtros/paginação/remoção de filtros e negações foram exercitados em APIs/PostgreSQL/Chrome reais. Nenhuma ativação operacional ou publicação PABX.
- [x] Revisão visual: lista desktop claro/escuro, histórico desktop e prévia mobile escura legíveis. Duas capturas mobile da lista mostram carregamento após Limpar filtros; não são prova da lista carregada. Mantidas como evidência real.
- [ ] Correção de QA preparada para aguardar GET200,20registros e ausência do carregamento antes da captura; preserva as176combinações e asserções anteriores. Conferir novamente no próximo SHA.
- [ ] Pausa adiada persistente e supervisor delimitado por fila preparados, ainda sem execução nativa. Vínculo regra→versão/respostas privadas e automações permanecem pendentes.23figuras e etapas completas não são declaradas concluídas.

### Call Center — primeira CI da pausa adiada56bf0670

- [x] CI44554654749 preservada:48exemplos de recarga,47aprovados e1falha;0pendências/erros externos. Artefato14545627143,hashbc2a2f4fb2aeaa9a3e3437e8da65e3f2937b0e94de6d6c2db6a43c6f2a691e50. Instalação inicial e proteção de migrations passaram. Core/Vue/Chrome não executados por esse bloqueio.
- [x] Causa exata: a fixture de ciclo de conta ainda continha AgentStateEvents; a FK nativa impede excluí-la. A correção preserva e testa esse bloqueio específico, além de um caso separado de cascade do novo ledger em identidade sintética sem histórico. Limpeza dos fixtures de concorrência atua somente nos próprios eventos do banco CI exclusivo.
- [x]21infrações Ruby identificadas. Correções preparadas de alinhamento, nome de contexto e métodos pequenos para a precedência de pendências, filtro de origem e SQL; nenhuma regra/validação suprimida.
- [x] Guarda SQL executada permanece idêntica após separar os trechos para lint:hash349b86d7bcf55f8c0490ab558da96771de033c7b91ce0fcb8c6f025f97a964fb. Novo hash de fonte da migration não publicada:d1c6f59eb20a060c7720c9c9ca1e9654090ac111d23789c0a5ca9a8baa4ff3a4. Migrations históricas, schema-base e SQLs anteriores intactos;28testes da proteção passaram novamente.
- [ ] Reexecutar no novo SHA: recarga/ciclo, Rails, concorrência, Vue, lint, assets e184Chrome. Nenhuma aprovação nativa da pausa persistente foi presumida.

### Call Center — recarga aprovada e contrato HTTP nativo4defb4f2

- [x] CI44558193422 preservada:49/49na recarga do schema,1417exemplos no core (1415aprovados e2falhas de expectativa),0pendências/erros externos. Artefato14545689996,hashb99241b144d94571ae6f99bfd2b0c43465ca59b8caf8aba6e2f87479363c69c5. Concorrência/Vue/Chrome não executados.
- [x] Causa confirmada das duas falhas: testes novos esperavam400,mas OperationError define422como contrato nativo. Produto não alterado; expectativas corrigidas para422 com código invalid_deferred_pause, ausência de pedidos e de auditorias de criação. Não aceitar erro genérico ou gravação parcial.
- [x] Restantes8infrações de formatação corrigidas em preparação: chamada Ruby, heredocs SQL com squish e recuo. SQL executado continua idêntico (349b86d7...); fonte da migration não publicada6dff254f8838085a16cd2eb6b4e516d477b8d15c6cba09873e7020ae792c9db2.28testes da proteção passaram.
- [x] Leitura do schema confirmou também a FK nativa de DailyFact. Acrescentada limpeza somente dos indicadores da própria fixture no banco de concorrência exclusivo; não é código de retenção/exclusão do produto.
- [ ] Revalidar no próprio SHA: todos os gates e184Chrome. Pausa persistente, formulário operacional e23figuras não declarados concluídos.

### Call Center — backend da pausa aprovado; mensagem de erro65079ad9

- [x] CI44561456418/65079ad9:1592Rails distintos+49schema,0falhas/pendências/erros externos;90exemplos de concorrência incluídos no total.99cenários novos de pausa comprovados em7arquivos, não adicionais aos1592. Nenhuma nova infração Ruby.
- [x] Artefato14549573982 verificado,hash9c8d5aec19e249c9a0a5eabe61dbc20226f15c13df12061b8ba78573208dd404. Vue:780/781,1falha;0pendências. Assets e184Chrome não executados.
- [x] Causa confirmada nos logs: alerta recebido JUSTIFICATION_ERROR mais COMMON.REFRESH; esperado somente JUSTIFICATION_ERROR. Correção mantém a assertiva antiga exata e move a ação de atualização para fora do role=alert. Mensagem e botão continuam disponíveis sem alterar permissões ou envios.
- [x] Teste de recuperação reforçado: após falha de observação, apenas clique explícito atualiza o estado; alerta não contém botão; nenhuma escrita/repetição automática. Lint local dos2arquivos frontend passou sem erros/avisos.
- [ ] Revalidar o SHA com a correção visual e executar184Chrome/inspeção de capturas reais. O backend aprovado não equivale à homologação visual ou à conclusão das23figuras.
- [ ] Próximo vínculo operacional de formulários em preparação separada, sem ativação/API publicada; não integra este checkpoint de mensagem.

### Call Center — pausa no Chrome e revisão de escopo no modo legado

- [x] CI44567268084/0c57e345:1592Rails distintos+49schema,781Vue,lint,assets e bootstrap15cards aprovados;0falhas/pendências/erros externos nesses relatórios. Artefato14555426924,hashfef33069ef2f668304c4a28fdb0529278b96a825c2ad695103b90f60dc2d42ea verificado.
- [x] Chrome:180/184aprovados; os8percursos de pausa (aplicar somente apósACW e resposta perdida/repetição/retirada) passaram nos quatro projetos. Quatro falhas do mesmo teste de Limpar filtros: browserEndpoint não declarado nessa função. Correção mantém URL exata,GET200,20linhas,carregamento ausente e todos os184cenários. Diagnóstico TypeScript limitado reproduziu a variável ausente e aprovou a declaração corrigida; não substitui Chrome.
- [x] Quatro capturas reais da pausa inspecionadas: desktop claro/escuro,390px claro/escuro, incluindo confirmação incerta e retirada. API/PG sintéticos reais; nenhuma confirmaçãoPABX fictícia. A lista mobile carregada continua pendente da nova captura.
- [x] Revisão identificou risco adicional: catálogo compatível não obrigatório,sem fila/justificativa, mudança de unidade podia degradar motivo restrito para legado livre sem mudar a revisão global. Preparada impressão interna que vincula revisão e tipo de seleção, usada pela projeção privada e aplicação; não altera os hashes nativos nem SQL/história.
- [ ] Executar quatro novas regressões nativas: perda e ganho de motivo restrito, bloqueio ao completarACW e preservação do motivo livre realmente legado. Revalidar todos os gates e184Chrome no novoSHA. Não declarar aceite integral enquanto isso.
- [ ] Cinco arquivos de vínculo operacional de formulário permanecem em preparação separada, fora deste checkpoint e sem teste nativo/ativação. Histórico operacional detalhado, automações e dependênciasPABX continuam registrados.

### Call Center — pausa adiada com evidência completa0ddd5a4b

- [x] CI44576255569/0ddd5a4bb8702537dfdec2c6b7c34e554f491007:1596Rails distintos+49schema,781Vue,184Chrome(46porprojeto),0falhas/pendências/erros externos/skips/flaky. Lint,assets e bootstrap15cards aprovados. Os103casos da intenção persistente estão incluídos nos1596, não são uma soma adicional.
- [x] Artefato14561440082:40850127bytes,hash149bb9b20d40c6891c69159411c991e465d3deb2a6486614c4bbd0f52b8382ec.276capturas conferidas pelo manifesto nativo. Primeira transferência falhou no hash; uma nova leitura do mesmo arquivo conferiu tamanho,digest eCRC. Verificador original passou sem alterações; nenhum job repetido.
- [x] Seis capturas inspecionadas: biblioteca mobile claro/escuro agora carregada, pausa aplicada desktop escuro/mobile claro, confirmação incerta mobile escura e retirada desktop claro. Toda a regra de pausa aguarda chamada encerrada e conclusão explícita doACW; rascunho/tempo vencido não iniciam pausa.
- [x] Perda/ganho de seleção no catálogo compatível sem fila/justificativa agora exige revisão e redige os detalhes privados; motivo realmente legado permanece compatível. As quatro regressões adicionais passaram no backend nativo.
- [x] Checkoutb77ffe55 e os três hashes pendentes conferidos e preservados. Sem imagemDocker,GHCR,merge,deploy ou comandoPABX.0ddd5a4b é o checkpoint funcional validado.
- [ ] Continuidade iniciada em preparação separada: vínculo de formulário, versões e respostas privadas nativas. Ainda sem execução nativa/ativação; nova migration preparada fora dos arquivos admitidos exige revisão, testes e gate próprios. História operacional detalhada e demais requisitosWord continuam abertos;23figuras não concluídas.


### 19/11 — Formulários operacionais de ACW (preparado, validação pendente)

- Biblioteca existente vinculada por regra/versão exata; campos obrigatórios adicionais e configuração atômica.
- Estado privado subordinado à qualificação, origem histórica, rascunho tipado, HMAC e bloqueio de conclusão incompleta.
- Quinta migration 203000 revisada e pinada; quatro anteriores preservadas.
- Testes Rails/PG, concorrência, Vue e 192 Chrome preparados; ainda não registrar como aprovados.
- Legado e pausa após chamada + conclusão explícita preservados. Contrato PABX, automações e aceite integral das 23 figuras continuam abertos.

### 19/11 — Formulários operacionais: backend aprovado, correção de apresentação

- CI44607985893/SHA35a8fff3:1686Rails distintos (1509core,92concorrência,85corporativo),66reexecuções de recarga do schema e817Vue; zero falhas/pendências/erros externos. Compatibilidade legada,guards de storage/migrations e lint Ruby sem novas infrações aprovados.
- Artefato14572449611 verificado por SHA-256:90bbc255fd9362bb581d4a1d62cb7e18e5fba105b83115f4937565268fd44cd8. Esse resultado não comprova assets ou Chrome: o lint frontend interrompeu a execução antes dessas etapas.
- Correção pontual: checkbox com rótulo associado explicitamente e formatação válida; nenhuma regra desativada. Checagem estática somente leitura:18arquivos,zero erros.
- Corrigido indicador de rascunho salvo que tratava objeto vazio como conteúdo. Cinco cenários novos distinguem ausência de conteúdo de respostas persistidas false/zero;192Chrome mantidos, com conferência do indicador antes/depois de salvar.
- Pendente: validar o novo SHA,compilar assets e homologar192Chrome nos quatro projetos. Formulários operacionais e23figuras ainda não declarados concluídos. Sem produção,PABX,imagem,merge ou deploy.

### 19/11 — Vínculo operacional de formulários aprovado2a0cde0c

- CI44614231287/SHA2a0cde0c9ee012cd807b1cbca6cffd508898e47a:1686Rails distintos,66reexecuções schema,822Vue,192Chrome(48em cada projeto),zero falhas,pendências,skips ouflaky. Lints,assets e bootstrap15cards aprovados.
- Artefato14575213612:41800945bytes,SHA-2565bae1770a1aec3823ef586b9a7a7f49d2f8fe68c94ad7c4357d6a136f0ca53a3.284capturas verificadas por hash;8novas inspecionadas individualmente: vínculo/obrigatoriedade e formulário/rascunho,desktop1440 ecelular390,claro/escuro.
- Comprovados versão exata imutável,precedência nativa,false/zero,persistência,negação por conta/unidade/autoridade,conflitos e pausa aguardando conclusão explícita. Metadados privados não expostos aos demais agentes/gestores. Nenhum comando ou confirmaçãoPABX inventado.
- Etapas/23figuras permanecem abertas. Próximo incremento:histórico operacional de estados/pausas com consulta nativa e escopo atual,sem duplicar auditoria de configuração.

### 19/11 — Histórico operacional de estados e pausas (em validação)

- Consulta nova somente leitura reutiliza AgentStateEvent,AccessScope,OrganizationalScope e autoridade control? nativa revalidada em transação;sem cadastro paralelo ou grants.
- Popup no catálogo existente,em português,com período de até31dias,fuso da conta,nome do agente,estado,fila,paginação20/100 e remoção de filtros. Histórico de configuração permanece separado e preservado.
- Projeção mínima sem razões livres,justificativas,formulários,comandos,identificadores externos ou metadados brutos. Eventos sem fila são negados à cobertura corporativa restrita;vínculos de outra conta são excluídos. Não inventa unidade histórica ausente nem confirmação atualPABX.
- Escopo de filas é o atual;datas/nome do usuário não constituem um cadastro histórico de unidade ou nome. Estado em aberto usa a observação da consulta para duração e não é encerrado por ela.
- Testes nativos de filtros,paginação,timezone,negação e isolamento preparados;Vue inclui trocas de conta/perfil,respostas tardias,erro e tentativa explícita. Um percurso Chrome completo acrescentado aos192anteriores:196esperados.
- Checagem estática dos7arquivos frontend:zero erros/avisos. Aprovação Rails/Vue/Chrome ainda pendente;nenhuma figura integral ou homologação externa declarada.

### 19/11 — Histórico: correção dos contratos reais da primeira rodada

- CI44630413378/c81911c7:1530exemplos core,1525aprovados e5falhas;66/66schema;sem pendências/erros externos.16infraçõesRuby novas. Artefato14581358183/SHA-256052a5e51581da80e8ac5d9c47ae75fa63d10937df5f361f1ce151d7256788c2f verificado.
- Causas confirmadas:3expectativas de negação devem respeitar401nativo;FKcomposta rejeita vínculo estrangeiro criado pelo teste;travel_to remove microssegundos e altera floor da duração. Correções mantêm assertivas exatas,usam savepoints para provar ambas asFKs e repetem o padrão ceil já utilizado nos testes nativos de estado.
- Route nova movida a escopo aditivo pequeno,sem expandir bloco existente além do limite;Array.new e alinhamentoRuby corrigidos. Nenhuma exclusão de lint,SQL ou permissão alterada.
- Matriz reconciliada com evidência2a0cde0c para figuras7/8/9/12,preservando os campos anteriores em snapshot histórico. Integração completa das23figuras segue aberta.
- Próximo gate precisa aprovar backend,Vue,lint,assets e196Chrome;sem reuso de resultados anteriores como homologação do histórico.

### 19/11 — Histórico:backend1707aprovado;teste de tradução e Hoya

- CI44632748080/33fb5eaf:1707Rails distintos(1530core,92concorrência,85corporativo),66reexecuções schema e nenhuma nova infraçãoRuby;zero falhas/pendências/erros externos no backend. Artefato14584991222/SHA-256ab6ab9d3464177927434d289c5a02480e99658280fd5501f39c1878d51fee088 verificado.
- Vue835/836:uma falha confirmada no stub de tradução do teste novo,que omitira parâmetros de interpolação. Correção mantém chave e valores,sem remover assertivas de agente/estado/fuso. Produto não alterado por essa correção;Chrome eassets ainda não executados nessa rodada.
- Novo percurso preparado com o componente HoyaInboxWorkspace inteiro,Pinia/Vuex com identidade nativa e APIsRails locais reais:formulário versionado,obrigatoriedade,false/zero,salvar,recarregar,concluir e confirmar persistência. Softphone não inicializado,HTTP externo bloqueado antes da rede,nenhum comando aoPABX.
- Quatro percursos novos(um por projeto)acrescentados aos196anteriores:200Chrome obrigatórios. Não equivale à aplicação implantada inteira,conversaWhatsApp real ou homologaçãoSIP/PABX. A nova compilação permanece exclusiva no runner isolado.
- Lint estático dos quatro arquivos frontend preparados:zero erros/avisos. Aguardar o próximo SHA nativo antes de declarar o histórico ou o Hoya homologados.23figuras seguem abertas.

### 19/11 — Chrome real do histórico e Hoya:192/200,correções finais necessárias

- CI44636656581/3456fbe7:1707Rails distintos,66schema,836Vue,lints,assets reais ebootstrap15cards aprovados. Chrome192/200;8falhas,0skips/flaky/erros externos. As192identidades aprovadas correspondem exatamente ao conjunto2a0cde0c,reexecutado no novoSHA.
- Causas confirmadas em4projetos cada:aguardava401na descoberta administrativa que corretamente permite200comcontrol=false;leitura final doHoya semcall_session_id retornou422após o fluxo efetivamente completar. Corrigidos somente os contratos de teste;histórico protegido continua401 e fila externa404.
- Artefato14586662951,43535321bytes,SHA-256e339cfe18499e9ebebc172ac0a6242ff579bdc1b1e08cf13c5b20aabfcad6430,CRCconferido.8capturas novas inspecionadas individualmente. Não são homologação integral porque os testes falharam.
- Mobile:histórico ocupava quase todo o popup com filtros;agora recolhíveis comHTMLnativo,sem retirar campos e com abertura/fechamento explícitos noChrome. FixtureHoya usa altura finitah-screen,já compilada peloCSSnativo,sem alterarTailwindglobal ou mascarar CSSdo produto.
-200cenários mantidos. Revalidar o próprio novoSHA e os quatro temas/tamanhos;nenhum gate reduzido,nenhumDocker/PABXreal,mergeoudeploy.23figuras continuam abertas.


### 19/11 — Catálogo administrativo de encerramentos preparado

- Reutiliza a política/API/auditoria nativa de ACW;sem nova migration,grant,cadastro paralelo ou ativação externa.
- Nome,código,categoria,descrição,ordem,status,versão,CAS,desativação sem apagar histórico e opções nomeadas no editor de regras.
- Popup com filtros,paginação10/100,erro visível,conflito revisado,descarte explícito e perda de autoridade sem retenção de dados.
- Registros v1 e versões/respostas do atendimento já capturado são preservados. Ausência do catálogo mantém exatamente a revisão legada.
- Testes Rails/Vue e um novo percurso Chrome por projeto preparados:204Chrome exigidos,sem retirar os200anteriores.
- Validação do novo incremento ainda pendente. Obrigatoriedade por fila,labels operacionais congelados e automações por destino permanecem pendentes das figuras9/10.


### 19/11 — Histórico/Hoya:200Chrome aprovados;manifesto final bloqueado por indentação

- CI44644260127/b11f3131:1707Rails distintos,66reexecuções schema,836Vue,200Chrome(50porprojeto),lints,assets ebootstrap15cards aprovados. Zero falhas,pendências,skips,flaky ou erros externos nos relatórios desses testes.
- O job final falhou depois de200passed:IndentationError na asserção de contagem do Python que gera o manifesto. O manifesto produtor ficou ausente;CI NÃO aprovada integralmente. Não criar manifesto fictício nem substituir o resultado agregado por sucesso.
- ZIP14591250055,42606531bytes,SHA-256f3af69eb72e740747f0626b4abb17afcdbf5e1fe9bf57418288d80c128843c3a eCRC verificados.292PNGs noZIP;8capturas de histórico/Hoya inspecionadas nos4projetos,com hashes derivados do arquivo íntegro. Não equivalem a um manifesto de aceite produzido pelo runner.
- Correção mínima de recuo preserva todas as assertivas. Novo compilador estático dos2blocos Python,sem executá-los,tem7regressões aprovadas incluindo a reprodução exata de unexpectedindent. Executa antes das dependências pesadas para evitar repetição dessa falha.
- Próximo checkpoint inclui o catálogo administrativo e exige204Chrome,os testes nativos afetados e manifesto íntegro;nenhumgate é dispensado.23figuras permanecem abertas.


### 19/11 — Catálogo:primeira rodada nativa e correção dos contratos de entrada

- CI44651345480/f89707d5:1566core,4falhas;66/66schema,0pendências/erros externos.8novas infrações de layout Ruby. Frontend/Chrome não executados. Artefato14590544888/SHA-25669fcfa73b033030441c18d57e0a7bc849c5aa345e5b8aaa3995cdc9dad29841a verificado;coletor estrito recusou uma dupla de descrições lógicas iguais,sem descartar registros.
- Duas preparações de teste enviavam revisão antiga e um hash usava ordem bruta de JSONB. Agora usa token HTTP real e vetor literal v1 de seis campos. Snapshot/formulários/respostas já iniciados continuam conferidos integralmente.
- Falha real:[null] era normalizado pelo Rails para[]antes do domínio. O novo DTO lê somente esse campo do JSON comActiveSupport,limite1MiB,sem alterar parsing global,autoridade ou mass assignment. Null/false e combinações com entrada válida devem continuar rejeitados atomicamente.
- Nomes dos casos agora distinguem os valores;verificador de identidades permanece estrito. Mais3cenários backend sobre null misto e substituto por query.204Chrome mantidos;nenhum teste desabilitado.
- Regra de negócio aprovada:filas selecionadas exigem motivo cadastrado,e chamadas iniciadas preservam a política anterior. Implementação operacional desse complemento ainda pendente,sem ativação em contas reais.

- [ ] **CC-ENDING-REASON-LINT-20261120:** CI `44654884502` aprovou 1.746 exemplos Rails distintos, 66 reexecuções de recarga de schema e 856 testes Vue. Uma infração Style/StringConcatenation em um teste bloqueou assets/Chrome. Correção apenas de interpolação; os 204 cenários Chrome continuam obrigatórios. A obrigatoriedade por fila está aprovada, mas sua implementação em andamento não integra este checkpoint.

- [ ] **CC-ENDING-REQUIRED-QUEUES-20261120:** Implementar a decisão aprovada da figura 9 com versão imutável por chamada, seleção e confirmação de filas, exigência nativa e SQL, contexto próprio no Hoya e preservação de chamadas antigas. ADR `docs/adr/call-center-ending-reason-call-versions-20261120.md`. Novo incremento preparado; testes nativos e 208 cenários Chrome ainda pendentes. Sem ativação real ou comandos PABX.

### 20/11 — Obrigatoriedade por fila: preparação nativa corrigida

- Catálogo administrativo anterior efetivamente validado no SHA a0cd67f4/CI44659483934:1.746Rails distintos,66reexecuções schema,856Vue,204Chrome e296capturas com hashes verificados. Essa evidência não cobre a nova exigência por fila.
- CI44667891699/267c8d17:instalação e recarga de schema executadas;13dos79exemplos de recarga falharam antes das assertivas porque o fixture chamou Current.set, inexistente no módulo nativo.66casos anteriores passaram. Cinco infrações Ruby restantes;core/Vue/Chrome não executados.
- Correção usa Current.user com restauração em ensure somente no fixture/seed sintéticos. Preserva o reconciliador nativo de eventos atrasados separando horário operacional corrigível e captura imutável da política. Regressões adicionais de SQL/upgrade preparadas,sem alteração das cinco migrations anteriores.
-36testes estáticos do gate aprovados:seis migrations exatas,dois SQLs com hashes independentes,ausência/mutação/retroatividade rejeitadas. Exigir nova CI nativa,208Chrome e manifesto íntegro no próprio SHA;nenhumPABXreal,deployoupublicação.

- CI44670523987/c6447b02:81/81recarga aprovados,inclusive upgrade populado,idempotência,cabeçalho inválido e histórico. Core1619exemplos,4falhas,0pendências/erros externos;as quatro compartilham encerramento sintético10segundos no futuro,rejeitado pelo CHECKcronológico nativo. Corrigir somente a linha do tempo do fixture,não oCHECK.5novosachadosRuby;os5anteriores foram resolvidos. Vue/Chrome não executados. ZIP14599529621/SHA-25613eaa6e719342d8681c98e11e7df549ff53b54f01805d623258c0524af878750 preservado.

###20/11 — Encerramentos nativos aprovados; autenticação atual de participantes preparada

- CI44672804599/722bee5a:1.798Rails distintos(1.619core,94concorrência,85corporativos),81reexecuções schema e869Vue aprovados,com0falhas/pendências/erros externos.4infrações somente de convençãoRSpec no teste novo bloquearam assets/Chrome. Corrigidas por renomeação revisada e described_class;as7assertivas e o histórico foram preservados. Artefato14601452894/SHA-256bc0bfae765abe6344d73fd74c1b923568882c2779f2e0aa385671188ca0eba9e verificado. Não declarar CI integralmente aprovada.
- Nova lacuna concreta das figuras3/12:um grant elegível remanescente podia permitir vínculo de usuário não autenticável. API/opções agora revalidam o User nativo;desativação segura continua disponível,sem mudar grants. O próprio ator é recarregado após espera dos locks.4testes HTTP,3corridas PostgreSQL,1Vue e4novosChrome preparados;212Chrome exigidos,sem retirar os208anteriores. ADR20261120-call-center-current-membership-authentication.md. Sem execução nativa ainda para esse complemento.

### 20/11 — Autenticação do gestor após lock de permissões

- Correção independente preparada em `AccessAuthorization#authorize!`: recarregar o User e exigir autenticação ativa antes das regras nativas de concessão.
- Um teste de objeto desatualizado e dois testes PostgreSQL concorrentes preparados, cobrindo autorizações individuais e de equipe sem alterar grants.
- ADR: `docs/adr/20261120-call-center-access-actor-authentication.md`. Este complemento é preparado neste incremento e ainda precisa de testes nativos próprios; não integra a CI de `76c37bbe`.

- CI `44676273362` / `76c37bbe`: 1.805 Rails distintos (1.623 core, 97 concorrência, 85 corporativos), 81 reexecuções de schema e 870 Vue aprovados, com zero falhas, pendências ou erros externos. Restaram quatro infrações de layout em três locais dos novos specs de usuários: recuo da chave interna, argumentos e linha vazia final. As convenções do spec de eventos foram corrigidas. Assets/Chrome não executados; CI continua reprovada. Artefato `14602728856`, SHA-256 `67eb015954e17b2738db9adad4a6ea9dca45a6516dfef716bfe40482d8395413`, verificado. Corrigir somente whitespace e validar o complemento de autenticação do gestor no próximo SHA; 212 Chrome continuam obrigatórios.

### 20/11 — Origem da correspondência telefônica

- [ ] **CC-PHONE-CANDIDATE-PROVENANCE-20261120:** Campo aditivo identity_source e aviso na tela para candidato único ainda sem vínculo nativo. Preservar status legado, filtros, ContactDirectory e call.contact_id nas escritas; painel360doHoya exige vínculo nativo,sem promover candidato. Cinco regressões Vue e ampliação do Chrome nativo nas quatro combinações preparados; lint direcionado aprovado, Rails/Vue/Chrome ainda pendentes no novo SHA. ADR20261120-call-center-phone-candidate-provenance.md. Não integra a CI86c4ad53 em andamento e não conclui a figura21.

### 20/11 — Aceite nativo dos encerramentos e da autenticação atual

- [x] **CC-ENDING-REQUIRED-QUEUES-20261120 / CC-CURRENT-MEMBERSHIP-AUTH / CC-GRANT-ACTOR-AUTH:** SHA86c4ad53,CI44679530987 com1.808Rails distintos,81recargas,870Vue e212Chrome aprovados;zero falhas/pendências/erros externos/ignorados/flaky.15cards no probe,308capturas com hashes verificados e12revisadas em1440/390,claro/escuro. Artefato14606540165/SHA-256d174620ae05e9ce122ab38a3c77490d7ab0c8565db845618299d7afeb555b8f8. Relatório docs/jrc_contact_center/required_ending_queues_verified_20261120.json. Não ativado em contas reais;sem aceite integral das23figuras.
- [ ] Seguimento visual identificado em evidência real:exibir nomes autorizados nos chips de filas selecionadas;alinhar a cor da barra nativa ao estado excedido doACW,sem alterar prazos/relógios.
- Próximo incremento já preparado:origem do candidato telefônico e projeção360doHoya somente com vínculo da chamada. A evidência86não comprova essa alteração posterior.

### 20/11 — Seguimento visual comprovado por capturas

- [ ] **CC-ENDING-QUEUE-NAMES-ACW-PAINT:** Preparados nomes autorizados das filas selecionadas fora do catálogo/revisão e cor da barra nativa conforme estado real doACW. Um novo Rails,assertivas de acesso negado,cincoVue e ampliação do Chrome existente nos quatro projetos;212cenários preservados. Lint direcionado sem erros;execução nativa pendente. ADR20261120-call-center-ending-queue-labels-and-acw-paint.md. Não integra oSHA50d26506 emCI;sem migrações ou alteração de regras.

### 20/11 — Contexto telefônico validado

- [x] **CC-PHONE-CANDIDATE-PROVENANCE-20261120:** SHA50d26506,CI44685351828:1.808Rails distintos,81recargas,875Vue,212Chrome;zero falhas/pendências/erros externos/ignorados/flaky.316capturas com hashes conferidos e8novas revisadas. Aviso real e360doHoya bloqueado sem vínculo;fluxo do Cadastro Mestre vinculado continua válido,sem autoassociação pelo telefone. Artefato14608219003,SHA-25691f07fbb27ea87c70bceb05056177ff5d9ab33d2d656c6b1bb7166e5179c3b9f. Relatório docs/jrc_contact_center/phone_candidate_provenance_verified_20261120.json. A figura21 e as23referências continuam parciais.
- Próximo incremento preparado:nome autorizado da fila selecionada e barraACW conforme prazo real;13arquivos de código/testes/documentação com lint estático sem erros,sem migrar ou alterar regras. Exigir CI própria e212Chrome.

### Call Center — 20/11/2026 — origem de equipe

- [x] Decisão: inativar somente a origem da equipe no Call Center; preservar vínculos e demais módulos.
- [x] Preparar estado local, autorização/cobertura atual e proposta, auditoria e confirmação da última elegibilidade em fila.
- [ ] Executar os testes nativos e conferir Chrome deste incremento antes de aceitar a alteração.
- [ ] Confirmar a pintura real da barra ACW: captura de 17d6536a ainda verde; accent-color isolado não era evidência suficiente.
- [ ] Implementar biblioteca institucional por unidade conforme decisão aprovada; não misturar gravações de chamadas.

#### Evidência intermediária 075d60b7

Rails: 1.847 exemplos distintos aprovados e90 reexecuções após recarga. Incremento não aceito: um mock Vue sem interpolação e15 infrações Ruby bloquearam assets/Chrome. Correções preparadas sem reduzir asserções, regras ou autoridade. A conferência da pintura ACW real continua obrigatória. Biblioteca por unidade segue em preparação separada, sem rota, banco ou operação ativa.

### 20/11 — Pastas institucionais por unidade (fundação)

- [x] Decisão por unidade nativa e cobertura atual; não é catálogo de gravações de chamadas.
- [x] Preparar pastas, hierarquia, revisão obrigatória, auditoria, filtros e popup, sem grants, duplicação do Help Center ou chamada ao fornecedor.
- [x] Quarenta verificações leves do gate de oito migrations e sete testes do compilador de workflow aprovados; novo componente/transportes sem erros de lint.
- [ ] Executar Rails/Vue, concorrência e os quatro cenários Chrome adicionais (220 totais) no próximo SHA. Nenhum resultado de mocks substitui a prova de banco e navegador.
- [ ] Implementar arquivos privados, versões, scanner, player e vínculos verificáveis; figuras5/6/16 continuam parciais. TTS/publicação/ACK aguardam contratos reais.
- [ ] Mostrar origem da equipe e pasta como recursos da auditoria existente; conferir filtros/isolamento/histórico nativamente.

### 20/11 — Aceite da origem de equipe e pintura ACW

- [x] **CC-TEAM-SOURCE-ACTIVITY / CC-ENDING-QUEUE-NAMES-ACW-PAINT:** e9e364ec/CI44709382400:1848Rails distintos,90recargas,890Vue,216Chrome,328capturas verificadas;zero falhas/pendências/erros externos/flaky/ignorados.Confirmação do gestor e pintura real revisadas em1440/390 claro/escuro; artefato14619566711/SHA-256304d0afed8f869a8a9d6cad1d3b0e2c660473d7b7d51c06a3a201ea4c1903cae.
- [ ] Seguimento textual: reutilizar TEAM_ALLOWED no popup da equipe e revalidar no próximo SHA. Biblioteca institucional permanece fundação preparada, não aceita por esse run.

### 20/11 — Primeiro gate nativo das pastas

- ce34ac15/CI44716460983:1883Rails distintos(1692core+106concorrência+85corporativos),101recargas e911Vue aprovados;lintfrontend sem erros. Quatro apontamentosRuby bloqueiam assets/Chrome. Corrigidos o filtro extraído sem mudança semântica, a posição da única rota aditiva no escopo existente e o alinhamento da mesma fixture. Nenhuma migration/SQL/permissão/configuração de lint alterada. Artefato14620304502/SHA-25619e0ebb0129f7ec868ea8f57828e02b8855d2a499679e27b93ef49c8c077c106 verificado. Exigir novo gate e220Chrome antes de aceitar.

### 20/11 — Checagem de pendências do card Áudios

- 0dc2c080/CI44720588860:1883Rails distintos,101recargas,911Vue,lint e assets reais aprovados. Chrome216/220: quatro falhas na checagem genérica do card Áudios, cuja organização de pastas já tem aviso específico de arquivos/Nico/publicação pendentes. Recuperados artefato14624389798/SHA-2562bd6bca282f86994e043ce761a730725dca1d77d4ffe1ba4d1c4202dcc5edcd5 e capturas reais. Corrigir a acessibilidade do aviso e exigir seu texto integral mais ausência de controles de upload/player/publicação; manter as checagens dos outros cards. Não aceitar o incremento sem220/220 no novo SHA.

### 20/11 — Aceite da fundação de pastas por unidade

- [x] fa43cbf7/CI44729757403:1883Rails distintos,101recargas,911Vue e220Chrome(55por projeto) aprovados;336capturas com hashes verificados e8amostras efetivamente abertas(1440/390,claro/escuro). Artefato14630025679/SHA-2562688543b2412ae6dbaa7c1203a2c1a7b50b24d5d165206538bb56e1770e18eb2. Cadastro/revisão/movimentação de pastas, filtros/paginação e isolamento nativos validados. Nenhum arquivo de áudio/versão/player foi aceito como concluído.
- [x] Caminho completo de ancestrais, nome de120caracteres em390px e limpeza após401 validados em7dfccc8f/CI44738873504:1890Rails distintos,101recargas,918Vue e220Chrome;340hashes de capturas e8imagens realmente revisadas. Artefato14632969101/SHA-2569a322d5bc205f8abe913eca93a56a06bc21cc4061045023af2628b2d090e59c3. Recebimento de arquivos/versões permanece incremento posterior, sem aceite nativo ainda.
- [ ] Arquivos/versões permanecem preparação separada e incompleta, fora deste checkpoint de navegação; sem nova migration, API ou dependência publicada para esses arquivos.

### 20/11 — Recebimento privado e versões de áudios (candidata ainda não homologada)

- [ ] APIs/UI de recebimento privado, edição/movimentação e histórico preparados; CAS/idempotência e guards de bytes/attachments. Migration20261120120000 aditiva, sem alterar as oito anteriores; schema/SQL fixados por hashes e upgrade/reload/tamper cases preparados. Exigir nova CI nativa no próprio SHA.
- [ ] Quatro Chrome novos, mantendo os220 anteriores: arquivo inválido/válido,6registros reais/página5, persistência/versões, acesso negado e temas390/1440. Stubs Vue e48checks leves do gate não substituem esta prova.
- [ ] Codec/scanner/metadados/player, gravação, Nico, vínculos e layout completo ainda pendentes. Todos os novos recibos são privados e não verificados; não aceitar as figuras6/16 nem todas23 como concluídas.

- [ ] Recebimento privado9b8: instalação nova aprovada; recarga113/114 e lint57infrações novas bloquearam a CI44759123101. Correção CR/LF sem relaxar fingerprint, JSON explícito e lint preparada; teste PostgreSQL real e224Chrome continuam obrigatórios. Ver audio_file_schema_reload_correction_20261120.json.

- [ ] Recebimento privado5c4b/CI44763568917:114/115recargas, novo casoCR/LF aprovado, lint57→1. Casts explícitos (mesmo conjunto permitido) e21pares PostgreSQL, alinhamento final e vetoresfresh/reload preparados; aprovação dos uploads e224Chrome ainda pendente.

- [x] Schema privado5e8b:116recargas aprovadas, vetoresfresh/reloadidênticos, lintRuby0novasinfrações. Não equivale ao aceite dos uploads.
- [ ] Core5e8b:1751/1753passaram;2falhas de transporteHTTP corrigidas nafixtureRackmultipart, comasserção adicional. Manter gates restantes e224Chrome obrigatórios; nenhuma imagem/publicação/deploy.

- [x] Backendbfc1:1947Railsdistintos,116recargas separadas, vetores schemaexatos e lintRuby0. IncluiHTTPmultipartreal, SQLorigem/imutabilidade, concorrência e regressões corporativas.
- [ ] Vuebfc1:962/964, duas expectativas booleanas de arquivo0/101bytes falharamnull≠false. PredicateBoolean corrigido, asserções mantidas, lintlocal1arquivo0infrações; CIe224Chrome pendentes.

- 2026-11-20 — Call Center: recebimentos privados e versões validados no SHA `82e330c8` (CI `44776659369`): 1.947 exemplos Rails distintos, 116 de recarga separados, 964 Vue, 224 Chrome; 348 hashes PNG e oito capturas revisadas. Arquivos continuam bloqueados para reprodução/publicação. Preparado o incremento aditivo de observações técnicas por versão, com scanner nativo reutilizado, decodificação limitada, histórico/API/UI, idempotência e testes de concorrência. Migration 10 e este incremento ainda aguardam execução nativa; as nove migrations anteriores permanecem preservadas. Figuras 6/16 e conjunto das 23 referências continuam parciais.

- 2026-11-20 — O checkpoint de inspeções `89441261` ficou bloqueado na prontidão do scanner sintético (CI `44788906642`), antes de migrations ou testes da aplicação. APT/identidade passaram. A saída interna não foi arquivada; preparado ajuste mínimo de observabilidade para preservar o startup em `/tmp/call-center-*.txt`, sem ampliar prazo ou aceitar falso resultado. O incremento continua não homologado.

- 2026-11-20 — O diagnóstico `d8d109b8` (CI `44790171557`) preservou a causa real: diretório CA CVD ausente. Preparada correção com certificado público oficial da tag assinada ClamAV 1.5.4, SHA-256 fixado e confiança isolada por processo; sem alterar certificados do sistema, verificações de assinaturas, prazos, migrations ou políticas. Nova validação nativa permanece obrigatória.

- 2026-11-20 — CI `44792107487` / `3b20ccc0`: preparação real do ClamAV/CA passou; 129/130 exemplos da recarga passaram, incluindo os seis casos nativos da migration de inspeções. Fingerprint original dos arquivos preservado. Corrigida a preparação da mutação do teste de imutabilidade e preparadas correções para 27 infrações Ruby, sem exceções ou redução dos guardas. Validação integral do novo SHA ainda obrigatória; byte reader futuro permanece fora deste checkpoint.

- 2026-11-20 — Preparada prévia/download autenticados por versão e inspeção atual, com dupla reautorização nativa e hashes de armazenamento/buffer/browser. Player sem autoplay e URL temporária revogável; sete cenários HTTP, seis de serviço, contratos Vue e quatro Chrome adicionais preparados. Nenhum aceite nativo ainda; exigir 232 Chrome no próprio SHA e preservar a validação pendente de codec antes da persistência final.

- 2026-11-20 — CI44796979099/53e5743f:130/130recargas e1818/1821core; três falhas no caminho WAV positivo. MP3/OGG/MP4 nativos passaram. Lint27→1 (linha152/150). Preparada prova direta dePCM pelo muxerhash, sem aceitar fluxo vazio, e diagnóstico nativo comparativo; nenhuma duração ou segurança inventada. Incremento de bytes/UI permanece separado e não aceito.

- 2026-11-20 — Inspeções técnicas aceitas em `c276759e`/CI44801034652:2022Rails distintos,130recargas separadas,974Vue e228Chrome(57/projeto),zero falhas/pendências/erros/flaky/ignorados,lintRuby0 eCSS/bootstrap15cards reais. Artefato14666236517/SHA-2560f8f11ff01fd506eafef969c64f2e33264f736e9f72a46aa2dc744fc8cc5d7ca;352hashesPNG e8capturas abertas. CausaWAV comprovada: progressofinal0 apesar de250ms reais; hashPCM bateu nas amostras independentes. Scanner real usa apenas base sintética, sem prova de malware em produção.

- [ ] Próximo incremento preparado: prévia/download autenticados e reauditados, inspeção/versão/hash exatos, reautorização apósIO e em cada download, ciclo deURL privada/perfil, falta de arquivo e falha da auditoria. Nove casos de serviço de leitura,noveHTTP,contratosVue e232Chrome previstos; nenhuma execução nativa desse código ainda. Árvore/tabela,usos,codec antes doSave,Nico e demais critérios permanecem abertos.

- [ ] **CC-AUDIO-ADMISSION-20261120:** Validar scanner e codec antes da versão final (Word Figura 6, §0158), gravar observação inicial/auditoria atomicamente e preservar recibos legados. Implementação e testes preparados; validação nativa/Chrome pendente. Ver `docs/jrc_contact_center/audio_admission_prepared_20261120.json`.

- [ ] **CC-AUDIO-WORD-LAYOUT-20261120:** Figuras 6/16: navegação de pastas contida, tabela nativa e painel de detalhes reautorizados preparados. Preservadas edição/movimentação, substituição, histórico e prévia exata. Vue e Chrome reais pendentes; árvore completa, vínculos e ações adicionais continuam abertos. Ver `docs/jrc_contact_center/audio_library_layout_prepared_20261120.json`.

- [ ] **CC-AUDIO-DURATION-20261120:** Duração real da observação atual na lista e nos detalhes, sem zero fictício ou reaproveitamento de inspeção antiga. Consulta em lote e atualização por identidade exata preparadas; testes nativos/Vue/232 Chrome pendentes. Ver `docs/jrc_contact_center/audio_verified_duration_prepared_20261120.json`.

- **Evidência parcial `1d11a7bf` / CI `44819662149`:** 2.060 Rails distintos e131 recarga aprovados; Vue999/1.000 com um índice de argumento incorreto no teste; quatro convenções RSpec restantes corrigidas no incremento seguinte. Assets/232Chrome não executaram. Não representa aceite do layout ou de todas as23figuras. Ver `docs/jrc_contact_center/audio_admission_backend_verified_20261120.json`.

- [ ] **CC-AUDIO-TREE-20261120:** Expansão de subpastas por API nativa, paginação limitada e limpeza de respostas atrasadas/perda de acesso preparadas.14Vue e os232Chrome ampliados ainda pendentes; não representa aceite das23figuras. Ver `docs/jrc_contact_center/audio_folder_tree_prepared_20261120.json`.

- **Evidência parcial `26867ce7` / CI `44826071664`:** 2.066 Rails distintos e131recargas aprovados; duração/consulta em lote nativas aprovadas. Vue1.010/1.011 e uma convenção de alinhamento Ruby bloquearam assets/Chrome. Correções mantêm inspeção atual indisponível, histórico antigo e ausência de prévia. Ver `docs/jrc_contact_center/audio_duration_backend_verified_20261120.json`.

- [ ] **CC-AUDIO-CAPTURE-20261120:** Gravação institucional no editor existente preparada: início explícito, recursos da sessão, remux nativo, prévia local e recebimento privado com origem por versão.12HTTP,25Vue e236Chrome pendentes; sem microfone físico, endpoint novo, migration ou comandos PABX. Nico permanece integração pendente. Ver `docs/jrc_contact_center/audio_browser_capture_prepared_20261120.json`.

- **Evidência parcial `faf35daa` / CI `44830541470`:** 2.066 Rails distintos,131recargas e1.025Vue aprovados, incluindo14novos de árvore e correção do histórico. Lintfrontend aprovado; uma coluna Ruby ainda bloqueou assets/Chrome, agora medida e alinhada exatamente. Ver `docs/jrc_contact_center/audio_folder_tree_backend_verified_20261120.json`.

- [ ] **CC-AUDIO-FILTERS-20261120:** Filtros de origem/formato da versão atual na relação nativa autorizada, antes da busca/contagem/paginação. Rota, recarga e remoção preservam a unidade;10HTTP,4Vue e236Chrome ampliados pendentes. Usos/status operacional continuam abertos. Ver `docs/jrc_contact_center/audio_current_filters_prepared_20261120.json`.

- **Evidência parcial `ca831c77` / CI `44834724720`:** 2.078 Rails distintos,131recargas e1.050Vue aprovados, incluindo12HTTP/25Vue de gravação. Alinhamento resolvido; dois limites ABC bloquearam assets/236Chrome. Preparada separação sem mudança funcional de validação e recibo, sem exceções de lint. Ver `docs/jrc_contact_center/audio_capture_backend_verified_20261120.json`.

- **Evidência parcial `fb0fcbd2` / CI `44838925096`:** 2.088 Rails distintos,131recargas e1.054Vue aprovados. Dez HTTP/quatro Vue de filtros passaram; os dois ABC anteriores foram resolvidos. Index26,94/26 ainda bloqueou assets/236Chrome, com extração privada equivalente preparada. Ver `docs/jrc_contact_center/audio_filters_backend_verified_20261120.json`.

- **Evidência parcial `8348dabe` / CI `44843469401`:** 2.088 Rails distintos,131recargas,1.054Vue, lint e assets novos aprovados; Chrome228/236, com4expectativas de aviso antigo e4recebimentos de captura422. Prévia local comprovada nos4perfis, salvamento ainda não. Preparadas normalização MIME Opus identificada por bytes,5regressões nativas e correção de legibilidade observada;236Chrome e políticas mantidos. Ver `docs/jrc_contact_center/audio_browser_chrome_failure_20261120.json`.

- **Evidência parcial `e6311213` / CI `44851946596`:** 2.093 Rails distintos,131recargas e1.054Vue aprovados; cinco novos casos Opus nativos confirmados individualmente. Dois alinhamentos de hash nos testes bloquearam assets/236Chrome. Correção limitada a quatro espaços, com reconstrução exata do hash anterior; sem alterar asserções, MIME, scanner ou permissões. Ver `docs/jrc_contact_center/audio_opus_native_verified_20261120.json`.

- **Evidência parcial `9da5f3e8` / CI `44854936459`:** 2.093 Rails distintos,131recargas,1.054Vue, lintRuby/frontend, assets e bootstrap aprovados; Chrome232/236(58/projeto). Gravação real sintética chegou a201, inspeção, hash do download e401negado antes da falha de origem ausente na linha. Layout/pastas foram revisados em quatro PNGs, com largura152pxdesktop/220pxmobile. Preparada a origem da versão na tabela e3Vue; manter236Chrome, incluindo os filtros ainda não alcançados. Ver `docs/jrc_contact_center/audio_capture_row_origin_20261121.json`.

- [ ] **Figura23 — direito próprio do Nico (21/11):** preparada a capacidade explícita `jrc_contact_center_quality_review`, dependente de acesso à gravação e sem concessão automática; migration adicional sem backfill, 37 casos nativos e3Vue preparados. Gate estático56/56 e7testes do verificador do workflow aprovados. Exigir CI nativa, reload e236Chrome antes de marcar a base de autorização validada. Popup/revisões imutáveis continuam pendentes. Ver `docs/jrc_contact_center/quality_review_authority_preparation_20261121.json`.

- [x] **Captura institucional e origem — `bfe0d49d`, CI44861246777:** 2.093 testes Rails distintos, 131 testes de recarga separados, 1.057 Vue e 236 Chrome aprovados (59 por projeto), sem falhas, pendências ou erros externos. Assets novos, lint e bootstrap de15cards aprovados. Arquivo56273827bytes verificado porSHA-256;376PNGs conferidos por hash e quatro capturas efetivamente abertas. Filtros, persistência, hash, negação de acesso e árvore nativa comprovados. As23figuras permanecem parciais; ver `docs/jrc_contact_center/audio_browser_capture_verified_20261121.json`.

- [ ] **QA do direito do Nico — `93935376`, CI44865637660:** instalação e recarga física aprovadas; RSpec da recarga executou159exemplos,158passaram e1falhou no mock delegado do teste de rollback. As16políticas novas e11dos12casos da migration passaram;4infrações de estilo ocorreram somente nos testes. Corrigidos o alvo para o adaptador real, a prova de primeira substituição antes da falha e os probes SQL/estilo. Produto, migration, workflow e gates mantidos. Exigir nova CI, incluindo APIs/Vue/236Chrome que não executaram nesta rodada. Ver `docs/jrc_contact_center/quality_review_fixture_correction_20261121.json`.

- [ ] **Resposta atual do perfil — `51f293b7`, CI44867208994:** recarga159/159 e lintRuby sem novas infrações; core1932/1933, incluindo36dos37casos novos. A única falha consultou um `let` que guardava a primeira resposta do perfil. A correção lê o segundo GET diretamente, exige ausência tanto de revisão quanto de escuta e mantém o grant original no perfil. Nenhuma regra ou migration foi alterada; exigir nova prova nativa e236Chrome. Ver `docs/jrc_contact_center/quality_review_profile_refresh_20261121.json`.

- [ ] **CC-IVR-AUDIO-PIN-20261121:** vínculo exato da biblioteca institucional no menu da URA local preparado, com esquema1 preservado e esquema2 explícito; prévia nativa, escopos, inspeção atual, histórico, transação, CAS/idempotência e auditoria. Onze verificações leves passaram; execução Rails/Vue/escala e240Chrome ainda pendentes. Nenhuma publicação PABX ou alteração real. Ver `docs/jrc_contact_center/ivr_exact_audio_references_prepared_20261121.json`.

- [x] **CC-NICO-REVIEW-AUTHORITY — `3c7747d8`, CI44869039094:** fundamento de permissão própria validado, sem concessão automática a administrador e exigindo acesso à gravação.2.130Rails distintos,159recargas separados,1.060Vue e236Chrome aprovados, zero falhas/pendências/erros. Os37casos novos foram conferidos no JSON. Onze migrations preservadas; upgrade populado/idempotência/rollback real/recarga aprovados.376PNGs verificados porhash e quatro perfis efetivamente abertos. A correção humana completa da figura23 permanece pendente. Ver `docs/jrc_contact_center/quality_review_authority_verified_20261121.json`.

- [ ] **URA/áudio — correção nativa de `d3320a64`, CI44873756661:**1933IDs do core anterior continuam aprovados; os76novos casos tiveram54aprovações e22falhas (21afetadas pela consulta usando`unit` em lugar da coluna nativa`unit_id`, uma pelo argumento obrigatório da versão no teste). Recarga159/159 aprovada. Treze infrações Ruby corrigidas no código aguardam confirmação. Asserções, escopos,11migrations e240Chrome preservados; Vue/assets/Chrome ainda não executaram nesse SHA. Ver `docs/jrc_contact_center/ivr_exact_audio_native_query_fix_20261121.json`.

- [ ] **URA/áudio — `73b7dd04`, CI44875894660:** consulta nativa corrigida;2007/2009core e159recargas aprovados, incluindo os1933IDs anteriores,48casos de esquema,12de grafo/escala e8APIs. Restam dois testes que mediam auditorias antes de criar a fila do fixture. O input agora é preparado antes da medição, preservando integralmente a exigência de zero gravações parciais. Dois ajustes de encaminhamento de bloco Ruby; nenhum código funcional, regra ou gate alterado. Vue/assets/240Chrome continuam pendentes. Ver `docs/jrc_contact_center/ivr_audio_backend_verified_fixture_warmup_20261121.json`.

- [x] **URA/áudio exato — `86ed16c6`, CI44877800328:** 2.206 Rails distintos,159 recargas separadas,1.099 Vue e240 Chrome (60 por projeto), sem falhas/pendências/erros externos. Os76 novos casos nativos foram conferidos; lint, assets novos e bootstrap15 aprovados. Artefato56773101bytes e380PNGs verificados porSHA-256, quatro capturas realmente abertas. Persistência, versão fixada, negações e histórico comprovados. Ver `docs/jrc_contact_center/ivr_exact_audio_native_verified_20261121.json`.
- [ ] **Seguimento pontual URA/áudio:** labels explícitos por instância; rejeição conhecida409 preserva edição, mantendo proteção de resultado incerto; fixture legado sintético sem inspeção falsa e quatro casos nativos preparados. Exigir novoSHA/240Chrome; não pertence à evidência anterior. Quatro arquivos de valores/snapshot Nico mantidos fora deste checkpoint.

- [ ] **Vínculos locais de áudio e valores privados do Nico (21/11):** consulta de cabeças atuais dos rascunhos com escopo nativo/histórico e Dialog existente preparada;13HTTP, Vue e240Chrome ampliados aguardam novoSHA. Quatro arquivos de entrada/snapshot do Nico preparados para validação nativa, sem API de escrita nem ledger persistente. Figuras6/11/16/23 reconciliadas com a evidência comprovada; demais destinos, ações e revisão completa continuam pendentes. Ver `docs/jrc_contact_center/audio_usages_and_nico_values_prepared_20261121.json`.

- [x] **URA/áudio — `49abeccd`, CI44881693667:** 2210 Rails distintos, 159 recargas separadas, 1102 Vue e240Chrome aprovados, sem falhas/pendências/erros. Os2009IDs anteriores do core e quatro novos casos do fixture nativo foram conferidos. Rejeição409 mantém edição e revisão1, posterior retirada preserva histórico; labels explícitos e novos assets aprovados. Quatro capturas abertas; ver `docs/jrc_contact_center/ivr_known_audio_refusal_verified_20261121.json`. Vínculos locais e valores privados do Nico preparados posteriormente continuam sem evidência deste SHA.

- [ ] **Vínculos locais/Nico — `f0ef9825`, CI44886482187:**2.314Rails distintos/159recargas separados/1.122Vue e lintfrontend aprovados, sem falhas/pendências/erros. Todos2013IDs anteriores e104novos casos (13HTTP vínculos,61entrada,30snapshot) conferidos. Doze infrações Ruby bloquearam assets/240Chrome. Extração equivalente de paginação/predicados e estilo preparada, sem mudar escopos, limites, grants, SQL ou gates. Exigir novoSHA; ver `docs/jrc_contact_center/audio_usages_nico_values_native_lint_followup_20261121.json`.

- [ ] **Forma de onda privada — figuras6/16 (21/11):** reutiliza WaveSurfer7.8.6 e o mesmo Blob/player verificado, sem dependência nova, autoplay, dados fictícios ou consulta de mídia adicional. Limites opcionais de visualização preservam reprodução/download. Testes Vue de ciclo de vida e mesmo240Chrome ampliados aguardam novoSHA; não é aceite integral. Ver `docs/jrc_contact_center/private_audio_waveform_prepared_20261121.json`.

- [x] **Vínculos locais/valores privados Nico — `015628bf`, CI44889202273:** 2314Rails distintos,159recargas separados,1122Vue e240Chrome aprovados; zero falhas/pendências/erros, lint e assets novos aprovados.104novos casos e todos2117/1122do parent conferidos; 392PNGs porhash, quatro capturas abertas. Histórico/negação/unlink comprovados. Revisão humana persistente e forma de onda não pertencem a este aceite. Ver `docs/jrc_contact_center/audio_usages_nico_values_native_verified_20261121.json`.

## CALL-CENTER-20261121 — Supervisão por equipe [WIP]

- Player privado com waveform: checkpoint a1a64397, CI44894876897 comprovada;2314 Rails/159 reload/1147 Vue/240 Chrome, quatro PNGs abertos. Limites no recibo private_audio_waveform_native_verified_20261121.json.
- Figuras3/12: vínculo explícito de supervisor principal/adicionais, cobertura nativa, CAS/auditoria e popup preparados.37 testes unitários com transporte substituído passaram; migrations, persistência, concorrência e244 Chrome ainda exigem CI do novo SHA. Não concluído.
- Nenhuma participação em equipe/fila ou concessão de permissões decorre desse vínculo. Contratos PABX e o ledger final de revisão Nico continuam pendentes; o direito próprio já está implementado sem concessão automática.

- Team supervision6a5e22fb:2210/2212 Rails aprovados; duas expectativas corrigidas preservando o legado.175 reload passaram;35 infrações de lint identificadas, correções exigem novo SHA. Mantidos os2117 casos anteriores. Concorrência, Vue, assets e244Chrome continuam obrigatórios e pendentes. Recibo team_supervision_first_native_20261121.json.

-7706a6f0:2212/2212 Rails e175 reload aprovados;112 casos concorrentes anteriores preservados. Os3 casos novos falharam apenas no after hook por FK corporativa; corrigida a limpeza exclusiva do fixture.35 infrações anteriores resolvidas;7 remanescentes no describe/described_class do spec corrigidas e aguardando revalidação. Vue/assets/244Chrome ainda bloqueados.


- [ ] **Duplicação institucional — figuras6/16 (21/11):** novo asset/versão1/blob na mesma unidade, origem fixada, nova inspeção, CAS e reautorização final, recibo idempotente e auditoria nativa. Mesmo editor com revisão explícita;48unitários com transporte substituído aprovados (28regressões/20novos). Preparados24casos Rails,2concorrentes,3Vue de apresentação e extensão dos mesmos244Chrome. Persistência, scanner e visual do novo SHA ainda não aprovados. Ver `docs/jrc_contact_center/audio_copy_prepared_20261121.json`. Sem PABX, grants ou migrations novos.


- [x] **Supervisão explícita — `31582e3a`, CI44906859540:** 2412Rails distintos,175reload separados,1188Vue e244Chrome aprovados;zero falhas/pendências/erros, lint/assets/bootstrap15 aprovados. Quatro capturas efetivamente abertas;persistência, paginação, conflito e negações comprovados. Sem grants ou participação automática. Ver `docs/jrc_contact_center/team_supervision_native_verified_20261121.json`. Figuras3/12 completas e cópia institucional ainda não concluídas por este resultado.


- [ ] **Cópia institucional — `9b2628a4`, CI44911548351:**2438Rails distintos/175reload/1213Vue aprovados; todos2212core/115concorrentes/1188Vue anteriores e26novos Rails/25Vue conferidos. Onze infrações Ruby em três arquivos bloquearam assets/Chrome; alinhamento e três sobrescritas equivalentes de kwargs corrigidos, sem mudança de comportamento, escopo, regras, migrations ou gates. Exigir novoSHA e244Chrome; ver `docs/jrc_contact_center/audio_copy_first_native_20261121.json`.


- [ ] **Transição Chrome da cópia — produtor25076ac1:**2438Rails/175reload/1213Vue e ambos os lints passaram. 240/244Chrome passaram; os quatro cenários ampliados pararam antes da cópia porque o novo seletor procurava Cancelar no histórico, cujo botão real é Fechar. DOM e duas screenshots efetivamente vistos confirmam a causa. Corrigido somente esse seletor com asserção de visibilidade; preservar todas as verificações e exigir novo244Chrome. Ver `docs/jrc_contact_center/audio_copy_chrome_close_diagnosis_20261121.json`.
- [ ] **Nicofig23:**confirmada permissão própria explícita por perfil/equipe mais acesso autorizado à gravação, sem concessão automática a administrador. Fundação nativa preservada; vínculo de origem e revisão completa continuam pendentes.


- [x] **Cópia institucional — produtora2c2a671:**2438Rails/175reload/1213Vue/244Chrome aprovados; todas as identidades anteriores preservadas, doze imagens efetivamente revisadas em1440/390claro/escuro. Cópia independente, nova inspeção, CAS409, repetição idempotente, operador401 e retorno à cópia fora do filtro confirmados. Legenda mobile dos vínculos de supervisão também conferida. Ver `docs/jrc_contact_center/audio_copy_native_verified_20261121.json`.
- [ ] **ZIP dos áudios selecionados — preparado:**reutiliza biblioteca, escopos, leitura privada auditada, vínculos locais e dependência já fixada; 20unidades da seleção e35unidades projetadas da biblioteca/API passaram (31casos anteriores incluídos), sem substituir execução nativa. 26Rails/24Vue novos e extensão dos244Chrome preparados; exigir novoSHA, assets, download real e evidências antes de aceite. Ver `docs/jrc_contact_center/audio_archive_prepared_20261121.json`.
- [ ] **Nicofig23:**decisão confirmada: permissão própria explícita sem concessão automática. Fundação já provada; revisão persistida completa continua bloqueada até vínculo de origem/gravação/unidade comprovado. Nenhum grant real alterado.


- [ ] ZIP institucional: primeira CI f98c630f confirmou2464 Rails/175 reload/1237 Vue e lint frontend; quatro infrações Ruby corrigidas sem supressões. Resultado interno entry_count evita colisão com Struct.count; cabeçalhos e testes de segurança preservados. Exigir nova CI, assets e244Chrome antes de aceite. Movimentação selecionada continua somente em preparação privada, sem misturar ao reparo.


- [x] ZIP institucional: produtor cfe118f1, 2464 Rails/175 reload/1237 Vue/244 Chrome aprovados e oito screenshots efetivamente revisadas. Download real e manifesto inspecionados no runner; JSONs e hashes preservados. Isso não declara inventário completo do fornecedor.
- [ ] Movimento selecionado: implementação com CAS de todas as origens, transação nativa/auditoria e popup revisado. 57 testes preliminares com mocks incluem34 anteriores; 24 casos Rails preparados, ainda não executados. Exigir CI nativa e Chrome real antes do aceite. A seleção em lote de todos os estados de metadados permanece pendente.


- [ ] Movimento selecionado90ab82f7: 2488 Rails/175 reload/1260 Vue aprovados; dois achados Ruby exclusivamente de linhas em branco no spec de concorrência. Correção preserva todas as linhas não vazias e asserções; novo SHA exige lint, assets e Chrome.


- [x] Movimento selecionado: produtor 3e3cc17f, 2488 Rails/175 reload/1260 Vue/244 Chrome, concorrência HTTP nativa e oito screenshots efetivamente revisadas. Sem alterações de arquivos, versões, inspeções ou provedor.
- [ ] Biblioteca: seleção para organização dos metadados no mesmo catálogo, finalidade explícita, limite anunciado, revisão/CAS, resposta sem arquivo explícita e filtro nativo da última inspeção. 102 testes preliminares incluem76 anteriores; 26 novos Vue e13 Rails preparados. Exigir CI e Chrome reais; figura6 e conjunto23 não concluídos.

- [ ] **CALL-CENTER-AUDIO-ORGANIZATION-STYLE-20261121:** CI44947188637/372e3e70 preserved:2501native,175reload,1286Vue passed; seven Ruby layout findings corrected in four files with identical nonblank code. New assets/244Chrome were not executed. Full revalidation remains mandatory; figure6/23 is not accepted. Receipt: docs/jrc_contact_center/audio_library_organization_first_native_lint_20261121.json.

- [ ] **CALL-CENTER-SELECTED-AUDIO-COPIES-20261121:** Same native duplicate flow, explicit per-item review/receipts, sequential writes and safe manual replay.79preliminary mocked cases include46prior Library cases;33newVue and2nativeAPI examples are prepared, not native-proved. Native footer dismissal is disabled while pending. Same244Chrome assertions extended for actual synthetic copies. Report: docs/jrc_contact_center/audio_selected_copies_prepared_20261121.json. Calendar precedence is confirmed separately; no PABX publication is enabled.

- [x] **CALL-CENTER-AUDIO-ORGANIZATION-INCREMENT-20261121:** 057fa978/CI44950332408 independently verified:2501native,175separate schema reload,1286Vue,244actualChrome;448PNGhashes and16actual visual opens;12native organization/filter receipts. Metadata-only/no-file organization preserves versions and byte restrictions. Fullfigure6/23 and external PABX acceptance remain open. Receipt: docs/jrc_contact_center/audio_library_organization_native_verified_20261121.json.


## Call Center — 21/11/2026 — calendário interno nativo candidato

- [x] Preservar o incremento anterior de cópias de áudio com evidências nativas, Chrome e imagens efetivamente revisadas.
- [x] Implementar o adaptador de calendários por unidade, precedência confirmada, expediente/feriados/exceções, revisão, filtros, paginação, auditoria e reautorização.
- [x] Verificar 55 testes leves da projeção formatada e nenhuma infração nova; 32 avisos antigos do componente administrativo permanecem registrados.
- [ ] Executar os 38 cenários Rails preparados, regressões, build protegido de assets e Chrome nativo em quatro projetos.
- [ ] Homologar vínculos/impactos, recorrência, calendário totalmente fechado e PABX, conforme o relatório preparado. Não declarar as23 figuras concluídas.


## Call Center — 21/11/2026 — correção do primeiro gate de calendários

- [x] Preservar o checkpoint 866832ee e a reprovação real: 2.541 testes nativos, 175 de recarga e 1.374 Vue aprovados; 19 infrações Ruby novas.
- [x] Corrigir as cinco fontes afetadas sem remover validações e preparar seis casos adicionais de rejeição persistente.
- [ ] Revalidar o novo SHA nos gates existentes; assets e Chrome ainda não executados para este incremento.
- [ ] Continuar os vínculos tipados e impactos do calendário sem inventar referências PABX.


## Call Center — calendário interno validado em22/11/2026

- [x] Produtor369e7351/CI44964018731:2547Rails distintos,175reload separados,1374Vue e244Chrome reais, zero falhas/pendências/erros; lint, assets novos e bootstrap aprovados.472hashes PNG e12capturas efetivamente revisadas.
- [x] Precedência exceção→feriado→expediente, bloqueio de sobreposição, persistência, conflito409, revisão manual, paginação e negações nativas comprovados. Ver docs/jrc_contact_center/unit_calendars_native_verified_20261122.json.
- [ ] Vínculos tipados de calendário e inventário de impactos continuam pendentes; referências externas permanecem desconhecidas. Categorias fixo/móvel não presumem recorrência automática. Nenhuma publicação PABX; conjunto23não concluído.


- [ ] Vínculo interno fila/calendário: snapshot exato, escopo nativo, dupla revisão CAS, auditoria e recuperação idempotente implementados.39Vue leves aprovados (29novos/10anteriores), sem aceite nativo ou visual deste novo incremento. Exigir novoSHA, banco real sintético e mesmos244Chrome. Números/URA/impacto externo continuam pendentes; nenhum Command/PABX/migration. Ver docs/jrc_contact_center/queue_calendar_bindings_prepared_20261122.json.


- [ ] Vínculo de calendário341120a2/CI44970957120:2573Rails,175reload e1403Vue aprovados; todos os casos anteriores preservados. Três achados Ruby em dois specs bloquearam assets/Chrome. Declaração dos três status e alinhamento corrigidos sem remover asserções; dois cenários adicionais de histórico e replay antigo preparados. Exigir novoSHA e prova Chrome. Ver docs/jrc_contact_center/queue_calendar_bindings_first_native_lint_20261122.json.


- [ ] Vínculo de calendário340b06af/CI44974688895:2575Rails,175reload,1403Vue,lint,assets novos e bootstrap aprovados; Chrome sem relatório final após limite75min. Quatro falhas90s vieram da navegação do helper para5387Rails/login em vez da prévia5386; quatro imagens efetivamente vistas. Corrigida somente a origem relativa, com asserção de mesma origem e biblioteca real. Preservados90s/75min,244casos e gates. Exigir novoSHA, sem aceite de figura ou UI por este resultado. Ver docs/jrc_contact_center/queue_calendar_browser_origin_diagnosis_20261122.json.


- [ ] Vínculo fila/calendário6fcaa384/CI44981141842:2575Rails,175reload,1403Vue,lint,assets e bootstrap aprovados;240/244Chrome, quatro timeouts no observador PATCH. UI real alcançou o estado exclusivo de conflito; a espera comparava Axios5386 com Rails5387. Corrigidos os dois observadores com identidade exata e diagnóstico limitado sem payloads;9testes portáteis passaram. Preservados244casos,90s/75min e todos os gates. Exigir novoSHA e provas completas; retirada permanece privada e separada. Ver docs/jrc_contact_center/queue_calendar_browser_response_observer_diagnosis_20261122.json.


- [x] Vínculo interno produtor38565237/CI44986114275:2575Rails distintos,175reload,1403Vue,244Chrome,484hashesPNG;12imagens efetivamente vistas.409/200reais do navegador e todos os casos anteriores preservados. Revisão manual encontrou rótulo pré-gravação na seleção imediata, apesar da persistência/lista corretas; aceite visual integral retido. Ver docs/jrc_contact_center/queue_calendar_bindings_native_proof_20261122.json.
- [ ] Retirada e correção da revisão imediata:21fontes aplicadas no overlay,78Vue leves aprovados (39anteriores/39novos), regressão real de legenda reproduzida com2falhas e corrigida com28casos aprovados. Serviços/API/UI/auditoria e corridas nativas preparados, mas novoSHA exige Rails,lint,assets e244Chrome. Sem migrations, grants ou PABX; conjunto23não concluído. Ver docs/jrc_contact_center/queue_calendar_removal_prepared_20261122.json.

- [ ] Retirada de calendário/fila: CI44991077806 preservada com 2401/2402 exemplos Rails; um erro de preparação Current.set e13 infrações Ruby corrigidos sem reduzir regras; nova execução nativa e Chrome pendentes.

- [x] Retirada auditada do calendário/fila e legenda após salvar: prova nativa e16 imagens revisadas em7abf7b0c; sem aplicação no PABX nem aceite integral do Word.
- [ ] Aba de vínculos internos, contagem/paginação no servidor e recarga após retirada: 87 testes leves aprovados; execução nativa e Chrome da nova candidata pendentes.

- [ ] Vínculos de calendário: CI44997899087 preservada com2621Rails,175recargas e1451Vue aprovados; duas infrações na mesma linha de teste corrigidas apenas no alinhamento; Chrome e aceite do próximo SHA pendentes.

- [x] Calendário/fila: inventário nativo confirmado em da6ee6e9/CI45000878232, com2621Rails distintos,175recargas,1451Vue,244Chrome e12imagens efetivamente revisadas nos4projetos. Sem publicação no PABX.
- [ ] URA/calendário: versão3 preparada no editor existente,91Vue direcionados aprovados;41casos nativos e248Chrome aguardam a CI do novo checkpoint. Preservados contratos1/2, escopos, histórico e todas as12migrations. Inventário de URAs e homologação externa continuam pendentes.

- [ ] URA/calendário: falha nativa6dcfa825 preservada (2445/2447Rails e175recargas); corrigidas as duas preparações de teste e22apontamentos Ruby sem remover asserções. O teste do trigger passa a exigir SQL real e a mensagem de imutabilidade; versão4 continua recusada, com positivo explícito da3. Concorrência/Vue/assets/248Chrome aguardam o novo SHA.

- [ ] URA/calendário:9745d047 comprovou2663Rails distintos e175recargas, mas o gate segue reprovado:1494/1495Vue e duas indentações Ruby. Corrigido somente o teste do aviso antigo de vínculos (agora exige o limite real do painel e impacto externo desconhecido) e os dois espaços;6testes direcionados aprovados. Assets/248Chrome e homologação visual continuam pendentes no próximo SHA. A consulta adicional de URAs por calendário permanece privada e não aplicada.

- [ ] URA/calendário:54aec107 passou2663Rails distintos,175recargas,1495Vue,lint/assets/probe e244Chrome anteriores. Os4novos pararam no seletor incorreto “Simulação” em vez da aba existente “Simulação local”. Oito capturas reais também mostram texto preto no calendário escuro: aplicada somente a cor nativa no corpo do editor e acrescentado contraste real>=4,5 no Chrome.91testes direcionados passaram;248Chrome/16capturas completas e os testes após a simulação permanecem obrigatórios no próximo SHA. Consulta de URAs por calendário continua privada, não aplicada.

- [x] URA/calendário: 151ba582/CI45019803114, 2663Rails distintos, 175recargas separadas, 1495Vue e248Chrome; 16imagens abertas nos4projetos. Precedência nativa, versão exata, simulação explícita e contraste CSS comprovados; sem operação no PABX.
- [ ] Inventário calendário→URAs locais: candidato separado, 54Vue com transporte simulado; 17cenários Rails e252Chrome pendentes. Não comprova configuração aplicada no fornecedor.
- [ ] Campo de data da simulação: corrigido esquema nativo claro/escuro para o ícone observado em151; 91Vue direcionados e lint sem novas infrações. CSS computado e8capturas aguardam a próxima CI; sem troca do relógio, contratos ou regras.
- [ ] Inventário URA/calendário: CI9ab08119 preservada,2448casos anteriores aprovados e16/17novos. Corrigida a preparação do catálogo em escopo novo, mantendo a negação histórica;13ajustes de lint sem exclusões. Próxima CI ainda precisa aprovar Rails/Vue/252Chrome.
- [ ] CI3f71ebf1 preservada:13infrações Ruby resolvidas;2464Rails aprovados e1falha na tentativa de reconfiguração proibida. Mantidas as validações nativas; adicionado teste de rejeição e separada a injeção adversarial de SQL no banco sintético. 18cenários novos e252Chrome ainda aguardam o próximo SHA.

- [x] Inventário calendário→URAs internas e campo de data: a9206b84/CI45030951154, 2681Rails distintos,175recargas,1526Vue,252Chrome;536hashesPNG e24imagens realmente abertas. Casos anteriores preservados,18novos Rails e4novos Chrome; sem PABX. Prova: docs/jrc_contact_center/calendar_ivr_usage_inventory_native_verified_20261122.json.
- [ ] Pausa com aprovação: confirmado uso da Central e cobertura de todas as empresas/unidades afetadas. Preparação privada em andamento; não ativada nem homologada.


## Call Center 2026-11-22: all-affected-scope pause approval

Implemented in the existing Central and deferred-pause flow; native CI, migrations, concurrency and actual Chrome remain pending. See docs/jrc_contact_center/pause_all_scope_approval_candidate_20261122.json. No real grants, policies, activation or provider commands.


## Confirmação do motivo antes do ACW — 22/11/2026 [WIP]

- [ ] **CALL-CENTER-ENDING-CONFIRMATION-20261122:** Implementação isolada preparada, com 86 casos Vue leves e 142 verificações estáticas de migrations. Execução nativa, lint Ruby e quatro novos cenários Chrome permanecem pendentes; não conclui a figura 10 nem as 23 figuras. Confirmação salva o rascunho e fixa o motivo, mantendo o ACW aberto. Automações de destino continuam separadas. Critérios e limites: [relatório](docs/jrc_contact_center/ending_confirmation_preparation_20261122.json) e [ADR](docs/adr/20261122-call-center-confirmed-ending-before-acw.md).

- [ ] Confirmação do motivo: CI45082939258/ce5d06b6 preservada,199/200 testes de recarga aprovados e13 apontamentos Ruby. Os187 casos anteriores continuam aprovados; recibos fresh/reload coincidem. Corrigidos o cenário que contrariava a retenção nativa da conta e os apontamentos, sem alterar migrations/SQLs/gates. Nova execução nativa,260Chrome e revisão real ainda obrigatórias. Relatório: docs/jrc_contact_center/ending_confirmation_first_native_failure_20261122.json.

- [ ] Confirmação do motivo: ADC43BAB/CI45084892809 preservada,2583/2585Rails e200/200recargas. Todos os2550 casos anteriores aprovados; dois testes novos usavam objeto anterior à confirmação. Corrigida a preparação e acrescentada rejeição da revisão anteriormente válida. Seis apontamentos Ruby tratados, com rename revisado dos dois cenários de formulário. Pré-teste curto23 adicionado antes da regressão completa, sem substituir gates;12Node/44Python sintéticos e verificações estruturais aprovados, não equivalentes a Rails/Chrome. Nova execução e260Chrome pendentes. Relatório: docs/jrc_contact_center/ending_confirmation_stale_native_failure_20261122.json.
