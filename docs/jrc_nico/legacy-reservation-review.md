# NICO: revisão administrativa de reservas legadas

Procedimento por Account. Não modifica limites, não executa o runtime/provedor,
não envia mensagens, não apaga inferências e não libera desconhecidos automaticamente.
Disponível para administradores da própria conta, pela API autenticada existente.
Não existe rotina de liberação em lote nem interface gráfica nova nesta entrega.

## O que é legado

Inference/Run sem `accounting.version`. Versões novas, inclusive versões futuras,
não são revisáveis por este procedimento. Ausência de `dispatch_started_at`,
`usage_event_id` ou recibo NÃO comprova ausência de execução.

O relatório distingue reservas brutas de reservas efetivas: eventos NICO já
associados são contabilizados em `used_tokens` uma única vez e excluem o respectivo
hold efetivo. Eventos próximos no tempo ou encontrados por request ID são candidatos
para investigação; não são associados ou utilizados para liberar capacidade pelo GET.

## Os 33 registros informados da conta 1

Diagnóstico fornecido pelo administrador, não consultado nem modificado nesta entrega:
limite 2.000.000; consumo de outubro 487.149; reservas desconhecidas de outubro
1.442.906; reservas legadas totais 2.230.127; 33 registros. A diferença entre o total
e outubro exige revisar cada período separadamente. Não somar todos os períodos
ao limite de outubro. IDs 116 e 122 possuem histórico que deve ser preservado.

1. Após homologação e implantação manual autorizadas separadamente, um administrador
   autenticado solicita `GET /api/v1/accounts/ACCOUNT_ID/jrc_ai/legacy_reservations?period=2026-10`.
   Repetir para cada mês presente no inventário original. Nenhuma conta é fixa no código.
2. Guardar o JSON em local de acesso restrito. Conferir quantidade, IDs, mês de criação,
   status, reserva, eventos associados, candidatos e histórico, especialmente 116 e 122.
3. Investigar um registro de cada vez. Correlacionar Account, ID de inference/run,
   usuário, request ID (quando persistido), horários e recibos. Inferências antigas
   sem request ID podem não ser correlacionáveis com precisão; mantê-las desconhecidas.
4. Consultar os logs já disponíveis do runtime e os eventos já existentes em modo de
   leitura. Não repetir chamadas de IA para tentar descobrir se a chamada antiga ocorreu.
   Este recurso não consulta logs externos automaticamente: sem acesso/prova verificável,
   a classificação correta continua sendo `unknown`.
5. Criar uma evidência sanitizada, guardada fora do banco: Account/registro, fonte,
   horário, request ID, resultado observado e a justificativa para associar ou descartar
   cada candidato. Remover chave, Authorization, prompts, respostas, telefones e PII.
   Calcular SHA-256; enviar somente referência interna curta e digest à API.
6. Simular a decisão individual. Conferir os tokens novos/reutilizados, período,
   reserva resultante e classificação. O token assinado da simulação expira em 15 minutos.
7. Somente depois da revisão e da autorização explícita administrativa, aplicar
   exatamente a decisão simulada, com `authorized: true` booleano. Não executar todos
   os POSTs indiscriminadamente. Nova simulação após mudança de dados, eventos ou evidências.
8. Guardar o recibo; consultar novamente o relatório e o consumo. Conferir histórico
   anterior, novo ator, justificativa, evidências, request ID e resultado. Comparar
   `used_tokens + effective_legacy_reserved_tokens` no mesmo mês e conferir os outros
   holds não legados no endpoint de consumo/capacidade existente.

Para inventariar TODOS os meses dos 33 registros, se houver acesso administrativo
ao Rails, o seguinte trecho é exclusivamente de leitura. Substituir o identificador
de **AccountUser administrador**, não o User ID. A conta é obtida da associação,
não é fixada. Executar via `bundle exec rails runner` somente como diagnóstico
autorizado; este trecho não chama `reconcile`, não escreve e não libera reservas:

```ruby
member = AccountUser.find(ADMIN_ACCOUNT_USER_ID)
report = JrcNico::LegacyReservations.new(member: member)
periods = [JrcNico::Inference, JrcNico::Run].flat_map do |model|
  model.where(account: report.account).where("accounting ->> 'version' IS NULL")
       .where('reserved_tokens > 0').pluck(:created_at).map { |at| at.strftime('%Y-%m') }
end.uniq.sort
puts JSON.pretty_generate(periods.to_h { |period| [period, report.report(period: period)] })
```

O arquivo de diagnóstico contém histórico administrativo; guardá-lo com acesso
restrito. Conferir o total dos registros entre os meses contra o inventário de 33.
Nenhum comando de aplicação em lote acompanha o procedimento.

## Classificações e prova exigida

