# ADR 0007 — Consumo do NICO e limites do provedor

Estado: Aceita pelo responsável em 23/11/2026. Implementação candidata; implantação exige CI e imagens verificadas.

## Contexto

Uma implantação recebeu resposta HTTP 200 do provedor, mas foi bloqueada antes de novas chamadas por reservas incertas e um teto mensal local. Valores locais e estimativas sem recibo não comprovam saldo financeiro nem cota restante do provedor. Evidências operacionais específicas permanecem na coordenação da implantação.

## Decisão

Uma nova conexão usa os limites do provedor por padrão e requer tipo compatível, URL, credencial e modelo. Teto mensal local é opcional. Configurações existentes mantêm sua política até alteração explícita; a implantação solicitante optou por operar pelo provedor. Concorrência, isolamento por conta, permissões e limites de tamanho permanecem obrigatórios.

Manter recibos confirmados, estimativas identificadas e tentativas incertas separados. Registros históricos sem marcador de recibo permanecem sem classificação; não são promovidos a consumo confirmado. Os totais cobrem somente chamadas registradas pelo JRC, não o uso da organização em outros sistemas. Operar pelo provedor não zera reservas antigas nem transforma incerteza em consumo confirmado. O histórico mantém o estado desconhecido para auditoria.

Capturar somente os cabeçalhos de limite permitidos e o status HTTP do provedor, com conta, request e data. Exibir como observação da última resposta, jamais como saldo global em tempo real. HTTP 429 preserva o Retry-After sem repetir a chamada automaticamente. Nenhuma credencial, prompt ou corpo de erro externo integra os metadados exibidos.

Orçamento financeiro cadastrado é apenas referência interna. Sem API oficial de faturamento integrada, mostrar saldo indisponível. Não inferir crédito a partir de tokens, HTTP 200, nome de plano ou valores digitados. Custos indisponíveis não equivalem a zero.

## Validação e limites

Cobrir admissão com reservas incertas preservadas, tetos locais explícitos, concorrência, isolamento entre contas, metadados reais e resposta 429. A implantação alvo deve receber a candidata somente após gates e imagem do SHA final. Não alterar outros ambientes por esta decisão. Sem migrations novas nesta correção.

Referência de unidades e limites organizacionais: https://console.groq.com/docs/rate-limits .
