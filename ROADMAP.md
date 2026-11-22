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
