# Homologação — CRM-PROP-ACCEPT-01

## CT-01 — Renderização
Abrir uma proposta `sent`/`viewed` pelo link público.

Esperado:
- Nome completo;
- CPF/CNPJ;
- checkbox de termos;
- botão `Aceitar proposta` inteiro;
- botão `Solicitar alteração / Recusar`.

Executar em desktop e viewport mobile.

## CT-02 — Campos obrigatórios
Tentar aceitar sem nome, sem documento e sem checkbox, um caso por vez.

Esperado: cada tentativa deve informar exatamente o campo/consentimento faltante e não mudar o status.

## CT-03 — Documento inválido
Usar CPF/CNPJ com dígitos verificadores inválidos.

Esperado: HTTP 422/API ou renderização do formulário com `CPF ou CNPJ inválido. Confira o documento informado.`.

## CT-04 — Aceite válido
Usar dados de teste permitidos no LAB e marcar o checkbox.

Esperado:
- status `Aceita`;
- nome/documento normalizado registrados;
- `accepted_at` preenchido;
- IP/user-agent registrados;
- evento `accepted` criado com consentimento;
- mensagem de sucesso clara.

## CT-05 — Pedido pós-aceite
Após CT-04, abrir CRM → Pedidos.

Esperado: existe exatamente um Pedido associado à mesma Proposta/Negócio/Cliente, ou o frontend mostra explicitamente o erro de ciclo caso a criação falhe.

## CT-06 — Idempotência
Repetir a chamada de aceite de uma proposta já aceita.

Esperado: não criar segundo Pedido; reutilizar o ciclo já existente.

## CT-07 — Recusa/alteração
Usar `Solicitar alteração / Recusar`, informar um motivo e confirmar.

Esperado: motivo registrado no evento e status atualizado conforme a regra do módulo.
