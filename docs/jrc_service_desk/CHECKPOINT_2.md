# Estado atual - CP2 apos aprovacao humana

CP2-D01/CP2-D02: APROVADAS, opcao A. Fundacao implementada para revisao.
Consulte `CP2_IMPLEMENTACAO.md` para o resultado atual e `CP2_MODELO_DE_DADOS.md` para as
fichas executaveis. Specs escritos nao equivalem a execucao nativa.
**PENDENTE — validação nativa em ambiente Docker/local**.
Nenhum CP3 iniciado. Nenhuma CP2-D03+ pendente nesta rodada.

## Historico preservado da preparacao (nao e o estado atual da implementacao)

> Atualizacao de continuidade: CP2-D01 e CP2-D02 foram APROVADAS, opcao A.
> O conteudo abaixo preserva a preparacao anterior. O desenho executavel, resultados e
> testes atuais sao registrados em CP2_MODELO_DE_DADOS.md e CP2_IMPLEMENTACAO.md.
> SD-D01 a SD-D05 permanecem obrigatorias. Somente CP2 autorizado.

# Checkpoint 2 - abertura, inventario e parada de arquitetura

## Estado efetivo desta rodada

**CP2 INICIADO NA ETAPA PREVIA; IMPLEMENTACAO DEPENDENTE INTERROMPIDA.**
**CP2-D01 e CP2-D02: DECISAO PENDENTE.** Nenhuma alternativa foi aplicada.

Somente documentos novos foram adicionados. Nao foram criados models, services, policies,
controllers, rotas, specs operacionais, tabelas ou migrations do CP2. Isso NAO e entrega
da fundacao de dados implementada, nem conclusao do Checkpoint 2.
O checkpoint para antes dessas partes porque a regra de parada foi acionada por decisoes
que alteram a propriedade dos registros e os limites de autorizacao dentro de uma Account.

## Base unica e precedencia da autorizacao atual

- Arquivo: `JRC-CONVERSAS-SERVICE-DESK-CP1-CONSOLIDADO-20260925.zip`.
- SHA-256 esperado e efetivamente conferido antes da extracao: `657a589816a52e4e0c8d18c20733540269ff638581a072e31b0e74534925ffe4`.
- Raiz preservada: `jrc-conversas-nico-v12-2-7-comercial-integrado-main/`.
- 9.410 arquivos na baseline; CRC conferido sem falha.
- A extracao foi feita diretamente desse ZIP em copia isolada. Nenhum ZIP central anterior
  foi utilizado para reconstruir codigo; nenhum patch CP1-R1/R2 foi aplicado.
- As referencias antigas a baseline e a 'CP2 nao autorizado' nos documentos historicos do
  CP1 retratam suas rodadas. A mensagem atual autoriza o CP2 restrito; o consolidado e agora
  a unica base de continuidade. Os documentos antigos permanecem intactos como historico.

Foram lidos antes de qualquer alteracao:
`CHECKPOINT_1.md`, `CONTRATOS_ARQUITETURAIS.md` e `DECISOES_APROVADAS.md`.
As cinco decisoes SD-D01 a SD-D05 continuam APROVADAS. Nao foram reabertas.

## Como cada decisao aprovada delimita o desenho do CP2

| Decisao | Aplicacao obrigatoria no desenho | O que nao sera feito |
|---|---|---|
| SD-D01 | Account e a fronteira externa; varias operadoras/unidades sao escopos operacionais separados dos clientes. Validar pertenca de toda referencia e escopo interno autorizado. | Reutilizar Company/Organization como operadora, outro Tenant, acesso implicito entre unidades. |
| SD-D02 | Condicoes contratuais aplicadas deverao referenciar origem externa e snapshot local versionado; nao reescrever historico utilizado. | ERP, integracao HTTP, provedor ficticio, assumir proposta como contrato, cobertura inventada. |
| SD-D03 | Solicitante e Contact nativo; identidade de portal e separada e futura. | Portal, conta de agente para cliente, sessao externa, SSO, impersonacao ou identidade por e-mail/ID. |
| SD-D04 | Dados de SLA do SD terao calendario proprio e condicoes versionadas por Account/escopo. Primeira resposta e resolucao sao marcos distintos. | Alterar SLA de Conversas, reapontar Inbox, calcular com timezone/jornada/fallback inventado. |
| SD-D05 | Pundit/AccountUser/contexto nativos, matriz especifica e menor privilegio; flag e pertenca nao concedem acao. | RBAC paralelo, emprestar permissao do CRM, bypass de admin, autorizacao so no frontend. |

A cardinalidade operadora/unidade e a origem dos vinculos de acesso NAO foram estabelecidas
pelas cinco direcoes. O registro aprovado ressalva expressamente cardinalidades/memberships.
As alternativas detalhadas estao em `CP2_DECISOES_PENDENTES.md`.

