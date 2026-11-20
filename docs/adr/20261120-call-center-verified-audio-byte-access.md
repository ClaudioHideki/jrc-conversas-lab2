# Prévia privada de versões de áudio verificadas

Status: implementação preparada; aceite nativo e Chrome pendentes.

A biblioteca institucional permanece separada das gravações. A política nativa `configure?` e a cobertura corporativa da unidade são verificadas antes e depois da leitura. O endpoint autenticado não usa IDs, chaves ou URLs assinadas de ActiveStorage como concessão de acesso. Somente a observação técnica mais recente, limpa e decodificada, pode autorizar a versão exata. Uma tentativa posterior indisponível bloqueia o uso da anterior.

Os bytes devolvidos precisam passar pelo checksum nativo, tamanho e SHA-256. O navegador também confere conta, unidade, versão, observação e hash antes de criar uma URL temporária. A troca de contexto ou permissão, o fechamento e a desmontagem revogam essa URL. Não há autoplay. O download exige clique e usa o mesmo buffer validado; respostas são `no-store`.

Essa decisão não concede participação em filas, acesso a gravações, publicação PABX nem compatibilidade com codecs do fornecedor. O scanner real de teste usa uma base exclusivamente sintética: testes positivos não equivalem a cobertura de malware ou homologação externa.

Testes preparados em `audio_bytes_spec.rb` (serviço e requisições), `useAudioBytes.spec.js`, contratos de API e quatro projetos Chrome. Os hashes e limitações estão em `docs/jrc_contact_center/audio_verified_bytes_prepared_20261120.json`. As nove migrations anteriores e a definição da migration de inspeções permanecem intactas neste incremento.

A liberação de bytes também registra ação nativa `read` com ator e escopo atual na mesma transação final. O snapshot não contém nome privado, chave de armazenamento ou bytes. Os filtros existentes ganham somente a ação de leitura e sua tradução; os controles de escopo permanecem intactos. O evento prova a liberação pelo servidor, não cada reprodução/download local posterior do mesmo buffer. Não se modifica a versão imutável para registrar a leitura.

Mesmo com prévia aberta, Baixar realiza outra requisição autenticada e verifica novamente escopo, observação e bytes. O buffer anterior não concede acesso ao novo download. O evento nativo fixa a inspeção, a versão e o hash e recebe o ator explicitamente, sem alterar `Current`. Não se afirma que cada reprodução local posterior foi auditada.
