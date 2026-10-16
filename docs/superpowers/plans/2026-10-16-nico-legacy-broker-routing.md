# Plano: coordenação de caixas Broker legadas

Spec: `../specs/2026-10-16-nico-legacy-broker-routing-design.md`. Execução inline autorizada no programa; somente candidata local, sem push/imagem/bot ativo.

- [x] RED em `spec/services/jrc_nico/broker_send_coordinator_binding_scope_spec.rb`: rota canônica sem registro não permite envio público; aprovação antiga revalidada; nota privada preservada.
- [x] Implementar detecção local em `app/services/jrc_nico/broker_send_binding.rb`, reutilizada pelos dois pontos de resolução atuais; não conceder autoridade nem consultar rede.
- [x] Regressões: caixas comuns, registros nativos, QR, Account e mudança de origem; adoção administrativa existente restaura o caminho coordenado.
- [x] RSpec/lint focal e revisão final; evidência em `docs/validation/2026-10-16-nico-legacy-broker-routing.md`. 20 bindings, 20 OperatorSession e 18 concorrência aprovados. Sem publicação até fechamento geral.
