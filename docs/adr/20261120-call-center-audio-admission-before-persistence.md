# Validar o áudio institucional antes da versão final

Estado: implementação preparada; execução nativa e Chrome pendentes.

O complemento do Word, Figura 6, parágrafo 0158, exige que a falta de arquivo ou falha de codec seja rejeitada antes da persistência final. O recebimento anterior mantinha os bytes privados, mas já criava a versão em quarentena antes da inspeção manual. Essa proteção não atendia integralmente ao critério do documento.

O upload nativo continua criando somente seu próprio blob privado temporário. Antes de criar o ativo ou a versão final, reutiliza `AudioSafetyObservation`: integridade dos bytes, scanner e somente depois decodificação real, com os mesmos limites de tempo e recursos. Scanner indisponível, infecção, alteração de integridade ou codec inválido bloqueiam o recebimento. A compensação usa o mecanismo existente e alcança somente o blob ainda não vinculado desta tentativa.

A versão imutável e a observação inicial são gravadas na mesma transação, com reautorização nativa da conta, usuário e unidade depois do I/O. Falha na auditoria de qualquer registro desfaz a operação inteira. A observação possui chave e digest de operação distintos da inspeção manual. Nenhuma informação de segurança enviada pelo navegador é aceita como evidência.

Uma repetição exata já aceita retorna o recibo anterior, sem regravar histórico nem exigir uma nova inspeção para a mesma operação. Isso também preserva recibos legados: repetir uma operação histórica não os transforma em arquivos verificados. A prévia continua exigindo autorização atual, observação atual válida e verificação dos bytes no momento da leitura.

Os testes que precisam representar quarentenas históricas passam a criá-las explicitamente por `SyntheticLegacyAudioReceipt`, limitado pelo guard de PostgreSQL, Redis e armazenamento exclusivo do runner descartável. Esse fixture não é uma rota pública nem um modo alternativo do upload. Os novos uploads de teste, inclusive os concorrentes, continuam passando pelo scanner e decodificador reais. A base de assinaturas usada na CI é sintética; não comprova cobertura antimalware de produção.

O editor conserva metadados após rejeição definitiva e permite selecionar outro arquivo. Uma resposta explícita de indisponibilidade anterior à persistência conserva arquivo e dados para revisão. Respostas ausentes ou incertas mantêm a solicitação original e sua chave; não são tratadas como rejeições definitivas.

Não há nova migration, mudança de permissões ou publicação de áudio no PABX. A disponibilidade operacional dos binários, do scanner e de sua base real permanece requisito de uma futura homologação do ambiente. A CI não configura produção.

A primeira execução nativa (`3e631663`, run `44816431858`) manteve a exclusão bloqueada, mas mostrou que o callback de dependências da inspeção era executado antes da proteção `readonly?`, produzindo `RecordNotDestroyed`. A correção local antecipa a proteção imutável de `AudioVersion`, preservando a exceção `ReadOnlyRecord` e evitando callbacks/auditoria de destruição em histórico persistido. O concern compartilhado e os SQLs históricos permanecem intactos. Teste específico de `destroy` e `destroy!` preparado; a nova execução ainda é necessária.
