# Biblioteca de áudios: organização, download e inspeção

Status: implementada incrementalmente; validação nativa e Chrome pendentes deste incremento.

A figura6 permite organizar os registros da biblioteca, inclusive aqueles sem arquivo ou sem inspeção concluída. Isso não concede acesso aos bytes.

A biblioteca existente oferece a finalidade explícita da seleção. Download continua exigindo os arquivos e provas técnicas já autorizados; organização reutiliza o movimento de pastas com identidade, revisão, unidade, configuração e auditoria nativas. A troca de finalidade descarta a seleção e a revisão anteriores. Os limites são anunciados pela API autorizada, sem valores de capacidade inventados no cliente.

O popup diferencia o estado nativo `latest_version: null` de uma resposta incompleta. Sem arquivo, não exibe versão, checksum ou contagem de bytes fictícios. As inspeções, versões e permissões permanecem intactas.

O filtro de inspeção usa a última versão e a última tentativa nativas, antes da contagem e paginação. Um scanner sem ameaça não autoriza bytes: as verificações de decodificação e integridade permanecem nativas. Valores inválidos falham explicitamente; não retornam uma lista mais ampla.

Os102 casos preliminares incluem76 anteriores e26 novos com transportes simulados; não são prova de persistência ou CSS. Há13 casos Rails preparados: API de metadados, preservação do fixture nativo e filtros de inspeção, sem arquivo nem prova técnica inventados. Exigir a CI com PostgreSQL sintético, API autenticada e Chrome real antes do aceite. Publicação/ACKs e inventário de vínculos externos continuam pendentes de contrato do fornecedor.