| Classificação | Fonte | Efeito autorizado |
|---|---|---|
| `confirmed` | `recorded_usage` | Reutiliza eventos existentes; não cria consumo duplicado. |
| `confirmed` | `external_receipt` | Registra tokens exatos de recibo externo revisado, na data da inferência; troca hold por consumo. |
| `estimated` | `recorded_usage` | Preserva o rótulo estimado dos eventos anteriores. |
| `estimated` | `conservative_estimate` | Estimativa explicitamente aprovada, rotulada; total deve ser pelo menos o hold anterior. Não reduz a cobertura desconhecida. |
| `not_executed` | `runtime_not_executed` | Exige evidência afirmativa de `not_dispatched` ou `rejected_before_provider`; ausência de recibo não serve. Libera somente o registro aprovado. |
| `unknown` | `investigation` | Registra a investigação, preserva integralmente a reserva. |

`external_receipt` e `runtime_not_executed` são atestações do administrador sobre
evidências verificadas externamente, não conclusões automaticamente comprovadas pelo
software. O digest registra a evidência; sua existência e conteúdo devem ser conferidos
pelo revisor. Recibos sem precisão ou logs incompletos não devem ser classificados como
confirmados/não executados. Estimativas novas não desbloqueiam capacidade por redução
arbitrária; o consumo estimado permanece visível.

## API individual

`POST /api/v1/accounts/ACCOUNT_ID/jrc_ai/legacy_reservations/inference/RECORD_ID/simulate`
(ou `run/RECORD_ID`). Exemplo de corpo de simulação desconhecida:

```json
{
  "decision": {
    "request_id": "UUID-V4-NOVO-POR-DECISAO",
    "fingerprint": "FINGERPRINT-DO-REGISTRO-NO-GET",
    "classification": "unknown",
    "source": "investigation",
    "justification": "Investigação individual concluída sem prova suficiente do consumo.",
    "excluded_usage_event_ids": [],
    "evidence": [{ "reference": "investigacao-local-116", "sha256": "SHA256-DA-EVIDENCIA-SANITIZADA" }]
  }
}
```

Para reutilizar recibos: `source=recorded_usage`, `usage_event_ids=[IDs revisados]`,
classificação `confirmed` ou `estimated` coerente com os eventos. Incluir TODOS os eventos
já associados. Eventos devem pertencer à Account, agente/feature NICO e mês corretos;
não podem estar vinculados a outro run/inference. Associação manual de eventos sem vínculo
exige também o usuário correto. Metadados originais são preservados.

Para consumo externo: `source=external_receipt`, `classification=confirmed`,
`provider_id` daquela Account, `model`, `usage={input_tokens,output_tokens,total_tokens}`.
Total positivo, inteiros até 270.000, total igual à soma. Para estimativa nova:
`source=conservative_estimate`, `classification=estimated`, mesmos campos e
`conservative_upper_bound=true`; total não inferior ao hold.

Para não execução: `source=runtime_not_executed`, `classification=not_executed`,
`runtime_outcome=not_dispatched|rejected_before_provider`, com evidência afirmativa.

Fora de `recorded_usage`, `excluded_usage_event_ids` deve listar exatamente todos
os candidatos examinados e descartados; explicar os motivos na evidência. Candidato
com o request ID exato persistido exige associação, não pode ser descartado para
criar outro consumo ou declarar não execução.

Aplicação: `POST .../reconcile` recebe `decision` IDÊNTICA, `authorized: true` e
`simulation_token` devolvido por simulate. Repetição idêntica do mesmo request ID/ator
retorna o recibo original, sem nova auditoria/consumo. Reutilização do UUID para outra
decisão/registro/ator é rejeitada. Ator desautorizado não pode reaplicar nem recuperar
recibos administrativos. Decisões desconhecidas podem ser revisadas novamente com nova
evidência e UUID. Uma decisão já encerrada não pode ser reinterpretada por esta API;
eventual ajuste de estimativa exige procedimento contábil separado e nova autorização.

Conflitos HTTP 409 exigem consultar novamente e simular novamente. Dados inválidos:
HTTP 422 sanitizado. Sem permissão: rejeição pelo contrato de autorização existente.
Account e registros estrangeiros não ficam acessíveis.

## Segurança operacional

Locks na ordem Account → AccountUser → registro → eventos, autorização atualizada sob
lock, simulação assinada vinculada à decisão e estado dos eventos, transação única,
journal append-only/idempotente nos campos existentes. Mantém os históricos e não
atribui `accounting.version=1` artificialmente aos legados.
Nenhuma migration, alteração de limites, provider, Runtime, Compose ou configuração.
As novas inferências continuam no ReservationLedger/ReservationReconciler existentes.

Não executar qualquer conciliação no servidor como parte da publicação da candidata.
Primeiro homologar com dados descartáveis. Esta entrega não declara os 33 registros
reconciliados e não declara R3/R4/R5 homologadas; R6 e produção permanecem pendentes.
