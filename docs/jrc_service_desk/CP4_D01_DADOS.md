# Dados adicionais CP4-D01 (registro anterior ao codigo)

Toda tabela nova possui account_id, unit_id obrigatorios, IDs bigint, timestamps,
FK account/unidade e indices compostos no padrao CP2. Nao ha tenant/RBAC paralelo.
Somente tabelas e colunas novas; zero edicao de schema.rb/migrations anteriores.

| Tabela jrc_service_desk_ | Finalidade | Colunas adicionais | FKs/relacoes | Indices/justificativa |
|---|---|---|---|---|
| services | Identidade minima de servico operacional por unidade, sem contrato/financeiro/catalogo completo | code, name, active | unit | account/unit/code unico; ref account/unit/id |
| lifecycle_policies | Referencia configuravel unidade/servico | service_id opcional, name, enabled false, current_version_id, lock_version | service e versao atual da propria politica | unicos parciais com/sem servico; ref composta |
| lifecycle_policy_versions | Regras imutaveis do dominio | lifecycle_policy_id, version, definition JSON, digest, actor_membership_id | politica da unidade, autor | politica/version unico; ref account/unit/policy/id |
| lifecycle_transitions | Comando/evento persistente append-only | ticket, versao, actor, action, rule_key, from_status_id, to_status_id, occurred_at, payload JSON, request_key, fingerprint | ticket, versao, ator, status na unidade | deduplicacao ticket/actor/key; timeline; ref ticket/id |
| sla_cycles | Identidade do ciclo medido, nao copia do contrato | ticket, versao, snapshot, number, started_at | snapshot do MESMO ticket | ticket/number unico; ref account/unit/ticket/id |
| sla_clocks | Execucao de um relogio em um ciclo | ticket, cycle, kind, state, budget_seconds, elapsed_seconds, anchor_at, due_at, achieved_at, calculator_version, lock_version | ciclo do MESMO ticket | cycle/kind unico; ref e prazos |
| lifecycle_pauses | Intervalo explicito de pausa (inclusive motivo que nao pausa relogios) | ticket, versao, cycle opcional, reason_code, clocks JSON, started_at, ended_at, started_by/ended_by, lock_version | ticket, ciclo, versao e atores | uma pausa aberta por ticket; timeline |

Tickets recebem service_id opcional (ausencia real de servico usa politica da unidade),
e lifecycle_policy_version_id opcional para tickets legados/sem politica. Unidade continua
NOT NULL; operadora derivada; essas colunas nao permitem autoconcessao ou mudar unidade.
A versao e fixada uma vez. As FKs compostas impedem referencias entre contas/unidades,
e ciclos/snapshots/pausas de outro ticket. Regras JSON sao estritamente validadas no dominio.

SlaMilestone anterior e preservado como registro vinculado ao snapshot. Os novos relogios
representam execucao por ciclo: o indice anterior snapshot/kind nao comporta reabertura
com novo ciclo usando o mesmo snapshot. Nao apagar/reutilizar essa semantica. A API lifecycle
identifica separadamente snapshot, ciclo e relogios atuais; marcos anteriores nao sao
reescritos nem apresentados como medidas do ciclo novo.

Rollback so com todas as tabelas novas vazias e nenhum ticket com referencias novas;
recusa antes de qualquer remocao se houver dados. Execucao real pendente.

## Conferencia pos-implementacao

A migration nova e `20260928120000_add_jrc_service_desk_lifecycle.rb`. Gravacao isolada das
declaracoes: 7 tabelas, 19 indices, 34 FKs, 7 CHECKs e 2 colunas adicionais em tickets.
Nenhuma migration aplicada aqui. Tabelas nativas nao recebem novas colunas/indices nesta rodada.
Versoes incluem tambem status_phases (semantica do estado congelada) e publication (nome,
enabled e service_id na publicacao); ambos compoem o digest. Pausa tem CHECK de pares
ended_at/ended_by com NULLs equivalentes; fim so e aceito junto com ator e depois do inicio.
Due_at dos clocks reais e NOT NULL; nao fabricar relogio sem prazo calculavel.
