# Rascunhos locais de URA: contrato interno separado do PABX

Estado: núcleo local validado em 7ab118ba; persistência transacional preparada no próximo incremento, ainda sem API/editor ou aceite de produto.

## Requisito e código auditado

Os dois Word, seção de URAs, exigem rascunho, importação/exportação JSON versionada, referências autorizadas, simulação DTMF e bloqueio de loops sem saída. As figuras 4/13 são painel técnico, não um editor de URA. O catálogo visual ivrBuilder não constitui persistência nem simulação.

Existem Unit, Queue, RoutingRule e IvrEvent, mas não há entidade nativa de rascunho/versionamento de fluxo. RoutingRule e IvrEvent não devem ser usados como depósito de JSON de outro domínio. A API/configuração do fornecedor não define publicação ou formato de fluxo. Não declarar um esquema interno como contrato PABX.

## Proposta aditiva

- Reutilizar Current.account, ModulePolicy.configure?, AccessScope/OrganizationalScope e AuthorityTransaction; nenhum novo papel ou grant automático. Unidade do rascunho imutável e pertencente ao escopo atual. Cada referência a fila é revalidada dentro do escopo na gravação e simulação.
- Acrescentar rascunhos locais e revisões imutáveis em tabelas próprias, sem outro cadastro de usuários/equipes/filas. Conta e unidade protegidas por FKs compostas; não alterar migrations históricas. Antes de qualquer nova migration, auditar colisões e ampliar somente a lista exata de hashes revisados do gate.
- Contrato JSON interno explícito v1 para menus DTMF, encaminhamento lógico a fila e término. Nenhum destino HTTP, código executável ou comando externo. Tempos/tentativas operacionais devem ser preenchidos explicitamente nos exemplos sintéticos; não presumir limites ou compatibilidade do fornecedor.
- Validar formato, IDs únicos, destinos existentes, opções DTMF exclusivas e caminhos sem saída. Simulação determinística e limitada retorna apenas percurso local/destino lógico; nunca uma chamada, ACK ou estado aplicado.
- Salvamento com revisão esperada, transação e idempotência. Rejeição não substitui a versão anterior; conflitos preservam o rascunho no editor. Histórico permanece imutável; arquivamento local não exclui revisões.
- Reutilizar a proteção append-only existente e o dumper PostgreSQL em lib/jrc_postgres_schema_dumper.rb, que já preserva funções/triggers/checks. Provar imutabilidade SQL, recarga do schema e ciclo de conta; não copiar o schema inteiro com divergências históricas.
- Reutilizar diálogos, listas, paginação, campos e navegação do Control Desk. A listagem externa continua separada de rascunhos locais. Áudio, calendário, DAC e publicação não serão apresentados como suportados antes dos contratos correspondentes.

## Aceite antes de considerar implementado

Rails/PostgreSQL reais em banco descartável: criação/edição/histórico, JSON inválido, ciclos, fila estrangeira/inativa, conta/unidade negadas, permissão revogada, concorrência e idempotência, FKs e exclusão de conta. Vue e Chrome: criar/importar/revisar/simular/exportar/recarregar, erro e conflito, desktop/celular claro/escuro, sem chamadas externas. Preservar integralmente os 96 cenários atuais e todos os gates.

## Limite externo

Publicação, homologação de voz/codec, aplicação/rollback PABX e aprovação de uma versão executável continuam bloqueados até contrato real. Uma simulação local aprovada não libera produção nem substitui o fornecedor.

## Primeiro subincremento preparado

IvrGraphSchema usa o JSONSchemer 0.2.24 já fixado no projeto. IvrGraph/Paths verificam identidade atual, elegibilidade, escopo, filas ativas da mesma unidade, IDs e DTMF exclusivos e saída alcançável em todos os nós. IvrSimulator reautoriza a cada uso, não guarda dígitos na trilha e não cria CallSession, Command ou EventInbox. Os limites de 128 nós/opções DTMF de até doze teclas, 1 MiB de definição e 256 passos/128 dígitos são proteções computacionais locais, não capacidades do PABX. A versão local inicial aceita destinos de fila na mesma unidade; expansão de roteamento entre unidades permanece requisito futuro, sem concessão implícita de escopo.

Estão preparados testes Rails com banco nativo para JSON inválido, versão estrita, caracteres de controle, ciclos, opções, referências, conta/unidade, reutilização após revogação e ausência de operações externas. Persistência de rascunhos/revisões, API, importação/exportação e interface ainda não foram implementadas; o núcleo não é anunciado como funcionalidade já disponível ao operador. Nenhuma migration nova foi criada nesta fase.

## Evidência do núcleo e correção de lint

CI 44214303140, SHA 7ab118baf6e27fc393f7c4a28facab99b8bf168b: 672 Rails principais + 14 concorrentes, 250 Vue e 96 Chrome aprovados, zero falhas/pendências/erros. Os 45 casos de IvrGraph/IvrSimulator passaram nativamente. 120 capturas verificadas; artefato 14388776353, SHA-256 f1daadbc66e328254fa2d743b487ee06982741efca2b28027159724b56515dd6. O SHA anterior 120fc72f passou os mesmos exemplos Rails/Vue, mas parou no lint; suas oito infrações foram corrigidas sem supressões.

