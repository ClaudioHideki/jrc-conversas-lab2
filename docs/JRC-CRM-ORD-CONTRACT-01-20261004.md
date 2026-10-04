# CRM-ORD-CONTRACT-01 — Pedido/Venda de origem vazio no Contrato

Data: 2026-10-04
Prioridade: Bloqueante
Status do código: correção candidata para homologação

## Sintoma

Ao criar um Contrato, o campo **Pedido / Venda de origem** podia aparecer vazio mesmo após o aceite de uma proposta. Isso interrompia a jornada:

`Negócio → Proposta → Aceite → Pedido → Contrato`

## Causa funcional encontrada

O aceite da proposta preserva corretamente a evidência comercial mesmo quando uma etapa posterior do lifecycle falha. Nessa situação a proposta pode ficar `accepted`, mas o Pedido pode não existir. A tela de Contrato consultava somente a listagem genérica de Pedidos e não distinguia:

- pedido elegível para contrato;
- pedido existente aguardando aprovação;
- proposta aceita sem pedido;
- pedido que já possui contrato.

O resultado era um combo vazio sem diagnóstico nem ação de recuperação.

## Correção

Foi criado o endpoint de leitura:

`GET /api/v1/accounts/:account_id/crm/contracts/order_options`

Ele retorna quatro grupos:

1. `eligible_orders`: pedidos nos estados `approved`, `separating`, `invoiced`, `shipped` ou `completed` e sem contrato principal;
2. `awaiting_approval`: pedidos `draft` ou `pending`;
3. `accepted_proposals_without_order`: propostas `accepted` sem Pedido ativo;
4. `already_contracted`: pedidos que já possuem contrato principal.

A tela **Novo contrato** passou a mostrar esses estados separadamente.

Para uma proposta aceita sem Pedido, existe a ação explícita **Criar/Reparar pedido**, que reutiliza o fluxo oficial `ProposalToOrderService`. A operação é idempotente e não deve duplicar um Pedido já existente.

Após o reparo, o Pedido continua respeitando o gate comercial: ele fica pendente até ser aprovado. Só então poderá originar um Contrato.

## Proteções de backend

A criação de Contrato agora também valida no servidor:

- Pedido precisa estar em estado elegível para Contrato;
- um Pedido não pode gerar um segundo Contrato principal;
- o vínculo do Contrato continua herdando Cliente, Negócio, responsável e unidade do Pedido.

Portanto, a regra não depende apenas do frontend.

## Identificação no combo

Pedidos elegíveis são apresentados com contexto comercial suficiente:

`PED-... — Cliente/Empresa — Negócio/Venda direta — Valor`

## Roteiro de homologação Nexora

1. Usar uma proposta aceita da Nexora sem Pedido ativo.
2. Abrir CRM → Contratos → Novo contrato.
3. Confirmar que a proposta aparece no bloco **Proposta aceita sem Pedido**.
4. Clicar em **Criar/Reparar pedido**.
5. Confirmar que um único Pedido é criado e passa ao bloco **Pedidos aguardando aprovação**.
6. Abrir o Pedido e aprová-lo.
7. Voltar ao Novo contrato.
8. Se o workflow tiver criado o contrato automaticamente, confirmar o Pedido em **Pedidos que já possuem contrato**.
9. Caso não haja geração automática para aquele produto/venda, confirmar o Pedido em **Pedido / Venda de origem**.
10. Criar o contrato e confirmar Cliente, Negócio, itens e valores.
11. Tentar criar outro contrato principal para o mesmo Pedido e confirmar bloqueio.

## Observação de segurança

O endpoint GET apenas diagnostica e lista estados. Nenhum registro é criado durante a leitura. A correção/reparo do Pedido exige ação explícita do usuário via POST já existente do módulo de Pedidos.
