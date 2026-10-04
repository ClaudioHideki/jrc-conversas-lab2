# Homologação — Fluxo Nexora ponta a ponta

## Pré-requisitos do LAB

- PostgreSQL com todas as migrations aplicadas.
- Redis disponível conforme compose do LAB.
- Gems do projeto instaladas (`bundle install`).
- Dependências frontend instaladas com pnpm.
- Features da conta: `jrc_crm`, `jrc_customer_master`, `jrc_projects`.
- Usuário comercial com permissões de CRM e Projetos.

## Teste automatizado alvo

Executar:

```bash
bundle exec rspec spec/services/jrc_crm/nexora_end_to_end_spec.rb
```

O teste deve provar:

- uma única Empresa Nexora do início ao fim;
- um único Contato Marcelo;
- Lead convertido no Negócio correto;
- proposta aceita promove Empresa para Cliente;
- uma única venda/pedido por proposta aceita;
- aprovação do pedido cria um único Contrato, Backoffice e Projeto de Implantação;
- replay não duplica registros;
- assinatura e checklist bloqueiam conclusão quando pendentes;
- fatura paga permite concluir o Backoffice quando os demais gates foram cumpridos;
- Customer 360 contém Lead, Negócio, Proposta, Pedido, Contrato, Projeto e Atividade da mesma Empresa.

## Teste manual de navegador

1. Criar Nexora Tech em Clientes → Empresas como Prospect.
2. Vincular Marcelo Andrade.
3. Criar Lead e qualificá-lo.
4. Converter o Lead em Negócio no funil Novas Vendas.
5. Criar/concluir demonstração.
6. Criar proposta com mensalidade + implantação.
7. Aceitar a proposta pelo link público e repetir o acesso para validar idempotência.
8. Verificar Negócio = Ganho, Empresa = Cliente e exatamente um Pedido.
9. Aprovar o Pedido.
10. Verificar Contrato, Backoffice e Projeto de Implantação.
11. Reprocessar/salvar o pedido e confirmar ausência de duplicidades.
12. Assinar o contrato.
13. Concluir checklist de implantação.
14. Emitir fatura e registrar pagamento.
15. Confirmar Backoffice concluído após todos os gates.
16. Abrir Clientes → Empresas → Nexora Tech e validar a Visão 360º.

## Validações obrigatórias antes de produção

- `rails db:migrate` em banco PostgreSQL de homologação.
- RSpec completo do CRM, Customer Master e Projects.
- build Vue/Vite.
- validação de browser dos fluxos interno e público de proposta.
- build Docker e smoke test dos containers Rails/Sidekiq/Vite.
- validar permissões de um vendedor não-admin e de um administrador.
- validar repetição do aceite e do workflow para ausência de duplicidades.
