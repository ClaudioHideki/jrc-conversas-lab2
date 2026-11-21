# Compatibilidade de Ogg/Opus na biblioteca institucional

Status: correção implementada; execução nativa e Chrome do novo SHA pendentes.

A CI44843469401 de8348dabe passou Rails, Vue, migrations, lint, assets novos e bootstrap real. O Chrome passou228/236 cenários. Quatro falharam por uma expectativa de aviso antigo e quatro por422 ao salvar gravações feitas pelo dispositivo sintético. A prévia local foi reproduzida nos quatro perfis; isso não comprova persistência.

O projeto fixa Marcel1.1.0. Sua [tabela oficial da versão](https://github.com/rails/marcel/blob/v1.1.0/lib/marcel/tables.rb) identifica Ogg/Opus como `audio/opus`. O recebimento só mapeava `audio/ogg`, rejeitando esse subtipo antes do scanner. O corpo do422 original não foi registrado; a próxima asserção preserva o código do erro, sem payload ou credenciais.

A correção normaliza somente `audio/opus` detectado pelos bytes para o tipo canônico existente `audio/ogg`. Não confia no MIME declarado ou extensão, não reescreve bytes, não altera o Marcel global, dependências, dados históricos, schema, contratos de canal ou permissões. Scanner, hash, decodificação real limitada e transação antes da versão final continuam obrigatórios. Reconhecer o cabeçalho é apenas admissão à inspeção; nunca prova de áudio válido.

Os testes preparados reproduzem a rejeição com o mapa anterior, verificam normalização sem mudança dos bytes e fazem recebimento autenticado de Opus realmente codificado no runner. Um cabeçalho truncado continua exigindo422, sem versão final ou blob de estágio restante. O probe também cobre libopus. Os236cenários Chrome permanecem obrigatórios.

A revisão das capturas identificou nomes de pastas comprimidos a uma letra por linha e ações estreitas no celular. A mesma árvore coloca a ação em linha própria, mantém o nome integral acessível e limita apenas a exibição visual. A mesma tabela e seus controles passam a blocos verticais no celular, com papéis explícitos e cabeçalhos acessíveis; desktop preserva as colunas. Asserções reais de largura/altura complementam a ausência de transbordamento. Não há renderização paralela, novo cadastro ou simulação de uso operacional.

Síntese Nico, vínculos completos, publicação/ACK PABX, cobertura operacional de malware e conclusão das23figuras continuam pendentes. Nenhuma imagem Docker, merge ou deploy foi autorizado por esta decisão.
