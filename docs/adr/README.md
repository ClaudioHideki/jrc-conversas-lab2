<!-- jrc-operational-init:v1 -->
# Registro de decisões arquiteturais

Use [0000-template.md](0000-template.md) para uma decisão relevante. Numere pela próxima sequência livre, registre contexto, decisão, consequências e evidências. Estados: Proposta, Aceita, Rejeitada ou Depreciada.

Não marcar uma proposta como aceita sem a decisão correspondente. Preserve os documentos anteriores; para alterar uma decisão aceita, escreva uma nova que indique qual decisão substitui.

## Decisões deste bootstrap

- [0001-governanca-operacional-init](0001-governanca-operacional-init.md): adoção do INIT solicitado pelo usuário.

- [20261117-call-center-role-revision](20261117-call-center-role-revision.md): precondição aditiva, conflito 409, recuperação explícita do rascunho e compatibilidade dos clientes nativos.

- [20261117-call-center-configuration-audit](20261117-call-center-configuration-audit.md): trilha sanitizada, leitura por cobertura e revalidação transacional das escritas.

- [20261117-call-center-configuration-revision](20261117-call-center-configuration-revision.md): revisão de estado opt-in, recarga autorizada e revisão explícita do rascunho.

- [20261117-call-center-native-profile-preservation](20261117-call-center-native-profile-preservation.md): omissão de perfil em PATCH preserva o vínculo e as permissões existentes.

- [Call Center: retirada de perfil sem aumento implícito](20261117-call-center-native-role-fallback.md).

- [Call Center: herança por equipe e elegibilidade](20261117-call-center-team-inheritance-and-eligibility.md).

- [Call Center: reautorização após locks administrativos](20261117-call-center-final-write-authorization.md).

- [Call Center: concessões latentes e dependências](20261117-call-center-latent-permission-effects.md).

- [Permissões efetivas CC no perfil autenticado](20261117-call-center-authenticated-permissions.md): reuso da política nativa nos consumidores de navegação.
- [Painel técnico PABX nativo](20261117-call-center-pabx-native-tabs.md): agrupamento sem outro conector, fronteiras de formulário e limites externos.
- [Supervisor e fontes observadas](20261117-call-center-observed-supervisor.md): ausência de dados não é zero nem referência visual operacional.

- [Rascunhos locais de URA](20261117-call-center-local-ivr-drafts.md): grafo interno versionado, simulação sem fornecedor e limites antes da persistência/API/editor.

- [Ordem das observações do supervisor](20261118-call-center-supervisor-observation-order.md): polling serial, fronteira de ator/perfil e descarte de dados após recusa.
- [Fontes corporativas atuais das equipes](20261118-call-center-current-team-corporate-sources.md): revogação efetiva, reinclusão autorizada e coordenação com os locks nativos.
- [Observações e autoridade atual](20261118-call-center-observation-write-authority.md): reautorização após locks, atribuição e histórico transacional preservados.
- [Atividade administrativa recente](20261118-call-center-recent-administrative-activity.md): reuso da API, popup e histórico nativos na página inicial, com fronteira autenticada.

- [Auditoria nativa da política global de pós-atendimento](20261118-call-center-acw-policy-native-audit.md) — figuras 9/14, incremento preparado; exige CI e não altera a política nativa.

- [Contato 360º nativo por chamada vinculada](20261118-call-center-linked-customer-master.md) — figura 21 parcial, implementação preparada; exige gate nativo e 116 cenários de navegador.

- [2026-11-18 — Revisão esperada global ACW nos dois clientes nativos](20261118-call-center-global-acw-revision.md) — preparado; CI/Chrome próprios pendentes, compatibilidade da API explicitada.

- [Autoridade atual nas escritas operacionais](20261118-call-center-operating-write-authority.md): lock nativo, histórico transacional e QA responsivo, aguardando CI própria.

- [Origem operacional e visibilidade nativa](20261118-call-center-operating-origins.md): reuso de escopos sem ampliação de acesso e prova em banco descartável.

- [Retirada indireta pela composição da equipe](20261118-call-center-indirect-team-withdrawal.md): prévia sem escrita, revisão explícita do gestor e auditoria transacional; implementação preparada, aguardando CI própria.

- [Relógio ACW e leituras antigas](20261119-call-center-acw-clock-stale-read.md): atualização condicional no banco preserva conclusão, limite atual e proprietário; sete testes nativos preparados, validação pendente.