## Inventario e desenho previo

- `CP2_INVENTARIO_NATIVO.md`: padroes reais e evidencias de arquivo/linha/hash da baseline.
- `CP2_PRE_MODELAGEM.md`: fichas conceituais, sem DDL; todas as dependentes estao bloqueadas.
- `CP2_PLANO_DE_TESTES.md`: testes obrigatorios futuros; nao sao specs implementados/executados.
- `CP2_DECISOES_PENDENTES.md`: problema, alternativas, impactos, recomendacao e dependencias.

## Resultado de implementacao desta rodada

| Tipo | Adicionados | Modificados | Removidos |
|---|---:|---:|---:|
| Documentos CP2 | 5 | 0 | 0 |
| Codigo executavel do projeto | 0 | 0 | 0 |
| Models/services/policies/controllers | 0 | 0 | 0 |
| Specs do projeto | 0 | 0 | 0 |
| Migrations | 0 | 0 | 0 |

Todos os 9.410 arquivos da baseline, incluindo os 16 acrescentados no CP1, devem permanecer
identicos por SHA-256. Nenhuma alteracao no db/schema.rb, nas migrations historicas, nas
rotas, nos jobs, nas dependencias, nas flags ou nos componentes Vue. A verificacao efetiva
esta no manifesto e nos logs externos desta entrega. Nao ha manifestos auto-inseridos que
modifiquem a arvore do projeto fora desses cinco documentos.

## Feature flag

`jrc_service_desk`: default false, `feature_flags_ext_1`, posicao 9, mascara 256.
72 definicoes na baseline: 71 anteriores mais a flag do SD. Os arquivos de registro e o
Featurable serao comparados byte a byte; nenhuma habilitacao de conta sera executada.
Flag ligada nao contorna a BasePolicy herdada do CP1; nenhuma API operacional sera exposta.
Isso e preservacao/inspecao, nao prova de execucao HTTP nativa.

## Validacao e limites

A rodada valida hash, CRC, diff, preservacao dos arquivos originais, escopo documental,
flags e ausencia de implementacao proibida. `git diff --check` deve abranger documentos
novos, e nao apenas arquivos previamente rastreados. Logs e script de verificacao ficam fora
da raiz do projeto.

CP1 permanece **PENDENTE — validação nativa em ambiente Docker/local** para Rails, ActiveRecord,
Zeitwerk, RSpec, Featurable, Vitest e smoke real. Nao transferir resultados isolados anteriores
para essas suites. Neste ambiente foram encontrados Ruby 3.3.8, Node 22.16.0 e Bundler 2.5.22;
nao os confundir com os requeridos Ruby 3.4.4, Node 24.13.0, Bundler 2.5.16 e pnpm 10.2.0.
Nao houve nova tentativa de instalar runtimes ou executar migrations nesta rodada de parada.

Para CP2 ha um bloqueio ANTERIOR ao ambiente: os models, services, policies e seus testes
operacionais dependem de CP2-D01/D02 e ainda nao foram escritos. Assim, testes CP2 nao podem
ser apresentados como meramente aguardando execucao: primeiro faltam as decisoes e o codigo.

## Riscos identificados

1. Reduzir 'operadora/unidade' a uma entidade plana ou impor dois niveis sem decisao fixaria
   FKs, unicidade, roteamento e calendario antes de confirmar a estrutura real.
2. Derivar acesso somente de equipe ou papel pode conceder outra unidade implicitamente.
3. FKs simples verificam existencia, nao igualdade dos account_id relacionados. E necessario
   desenhar e testar as restricoes de relacionamento; nem RLS nem FK composta sao padroes
   ja presentes no schema inspecionado que possam ser copiados automaticamente.
4. Tabelas Active Storage nao tem account_id; assinatura do blob nao comprova o direito
   sobre o chamado. Nenhuma rota de arquivo ou upload foi introduzida nesta rodada.
5. Historico generico do CRM nao e automaticamente auditoria imutavel do SD; copiar seu
   service que captura falhas poderia perder evidencia de alteracoes relevantes.
6. Falta evidencia nativa do CP1. Os novos testes CP2 tambem precisarao do ambiente correto.

## Decisao humana necessaria e parada

Aprovar ou especificar CP2-D01 (cardinalidade/propriedade) e CP2-D02 (escopo de acesso),
sem reabrir SD-D01 a SD-D05. Recomendacoes estao apenas documentadas.

Nenhuma implementacao de Projetos, integracao externa, tela, dashboard, menu, grafico,
relatorio, automacao final ou notificacao final foi criada.
**CP3 NAO INICIADO. NENHUM ZIP CP2 GERADO.**
