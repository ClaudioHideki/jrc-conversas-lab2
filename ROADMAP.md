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
