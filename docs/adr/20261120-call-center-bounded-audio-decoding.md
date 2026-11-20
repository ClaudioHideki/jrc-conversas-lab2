# Inspeção técnica de áudios por descritor privado

Status: preparação; sem validação nativa deste incremento.

As figuras 6 e 16 exigem duração, formato e prévia reais. A admissão por cabeçalho não prova que um codec pode ser decodificado. O recebimento privado continua sem player, download, publicação ou indicação de segurança aprovada.

A próxima implementação usa FFprobe para metadados e FFmpeg para decodificação efetiva, ambos sem shell. O único input é o descritor regular e seekable do arquivo pertencente à operação, por `fd:`. A lista de protocolos do produto permite apenas `fd`, com containers explícitos. Não há URL, nome de arquivo privado, tags ou credenciais nos argumentos e resultados. Limites de CPU, memória, saída e tempo abrangem apenas o processo criado pela chamada; um limite de recursos ou dependência ausente representa indisponibilidade, não arquivo comprovadamente inválido.

Os testes preparados utilizam WAV sintético real e codificações MP3/OGG/MP4 geradas no próprio runner, sem JSON substituir o executável. Também cobrem cabeçalho sem amostras, playlist externa, dependência ausente, limite de saída, timeout, ambiente mínimo e preservação do descritor do chamador. Ainda não foram executados. Não comprovam compatibilidade com o codec do PABX.

Este incremento não adiciona regras de negócio, scanner alternativo, tabela de inspeções incompleta, endpoint de liberação ou conversão/publicação. Uma futura liberação exige observação imutável da versão exata, SHA-256 dos bytes, scanner nativo com resultado válido, decodificação comprovada e reautorização de conta/unidade. O modelo de inspeção em preparação permanece fora do checkpoint até que seu schema e suas políticas estejam completos.

`AudioSafetyObservation`, ainda fora do checkpoint e sem execução nativa, prepara essa correlação reutilizando `JrcServiceDesk::AttachmentScanner` e suas verificações de socket local. A configuração específica `JRC_CC_AUDIO_CLAMAV_SOCKET` não altera o scanner ou as variáveis do Service Desk. Ausência do serviço, resposta malformada ou falta do SHA correto mantêm a observação bloqueada. Os testes de composição com doubles são identificados como contratos de dependências, separados dos testes que executam FFmpeg/FFprobe reais. Nenhum resultado isolado desse serviço autoriza reprodução nem modifica o estado de uma versão.

A disponibilidade/versionamento de FFmpeg no runner e no runtime deverão ser verificados, sem assumir que a imagem já o inclui. Não há build Docker autorizado nesta frente.
