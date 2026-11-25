<!-- jrc-operational-init:v1 -->
# Roadmap operacional — JRC Conversas LAB2 — Grupo JRC

Referência inicial: INIT solicitado pelo usuário em 2026-11-13. É uma trilha documental Brownfield, não uma declaração de conclusão do produto.

## Fase 1: Fundação e alinhamento de contexto

- [x] Identificar o projeto e preservar as regras existentes em AGENTS.md.
- [x] Organizar o domínio em docs/domain/ e a arquitetura em docs/architecture/.
- [x] Configurar o pipeline documental de tarefas em TASKS.md e o registro ADR.
- [ ] Revisar os mapas iniciais com os responsáveis do projeto e manter as fontes atualizadas.

## Fase 2: Operação e desenvolvimento ativo

- [ ] Reconciliar conversas por caixa e a política de acesso Minhas/compartilhadas/exclusivas.
- [ ] Manter homologação de voz, histórico e mídias distinta de teste sintético e de publicação.
- [ ] Registrar critério de aceite, teste pertinente e evidência de cada alteração funcional autorizada.

## Fase 3: Estabilização e manutenção

- [ ] Documentar casos de borda comprovados e dependências operacionais.
- [ ] Otimizar rotinas repetitivas somente após medir a necessidade.
- [ ] Revisar proveniência, isolamento e versões a cada candidata de release.

Veja [TASKS.md](TASKS.md). Roadmaps e planos anteriores continuam válidos no seu escopo.


### Incremento autorizado de 15/11/2026

Respostas rápidas contextuais e configuração/importação da Central de Aprovações evoluem os módulos existentes. Aceite exige testes nativos e interface real em desktop/celular, claro/escuro. A importação não ativa regras, não cria aprovadores por nome e mantém integrações não mapeadas como pendências explícitas.

Release funcional `5c3fb7f` publicada e implantada no Grupo JRC após CI 49/49, Chrome 13/13 e testes integrados privados. Runtime, API, migrations e interface foram conferidos. O aceite operacional de histórico, autoridade e mídias continua parcial; a validação física foi adiada pelo usuário. Detalhes e evidências em `CONTINUE-AQUI.md` e `docs/jrc_consolidation/quick_replies_whatsapp_release_20261115.md`.

### Parte 1 do Call Center — continuidade autorizada em 17/11/2026

Concluir primeiro a revisão concorrente, herança explícita, elegibilidade e auditoria por escopo das etapas 0–2; depois seguir os contratos e dependências das etapas 3–8. A matriz das 23 figuras é o controle de aceite. A revisão esperada usa ampliação aditiva documentada em docs/adr/20261117-call-center-role-revision.md. A main concorrente e os ambientes permanecem preservados. CI, interface nativa e homologação externa continuam estados distintos.

A revisão esperada foi validada em 80632726 (431 Rails/185 Vue/56 Chrome). Próximo bloco: auditoria administrativa nativa com escopo duplo e proteção de escritas concorrentes; seguir depois com herança, elegibilidade e etapas 3–8. A aprovação deste sub-bloco não encerra 0–2 nem a Parte 1.

- Auditoria administrativa: contratos e duas corridas transacionais passaram no PostgreSQL sintético; interface e correções de lint aguardam CI do novo checkpoint. Sem aceite integral F14 ou Parte 1.

- Próximo checkpoint: revisão de cadastros com rascunho preservado, comparação explícita e descarte por conta; correção de contraste auditável no popup. Nova validação pendente. Sem conclusão de 0–2 ou Parte 1.

- Auditoria e revisão de cadastros validadas no 3c5054ac. Próxima frente executável: impedir perda de perfil por campo omitido no atualizador nativo, preservando permissões dos demais módulos; nova CI pendente.

Call Center 17/11: ampliar a proteção contra concessões implícitas na retirada de perfis antes de implementar herança/elegibilidade. Preservar acesso nativo dos demais módulos e validar cada incremento em banco sintético.

Call Center: proteção de retirada de perfis validada no SHA 30fbf0b1. Próximo incremento implementa elegibilidade/herança de forma explícita, com fixtures sintéticas identificadas, upgrade populado e nova execução nativa; interface e demais figuras permanecem abertas.

Call Center: evoluir a área Permissões com Perfil/Equipe/Usuário, mantendo os 68 cenários Chrome anteriores e ampliando para 80; revalidar backend e banco junto à interface real, antes de qualquer aceite de F11/F12.

- 22/11/2026 — calendário nativo: inventário de filas aceito em da6ee6e9. Próximo incremento: desvio interno de URA pela versão exata do calendário, com simulação determinística e escopo nativo; candidato ainda sem aceite Rails/Chrome. Os23 referenciais e o contrato operacional PABX continuam abertos.


## Confirmação do motivo antes do ACW — 22/11/2026 [WIP]

