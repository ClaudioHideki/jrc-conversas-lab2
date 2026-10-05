# BUG CRM-PROP-ACCEPT-01 — Aceite digital da proposta

## Severidade
Bloqueante para o fluxo comercial `Proposta → Pedido → Contrato`.

## Cenário reproduzido
- proposta enviada;
- acesso pelo link público;
- preenchimento dos dados do signatário;
- tentativa de aceite.

## Causas identificadas
1. O formulário HTML público usava grade `nome | documento | botão` dentro de uma área comprimida pela coluna lateral de ações. Em larguras menores o submit podia ser reduzido visualmente até exibir apenas parte do texto.
2. Os dois endpoints públicos validavam apenas presença de nome/documento. Não havia validação real de CPF/CNPJ nem consentimento explícito dos termos.
3. O frontend Vue não enviava confirmação dos termos e a recusa não possuía um fluxo equivalente ao formulário público clássico.
4. Quando o aceite era persistido e o pós-aceite falhava ao gerar o Pedido, a mensagem não diferenciava claramente aceite concluído de falha do ciclo comercial.

## Correção aplicada
- layout do aceite passou para bloco próprio e responsivo;
- campos obrigatórios: Nome completo e CPF/CNPJ;
- checkbox obrigatório: `Li e aceito os termos desta proposta`;
- botão visível e não truncável `Aceitar proposta`;
- ação secundária `Solicitar alteração / Recusar` com motivo;
- novo `JrcCrm::ProposalAcceptanceService` centraliza validação e persistência;
- CPF/CNPJ validado por `JrcCustomers::TaxIdentifier` e salvo normalizado;
- evidências preservadas: nome, documento, data/hora, IP e user-agent;
- evento de aceite registra consentimento e origem;
- após o aceite é executado `AcceptedProposalLifecycleService`, mantendo a geração/reutilização idempotente de Pedido;
- se o aceite for salvo mas a geração do Pedido falhar, a interface informa explicitamente que a proposta está aceita e que o Pedido precisa de revisão no CRM;
- API JSON retorna erros específicos em vez de uma mensagem genérica.

## Critérios de homologação
1. Link público desktop e mobile mostra o botão completo `Aceitar proposta`.
2. Nome vazio bloqueia e informa o motivo.
3. CPF/CNPJ vazio bloqueia e informa o motivo.
4. CPF/CNPJ inválido bloqueia e informa `CPF ou CNPJ inválido`.
5. Checkbox não marcado bloqueia e informa o motivo.
6. CPF ou CNPJ válido + checkbox marcado aceita a proposta.
7. Após sucesso, status = `accepted`/`Aceita`.
8. Banco registra `accepted_by_name`, `accepted_by_document`, `accepted_at`, `accepted_from_ip`, `accepted_user_agent`.
9. Evento `accepted` contém `terms_accepted=true` para link público.
10. O pós-aceite cria ou reutiliza um único Pedido; nunca duplica em replay.
11. Se o ciclo de Pedido falhar, o aceite não é perdido e o erro operacional fica visível.
12. `Solicitar alteração / Recusar` grava o motivo e muda o status conforme a regra existente.

## Validações ainda exigidas no LAB
- RSpec completo;
- teste browser desktop/mobile;
- build Vue/Vite;
- teste real do link público com CPF e CNPJ válidos;
- confirmação da criação do Pedido após aceite;
- confirmação do Pedido no fluxo de Contrato.
