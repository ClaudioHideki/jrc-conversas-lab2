# Download privado dos áudios selecionados

Data: 21/11/2026. Estado: implementação preparada; validação nativa e visual obrigatória antes do aceite.

A figura 6 dos dois Word exige seleção de arquivos e ações sobre os selecionados. O incremento acrescenta download em um único ZIP à biblioteca existente, com seleção na lista e barra de ações abaixo dela. Não cria catálogo, armazenamento, permissão, migration ou integração de fornecedor.

O endpoint recebe somente uma lista de identidade do ativo, versão, observação técnica e SHA-256. `AudioLibraryAccess` revalida usuário, conta, capacidade nativa `configure` e cobertura de unidade. As versões devem pertencer à mesma unidade autorizada. Conta, usuário e unidade informados pelo cliente não concedem acesso. A leitura usa `AudioBytes`, incluindo nova verificação de hash, inspeção atual e auditoria nativa. Antes da liberação do ZIP, todas as fontes são novamente autorizadas. Uma falha impede a resposta ZIP completa; uma leitura efetivamente realizada continua registrada como leitura, sem ser apresentada como entrega concluída.

A revisão consulta também `AudioIvrUsages`, preservando seus escopos e sua cobertura declarada: apenas cabeças atuais de rascunhos locais de URA autorizados. O manifesto repete essa limitação. Um total zero não prova ausência de vínculos em filas, números, campanhas ou PABX. Download não modifica nenhum vínculo. Exclusão de ativos e publicação permanecem indisponíveis neste incremento.

O servidor admite no máximo 20 versões e limita a soma dos arquivos ao menor valor entre 40 MiB e o limite atual do leitor institucional. A interface recebe esses limites da API e não baixa arquivos ao selecionar ou abrir a revisão. As versões e observações são fixadas; alteração concorrente exige seleção atualizada, sem substituição silenciosa. A seleção é limpa ao trocar conta, unidade, perfil ou lista. Uma confirmação explícita inicia uma única requisição em andamento.

O ZIP é construído em memória com a dependência `rubyzip` já fixada no projeto, sem instalar ou atualizar bibliotecas. Os nomes internos são técnicos e únicos, derivados da identidade e número da versão; nomes fornecidos pelos usuários não viram caminhos. `manifesto.json` contém identificação, versões, integridade, nomes e verificação limitada de vínculos. Não contém locators de armazenamento, tokens ou credenciais. A resposta usa `no-store`, `nosniff` e recibos de conta, unidade, seleção, contagem, bytes e digest do ZIP. O navegador verifica identidade e hash antes de entregar o download; a interface orienta conferir a conclusão no navegador, sem afirmar gravação no disco.

API da biblioteca: [Rubyzip — streaming e buffer de saída](https://github.com/rubyzip/rubyzip). A prevenção de entradas duplicadas é explícita e não depende de comportamento de versões futuras da biblioteca.

Testes preparados: entrada, serviço real de ZIP e leitura autorizada, APIs autenticadas, fontes corrompidas, revogação durante a geração, observação substituída, limites, unidades, transporte Vue, revisão, navegação e download real no Chrome em quatro projetos. Unidades locais com transporte substituído são evidência preliminar separada. Não comprovam PostgreSQL, ClamAV, codecs, ZIP nativo ou Chrome.

Permanecem separados: operações em lote de cópia/movimentação, exclusão com dependências publicadas, síntese Nico, codecs/publicação/ACKs do fornecedor e demais lacunas dos Word. Nenhuma das 23 figuras é declarada concluída por este incremento.
