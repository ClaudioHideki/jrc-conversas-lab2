# ADR 0007 — Consumo do NICO e limites do provedor

Estado: Aceita pelo responsável em 23/11/2026. Implementação candidata; implantação exige CI e imagens verificadas.

## Contexto

Na Branef, o provedor Groq respondeu HTTP 200 e informou 8.000 tokens/minuto. O JRC impediu o NICO antes da API por 858.240 tokens reservados como incertos, somados a 110.388 registrados, contra um teto local padrão de 1.000.000. Esses valores locais não comprovam saldo financeiro nem cota restante do provedor.

## Decisão

Uma nova conexão usa os limites do provedor por padrão e requer tipo compatível, URL, credencial e modelo. Teto mensal local é opcional. Configurações existentes mantêm sua política até alteração explícita; a Branef solicitou operar pelo provedor. Concorrência, isolamento por conta, permissões e limites de tamanho permanecem obrigatórios.

Manter recibos confirmados, estimativas identificadas e tentativas incertas separados. Operar pelo provedor não zera reservas antigas nem transforma incerteza em consumo confirmado. O histórico mantém o estado desconhecido para auditoria.

Capturar somente os cabeçalhos de limite permitidos e o status HTTP do provedor, com conta, request e data. Exibir como observação da última resposta, jamais como saldo global em tempo real. HTTP 429 preserva o Retry-After sem repetir a chamada automaticamente. Nenhuma credencial, prompt ou corpo de erro externo integra os metadados exibidos.

Orçamento financeiro cadastrado é apenas referência interna. Sem API oficial de faturamento integrada, mostrar saldo indisponível. Não inferir crédito a partir de tokens, HTTP 200, nome de plano ou valores digitados. Custos indisponíveis não equivalem a zero.

## Validação e limites

Cobrir admissão com reservas incertas preservadas, tetos locais explícitos, concorrência, isolamento entre contas, metadados reais e resposta 429. A Branef deve receber a candidata somente após gates e imagem do SHA final. Não alterar outros ambientes por esta decisão. Sem migrations novas nesta correção.

Referência de unidades e limites organizacionais: https://console.groq.com/docs/rate-limits .