- [ ] **CALL-CENTER-ENDING-CONFIRMATION-20261122:** Implementação isolada preparada, com 86 casos Vue leves e 142 verificações estáticas de migrations. Execução nativa, lint Ruby e quatro novos cenários Chrome permanecem pendentes; não conclui a figura 10 nem as 23 figuras. Confirmação salva o rascunho e fixa o motivo, mantendo o ACW aberto. Automações de destino continuam separadas. Critérios e limites: [relatório](docs/jrc_contact_center/ending_confirmation_preparation_20261122.json) e [ADR](docs/adr/20261122-call-center-confirmed-ending-before-acw.md).

- [ ] Confirmação do motivo: CI45082939258/ce5d06b6 preservada,199/200 testes de recarga aprovados e13 apontamentos Ruby. Os187 casos anteriores continuam aprovados; recibos fresh/reload coincidem. Corrigidos o cenário que contrariava a retenção nativa da conta e os apontamentos, sem alterar migrations/SQLs/gates. Nova execução nativa,260Chrome e revisão real ainda obrigatórias. Relatório: docs/jrc_contact_center/ending_confirmation_first_native_failure_20261122.json.

- [ ] Confirmação do motivo: ADC43BAB/CI45084892809 preservada,2583/2585Rails e200/200recargas. Todos os2550 casos anteriores aprovados; dois testes novos usavam objeto anterior à confirmação. Corrigida a preparação e acrescentada rejeição da revisão anteriormente válida. Seis apontamentos Ruby tratados, com rename revisado dos dois cenários de formulário. Pré-teste curto23 adicionado antes da regressão completa, sem substituir gates;12Node/44Python sintéticos e verificações estruturais aprovados, não equivalentes a Rails/Chrome. Nova execução e260Chrome pendentes. Relatório: docs/jrc_contact_center/ending_confirmation_stale_native_failure_20261122.json.

- [ ] Confirmação:2a0fc2de/CI45087999785 comprovou2809Rails distintos,200recargas separadas,23pré-testes repetidos,1795Vue e260Chrome, todos sem falhas/pendências. Encerramento falhou porque exigia256Chrome. Corrigida somente a contagem e acrescentada regressão inicial8casos (antes2falhas; depois0). Código funcional/migrations/SQLs iguais; nova CI e revisão das imagens ainda obrigatórias. Relatório: docs/jrc_contact_center/ending_confirmation_counter_gate_findings_20261122.json.

- Call Center: confirmação de motivo e aprovações de pausa preservadas. Ajustes focados de instrução e observação nativa preparados; não concluir figura 10 nem os 23 requisitos sem execução das integrações por destino. Ver docs/jrc_contact_center/ending_confirmation_visual_followup_20261122.json.

- 23/11/2026: confirmação e pausa aceitas no incremento68d5011b/CI45102299490:2809Rails distintos,200recargas,1795Vue,260Chrome e48capturas revisadas; sem falhas/pendências. Não conclui as23figuras. Próximo incremento: registro imutável e prospectivo do escopo das filas para automações, ainda sem aceite nativo ou execução de destinos. Ver docs/jrc_contact_center/ending_action_scopes_candidate_20261123.json.

- 23/11/2026: escopos2d2b8154/CI45110347415 preservados como reprovados. Instalação inicial passou; recibo da recarga divergiu antes de RSpec. Diagnóstico agora será salvo antes da mesma verificação obrigatória; seis infrações dos testes novas tratadas. Nenhuma migration/SQL/recibo publicado ou funcionalidade alterada neste ajuste; nova CI ainda necessária. Ver docs/jrc_contact_center/ending_action_scopes_first_native_findings_20261123.json.

- 23/11/2026: diagnóstico f8cf0902/CI45113230705 confirmou divergência somente na representação dos casts do CHECK de estados. Preparado array text explícito apenas na15ªmigration ainda não implantada; mesmos3estados e verificador estrito, sem whitelist. Os14históricos, SQLs e recibos permanecem idênticos. Nova execução nativa ainda obrigatória; ver docs/jrc_contact_center/ending_action_scope_reload_cast_findings_20261123.json.

- 23/11/2026: CI45113230705 reprovada e preservada; quatro infrações restantes no teste de histórico corrigidas por rename e described_class, mantendo os12casos e os gates. Acrescentado terceiro cenário nativo de concorrência conta/emissora/fila, ainda não executado. Não representa aceite do novo componente.

- 23/11/2026:447ad396/CI45115534273 comprovou recibos fresh/reload iguais e231/232recargas sem pendências/erros externos; os200anteriores preservados. Única falha: helper1.microsecond ausente no runtime do teste. Preparado Rational(1,1_000_000), mantendo o limite temporal e a mesma asserção; produto/migrations/SQLs/recibos/gates intactos. Novo aceite completo ainda pendente.

- 23/11/2026:c0c47932/CI45117406905 aprovou2618Rails principais e232recargas, mas139/141concorrências passaram; duas falhas revelaram novo bloqueio da FKdo histórico na linha nativa de Account. Preparada referência técnica imutável, mantendo FKs/cascata e teste legado idêntico. Previstas38verificações do escopo e5concorrências; nenhuma aprovação inferida. Ver docs/jrc_contact_center/ending_scope_account_lock_findings_20261123.json.

