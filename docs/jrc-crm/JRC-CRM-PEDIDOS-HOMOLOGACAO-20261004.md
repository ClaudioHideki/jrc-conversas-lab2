# Homologação — Criação de Pedido

## Cenário principal — Nexora Tech

1. Criar/usar Marcelo Andrade vinculado à Nexora Tech.
2. Abrir Novo Pedido.
3. Confirmar que a tela abre sem carregar todos os clientes.
4. Digitar `Marcelo`, `Nexora`, telefone, e-mail, CNPJ/CPF ou `EMP-...` e confirmar o mesmo contato.
5. Confirmar que contatos homônimos aparecem separadamente.
6. Selecionar Marcelo e verificar que somente negócios da Nexora/Marcelo aparecem.
7. Selecionar o Negócio Nexora — Implantação JRC Conversas.
8. Confirmar preenchimento automático do Cliente.
9. Criar uma Proposta `sent` e uma `accepted` para o mesmo negócio.
10. Confirmar que somente a `accepted` é selecionável para Pedido.
11. Confirmar mensagem informativa sobre propostas aguardando aceite e ação `Ver proposta`.
12. Selecionar a Proposta aceita e validar importação de itens, preços, descontos, setup, MRR, pagamento e vigência.
13. Finalizar o Pedido e confirmar Cliente + Negócio + Proposta + versão.

## Testes negativos obrigatórios

- tentar enviar `proposal_id` de um negócio com `deal_id` de outro: deve bloquear;
- tentar vincular Negócio de outro Cliente: deve bloquear;
- tentar gerar Pedido de Proposta não aceita: deve bloquear;
- tentar criar Venda direta sem Cliente: deve bloquear;
- tentar acessar Proposta/Negócio de outra conta: deve bloquear;
- alterar valores comerciais de Pedido originado de Proposta aceita: deve bloquear.

## Pedido direto

Validar cada origem:
- Venda direta;
- Renovação;
- Upgrade / Expansão;
- Proposta / Negócio sem Proposta, quando autorizado.

Confirmar `order_created_without_proposal` e usuário criador no histórico.

## Auditoria

Validar que criação e atualização gravam:
- actor/usuário;
- Cliente;
- Negócio;
- Proposta;
- versão;
- origem;
- status;
- data/hora.

## Gate técnico pendente no LAB

- executar migration PostgreSQL;
- executar RSpec incluindo `sales_order_link_integrity_spec.rb`;
- executar testes frontend/Vitest relacionados ao CRM;
- executar build Vue/Vite;
- validar fluxo no navegador;
- executar build Docker e smoke test da imagem.
