# Plano: radar de atendimento do NICO

Spec: `../specs/2026-10-16-nico-conversation-radar-design.md`. Execução inline autorizada, candidata local, sem publicação/ativação.

- [x] Escrever RED em `spec/services/jrc_nico/conversation_radar_spec.rb`, pela ToolExecutor: regras de espera, agente/bot, atividade, status encerrado, isolamento e total além da amostra.
- [x] Implementar `app/services/jrc_nico/conversation_radar.rb`; integrar DomainToolCatalog, DomainActions e resumo legível em OperatorSession. Manter comando de consulta interno.
- [x] Validar inbox_id/page, revogação e origem de cliente; conferir mecanismo de proveniência do histórico.
- [x] RSpec focal e regressões NICO (43), lint, revisão final e evidência local em `docs/validation/2026-10-16-nico-conversation-radar.md`. Nenhum push/imagem/servidor.

Ruling de revisão: dois achados Important reproduzidos em RED. Substituir resource refs Conversation pelos display IDs nativos de sessão; corrigir a divergência de custom role no filtro compartilhado Enterprise. Acrescentar regressões do filtro nativo e preservar administrador com conversation_manage. Não adicionar dependência do módulo Relacionamento ao radar.

Ruling da base 98a4be7: OperationalContext permite administrador nativo sem custom role ler unidades autorizadas pela cobertura corporativa, mesmo sem UnitMembership; executores automáticos têm verificação operacional separada. O teste NICO antigo supunha revogação da unidade também para esse administrador manual. Alinhar sua restrição a um papel operacional personalizado e acrescentar caso positivo de administrador nativo + revogação do módulo. Nenhuma policy do Service Desk foi alterada para satisfazer o teste.
