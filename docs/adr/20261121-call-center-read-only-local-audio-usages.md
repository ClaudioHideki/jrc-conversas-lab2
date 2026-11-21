# Consulta dos vínculos locais de áudio institucional

Status: implementação preparada; execução nativa e Chrome pendentes no próximo checkpoint.

As figuras 6 e 16 exigem consultar os destinos de um áudio. O vínculo exato de áudio no menu da URA local foi validado no SHA `86ed16c6919adfb4a7abd44c9605dad99cbcb0e4`. Não existe prova de configuração aplicada no PABX nem contrato de vínculos operacionais de números, filas ou campanhas.

A consulta reutiliza `AudioLibraryAccess` e `IvrDraftAccess`. O primeiro autoriza a conta, o usuário autenticável, a capacidade nativa de configuração e a unidade atual do áudio. O segundo mantém tanto a cobertura atual quanto o snapshot corporativo histórico do rascunho. Não há nova permissão, concessão automática, model, migration, cópia de arquivos ou operação no provedor.

O endpoint aditivo de leitura retorna somente as revisões mais recentes dos rascunhos autorizados que ainda contêm o `asset_id` exato. A consulta seleciona a revisão mais recente antes de testar a presença do vínculo. Assim, retirar um vínculo elimina sua ocorrência na consulta atual sem apagar as versões históricas. Rascunhos arquivados continuam identificados como arquivados; não comprovam aplicação ou retirada no PABX.

Cada item contém identificação, nome, revisão e estado do rascunho, unidade e referências de menus com identificação da versão de áudio e SHA-256. Não retorna grafo completo, bytes, blob, URL, transcrição, segredo ou token. O resultado conta rascunhos, não ocorrências de menus. A paginação padrão é de 10 itens, limitada a 20, com ordem estável. A resposta usa `Cache-Control: no-store`.

O botão “Ver vínculos locais” abre o Dialog nativo nos detalhes do áudio. A interface informa os limites da consulta, permite paginação e nova tentativa explícita após erro, apaga resultados ao fechar ou trocar o contexto e não promove uma resposta vazia a prova de ausência de uso externo. A biblioteca nativa já invalida os detalhes após troca de conta, usuário, perfil, capacidades ou unidades autorizadas.

A validação preparada inclui 13 cenários HTTP, cenários Vue de resultado, paginação, erro, negação e respostas tardias, além da extensão dos mesmos 240 cenários Chrome para conferir o vínculo antigo após uma nova versão e sua retirada posterior. São usados banco e arquivos sintéticos, sem simular uma inspeção bem-sucedida. Os resultados ainda precisam ser conferidos no SHA que receber esta implementação.

Permanecem pendentes: vínculos operacionais de outros destinos, ações de duplicação/exclusão com impacto completo, forma de onda, geração TTS e homologação externa. Esta decisão não declara as figuras 6 ou 16 integralmente concluídas.
