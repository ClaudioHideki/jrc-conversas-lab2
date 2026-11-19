# Exclusão da equipe e revisão do último agente configurado

Status: preparado sobre a8c6c78d; não validado nativamente nem homologado.

## Problema confirmado

A remoção de membros nativos já usa a revisão explícita do gestor. O DELETE da entidade Team era independente e podia remover em cascata a fonte funcional AccessGrant sem revisar a perda do último agente elegível configurado em uma fila ativa. Isso não representa presença online nem capacidade confirmada pelo PABX.

## Decisão incremental

O controller core passa a carregar o overlay Enterprise, que protege somente destroy. Reutiliza AuthorityTransaction (lock Account), trava a linha Team antes de revisar/excluir (preservando a revisão diante de um rename concorrente), TeamPolicy e a projeção atual TeamRosterPreview. A operação delete_team projeta a lista vazia e usa o mesmo cálculo de elegibilidade, permissões e cobertura corporativa. Outra fonte direta ou outra equipe continua independente. A confirmação não cria grants.

TeamDeletionReview reutiliza o protocolo TeamRosterWithdrawalReview com propósito criptográfico próprio jrc_cc_team_deletion_v1. O recibo expira em dez minutos, exige confirmed booleano true e é vinculado à conta, gestor, equipe, versão da equipe, membros, agentes elegíveis e versões de fila/unidade. Um recibo de retirada de membro não autoriza excluir a equipe, nem o contrário. Toda chamada reautoriza depois de adquirir o lock.

A auditoria obrigatória em cada fila impactada e a exclusão nativa estão na mesma transação. Mantêm-se callbacks, invalidação de cache, dissociação nativa dos módulos e FKs corporativas. Nenhum vínculo corporativo é removido automaticamente para forçar a exclusão. Falha de FK/RecordNotDestroyed desfaz a transação e retorna team_in_use, sem expor detalhes SQL. Falha da auditoria também impede excluir. A ausência de impacto não inventa uma confirmação ou auditoria.

## Interface reaproveitada

A página existente de Equipes conserva primeiro a confirmação nativa com digitação do nome. Se a API exigir revisão do gestor, reutiliza o diálogo, impacto e checkbox existentes, com textos específicos de exclusão. Não há retry automático. A conta é capturada no pedido; o store não remove dados de outra conta após troca de contexto. O contrato legado de delete por ID e seus erros permanece preservado. O retorno 409 do fluxo novo é mantido sem embrulhar a resposta.

## Validação preparada e limites

Há testes HTTP de confirmação, validade, propósitos, alteração de roster/versões, papel, escopo, conta, fontes independentes, auditoria, bloqueio por FK e compatibilidade sem a feature; três casos de espera real por lock PostgreSQL (Account e linha Team). Os testes Vue incluem a página nativa, API, store e protocolo de revisão. Os testes Vue usam mocks HTTP/diálogo e não constituem homologação de navegador.

Um cenário Chrome em quatro projetos (1440/390, claro/escuro) usa a página de Equipes e as rotas/componentes reais num harness, com confirmação nativa, APIs, cache e banco sintéticos reais. O fixture habilita team_management somente na conta exclusiva deste cenário e cria desde o início seu administrador nativo com elegibilidade e capacidade de auditoria explicitamente sintéticas. A permissão de rota administrador é preservada, sem remover perfis restritivos nem transformar um custom role em administrador. Nenhum dado ou permissão real é alterado. Os 164 cenários anteriores permanecem exigidos; o novo total será 168. Esse incremento ainda não tem resultado executado.

O harness não monta todo o shell do produto. As demais lacunas da figura12 (supervisores/hierarquia/status) e os contratos/capacidades/ACKs externos permanecem abertos. Nenhum comando PABX, build Docker, publicação ou deploy é autorizado por este documento.


## Primeira execução nativa — e0b0feac

CI44484176155/job135423415249 aprovou1168Rails principais, incluindo os22casos HTTP novos, e16schema separados. A suíte de concorrência executou82casos:80passaram e2falharam ao comparar nomes esperados em maiúsculas com a normalização minúscula nativa de Team. As esperas SQL reais e as asserções HTTP409 anteriores a esses pontos passaram; as asserções posteriores ao primeiro erro de cada exemplo ainda exigem reexecução. Nenhum desses dois exemplos é declarado aprovado.

O gate Ruby apontou5infrações novas: ABC26.19no montador de revisão, ABC28.46na coleta de resposta da fixture, dois alinhamentos e uma linha vazia de separação. A correção preserva entradas em maiúsculas e exige nomes normalizados exatos; guarda o propósito confiável da classe ao inicializar o revisor; separa a coleta repetida de status/body da execução HTTP; e corrige só os espaços/linha vazia. Nenhuma regra foi desativada e nenhum assert foi removido.

Artefato14510134218, SHA-25600ac5378bc2ffaefba37c259f522430af85d5647f9a4dd3c38ff460045c3b9b8. Approvals/Backoffice, Vue, frontend e168Chrome não executaram nesse SHA por causa da falha de concorrência. A última prova integral permanece a8c6c78d (1310Rails+16schema,631Vue,164Chrome), que não valida a exclusão de equipe preparada.
