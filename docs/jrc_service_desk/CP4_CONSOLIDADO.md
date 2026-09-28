# CP4 consolidado - ciclo de vida versionado

**CP4 CONSOLIDADO PARA REVISÃO — VALIDAÇÃO NATIVA ACUMULADA PENDENTE**

Continuidade exclusiva: JRC-CONVERSAS-SERVICE-DESK-CP4-INTERMEDIARIO-20260925.zip.
SHA-256 conferido antes das alteracoes: 2444d57589577423db47d0f21c40856a20a0491549b2a884ac92f918a5c26975.
CP1/CP2 nao foram reconstruidos; nenhum patch reaplicado. Registro de 28/09/2026.
CP4-D01 alternativa A APROVADA. SD-D01..05 e CP2-D01/02 preservadas. CP5 NAO iniciado.

## Entregue nesta continuacao

Politicas por unidade/servico com publicacao/versionamento e precedencia, identidades minimas
de servico, vinculo historico de politica no chamado, regras de pausa/retomada/resolucao/
encerramento/cancelamento/reabertura, requisitos/evidencias, janelas e ciclos configuraveis.
APIs e painel de transicao fazem releitura do proprio evento e ticket antes de confirmar.
Dashboard/listas sao novamente consultados depois, nunca incrementados no navegador.

Interpretador de calendario de snapshot explicito, sem calendario/master/feriado presumido;
pausas por relogio e ciclos com continue/new configuraveis. Campos ausentes/formatos nao
suportados produzem dependencia, sem transicao parcial nem SLA simulado. Modo sem SLA so
quando explicitamente configurado not_applicable. Nao capturar first_response por nota interna.

Servicos de dominio incluem atomicidade/idempotencia/revisao de versao. Nenhum bypass admin.
Configuracao exige unidade vinculada e permissao nativa; nenhum usuario ganhou acesso.
As 71 flags anteriores e jrc_service_desk default false/ext1/posicao9/mascara256 continuam iguais.

Nova migration aditiva: 7 tabelas/19 indices/34 FKs/7 CHECKs/2 colunas do Ticket SD.
As 203 migrations anteriores e db/schema.rb ficaram intactos. Migration escrita, nao aplicada.
Nenhum catalogo completo, ERP, SSO, Projects, novo menu/flag ou CP5 foi implementado.

## Validacoes reais e limites

- 24 testes Ruby isolados/166 assercoes: regras e algoritmo de calendario com zona fixa de teste.
- 9 testes Ruby isolados/40 assercoes: motor de clocks REAL com repositorio de teste em memoria.
- 8 testes Ruby isolados/186 assercoes: gravador das declaracoes da migration, SEM SQL.
- 41 testes Node lifecycle + 100 anteriores CP3 + 57 anteriores CP4: clientes/contratos/estado.
- Sintaxe/parsing/imports/i18n, comparacao integral, Git e CRC/hashes do ZIP registrados externamente.
Esses testes nao montam Vue, nao executam Rails/ActiveRecord/RSpec/TZInfo real/PostgreSQL/Vitest.
Os doubles estao confinados aos testes; nao sao imports nem dados operacionais.

PENDENTE — validação nativa em ambiente Docker/local

Tentativas de Rails/RSpec falharam por executaveis/dependencias ausentes; bundle check
identificou Ruby incorreto. pnpm/Docker/psql ausentes. Nao se alteraram runtimes/lockfiles.
Specs novos cobrem seguranca, versoes, todos os fluxos, clocks, concorrencia, constraints,
API e KPI 27=8+12+7 -> 27=7+12+8 por resolucao real. Sua execucao nativa esta pendente.

## Arquivos anteriores e riscos

Dois specs existentes receberam adaptacao pontual para exigir a politica work_status e
verificar seu novo evento; exemplos nao foram excluidos. Os demais specs anteriores estao
preservados. Codigo alterado somente em Service Desk e registro de rotas Rails; nao se
alteraram sidebar/Cockpit/CRM/Campanhas/NICO/Calling/canais/autenticacao ou permissoes globais.

Riscos: validar SQL/FKs/dump real antes de usar a migration; locks por unidade precisam de
ensaios concorrentes; append-only de dominio nao protege de SQL privilegiado; consumo temporal
entre leituras nao e contador ao vivo; publicacao e JSON avancado, nao editor visual de regras;
fixtures nao certificam contratos externos. Desabilitar politica bloqueia comandos ate nova
configuracao explicita, inclusive tickets antigos. Janelas em segundos decorridos nao sao
janelas em horas uteis. Snapshot antigo sem contrato v1 e uma dependencia real.

## Itens ainda fora/pendentes

Validacao nativa acumulada CP1..CP4; UI e policies reais; F5/concorrencia/KPI por SQL; cadastro
mestre/importacao/editor visual de calendarios; primeira resposta por canal real; upload/download;
assumir-proximo e transferencia entre unidades; dominios complementares nao implementados.
Nao existem novas decisoes arquiteturais humanas pendentes desta continuacao. Parametros da
politica precisam ser configurados explicitamente pelo operador autorizado, sem seed silencioso.

Detalhamento: CP4_D01_APROVADA.md, CP4_D01_POLITICA.md, CP4_D01_CALENDARIO_E_SLA.md,
CP4_D01_DADOS.md, CP4_D01_VALIDACAO_NATIVA.md, CP4_MATRIZ_CONSOLIDADA.md e
CP4_ENDPOINTS_CONSOLIDADOS.md. Os documentos anteriores sao historicos, nao resultados novos.
