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
