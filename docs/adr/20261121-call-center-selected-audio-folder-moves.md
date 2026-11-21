# Movimentação de áudios institucionais selecionados

Status: implementação inicial no overlay próprio; banco nativo e Chrome ainda pendentes.

As figuras 6 e 16 exigem reorganização entre pastas sem alterar a identidade do áudio nem suas versões e referências. A gravação individual existente já usa `AudioLibraryAccess`, `AudioAssetRevision`, `AuthorityTransaction` e os callbacks de auditoria do `AudioAsset`. O incremento compõe essas mesmas regras numa transação limitada a vinte identidades distintas de uma única unidade.

O servidor deriva usuário, conta e cobertura da sessão nativa. Os parâmetros `unit_id`, `folder_id` e IDs selecionam registros dentro dessa cobertura; nenhum deles concede acesso. As revisões de todos os áudios são verificadas antes da primeira gravação. Uma origem inválida, uma revisão vencida, um erro de auditoria ou uma perda de autoridade invalida toda a operação. A ordenação de gravação é determinística. Uma escolha já posicionada no destino não produz outra atualização nem outra auditoria.

Somente `folder_id` pode mudar. Não são gerados arquivos, versões, inspeções ou permissões. Os IDs e caminhos de armazenamento permanecem estáveis. A versão publicada não é atualizada, e não há comandos ao PABX. A checagem de vínculos apresentada é explicitamente limitada aos rascunhos locais de URA autorizados; não representa inventário completo do fornecedor.

O popup reutiliza o Dialog e o seletor de pastas nativos. Exige consulta atual de metadados, conferência de vínculos locais e revisão explícita do destino. Mudança de perfil, conta, unidade ou seleção elimina o estado privado; respostas tardias não são aplicadas a outro contexto. Uma falha ou resposta incerta conserva a intenção para conferência, mas bloqueia outra gravação até nova revisão. Repetição de um pedido já aplicado encontra a revisão antiga e não gera outra atualização silenciosa.

Nesta primeira interface, o acionamento reutiliza a seleção de arquivos tecnicamente verificados já existente para ZIP. A movimentação individual de metadados continua disponível para os demais áudios. O backend de movimentação não usa inspeção ou acesso a gravações como fonte de autoridade. A extensão da seleção em lote para todos os estados de metadados permanece um critério separado; esta entrega não conclui integralmente a figura 6.

As provas obrigatórias incluem autorização por conta/unidade/perfil, revisão vencida sem gravação parcial, rollback da auditoria, preservação dos bytes e versões, duas sessões HTTP concorrentes e perda de autoridade após espera real pelo mutex da conta. A interface deve ser testada em 1440/390 px, claro/escuro, incluindo CSS calculado, persistência após navegação, acesso negado e retorno revisado à raiz.

Não há migrations, dependências novas, concessões reais, limpeza, publicação Docker ou alteração de ambientes existentes neste incremento.
