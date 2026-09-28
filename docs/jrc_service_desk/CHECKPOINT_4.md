# Checkpoint 4 - integracao operacional

Baseline exclusiva: JRC-CONVERSAS-SERVICE-DESK-CP3-INTERMEDIARIO-20260925.zip.
SHA-256 confirmado antes das alteracoes:
7a899c176eb9ca6e340276299b7810461e90059bffa9b1f1d52729fe09e9ede8
Nenhuma reconstrucao CP1/CP2 ou reaplicacao de patches.

Esta etapa expoe os comandos CP2 por endpoints restritos e conecta as telas CP3.
Nao ha auto-provisionamento de unidade/operadora/membership, grant de admin global,
bootstrap de calendario, mudanca de flag nem Projetos. Unidade e classificacoes
precisam estar previamente configuradas por um processo explicitamente autorizado.

CP4-D01 bloqueia o ciclo de vida/SLA dependente, nao criacao/edicao/consulta/atribuicao/notas/KPIs.
Os testes nativos CP1/CP2/CP3 continuam: PENDENTE — validação nativa em ambiente Docker/local.
Ver CP4_VALIDACAO_NATIVA.md e CP4_MATRIZ_FUNCIONAL.md para o estado preciso da entrega.

CP4 IMPLEMENTADO PARA REVISÃO — VALIDAÇÃO NATIVA ACUMULADA PENDENTE

Consultar CP4_IMPLEMENTACAO.md, CP4_APIS.md, CP4_KPIS.md e a matriz funcional.
