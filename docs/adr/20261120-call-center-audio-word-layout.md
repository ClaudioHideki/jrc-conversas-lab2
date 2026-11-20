# Biblioteca institucional em navegação, tabela e detalhes

Estado: implementação preparada; lint direcionado aprovado, Vue e Chrome pendentes.

As figuras 6 e 16 do complemento mostram navegação de pastas, lista de arquivos e detalhes. A lista vertical anterior apresentava até vinte pastas antes dos arquivos, alongando a página. A revisão conserva os mesmos recursos e APIs: usa colunas em desktop e empilhamento em celular, com rolagem contida nas pastas e na tabela. Os formulários de organização continuam nos popups nativos, com revisão e controle de concorrência.

A seleção de um arquivo consulta novamente `audioAsset`, identifica conta e unidade da resposta e apresenta os metadados autorizados no painel de detalhes. Respostas atrasadas não substituem outra seleção. Mudança de conta, unidade, pasta, perfil, filtros ou página limpa o painel; acesso negado limpa os dados privados. O painel reutiliza as verificações por versão e o componente de prévia existente, sem iniciar leitura de bytes automaticamente.

Nome, pasta, descrição, finalidade, versão, tamanho, formato e hash vêm do servidor. Duração e demais informações técnicas permanecem na observação real da versão, aberta pelo usuário. Não se desenha waveform fictício nem se converte ausência de metadados em duração zero. O estado de arquivo privado e o bloqueio de uso no PABX são explícitos.

Esta revisão não fecha as figuras inteiras. A árvore completa, as colunas de uso/duração por arquivo, os vínculos reais e suas ações, duplicação/exclusão com dependências, captura e geração pelo Nico continuam na matriz. Nenhum contrato externo, capacidade de publicação ou estado operacional do PABX é presumido.

Cinco casos Vue de interação e concorrência de seleção foram preparados. Os quatro cenários Chrome de recebimento existentes mantêm toda a cobertura e acrescentam medidas reais de disposição/rolagem, detalhes da API e inspeção persistida, nos dois tamanhos e temas. As evidências devem pertencer ao novo SHA; capturas anteriores não comprovam esta interface.