- 23/11/2026:fb90991f/CI45122364380 preservada:236/238recargas e recibos das duas tabelas iguais. Corrigidos apenas defaultnil da PKtécnica e preparação do cenário de retirada: a exclusão nativa continua bloqueada com filas/unidades; o teste valida rollback e só depois remove seus registros sintéticos antes de comprovar a cascata. Os6casos/38exemplos e critérios permanecem obrigatórios; nova validação pendente.

- 23/11/2026: CI45122364380 final preservada (artefato14794932522/SHA25699440f9d...628a3):236/238recargas e3infrações Ruby novas. Corrigida a organização do helper concorrente e o alinhamento do fixture, sem retirar asserções ou modificar locks nativos. Correções de default e ciclo de conta seguem para revalidação real; nenhuma aceitação antecipada.

- 23/11/2026:21990ca9/CI45124532184 validada:2852Rails distintos +238recarga separados,1795Vue,260Chrome; zero falhas/pendências,584hashes e8capturas atuais abertas. Base de escopos aprovada, não a figura10inteira. Próximo incremento: versões privadas imutáveis na política ACW existente, cabeça pública apenas versão/nonce, 89casos nativos preparados +2de concorrência, sem API/editor/executor público; validação nativa ainda pendente.

- 23/11/2026:763ac60a/CI45133930374 reprovada antes dos testes nativos:47infrações Ruby preservadas no artefato14799223455. Preparadas correções focadas e decisão explícita de desativação: bloquear pendências antigas sem ressuscitá-las na reativação, preservando versões e concluídos. 102casos nativos focados +3de concorrência preparados;287Node/24Python e sintaxe YAML/28Bash/2Python aprovados, sem equivalência com Rails. Nova CI obrigatória, executor/editor e figura10 completos ainda pendentes. Ver docs/jrc_contact_center/ending_deactivation_decision_20261123.json.

- 23/11/2026:d026fe8a/CI45169703343 preservada:5infrações Ruby restantes, nenhum teste nativo executado. Corrigidos somente navegação segura, alinhamento exato e carregamento da dependência real no teste isolado ACW, sem retirar seus5casos. Mesmos102pré-testes e3concorrências obrigatórios; gates, migrations, SQLs, permissões e fornecedor intactos. Próxima CI ainda necessária. Ver docs/jrc_contact_center/ending_rule_versions_lint_followup_20261123.json.

- 23/11/2026:c8f2a0c5/CI45174140144:lint focado aprovado; instalação parou corretamente no hash do recibo da16ªmigration candidata. Log confirmou load_sources!:34. Corrigida somente a referência ao recibo, mantendo DDL/timestamp/SQL e15históricos. Regressão estática falhou antes e passou após;289Node/25Python e sintaxe YAML/28Bash/2Python aprovados. Uma linha em branco do teste isolado corrigida.102pré-testes/3concorrências e homologação real permanecem obrigatórios. Ver docs/jrc_contact_center/ending_rule_versions_source_pin_findings_20261123.json.

- 23/11/2026:50f50458/CI45177093066:instalação e recibos fresh/reload iguais;240/252recargas aprovadas, incluindo238anteriores. 12falhas novas:Current.set inexistente e preparação dos snapshots. Reutilizado NativeExecutionContext existente, sem alterar Current/helper/locks; comparação dos atributos persistidos e recarga após rollback corrigidas, mantendo verificações e102pré-testes/3concorrências. Lint final sem infrações novas. Correções ainda aguardam CI nativa; não conclui figura10. Ver docs/jrc_contact_center/ending_rule_versions_current_context_findings_20261123.json.

- 23/11/2026:a0c0dbc0/CI45185620677:250/252recargas aprovadas, incluindo238anteriores e10falhas de contexto corrigidas. Duas falhas restantes de preparação:materializar a elegibilidade sintética antes dos contadores e persistir a conta antes do savepoint revertido. Mantidas todas as verificações e252casos; acrescentada comparação integral da conta persistida após rollback. Sem alterações de produto, permissões, fábrica, migrations, SQL ou locks. Correções aguardam CI nativa; não conclui figura10. Ver docs/jrc_contact_center/ending_rule_versions_fixture_findings_20261123.json.

- 23/11/2026:39be8717/CI45188994956:252/252recargas,23confirmações,38escopos e100/102pré-testes aprovados;13autorizações de configuração e10bloqueios por histórico aprovados. Duas falhas reais de privacidade no SQL:logger do Rails7.1.5.2 filtra pelo Base e não pelo filtro inspect do modelo. Preparado initializer nativo com três nomes privados, preservando filtros existentes, logs úteis e testes reais; controle positivo do bind de conta acrescentado. Concorrência e regressão completa ainda não executadas; correção aguarda CI. Ver docs/jrc_contact_center/ending_rule_versions_sql_privacy_findings_20261123.json.


- [ ] **Rastreabilidade Word e editor de automações — 23/11/2026**: ambos os Word e suas23 figuras relidos; matriz por requisito em `docs/jrc_contact_center/word_traceability/index.json`. API/editor, modo explícito e correção mobile preparados sobre c5d69cee; aguardam CI própria,19 cenários Rails e264 Chrome. Não equivale ao executor ou ao aceite F10-A/B. Nenhuma migration/SQL alterada; main, checkout b77ffe55, três arquivos e ambientes preservados.


