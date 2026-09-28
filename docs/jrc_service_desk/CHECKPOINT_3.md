# Checkpoint 3 - Frontend do JRC Service Desk

**CP3 IMPLEMENTADO PARA REVISÃO — VALIDAÇÃO NATIVA ACUMULADA PENDENTE**

Registro de 25/09/2026. Autorizado somente CP3. CP4 não iniciado.

## Continuidade

Base única: `JRC-CONVERSAS-SERVICE-DESK-CP2-INTERMEDIARIO-20260925.zip`.
SHA-256 verificado ANTES da extração/edição: `08f0f94b6a8d6e8d04c160e771b661563642d9e5531eb1bf56a054815bfa2d5c`.
O pacote foi extraído diretamente; não houve reconstrução do CP1 nem aplicação de patches.
Os documentos, models, services, policies, specs e migrations CP1/CP2 estão preservados.
SD-D01 a SD-D05 e CP2-D01/CP2-D02 continuam aprovadas sem reinterpretação.

## Entrega estritamente frontend

Implementa navegação e estruturas de tela, não o Service Desk operacional completo.
Service Desk é adicional ao JRC. Nenhum módulo existente foi substituído.

- Layout próprio do módulo dentro do Dashboard nativo e item na sidebar, sem alterar Cockpit/jrcService.
- 25 rotas visuais com namespace `jrc_service_desk_*`, 7 componentes de página reutilizados e 9 componentes locais.
- Componentes nativos de botão, input, select, textarea, tabela, paginação, abas, banner, ícone e spinner.
- Mensagens PT-BR, PT e EN, com o fallback nativo existente.
- Formulário em quatro etapas, edição estrutural, listagem/prévia/detalhe, filtros, cadastros e estruturas das referências complementares.
- Clientes de LEITURA e decodificação do contrato frontend, sem POST/PATCH/DELETE e sem endpoints Rails novos.
- KPIs sem valores; gráficos sem séries fictícias; ausência de API nunca vira uma lista vazia confirmada.
- Ações sem API são desabilitadas e marcadas PENDENTE PARA CP4.

**O CP2 não expõe APIs operacionais.** Portanto, com a flag ligada e sem CP4, o comportamento
esperado é a estrutura visual em estado de indisponibilidade. Uma chamada 404 ao contrato
`ui_context` é tratada como pendência, não como uma consulta bem-sucedida sem chamados.
O adaptador não tenta endpoints de CRM, Conversas ou outro módulo como fallback.

## Feature e contexto

A mesma flag `jrc_service_desk` permanece false, `feature_flags_ext_1`, posição 9,
máscara 256; nenhuma nova flag foi criada. Registro e 71 flags anteriores intactos.

O item principal é omitido quando a feature nativa não é literalmente true. Guards das rotas
consultam o endpoint NATIVO de Account usando o ID de destino, conferem ID e features, e
atualizam o store nativo de contas. Falha de transporte ou resposta incompatível cancela
entrada; flag false redireciona ao home. Não se usa o caminho da Account anterior, nem o
`accounts/get` para concluir sucesso, pois a action nativa absorve erros de transporte.
A action original não foi alterada.

O provider local cancela requisições e apaga dados ao mudar Account, usuário ou flag.
Uma resposta antiga não pode repovoar a nova sessão. 401/403 e contrato incompatível
removem o contexto de leitura. Não há cache persistido, localStorage ou singleton operacional.

Sem contexto da API, os esquemas visuais não contêm registros privados. Uma resposta de
permissão negada bloqueia o conteúdo; com contexto confirmado, menus e campos respeitam as
capacidades retornadas. Não há decisão por nome de role nem bypass para administrador.

**Essas proteções de interface não são autorização.** A futura API deverá aplicar
Account -> OperatorCompany -> Unit -> UnitMembership ativo + policies do backend em toda
requisição, consulta, contagem, registro e campo. Nenhuma policy CP2 foi enfraquecida.

## Estado e formulários

Estados separados: inicial, carregamento, API pendente, acesso negado, sessão não confirmada,
erro, contrato incompatível, filtro inválido, chamado não encontrado e resultado realmente vazio.
Rascunhos ficam somente na instância da tela, exigem capacidade expressa para habilitar campos
e são descartados ao sair, recarregar, trocar usuário/Account ou unidade. Nunca são gravados.
Nenhuma unidade, prioridade, categoria, status, equipe ou responsável fictício foi criado.
Fixtures existem exclusivamente nos testes, sem importação pelo código da aplicação.

## Limites preservados

Zero controllers, serializers Rails, APIs operacionais, tabelas, migrations, jobs ou alterações
de banco nesta etapa. `db/schema.rb` continua intacto. Portal autenticado, SSO, alteração
de SLA, roteamento, cálculo de calendário, integrações, IA operacional e Projetos não foram
implementados. Não há rota nem feature de Projetos. Referência do portal vira apenas um aviso
de fronteira em Configurações, sem rota externa, sessão, link de impersonação ou tela de cliente.

## Evidências e limites de validação

Executados 100 testes Node isolados sobre helpers, decodificadores, guard e sessão de leitura reais.
O wrapper Vitest executa os mesmos casos quando houver o ambiente correto, mas o Node isolado
NÃO monta Vue nem executa Rails/RSpec/Vitest/SQL. Specs de componentes, views e roteador foram
adicionados para execução nativa posterior.

Sintaxe JS e expressões extraídas dos templates foram analisadas com o parser TypeScript instalado,
e CSS com PostCSS. Isso NÃO é compilação Vue, lint completo ou teste de layout em navegador.
Contagens finais, hashes e saídas estão no manifesto/relatório/evidências externos.

**PENDENTE — validação nativa em ambiente Docker/local** para CP1, CP2 e a execução nativa do CP3.
As tentativas de pnpm/Vitest/ESLint/Vite não iniciaram: pnpm indisponível. Runtime disponível:
Node 22.16.0 e Ruby 3.3.8; os requisitos do JRC continuam Node 24.13.0/Ruby 3.4.4.
Não foram alterados requisitos/lockfiles para contornar isso. Sem aprovação implícita.

## Registros complementares

- `CP3_TELAS_E_ACOES.md`: matriz completa por rota e ação.
- `CP3_CONTRATO_FRONTEND_API.md`: contrato de leitura proposto; endpoints ausentes no pacote.
- `CP3_REFERENCIAS_VISUAIS.md`: mapa das 22 imagens originais e adaptações.
- `CP3_VALIDACAO_NATIVA.md`: pendências acumuladas e roteiro de testes.

Não surgiu decisão arquitetural nova dependente de aprovação humana para esta camada.
O contrato de apresentação não redefine SD-D01..SD-D05 nem CP2-D01/D02.
**CP4 NÃO INICIADO.**
