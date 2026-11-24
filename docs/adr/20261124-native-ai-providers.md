# Provedores nativos do NICO e catálogo real

Decisão em 24/11/2026: suportar Anthropic Messages e Gemini generateContent, mantendo OpenAI/compatíveis. A configuração usa credenciais criptografadas da conta, host autorizado e protocolo correspondente; nunca envia a chave ao prompt ou a outro provedor.

A tela preenche a URL oficial e consulta modelos pela API do provedor no servidor. Recomendações usam somente IDs retornados. A validação verifica autenticação e catálogo; não se confunde com inferência ou saldo. Workspace Anthropic é opcional, exigido por chaves de organização. A conexão Branef é configuração de ambiente; nenhuma credencial ou ID de cliente pertence ao núcleo.

Consumo usa os recibos nativos, incluindo cache Anthropic e pensamento Gemini sem duplicar cache. Áudio não é enviado à API de transcrição OpenAI com chave Anthropic/Gemini; o modo textual continua disponível. Transcrição nesses provedores permanece sem adaptador e é informada como limite, sem fallback para chave global.

Testes locais de protocolos, uso, escopo e interface; CI e implantação são evidências separadas.

Fontes: https://platform.claude.com/docs/en/api/messages/create ; https://platform.claude.com/docs/en/api/models/list ; https://platform.claude.com/docs/en/api/migration-2026-10-21 ; https://ai.google.dev/api/generate-content .
