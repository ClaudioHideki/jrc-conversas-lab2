# Integracao controlada de Pedidos - LAB2

## Origem e preservacao

- Base Git: `128243d925617c08896a2a9448b2bb9f6e5da115`.
- ZIP: `JRC-CONVERSAS-LAB2-CRM-PEDIDOS-INTEGRIDADE-VINCULOS-INTEGRADO-CANDIDATO-20261004.zip`.
- SHA-256: `b3901bf26a6ec23d05d8a33e1dfb018b22931afe0c589bb268e6e1d8c2db7540`; CRC verificado.
- Nenhum arquivo ou modulo removido; nenhum arquivo versionado ausente no ZIP.
- Mantidos o workflow bem-sucedido e o package `ghcr.io/claudiohideki/jrc-conversas-lab2`, corrigindo as referencias antigas presentes no ZIP.
- Nao foram importados credenciais, ambientes reais, caches, dependencias ou dumps.

## Revisao funcional

- Autocomplete de contatos sob demanda, minimo de dois caracteres e limite de 20 resultados, sem mesclagem por nome.
- Busca por nome, e-mail, telefone, identificador, empresa, nome fantasia, CPF/CNPJ e codigo `EMP-...`; contexto distingue homonimos.
- Negocios filtrados por contato direto, contato associado ou mesma empresa mestre, com visibilidade por responsavel/escopo existente.
- Propostas filtradas por negocio e status `accepted`; pendencias informativas e acesso a proposta aguardando aceite.
- Os tres caminhos de selecao sao suportados, incluindo abertura do wizard com `proposalId` ou `dealId`.
- `ProposalToOrderService` permanece a fonte canonica de itens, valores e termos aceitos. Payload financeiro do navegador nao substitui esses valores.
- Modelo e API verificam cliente/negocio/proposta, aceite e conta; pedidos diretos exigem cliente na criacao e preservam as quatro origens.
- Origem, criador, versao, vinculos e eventos de criacao/atualizacao ficam registrados; criacao sem proposta recebe evento proprio.
- Empresa e Contato continuam sendo as entidades existentes. Cadastro Mestre, CRM, organizacao e demais modulos foram preservados.

## Migrations e ajustes minimos

- `20261004170000`: perfil da empresa mestre e segmentos por conta; JSONB, indices e foreign keys PostgreSQL; rollback explicitamente irreversivel para preservar dados comerciais.
- `20261004183000`: origem, versao aceita e criador do pedido, indices e foreign key; `up`/`down` presentes.
- Corrigido o backfill de origem: coluna criada inicialmente sem default, classificacao dos registros existentes, depois default e obrigatoriedade. Evita classificar pedidos antigos com proposta como venda direta.
- Corrigida a assinatura de `index_exists?` no `down` da migration de Pedidos, encontrada ao testar a reversao real no Rails 7.1/PostgreSQL isolado.
- Datas do novo servico de implantacao serializadas em ISO 8601 para respeitar o contrato JSON/idempotencia da API existente de Projetos; falha identificada pelo teste ponta a ponta.
- Formatacao/lint restritos aos fontes alterados; removida uma variavel nao utilizada da tela de Pedidos e corrigido placeholder para reutilizar o catalogo textual existente.
- Workflow existente ampliado com sintaxe Ruby, parse Vue/JS/JSON, verificador de timestamps, RSpec afetado e PostgreSQL descartavel. Build continua em `linux/amd64`, tag SHA exclusiva e verificacao antes/depois do push.

## Limites operacionais

Esta entrega nao faz deploy, nao modifica Compose/Dokploy, nao para containers e nao executa migrations no servidor. Homologacao manual da instalacao e eventual aplicacao das migrations sao etapas separadas. Consultar o resultado real de cada gate no Actions; os documentos de homologacao do ZIP nao constituem prova de execucao.

Rollback de imagem preservado: `ghcr.io/claudiohideki/jrc-conversas-lab2:sha-905d4a731996919f190830034a0ff8a64a520c37`. Nenhuma tag existente e sobrescrita ou removida.
