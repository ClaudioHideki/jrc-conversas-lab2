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