- [ ] **Primeiro gate do editor — 9a13e917**: CI45222369556 bloqueada por24 infrações Ruby, com0 exemplos Rails/Vue/Chrome executados. Correções de estrutura/alinhamento, conflito de código `__new__`, rascunho inativo e QA de tema preparados; nova CI exigirá20 pedidos nativos e264 execuções Chrome, sem reduzir os260 cenários anteriores. Relatório e SHA-256 preservados. Executor e aceite integral da figura10 continuam pendentes.


- [ ] **Alinhamento final do editor — 27d16e5b**: diagnóstico nativo reduziu24 infrações para2, ambas no mesmo argumento do teste. Somente espaços corrigidos nessa chamada; relatório final14845798014 e SHA-256 preservados. 0 cenários funcionais executados neste SHA. Verificador independente com13 casos leves de JSON aprovado, sem equivalência a Rails/Chrome. Aguardar CI própria com20 pedidos,260 cenários antigos e4 novos do editor.

- [ ] **Revisão real da API — f6119dc5**: lint sem novas infrações;252 recargas,23 confirmações,38 escopos e102 versões aprovados.19/20 pedidos do editor passaram; a reativação usou a revisão anterior à desativação e recebeu corretamente409. Preparado o uso da revisão devolvida pela API, mantendo422 e exigindo o erro específico do destino encerrado. Nenhuma regra de produção ou permissão alterada. Vue/Chrome e aceite do editor permanecem pendentes; artefato inicial14847539060/SHA256def45ed2…b8bdea8 preservado.


- 23/11/2026: editor de configuração8f362263/CI45237591913 aceito no escopo comprovado:2977Rails distintos,252recargas separados,1812Vue,264Chrome,592hashes e8capturas abertas. Figura10 permanece parcial; filtros mobile e campos superiores precisam de enquadramento adicional. Próximo incremento em trabalho: origem/conclusão nativas imutáveis, instalação prospectiva sem backfill nem ativação,33casos nativos e4concorrências reais preparados, ainda não executados. Nenhum efeito CRM/ServiceDesk/Projetos habilitado. Ver docs/jrc_contact_center/ending_editor_acceptance_20261123.json e ending_origin_candidate_20261123.json.

- 23/11/2026:d72549b0/CI45257934782 preservada como falha de lint:33infrações novas e0cenários funcionais executados. Preparadas correções de estilo, alinhamento e separação dos verificadores, sem retirar condições. A17ªmigration candidata mantém DDL/colunas/ordem; declaração de created_at separada e referências ao recibo atualizadas. Todos osSQLs e16históricos inalterados.6+57verificações estáticas e12regressões do coletor passaram; não são testes Rails. Mesmo33pré-testes e4concorrências obrigatórios; aguardar conclusão da CI antes do novo checkpoint. Ver docs/jrc_contact_center/ending_origin_lint_findings_20261123.json.

- 23/11/2026:1a3bb2b3/CI45261324311 reduziu33infrações novas para4, todas no nome/classe do teste de privacidade. Preparada renomeação revisada para ending_action_origin_privacy_spec.rb, descrição da classe e described_class, preservando os3cenários e todas as asserções. Workflow e coletor seguem exigindo os mesmos33casos; nenhuma migration,SQL,permissão ou regra de negócio alterada. Resta nova CI nativa após encerrar a atual. Ver docs/jrc_contact_center/ending_origin_remaining_lint_20261123.json.

- 23/11/2026:e9c54ed8/CI45264890513 aprovou lint e recibos idênticos de instalação/recarga, mas251/252testes existentes de recarga passaram. Um helper de DDL encontrou FK adiada com eventos pendentes. Preparada validação imediata somente dessa FK no helper transacional; mesmas252asserções e33pré-testes/4concorrências ainda obrigatórios. Nenhuma migration,SQL,recibo ou regra de runtime alterada. Ver docs/jrc_contact_center/ending_origin_reload_fixture_findings_20261123.json.

- 23/11/2026:151bf30d/CI45269263508 aprovou lint,252recargas anteriores e33novas de origem, com recibos estruturais iguais. Upgrade populado parou na comparação com snapshot de objetos ainda não relidos do banco. Preparada releitura antes da linha de base e uma regressão PostgreSQL adicional (34obrigatórias), sem reduzir a comparação de dados ou alterar migrations/SQL/permissões. Artefato final14864652722/SHA256b459bf40…01b03 e log sanitizado preservados. Upgrade completo,4concorrências e novas capturas Chrome continuam sem aceite. Ver docs/jrc_contact_center/ending_origin_upgrade_snapshot_findings_20261123.json.

- 23/11/2026: preparado incremento do contexto do agente original e das guardas do executor:13casos de autoridade/escopo, 7gatilhos nativos,6seleções de versão/desativação e3concorrências/contextos, ainda sem execução nativa. Não concede permissões, não ativa regras históricas e não executa efeitos nos destinos. CI45273757511 do incremento anterior deve concluir e ter artefatos verificados antes deste checkpoint. Requisitos F10-A/F10-B e executor completo seguem pendentes. Ver docs/jrc_contact_center/ending_executor_guard_candidate_20261123.json.