## Persistência preparada: revisão técnica antes da CI

Migration aditiva 20261117200000_create_contact_center_ivr_drafts.rb, SHA-256 67424d8158f78886a716b37998026fabed35edc9cce9c30db07f37524311dc90. O inventário remoto não contém esse caminho ou timestamps duplicados. A migration anterior 20261117190000 permanece byte a byte inalterada; schema/SQLs/migrations históricos não mudam. O gate preserva o verificador antigo e seus testes, e admite no candidato somente as duas adições exatas por caminho/hash, com novos testes negativos para omissão, duplicação, conteúdo alterado, schema/SQL e migração desconhecida. A verificação Node local encontrou EPERM ao criar subprocesso: não foi contornada; os testes serão executados no runner isolado.

A identidade IvrDraft tem conta, unidade e fotografia corporativa imutáveis, capturada no banco a partir da unidade real. Os valores editáveis ficam somente em IvrDraftVersion, sequência append-only por rascunho, UUID de operação único por conta e checksum gerado no PostgreSQL. O cabeçalho é a maior revisão, sem ponteiro mutável nem FK cíclica. Trigger diferido exige a primeira revisão na mesma transação. FKs compostas protegem conta/unidade; a FK de unidade é diferida para preservar o ciclo nativo de exclusão de conta. Triggers recusam UPDATE/DELETE enquanto a conta existir. Remoção de conta pode executar o cascade nativo; retirada de usuário não apaga o recibo histórico do autor. Nenhum grant é criado pela migration.

IvrDraftAccess combina a política configure?, elegibilidade e unidade atuais com a fotografia corporativa histórica; uma troca da unidade para outra empresa não transfere os rascunhos antigos. Remover a estrutura corporativa também não reativa acesso legado a artefatos previamente classificados. GROUP é explícito e continua limitado à conta. IvrDraftWrite usa AuthorityTransaction, relê o escopo após locks, exige revisão esperada e torna repetição de UUID verificável por ator, destino e conteúdo. Recibo antigo não substitui o cabeçalho mais recente. Escrita/simulação exige referências atuais; leitura de histórico e arquivamento local preservam definições antigas mesmo com fila inativa. Remapeamento corporativo bloqueia nova edição da mesma identidade; requer outro rascunho revisado, sem reclassificação silenciosa.

A revisão e a auditoria nativa são gravadas na mesma transação. A auditoria lista somente revisão, estado, checksum e escopo; nome, grafo e DTMF não entram no payload do log de auditoria. A API futura deverá filtrar também os parâmetros de definição/DTMF antes de ser exposta. Nenhum endpoint, formulário ou caminho de publicação foi acrescentado neste subincremento.

Testes preparados: inserção, sequência, idempotência e conflitos, reautorização, falha/rollback da auditoria, escopo histórico/atual, alteração e exclusão SQL, vínculos/autor estrangeiros, exclusão de conta, upgrade populado/reexecução e recarga do schema em banco separado. Os mesmos testes de ledger serão executados depois da recarga do schema, não apenas inspeção dos nomes dos triggers. Execução nativa deste incremento ainda pendente; concorrência HTTP, API, paginação e editor/Chrome específicos permanecem próximos critérios, sem declarar URA concluída.

## Primeiro gate da persistência e ajuste mínimo

207bc523 / CI 44216984172: instalação/migration e recarga do schema executadas; 14 dos 15 exemplos do ledger passaram no banco recarregado. O único erro era uma suposição do teste sobre exclusão direta de Account: a FK nativa de Unit→Account já a bloqueia. A FK foi preservada. A prova foi dividida em rejeição/rollback da exclusão prematura e retirada atômica explícita unidade-antes-conta, para conferir que as novas FKs diferidas não impedem a ordem existente. Isso não cria endpoint ou rotina de exclusão de contas e não homologa o ciclo completo dos demais módulos.

O lint identificou complexidade no validador de entrada, atribuições paralelas, alinhamentos, merges de keywords e uso de update_all nos testes. As verificações negativas de imutabilidade SQL continuam passando por SQL real, agora explicitamente pela conexão; os testes de cobertura usam update! validado. As expectativas de auditoria foram separadas em exemplos focados, sem remoção de asserções. Nenhuma regra foi desligada.

A migration desta candidata, ainda não implantada, recebeu somente alinhamento e .squish nos três heredocs. Hash anterior 5463324499ceb16908d3605552339cb4c7370881871ea643174976ac8252257c; hash atual 67424d8158f78886a716b37998026fabed35edc9cce9c30db07f37524311dc90. Os três blocos SQL normalizados foram comparados e permanecem idênticos. O gate e o transporte continuam aceitando apenas os caminhos/hashes exatos revisados. Migration histórica de elegibilidade e demais SQLs/schema não foram alterados.

A etapa auxiliar opcional de sugestões de formatter também falhou; suas sugestões não foram usadas nem declaradas aprovadas. O próximo SHA deve passar lint e todos os testes nativos novamente. Não atribuir os resultados do núcleo ou do schema parcial à persistência completa.
