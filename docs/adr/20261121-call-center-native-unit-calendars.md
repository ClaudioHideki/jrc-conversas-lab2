# Calendários internos por unidade com cálculo nativo

Data: 21/11/2026. Estado: implementação candidata; homologação nativa pendente.

A decisão confirmada pelo usuário aplica exceção explícita da data, depois feriado e depois expediente semanal, bloqueando sobreposições.

O catálogo reutiliza a unidade e o JSONB já existentes no Call Center. Não cria tabela paralela, Inbox artificial nem iguala IDs de unidades do Service Desk. WorkingHour pertence a Inbox e não representa múltiplos períodos ou exceções; os calendários de OLA são snapshots de outra autoridade. O cálculo e a validação continuam em SnapshotCalendar, com os auxiliares de formulário nativos.

Cada gravação reautoriza conta, usuário, perfil e cobertura corporativa depois de esperar o mutex de Account. A revisão é condição de estado, não autorização. O recibo é capturado dentro da mesma transação. O cabeçalho de escopo impede transferência silenciosa do catálogo; a API genérica de unidades não aceita sua substituição nem expõe seu conteúdo.

O popup exige revisão, preserva rascunhos em conflito e não repete automaticamente gravações incertas. A identidade de criação é mantida para recuperar um recibo idêntico. Datas e horários permanecem explícitos; classificar um feriado como fixo/móvel não inventa recorrência.

Não há publicação nem mudança de roteamento no PABX. Vínculos/impactos, recorrência, calendário deliberadamente fechado e confirmação externa permanecem registrados como pendências. O estado pending_contract da navegação é preservado.

Evidências e limitações: docs/jrc_contact_center/unit_calendars_prepared_20261121.json. Não representa conclusão das 23 figuras.
