# Forma de onda da biblioteca institucional

Estado: implementação preparada; testes nativos e Chrome do novo SHA ainda necessários.

A figura 16 e o complemento, linha 338, pedem player/forma de onda no painel de detalhes do arquivo institucional. O produto já possui o player privado `AudioVersionPreview`, autorização por conta/unidade, inspeção técnica e comparação SHA-256 no `useAudioBytes`. O catálogo de gravações telefônicas permanece distinto.

Reutilizamos `wavesurfer.js` 7.8.6, dependência já presente e usada pelo `AudioRecorder`; não adicionamos pacote nem outro player. A forma de onda recebe o mesmo objeto de mídia HTML e a mesma URL de Blob criada somente depois da leitura autorizada e da comparação de integridade. Não recebe URL do provedor, localizador de armazenamento, token nem picos inventados. Não inicia reprodução ou consulta autenticada adicional. Reprodução, pausa, volume, busca e acessibilidade continuam nos controles nativos existentes; a visualização é somente leitura.

A renderização opcional é limitada a 20 MiB, dez minutos e até dois canais, com amostragem visual de 8 kHz. Estes são limites de memória da visualização, não limites novos para upload, download ou reprodução. A duração e os canais vêm da observação técnica real da versão. Fora desses limites ou se a decodificação falhar, a interface informa a indisponibilidade da forma de onda e mantém o player e download autorizados. O erro interno da biblioteca não é mostrado.

Trocar versão, fechar a prévia, perder autorização ou desmontar a tela desfaz o renderer; respostas tardias de decodificação não substituem o estado atual. O controle de gerações e revogação da URL privada existente permanece. O desenho usa as cores Tailwind do tema. Não há armazenamento de picos ou alteração de migrations, APIs, permissões, históricos ou configurações PABX.

Referências verificadas: código fixado do produto `015628bf157f17a581715b47ee282cf35639d013`, `package.json` e `AudioRecorder.vue`; [opções oficiais](https://wavesurfer.xyz/docs/types/wavesurfer.WaveSurferOptions), [carregamento e descarte na versão 7.8.6](https://github.com/katspaugh/wavesurfer.js/blob/7.8.6/src/wavesurfer.ts) e [tratamento de mídia externa nessa versão](https://github.com/katspaugh/wavesurfer.js/blob/7.8.6/src/player.ts).

Os testes Vue usam a biblioteca substituída, portanto não provam o decoder ou CSS real. O caso Chrome existente de prévia privada conserva todas as verificações anteriores e acrescenta desenho, quantidade real de amostras, canvas, fechamento, revogação e recibo, nos quatro projetos. A origem é o WAV sintético realmente silencioso de dois segundos; uma linha plana é correta, e não se fabricam picos para melhorar a captura. A evidência deve pertencer ao novo SHA antes do aceite.

Continuam pendentes destinos externos, publicação, codecs do PABX, TTS e os demais critérios das figuras 6/16. Esta alteração não conclui as figuras inteiras nem a revisão humana do Nico.
