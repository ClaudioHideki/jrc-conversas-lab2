# Provedores nativos do NICO e catálogo real

Decisão em 24/11/2026: suportar Anthropic Messages e Gemini generateContent, mantendo OpenAI/compatíveis. A configuração usa credenciais criptografadas da conta, host autorizado e protocolo correspondente; nunca envia a chave ao prompt ou a outro provedor.

A tela preenche a URL oficial e consulta modelos pela API do provedor no servidor. Recomendações usam somente IDs retornados. A validação verifica autenticação e catálogo; não se confunde com inferência ou saldo. Workspace Anthropic é opcional, exigido por chaves de organização. A conexão Branef é configuração de ambiente; nenhuma credencial ou ID de cliente pertence ao núcleo.

Consumo usa os recibos nativos, incluindo cache Anthropic e pensamento Gemini sem duplicar cache. Áudio não é enviado à API de transcrição OpenAI com chave Anthropic/Gemini; o modo textual continua disponível. Transcrição nesses provedores permanece sem adaptador e é informada como limite, sem fallback para chave global.

Testes locais de protocolos, uso, escopo e interface; CI e implantação são evidências separadas.

Fontes: https://platform.claude.com/docs/en/api/messages/create ; https://platform.claude.com/docs/en/api/models/list ; https://platform.claude.com/docs/en/api/migration-2026-10-21 ; https://ai.google.dev/api/generate-content .

## Correcao Unicode em registros de chamados
Na validacao produtiva do chamado 4152, ITILSolution/1998 tinha 1000 caracteres Unicode e 1001 unidades UTF-16. O runtime recusava a projecao Rails antes da inferencia. O limite permanece 1000 caracteres, contado por ponto de codigo Unicode, com o limite HTTP de bytes preservado. Regressao reproduz o emoji no limite e rejeita 1001 caracteres. CI/imagem/deploy e nova analise devem ser registrados separadamente nas evidencias da Branef.
