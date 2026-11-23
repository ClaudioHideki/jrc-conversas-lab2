# Groq: espera limitada após rejeição HTTP 429

Estado: implementação candidata autorizada em 23/11/2026; homologação do conhecimento depende de teste no ambiente alvo.

## Problema observado

Uma consulta curta respondeu, mas a consulta com pesquisa ao conhecimento recebeu HTTP 429 com Retry-After. O runtime encerrava a inferência sem respeitar esse prazo. Limite por minuto e crédito financeiro são conceitos distintos.

## Decisão

Somente para o host exato api.groq.com, admitir uma nova tentativa da inferência explicitamente rejeitada como limite temporário quando Retry-After for numérico e couber no prazo original. O corpo permanece idêntico; ferramentas e ações do chamador não são reexecutadas. Uma rejeição financeira, falha de transporte, ausência de prazo válido ou segundo 429 retorna erro controlado. Cancelamento interrompe a espera. O prazo de 45 segundos e os contratos Rails permanecem.

A rejeição 429 não gera recibo de tokens. Somente a usage efetivamente devolvida pelo provedor integra os registros confirmados. Reservas antigas e consumo sem comprovação permanecem preservados. Não mudar chaves, modelos, limites financeiros ou clientes por essa correção.

## Validação

Testes de espera, cancelamento, limite de tentativas, consumo confirmado e reparo JSON. CI no SHA final; publicar somente runtime e implantar apenas no ambiente autorizado. Validar consulta real de conhecimento e separar a prontidão de rotas GLPI de abertura real de chamado e SLA.

Fonte: https://console.groq.com/docs/rate-limits

## Histórico de recursos

A análise de sentimento aceita também uma origem identificada e IDs qualificados reais, sem atribuir um ticket a uma conversa JRC fictícia. O contrato de conversas existente permanece compatível. O núcleo não lê GLPI: autorização, período e projeção pública pertencem ao adaptador exclusivo da Branef.

## Evidência posterior:413 após leitura do conhecimento

Na Branef, a consulta search_knowledge foi executada, mas a síntese recebeu HTTP413 com limite observado de8000TPM. O retorno429 não era a única causa. Para esse provedor/modelo e cota observada, a projeção da inferência omite guias de módulos redundantes, mantém quatro mensagens recentes, limita corpos de conhecimento a1000caracteres preservando IDs/URLs e elimina apenas duplicatas exatas de resultados. Fontes, autorizações e ferramentas permanecem intactas. A cadência usa reset do provedor e último recibo confirmado, antes de criar reserva; nenhuma espera é contabilizada como consumo. Não alterar outros provedores/modelos nem liberar reservas incertas antigas.