- 23/11/2026:dc9944c5/CI45273757511 aprovada e artefato14871192042 verificado pelo SHA2564a0a33b4…bc460: 3015Rails distintos,252recargas anteriores e34novas separadas,1812Vue,264Chrome e604hashes. Instalação,upgrade populado,recarga e4concorrências reais comprovados; linha de base agora relida do PostgreSQL. Aberta revisão real de16PNG. Aceite somente da base imutável de origem/conclusão, sem ativação nem efeitos. Detectado card de equipe mobile com texto comprimido apesar da CI verde; correção mínima e4provas geométricas preparadas para novaCI. Executor,recibos e campos de responsável ainda pendentes. Ver ending_origin_native_acceptance_20261123.json e ending_authority_mobile_visual_findings_20261123.json.

- 23/11/2026:ff05d569/CI45286393732 preservada como falha do gate inicial, antes deRails/Vue/Chrome. Causa: novo heredocPython sem-B; corrigida somente essa declaração, mantendo o verificador original e erro por artefato ausente. 7testes do gate e5blocosPython aprovados estaticamente;6mutações rejeitadas pelo verificador de preservação. Logs ehashes preservados; os29novos testes e o cardmobile aguardam novaCI. Base imutável dc9944c5 segue validada. Ver docs/jrc_contact_center/ending_executor_initial_gate_findings_20261123.json.

- 23/11/2026:4f3a41c8/CI45287983933 superou o gate inicial e encontrou9infrações novas no lint. Preparadas correções de complexidade por identidade composta/validação de escopo separada, navegação segura e organização dos testes. Todas as condições e29cenários mantidos; regras/limites/exclusões inalterados. Predicado conferido estaticamente em864combinações tipadas (nãoRSpec);2arquivosUI já formatados peloPrettier3.3.3/configuração nativa verificada. Artefato inicial14873131983/SHA2562930b4d3…a26d3d preservado. Nenhum cenárioRails/Vue/Chrome executado nessa tentativa; aguardar conclusão do diagnóstico atual antes do próximo checkpoint. Ver docs/jrc_contact_center/ending_executor_guard_lint_findings_20261123.json.

- 23/11/2026: preparado adaptador interno de tarefas de Projetos, reutilizando criação, autorização e auditoria nativas. Dezessete casos Rails preparados para permissões atuais, atribuição, projeto privado, WIP, datas estáveis, rollback e privacidade SQL/inspect. Ainda sem execução nativa deste incremento. Não instala dispatcher, ativação ou recibos; executor e figura 10 continuam parciais. CI mantém todos os gates anteriores e adiciona pré-validação própria; 29 testes leves do coletor não substituem Rails. Ver docs/jrc_contact_center/ending_project_destination_candidate_20261123.json.

- 23/11/2026: preparado registro técnico de ativação prospectiva, separado do salvamento da configuração, com carimbo/ator/fuso e limites de IDs gerados pelo PostgreSQL, herança somente de regra exatamente igual e barreira permanente de desativação. Migration18 aditiva; 28casos nativos,1upgrade populado M17 e3concorrências preparados, sem execução. Instalação,recarga eupgrade exigem recibos idênticos e zero regras armadas; 17casos do adaptador de Projetos também aguardam runner. Nenhum dispatcher, endpoint de ativação ou efeito automático instalado. Figura10/Parte1 permanecem parciais. Ver docs/jrc_contact_center/ending_readiness_candidate_20261123.json.

- 23/11/2026:4be94754/CI45290790691 aprovada e artefato14879673821 conferido: 3044Rails distintos,1812Vue,264Chrome e608hashes PNG;26guardas e3concorrências reais incluídas no total. Inspecionados6PNG originais; card longo e filtros mobile legíveis nos dois temas, sem sobreposição. Aceite restrito às guardas do ator/origem/gatilho e à correção mobile. O seletor de responsável de Projetos já existe; sua operação ainda exige evidência específica. Os49cenários seguintes de ativação/adaptador permanecem preparados, sem aceite. Executor completo,recibos eFigura10/Parte1 continuam parciais. Ver ending_executor_guard_native_acceptance_20261123.json.

- 23/11/2026:852d8760/CI45307382415 interrompida no lint, antes de Rails:27infrações novas. Artefato14882068237 verificado pelo SHA256fa3187f8…77d3b. Corrigidos alinhamentos, descrição/caminho do spec de upgrade e complexidade do predicado de schema, mantendo todas as verificações e49cenários. Migration18 candidata ainda não instalada recebeu apenas formatação e novos pins Ruby; SQL e17migrations anteriores preservados. 68testes estáticos de admissão e35do coletor aprovados; não substituem novaCI nativa. Ver ending_readiness_lint_correction_20261123.json.

- 24/11/2026:38b0b2db/CI45313705722 e artefato14887453199 verificados por SHA-256: 3092Rails distintos,1812Vue,264Chrome e608hashes PNG;10PNG originais abertos. Aceite restrito à ativação prospectiva interna (28casos+3concorrências),upgrade M17 separado (1caso,10registros preservados) e adaptador nativo Projetos (17casos). Instalação sem ativação nem efeitos. Recibos atômicos,dispatcher,ativação operacional,CRM/ServiceDesk eFigura10/Parte1 continuam pendentes. Ver ending_readiness_native_acceptance_20261124.json.

