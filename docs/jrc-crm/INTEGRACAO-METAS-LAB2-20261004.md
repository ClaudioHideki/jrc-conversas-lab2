# Integracao controlada de Metas e acoes inteligentes - LAB2

- Base Git e imagem anterior: `70cfbd76f0571d2056a11199b34069032f13edc7`.
- Branch: `codex/crm-metas-acoes-inteligentes-20261004`.
- ZIP: `JRC-CONVERSAS-LAB2-CRM-METAS-ACOES-INTELIGENTES-INTEGRADO-CANDIDATO-20261004.zip`.
- SHA-256 conferido: `27691626defa57a938cadec8cc9c9225ffc7ecaae414a1f77960d957467e38dd`; CRC aprovado.

## Preservacao

Comparacao em tres vias: ZIP anterior, HEAD publicado e ZIP novo. Conteudo identico ao ZIP anterior nao substitui correcoes posteriores do Git. Preservados os guards de Pedido, datas ISO do projeto, backfill/down de migration, testes e workflow de publicacao. Mantidos os dois arquivos anteriores de validacao/integracao ausentes do ZIP novo. Nenhum arquivo ou modulo removido.

CRM-ORD-CONTRACT-01 estava presente no ZIP novo e foi incorporada sobre a base atual. Endpoint GET somente lista pedidos elegiveis, pendentes, propostas aceitas sem pedido e pedidos ja contratados; reparo exige POST explicito. Criacao de contrato valida aprovacao e contrato principal existente dentro do lock do Pedido.

## Metas

- Pipeline dividido pela meta e forecast dividido pela meta; denominador zero retorna zero.
- Ranking com meta, realizado, pipeline, forecast, percentual realizado e esperado; carteira filtra vendedor/status pela rota.
- Recomendacoes com motivo, prioridade, valores/percentuais/quantidades, IDs e registros reais: gap, cobertura, vendedores abaixo do ritmo, negocios parados, propostas sem retorno e produtos abaixo da meta.
- Criacao de atividade preenche negocio em uma rota de edicao; nao cria dados automaticamente ao abrir o dashboard.
- NICO recebe numeros da meta, periodo, conta e registros da recomendacao. Sem clientes de teste no runtime.
- Vendedores sem limite artificial de oito; selecao individual, adicionar todos, remover e divisao igual com valores em centavos. Pesos iniciais proporcionais e editaveis.
- Produtos ativos com normalizacao de resposta array/payload, selecao individual, adicionar todos, remover e divisao da meta.

## Ajustes minimos

- Adicionar todos completa uma selecao parcial sem duplicar ou apagar os valores existentes. Distribuir igualmente atua somente nos registros selecionados.
- Contexto do NICO inclui os registros reais, nao somente os totais agregados.
- Fixtures do teste comercial incluem cliente obrigatorio e editam o rascunho antes de aprovar, preservando o bloqueio de termos apos gerar contrato.
- Fixture da proposta sem Pedido existe antes do GET no teste de Contratos.
- Workflow existente conserva seus gates e acrescenta testes de Metas/fluxo comercial e reconhecimento da nova rota.

## Validacoes e limites

Nenhuma migration nova; migrations anteriores conservadas. Parse JS/Vue/JSON e 226 timestamps verificados; 387 testes Node passaram localmente. Ruby indisponivel localmente; Vitest local nao iniciou por restricao de leitura do esbuild. Confirmar resultados efetivos do Actions antes de considerar RSpec/Vitest/build aprovados.

Lint completo das telas comerciais revela divida preexistente de formatacao, ordem de declaracao e textos nao internacionalizados, incluindo textos do candidato. O resultado comparativo esta no relatorio da entrega. Nao foram desativadas regras nem removidos gates existentes; nao declarar o lint completo dessas telas como aprovado.

Sem deploy, alteracao de Compose/Dokploy, migrations no servidor, parada de containers atuais, sobrescrita de tags ou publicacao de latest. Rollback de imagem nao reverte schema.

Imagem anterior preservada: `ghcr.io/claudiohideki/jrc-conversas-lab2:sha-70cfbd76f0571d2056a11199b34069032f13edc7`.
