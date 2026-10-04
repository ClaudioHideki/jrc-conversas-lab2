# JRC Conversas — Integridade de criação de Pedido

Data: 04/10/2026
Prioridade: ALTA

## Objetivo

Garantir que Pedido preserve vínculos consistentes entre Cliente, Negócio e Proposta, impedindo que um pedido comercial contamine Contrato, Financeiro, Implantação, Comissão e indicadores com registros de outro cliente.

## Regras implementadas

### Cliente
- Busca sob demanda; a tela não carrega toda a base ao abrir.
- Pesquisa por nome, empresa, telefone, e-mail, identificador, CPF/CNPJ e código da empresa.
- Resultado distingue homônimos por empresa, telefone, e-mail e código.
- Nenhuma mesclagem é feita somente por nome.

### Negócio
- Com Cliente selecionado, são retornados apenas Negócios ligados ao contato ou à mesma Empresa do Cadastro Mestre.
- Também é possível pesquisar/selecionar Negócio primeiro.
- Selecionar Negócio preenche o Cliente relacionado.
- Resultado exibe nome, cliente/empresa, valor e etapa/status.

### Proposta
- Com Negócio selecionado, somente Propostas daquele Negócio são consultadas.
- Somente Propostas Aceitas aparecem como elegíveis para geração normal de Pedido.
- Propostas enviadas, visualizadas ou aguardando aprovação são resumidas de forma informativa.
- A interface oferece ação para abrir uma proposta pendente quando aplicável.
- Selecionar Proposta preenche Negócio e Cliente automaticamente.

### Importação
A Proposta aceita é a fonte canônica dos dados comerciais. O Pedido preserva:
- itens, produtos e serviços;
- quantidades e preços unitários;
- descontos;
- setup/implantação;
- recorrência/MRR;
- condição e meio de pagamento;
- vigência;
- renovação e demais termos serializados;
- versão da proposta aceita.

O backend não aceita substituição dos valores comerciais de uma proposta aceita pelo payload do navegador.

### Integridade no backend
Antes de criar/salvar:
- Proposta precisa estar `accepted`;
- `proposal.deal_id` precisa ser igual ao Negócio do Pedido;
- Cliente precisa pertencer ao Negócio por contato direto, contato associado ou mesma Empresa do Cadastro Mestre;
- vínculos de outra conta continuam bloqueados;
- origem `proposal_deal` exige Negócio ou Proposta.

### Pedido direto
Pedido sem Proposta continua permitido, com Cliente obrigatório pela API de criação.

Origens:
- `proposal_deal` — Proposta / Negócio;
- `direct_sale` — Venda direta;
- `renewal` — Renovação;
- `expansion` — Upgrade / Expansão.

### Auditoria
O Pedido passa a preservar:
- usuário criador (`created_by_id`);
- origem (`order_origin`);
- Cliente;
- Negócio;
- Proposta;
- versão da Proposta;
- data/hora;
- alterações posteriores;
- indicador de criação sem Proposta.

Eventos adicionados:
- `order_created`;
- `order_updated`;
- `order_created_without_proposal`.

## Fluxo comercial de referência

Lead → Negócio → Proposta → Aprovação interna → Envio → Visualização → Aceite → Pedido → Contrato → Implantação/Operação

Pedido permanece como ponto de rastreabilidade entre o fechamento comercial e os módulos posteriores.