- 24/11/2026: candidato incremental do executor interno de Projetos com Task/Audit+recibo atômico; M19aditiva/sem hooks,19fontes protegidas e73verificações estáticas aprovadas. 23casos nativos preparados,nenhum executado nesta candidata. M18aceito em38b0b2db não é aceite deste executor. Ver ending_success_candidate_20261124.json.

- 24/11/2026:CI45330295404/5bc6959a teve3116Rails e1812Vue aprovados, masChrome260/264: o perfil sintético não possuía task.update exigido pelo alias nativo de atribuição. Corrigida somente a preparação explícita do teste, preservada a política real, adicionadas2regressões nativas e verificação antecipada de capacidade/membro nos4fluxos Chrome. Aceite completo ainda bloqueado; rascunho M20 permanece separado. Ver ending_assignee_alias_correction_20261124.json.

- 24/11/2026:56c29c3c/CI45345327177: lint antecipado identificou1RSpec/DescribeClass no teste novo. Corrigidos descrição/classe e caminho canônico, preservadas as2regressões e todas as assertivas; sem alterações de produto, permissões ou exclusões. Novo checkpoint aguarda término da CI ativa. Ver ending_assignee_alias_lint_followup_20261124.json.

- 24/11/2026: CI45347833396 encerrou com260Chrome aprovados/4falhas de QA: a verificação extra de Projetos leu capabilities fora do envelope HTTP data. Corrigida só a leitura do teste, com identidade do projeto, sem remover asserções, alterar permissões ou fontes funcionais. Revalidação integral obrigatória; figura10/Parte1 permanecem parciais. Ver ending_projects_response_envelope_qa_20261124.json.

- 24/11/2026:2c352573/CI45358578992: 3118Rails distintos,1812Vue,264Chrome e608hashes PNG verificados; executor interno Projetos com Task/auditoria/recibo atômicos,17cenários reais,7casos de schema eupgrade separado preservando14registros nativos. Deparse/reparse tipado corrigido sem normalizar recibos ou alterar M1–M18; seleção/persistência/reabertura do responsável comprovadas nos4projetos Chrome;10PNG originais abertos. Tentativas persistentes,dispatcher,ativação operacional,CRM/ServiceDesk eFigura10/Parte1 continuam pendentes. Ver ending_success_native_acceptance_20261124.json.

- 24/11/2026: sobre2c352573 nativamente aceito, preparado incremento M20 de tentativas/resultados imutáveis e acionamento por eventos nativos após commit;56novos cenários preparados, ainda sem execução nativa. Reutiliza executor e permissões originais; não ativa legado nem inventa parâmetros. Corrige também o título acessível do popup de automações observado na figura10, com um novo caso Vue e conferência Chrome preservada. Ativação/manual/UI,CRM/ServiceDesk eFigura10/Parte1 permanecem abertos. Ver ending_attempt_candidate_20261124.json.

- CI45374803728/3a05945a: preservado diagnóstico de48infrações Ruby em13arquivos doM20; corrigidos alinhamento,arrays,blocos e complexidade sem alterar gates,SQL ou permissões. Mantidos todos os cenários e asserções; imutabilidade continua testada por SQL real. Revalidação nativa pendente; nenhum teste ignorado foi considerado aprovado. Ver ending_attempt_block_style_qa_20261124.json.

- CI45379976587/102e368b: diagnóstico Ruby completo confirma48→1infração; preparada correção final deuma linha para manteryield direto eencaminhamento explícito dobloco. Regras,esquemas,permissões e testes preservados; revalidação nativa permanece pendente.

- CI45384095210/b2b568e6: relatório final confirma somente duas ocorrências de Naming/BlockForwarding; corrigidos os dois pontos com encaminhamento anônimo, preservando o caminho padrão, a autorização original, todas as asserções e os vinte esquemas históricos. Revalidação nativa do M20 continua obrigatória; os testes ignorados nesta execução não foram aprovados.

- M20/c79883dd/CI45407961337:3174Rails distintos,1813Vue,264Chrome e608PNG verificados; tentativas/resultados imutáveis, eventos nativos após commit e concorrência PostgreSQL aceitos no escopo interno Projetos. Ativação operacional,manual,CRM/ServiceDesk,broker real eParte1 continuam abertos. Ver ending_attempt_native_acceptance_20261124.json.

- ApósM20/c79883dd aceito: preparadoM21 com ativação explícita e consulta autenticada da revisão operacional;24novosRails/18novosVue/4novosChrome preparados, ainda sem aceite nativo. Mantidos os264Chrome anteriores;Figura10,manual,CRM/ServiceDesk ebroker real continuam abertos. Ver ending_activation_candidate_20261124.json.

- M21/b3117ee4/CI45446266789: ativação e consulta prospectiva explícitas validadas; 3198Rails distintos,1831Vue,268Chrome e620PNG verificados. Histórico operacional, execução manual, CRM/ServiceDesk, broker e Parte1 continuam abertos.

