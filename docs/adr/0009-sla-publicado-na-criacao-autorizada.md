# 0009 — Aplicação do SLA publicado durante a criação autorizada

Data: 2026-11-23. Escopo: correção local, sem publicação ou implantação.

## Evidência

O diagnóstico de produção fornecido pelo operador confirma criação autorizada,
catálogo sem restrições comerciais, ausência de captura NICO publicada e regra
`sla_selection` ativa. O agente não possui `sla_snapshots_record`.

A reprodução isolada pela API autenticada, com um serviço aberto e uma regra
genérica publicada, retorna 403 com o destinatário padrão e com seleção explícita.
Um TracePoint restrito à classe da exceção identifica
`IntakeRuleApplication#record_sla!`, linha 28 da base b6cfb57. A exigência de
permissão manual acontece depois de salvar o ticket, dentro da transação.

## Decisão

- A criação continua exigindo identidade autenticada, permissão de criação,
  conta/unidade autorizadas, catálogo válido, destinatário elegível e supervisão.
- Aplicar condições exclusivamente da regra publicada, selecionada no servidor,
  com digest e referências conferidos, integra essa criação autorizada.
  Essa aplicação não depende de permissão para fornecer condições manuais.
- Compartilhar somente a persistência de snapshot, marcos e evento de auditoria
  em `SlaSnapshotWriter`. Seus dois chamadores continuam dentro das transações
  e bloqueios de unidade dos comandos autorizados. Não há endpoint novo.
- `RecordSlaSnapshotService`, seu endpoint e `SlaSnapshotPolicy#create?` mantêm
  a autorização para gravação manual. Não adicionar permissões ao agente.
- Conservar calendário, budgets, política de ciclo de vida, relógios, versionamento,
  auditoria e proteção de replay. Não substituir SLA ausente/inválido por sucesso.
- Um 403 de escrita informa recusa local e preserva contexto e rascunho.
  Um 401 continua encerrando a sessão; as negações nas leituras continuam limpando
  dados protegidos. Um resultado aceito sem leitura confirmada continua pendente.
- A confirmação de destinatário explícito compara a pessoa persistida, sem exigir
  a fila legada quando o servidor autorizou outro destino na mesma unidade.
- Na abertura interna, a fila padrão do serviço não é uma referência intermediária
  obrigatória: `InternalIntake.apply!` resolve a fila/equipe do destino selecionado.
  Isso evita recusar um destinatário válido por uma fila padrão inativa que seria
  substituída. As demais aberturas conservam os padrões de catálogo anteriores.
- A seleção interna também exige a autenticação nativa ativa do destinatário,
  conferida novamente no servidor. Vínculo, conta/unidade, autorização de
  atribuição manual, equipe e supervisão continuam exigidos. Não há exceção por
  nome ou ID de usuário, nem mudança nas permissões das demais operações.

## Limites

A reprodução usa dados sintéticos, não o banco produtivo. O diagnóstico de
produção foi fornecido pelo operador; o rastreamento de exceção foi feito apenas
no teste local. Nenhum contato, usuário ou chamado produtivo foi alterado.
Push, merge, publicação de imagem e deploy exigem nova autorização.
Aceite operacional na sessão do usuário permanece posterior à homologação.
