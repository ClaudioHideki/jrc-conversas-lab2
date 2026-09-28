# Fase 2A — Propostas e PDF JRC

Baseline: `16c9bee98dea402aae0d40637617687b75d768c3`, branch `codex/softphone-desktop-windows`.

## Implementação

- Serviço PDF evoluído sobre a baseline, sem copiar arquivos dos ZIPs. Logo permanece `public/brand-assets/logo-jrc.png`; paleta azul JRC preservada.
- Paginação por altura disponível, considerando linhas e largura conservadora dos glifos Helvetica regular/negrito. Palavras sem espaços também quebram; descrições não são truncadas. Linhas comuns da tabela ficam juntas; descrições maiores que uma página continuam nas seguintes com cabeçalho repetido.
- Corpo limitado acima de 76 pontos e rodapé reservado abaixo de 58 pontos. Todas as páginas recebem `Página X de Y`. Títulos de seção reservam espaço para o conteúdo seguinte.
- Versão, descontos individuais/adicional, validade, vigência, pagamento/vencimento, impostos, reajuste, renovação, multa, observações comerciais e próximos passos salvos permanecem no PDF. Não foram inventados blocos de assinatura/aceite inexistentes no PDF anterior.
- Modal de criação com altura máxima de 85vh/rolagem. Contexto `new=1&contactId=...` filtra somente negócios autorizados retornados pela API; `proposalId` numérico abre pela API existente da conta. Falhas de acesso fecham o detalhe.
- Ações PDF consolidadas em `Baixar PDF`: requisição Axios autenticada com resposta Blob, link com atributo download, limpeza da URL temporária e sem window.open/navegação da página JRC.
- Estado ocupado bloqueia repetição e download durante persistência de itens. Alterações comerciais, desconto e produto ainda não adicionado exigem ação explícita antes do PDF. Não há salvamento implícito que invalide aprovações. Falha de atualização de item exige reabrir/revisar; o rascunho comercial não é sobrescrito pelo retorno de operações de itens.

## Validação executada (sem banco)

- Propostas/API: **15 testes**, incluindo sucesso, HTTP 401/403/500, clique repetido, dados não salvos, falha de salvamento, produto pendente, retorno de produto preservando observações, proposta aceita/bloqueada e contexto autorizado.
- Regressão CRM/Fase 1: **91 testes existentes** aprovados. A execução completa inicial teve 103 testes; os três cenários adicionais foram executados depois na suíte final de 15 testes de Propostas/API.
- Desktop/provisionamento: **40 testes** aprovados.
- Webphone/bridge/download: **88 testes** aprovados.
- NICO frontend: **61 testes** aprovados. Runtime NICO não alterado nem executado.
- PDF Ruby independente: **4 testes, 4.502 asserções**, aprovados. Executado diretamente com Minitest/ActiveSupport/ActionController, sem carregar ambiente Rails, ActiveRecord, rails_helper ou qualquer preparação de schema. Contêiner preexistente usado somente como runtime, sem rede e com fontes montados somente para leitura; nenhuma imagem foi construída.
- Electron 44.4.5 real: **1 teste de integração** aprovado. Perfil temporário, janela invisível, origem HTTP exclusivamente em loopback de teste, contextIsolation/sandbox ativos, nodeIntegration desativado, política trustedUrl existente, novas janelas negadas. Executa a ação downloadPdf lida do componente real; confirma bytes recebidos, autenticação de teste, ausência de navegação e ausência de nova janela. Não inicia o app instalado, SIP ou instalador.
- PDFs sintéticos de **3 e 14 páginas**, incluindo 35 produtos, descrição individual maior que uma página e observações/próximos passos extensos: renderização Poppler inspecionada; pdfplumber verificou limites de todas as palavras, ausência de interseções, faixa livre do rodapé e numeração. Saídas de QA ficam em `tmp/pdfs`, ignorado pelo Git.

Comandos de testes:

```sh
npx --no-install vitest run --config vitest.crm-phase1.config.mjs
node --test desktop/test/*.test.cjs
npx --no-install vitest run --config desktop/test/webphone.vitest.config.mjs --maxWorkers 1 --minWorkers 1
npx --no-install vitest run --config vitest.nico.config.ts
bundle exec ruby test/jrc_crm/proposal_pdf_service_test.rb
```

O teste nativo é `test/jrc_crm/proposal_pdf_download.electron.cjs`, executado com o runtime Electron já instalado em desktop/node_modules, com ELECTRON_RUN_AS_NODE ausente. Não instalar o EXE para executá-lo. A variável opcional PDF_QA_OUTPUT aponta para um diretório existente para exportar os dois PDFs sintéticos do teste Ruby.

## Lint e limites da validação

- ESLint nos arquivos JS/Vue afetados: **zero erros**, 15 avisos de formatação de template em ProposalsIndex.vue. Os demais arquivos JS novos/alterados passaram sem ocorrências.
- RuboCop `Lint,Layout,Security`: **zero ocorrências** nos arquivos Ruby afetados. Teste Ruby também passa no RuboCop completo.
- RuboCop completo no serviço: **22 ocorrências de estilo/estrutura/complexidade**, contra 46 na baseline, incluindo classes internas, nomes de coordenadas e escritor PDF existente; a classe de layout continua acima do limite de tamanho. Não se afirma aprovação integral do RuboCop e não foram relaxadas regras globais.
- `git diff --check`: aprovado.
- Os testes Rails que carregam rails_helper e poderiam preparar schema não foram executados. Não há confirmação end-to-end contra banco/servidor LAB nesta etapa; permissões, conta, aprovações, duplicação e bloqueio permanecem nos mesmos controllers/models/policies, sem alterações. A homologação posterior deverá confirmar o fluxo com login real no navegador e Desktop.

## Proteções e escopo

SHA-256 dos **456 arquivos protegidos: zero mudanças**, incluindo Desktop universal, Webphone, NICO, políticas e banco. Nenhum controller, model, serializer, rota, schema, migration ou configuração de deploy foi alterado.

Busca nos quatro arquivos de aplicação alterados: **zero referências a GoPure, assets institucionais ou slogan**. A única referência negativa no teste PDF existe para impedir regressão de branding. A geração usou o logo JRC efetivamente embutido como imagem no PDF.

Não foram implementados frete, entrada, parcelas, novas condições comerciais, has_monthly_fee, pedidos, contratos, comissões, metas ou alterações de responsável. Não houve commit/push, build Docker/EXE, publicação, deploy ou alteração de produção.