- ApósM21/b3117ee4 aceito: preparadoM22 com histórico operacional somente leitura,19novosRails/23novosVue/4novosChrome; sem aceite nativo ainda. Preservados os268Chrome anteriores e todos os recibos imutáveis. Execução manual,retry,CRM/ServiceDesk,broker real eParte1 continuam abertos.

- M22/95e10e8d:4infrações nativas de alinhamento corrigidas em3linhas de um spec; tokens/asserções/17cenários preservados. Acrescentado diagnóstico inicial de histórico; 19Rails/23Vue/272Chrome continuam exigidos. Sem aceite nativo ou visual deste incremento.

- M22/de57c426: Rails3217distintos,Vue1854 e recarga252 passaram; lintRuby618arquivos semnovasinfrações. Únicoerrofrontend no-plusplus corrigido por +=1 seguido dacaptura. O novoSHA exigiráCI e272cenáriosChrome completos; histórico ainda semaceite.

- M22/a90ab9d4:3217Rails e1854Vue passaram;270Chrome passaram e2falharam no contraste claro do estado bloqueado. Correção limitada ao texto amber12 no claro, preservando amber11 noescuro e4,5:1 nos testes. Captura de falha passa a ocorrer antes de fechar a página; todos os gates permanecem obrigatórios.

- M22/5040861f/CI45493347951: histórico operacional somente leitura validado; 3217Rails distintos,1854Vue,272Chrome e632PNG verificados. Manual/retry,CRM/ServiceDesk,broker real eParte1 permanecem abertos.

- ApósM22/5040861f aceito: preparadoM23 com3cenários reais deRedis/Sidekiq/PostgreSQL emrecursos próprios do runner; ainda não executados. Sem mudança funcional,grants oumigrations. Broker,PABX,CRM/ServiceDesk eParte1 ainda sem aceite integral.

- M23:CI45506197668 bloqueada por15infrações novas em2arquivos de teste do worker; preparada correção por extração de métodos/alinhamento, mantendo3exemplos e todasas proteções. Novo lint/broker nativo ainda não aprovado. HistóricoM22 preservado; Parte1aberta.

- M23/CI45510597893: lint focado corrigido eRails/concorrência anteriores passaram; primeiro caso real não chegou aoRedis porinterceptação doTestHelper. Preparada seleção doSidekiq somente paraoJob próprio apóssetup, comrestauração;3cenários preservados,ainda semaceite.

- M23/d7f17062/CI 45516626913: 3 cenários reais isolados de Redis/Sidekiq/PostgreSQL validados; 3220 Rails distintos, 1854 Vue, 272 Chrome e 632 PNG verificados. Execução manual/retry, CRM/Service Desk, recuperação operacional, PABX externo e Parte 1 permanecem abertos.

- Após o aceite da fila real em d7f17062: preparado bloco conjunto de operação selecionada, cliente original e adaptador CRM; 49 Rails, 15 Vue e 4 Chrome novos exigidos. Sem migrations, grants ou aceites intermediários simulados. Execução CRM/SD completa, F10-B e Parte 1 continuam abertos.

- CI 45530029703 bloqueou o bloco A por oito erros de preparação nativa e 16 infrações novas Ruby. Preparada correção mínima em nove arquivos, preservando 49 cenários, FKs, permissões e todos os gates. Nova execução nativa e Chrome ainda exigidos; sem aceite do incremento ou da Parte 1.

- CI 45534964667: 2925 Rails principais e 241 de concorrência passaram; o gate de execução selecionada parou antes dos 15 casos por duas infrações de linhas em branco. Correção preparada preservando todas as linhas executáveis, testes e gates. Aceite do bloco A e Parte 1 continuam abertos.

- Relatório final da CI 45534964667: sete infrações novas, incluindo as duas linhas em branco já tratadas, quatro alinhamentos de fixtures e uma associação ambígua do matcher. Correções mínimas preparadas em três arquivos Ruby, com os 49 cenários e gates preservados. Revalidação nativa e Chrome continuam obrigatórias; sem aceite do bloco A ou da Parte 1.

- CI 45540056856: 2925 Rails principais e 241 de concorrência passaram; lint focado corrigido. Dos 15 cenários selecionados, dois confundiram recusa anterior ao executor com recibo terminal de worker. Preparada correção somente dos testes: recusa permanente explícita, repetição segura e zero efeitos/alterações. Executor, SQL, gates e testes anteriores do worker preservados. Bloco A e Parte 1 ainda sem aceite.

- Relatório final 45540056856 preservado e verificado por SHA-256: 630 arquivos Ruby comparados, zero infrações novas. Falha restrita aos dois testes de pré-admissão; correção ainda requer nova CI. Frontend/Chrome ignorados não foram aprovados.

- CI 45544762024: 3269 exemplos operacionais Rails e 1869 Vue passaram; Chrome teve 273 aprovações e 3 falhas. Preparadas correção de contraste no popup escuro e sincronização com HTTP 201/identidade nativa da gravação de vínculo. Mesmo cenário extraído para preservar o limite de 400000 bytes, sem remover asserções ou aumentar timeouts. 276 cenários continuam obrigatórios; bloco A e Parte 1 ainda sem aceite.

