# Verificações técnicas dos áudios institucionais

Status: preparado; pendente de execução nativa no SHA que incorporar este incremento.

As pastas, os recebimentos privados e as versões imutáveis existentes são preservados. Uma observação técnica adicional pertence à versão exata e conserva conta, unidade, usuário, hash esperado, hash observado, resultado do scanner, metadados medidos e tentativa. Não reescreve o arquivo, as migrations anteriores, o histórico ou a política corporativa.

O servidor exige a autorização nativa de configuração e a cobertura atual da unidade antes da leitura, após o processamento externo ao mutex e antes da transação final. Uma mesma chave aceita retorna a mesma observação; uma nova tentativa explícita produz outro registro imutável. A auditoria guarda somente os campos técnicos permitidos, sem chave de armazenamento, URL assinada ou chave de idempotência.

O adaptador ClamAV INSTREAM já existente no Service Desk é reutilizado sem alterações. O Call Center usa uma configuração de socket própria, local, que não muda o scanner dos outros módulos. Scanner ausente, resposta malformada, integridade divergente, processo indisponível ou limite excedido conservam o bloqueio. Nenhum estado de segurança é aceito do cliente.

O ffprobe extrai apenas os sete campos declarados; o ffmpeg também decodifica o arquivo. A conclusão exige progresso final com tempo decodificado positivo: saída com código zero, sozinha, não prova reprodução de um cabeçalho vazio. Os processos recebem um arquivo privado regular no descritor padrão, não recebem um caminho ou URL fornecidos pelo usuário, não herdam segredos do ambiente e não acessam protocolos arbitrários. Cada processo possui limites de tempo, saída, memória e CPU; a inspeção completa também tem limite próprio de 45 segundos. Somente o grupo de processo criado para a operação pode ser encerrado.

Os testes no runner descartável usarão o engine real do ClamAV com uma base exclusivamente sintética, gerada de um WAV inofensivo, e os binários reais do ffmpeg/ffprobe obtidos pelo APT verificado. Esse teste comprova integração, detecção do marcador e tratamento de falhas; não comprova cobertura antimalware, atualização de assinaturas de produção ou homologação de fornecedor. Não inicia serviço do sistema, freshclam, PABX ou operações externas reais.

O histórico apresenta resultados e duração medida, sem inventar zero. A indicação técnica de uma observação válida não é aprovação formal, capacidade do PABX, reprodução ou publicação. Os endpoints genéricos do ActiveStorage continuam negando os bytes; prévia, download, gravação, Nico e publicação exigem incrementos e validações próprios.

A nova tabela será admitida somente com migration adicional, hashes dos helpers, testes de instalação, atualização populada, recarga do schema, concorrência e preservação dos nove domínios anteriores. Nenhuma migration é executada no Windows ou em bancos existentes nesta preparação.

Referências oficiais consultadas: [progresso do FFmpeg](https://ffmpeg.org/ffmpeg.html#Main-options) e [descritor de arquivo e restrição de protocolos](https://ffmpeg.org/ffmpeg-protocols.html#fd).
