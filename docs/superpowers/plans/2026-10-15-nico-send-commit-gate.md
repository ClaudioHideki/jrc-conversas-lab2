# Envio NICO — plano focal de commit e ciclo de vida

Execução inline com TDD. [Desenho aprovado](../specs/2026-10-15-nico-send-commit-gate-design.md). Rails/PostgreSQL real em laboratório sintético; sem novos agentes, commit, push ou suíte total.

## Escopo

Novo Gate, BrokerSendJob, BrokerSendOperation, Cancellation, Command dependency, Coordinator recipient, Context keyword actor_id interno, migration candidata 20261015130000 e novo spec focal. Controllers/OperationalAccess/EE não mudam. Guard opt-in restrito ao DB novo jrc_nico_gate_test; DB principal do laboratório preservado.

- [x] Revisar controllers de AccountUser/InboxMember/TeamMember/CustomRole e Devise confirmable.
- [x] Verificar cascades User → Session → Command → operação e rota contact_inbox_id/source_id.
- [x] Registrar desenho e plano antes de produto.
- [x] Escrever regressões no novo spec com fixtures committed e conexões separadas.
- [x] Copiar somente o spec para volume baseline, confirmar migration candidata, preparar DB novo e observar RED real.
- [x] Confirmar migration original no volume e preparar DB novo. RED real no primeiro caso do spec, linha86: esperava0 Messages durante revogação de role aberta em outra conexão, recebeu1. Os outros dez casos pararam em fixture e não são contabilizados como RED semântico.
- [x] Implementar Gate NOWAIT/uncached e hook de commit, com contenção conservadora.
- [x] Observar RED dos cinco casos de rota/ledger: alteração de rota aceita, ledger destruído por Command/User e campo do fato ausente. Log `nico-ledger-route-red.log`, 5 exemplos/5 falhas semânticas.
- [x] Fixar rota da prévia, incluindo contact_inbox_id e digest de source_id.
- [x] Tornar ledger independente de Command/User, registrar actor_id e fato irreversível da Message com proteção no banco.
- [x] Suportar cancel-only para órfã sem Message e HALTED/reconciliação conservadora após Message.
- [x] Verificar focais novos; regressão coordenada anterior permanece na consolidação/CI, sem repetir suíte total.
- [ ] RuboCop focal, hashes fonte/volume e diffcheck; atualizar evidência e entregar ao coordenador.

Gate18 confirmado pelo coordenador em `nico-gate-root-final.log`: **18 exemplos, 0 falhas**, 54,27 s de exemplos + 19,48 s de boot, exit0. A migração revisada foi aplicada somente a jrc_nico_gate_test. Esta rodada usou o corte NICO anterior à composição de OwnershipHooks; validação final da árvore completa permanece na CI/consolidação.

- [x] Comprovar RED dos cinco drifts e corrigir comparação de Integration/Binding; corrigir NULLIFY de Command.
- [x] Verificar Gate18 corrigido em PostgreSQL real, incluindo idle de transações ao devolver conexões.
- [x] Confirmar por fonte os gaps posteriores de identidade Inbox e fallback NativeBinding.
- [x] Preparar `spec/services/jrc_nico/broker_send_coordinator_binding_scope_spec.rb` separado com oito regressões.
- [x] Observar RED separado, corrigir pin de Inbox e recusa de fallback público nativo, verificar GREEN focal.

RED8 observado pelo coordenador no volume anterior: **8 exemplos, 6 falhas funcionais e 2 controles preservados**, sem erros de carga, em `nico-native-binding-red.log`. O bootstrap adicionou somente os dois models nativos e a migration existente `20261009180000` ao DB isolado. A rodada adicional confirmou **4 exemplos, 4 falhas funcionais** em `nico-native-control-red2.log`: BROKER/CENTRAL não preparavam operação e as divergências de channel/credentialRevision eram aceitas. O contrato `0062` já é genérico, portanto o complemento fica restrito ao resolver local, locks/pins, guard da ferramenta e CI focal.

GREEN conjunto confirmado pelo coordenador em `nico-native-gate-green.log`: **30 exemplos, 0 falhas**, 88,22 s de exemplos + 20,78 s de boot, exit0, no DB isolado `jrc_nico_gate_test`. Inclui Gate18 e Binding12, com BROKER_TRANSPORT/CENTRAL_TRANSPORT coordenados pelo controle de Account sem criar binding QR. O workflow inclui o novo spec e lint do resolver/spec, mínimo150 exemplos e nenhum pending. RuboCop final e regressão da árvore composta permanecem na consolidação do coordenador.

As corridas devem observar lock wait/commit reais; sleeps não são prova. Todas as transações de teste terminam e threads são liberadas no ensure. Logs/SCHEMA ficam no scratch do laboratório, fora do produto.

Base RED do volume: Job SHA-256 `89424fb80505954bcafd0a778306191ff4659d6af36b4137a3a4f02c0589d71b`; migration SHA-256 `5425bd1214f9793e1f0f8856a140aee13e73b45c0804bf3d3645b7c7312c1397`. A limpeza de fixtures foi corrigida somente no spec opt-in: todas as tabelas de aplicação do DB estrito são truncadas, pois AccountUser não possui FK que permita depender apenas de TRUNCATE accounts/users CASCADE. Cache de queries é limpo antes/depois; factory e guard globais permanecem iguais.