- Bloco operacional A/28e0f440/CI 45558082951: 49 novos casos nativos verificados no mesmo SHA, 3269 Rails distintos, 1869 Vue, 276 Chrome e 644 PNG; 46 originais abertos. Sem aceites intermediários inventados. CRM completo, SD, F10-B e Parte 1 permanecem abertos.

- Bloco B após 28e0f440: adaptador Service Desk, entrega NICO prospectiva após commit e validação dos formatos de destino; 68 casos nativos novos e oito arquivos de regressão exigidos. Migration técnica vazia e sem backfill. Execução CRM/SD, recibos independentes, F10-B e Parte 1 ainda abertos.

- Após 28e0f440: agrupados adaptadores nativos Service Desk/atividade CRM/edição de chamado e formatos prospectivos para uma única CI, com os 142 cenários novos e regressões anteriores preservados. Sem aceites intermediários inventados; uma única migration técnica já auditada. Nenhum novo destino operacional habilitado. Recibos independentes, F10-B e Parte 1 permanecem abertos.

- Correção após bf8ad841: 39 infrações Ruby tratadas sem exclusões; admissão exata da migration NICO sem modificar M1–M20 nem o arquivo publicado. Conferência Chrome ampliada para exigir GET nativo e detalhe de tarefa carregado, sem alegar edição. 71 testes leves do gate aprovados; lint/Rails/Vue/Chrome desta correção aguardam CI. Os 554 requisitos, 142 cenários novos preparados e pendências F10-A/F10-B permanecem preservados.

- Após a4463ee9: corrigidos seis apontamentos restantes; o spec de esquema passou a ter nome compatível com RuleDefinition, preservando seus 13 cenários e corpos. Artefatos diagnósticos de fases diferentes agora têm nomes distintos, sem sobrescrever evidências. Lint ganhou progresso por arquivo; os sete testes originais e quatro regressões simuladas do procedimento passaram. A nova validação nativa permanece pendente.

- Correção após c737e863: a CI executou 3034 exemplos no núcleo e encontrou 13 falhas de fixture/asserção; a aprovação global permanece bloqueada. Descrições sintéticas foram acrescentadas aos chamados preparados e o rollback CRM passou a consultar registros realmente persistidos, incluindo auditoria. Verificações direcionadas de 24 casos e nove de concorrência precedem suas regressões completas; repetições não são contadas como casos novos. Nenhuma validação ou permissão de produção foi alterada.

- Correção do observador de concorrência após fc1ead7e: 3034 casos Rails e 24 direcionados passaram; um dos nove direcionados de concorrência falhou ao observar o segundo trabalhador. O teste passa a consultar os bloqueadores reais via pg_blocking_pids, exigindo bloqueio pela sessão observadora, inclusive após carregar um snapshot de atividade antes de iniciar os trabalhadores. Os seis cenários, asserções, prazos, locks e permissões do produto permanecem preservados; novo aceite nativo é obrigatório.

- A espera concorrente continuou falhando após 2cb42ad9; cache estatístico não foi confirmado como causa suficiente. O teste passa a registrar somente PIDs, estados, bloqueadores, contagens do pool e backtraces sem parâmetros; uma exceção já retornada pelo trabalhador é propagada imediatamente, preservando a fila de resultados. O mesmo bloco completo de concorrência é executado antes da regressão principal para produzir o diagnóstico mais cedo. Nenhum caso, asserção, timeout, lock ou validação foi removido. O aceite continua bloqueado.

- O diagnóstico nativo e99618db registrou o segundo worker 1345 bloqueado pelo primeiro 1344, com o observador 1343 ainda mantendo o lock. A condição anterior aceitava somente bloqueio direto. A observação passa a percorrer a cadeia viva de PIDs até a conexão proprietária exata, com UNION para limitar ciclos; um PID sem bloqueadores não passa. Os seis cenários, os dois backends, as asserções de efeito/auditoria e todos os timeouts foram preservados. A coleta limitada das stacks foi separada para corrigir a infração Metrics/AbcSize identificada, sem retirar dados do diagnóstico ou alterar configurações de lint. Não houve mudança em locks, permissões ou efeitos do produto; a correção ainda exige execução nativa.

- O bloco nativo de concorrência corrigido passou (9/0), assim como a regressão principal (3034/0). As regressões NICO/Service Desk tiveram 87 exemplos e duas falhas R15: a preparação não executava o SurveyClosureJob assíncrono responsável pela decisão que o teste precisava consultar. A preparação agora executa somente esse job real ao resolver/fechar o chamado R15, e repete explicitamente o job para verificar que não cria outra pesquisa. Não há mock do motor ou concessão nova. As duas contagens exatas dos eventos de criação foram reunidas em uma comparação agrupada equivalente para corrigir MultipleExpectations, preservando os predicados e timeouts. Dois relatórios NICO foram adicionados ao artefato de falha antecipado. A ordem com política NICO já publicada antes do fechamento continua exigindo um cenário nativo independente; não foi declarada homologada.
