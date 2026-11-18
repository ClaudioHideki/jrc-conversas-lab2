# Rascunhos locais de URA: contrato interno separado do PABX

Estado: núcleo e persistência local validados em 6a8b9c72. API/editor preparados em incremento separado; dependem dos novos testes nativos e de 108 cenários Chrome. Não há publicação PABX ou aceite integral das 23 figuras.

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


## Segundo gate da persistência

868ecad5 / CI 44219155439: 16/16 exemplos do ledger passaram no schema recarregado. Na suíte principal, 729/730 passaram; o cenário de schema adulterado gerou corretamente ActiveRecord::MigrationError, mas o matcher esperava a mensagem sem as linhas em branco que Rails acrescenta. O teste mantém a classe e o texto significativo por regex. Restavam quatro infrações de lint: separação de private, continuação de argumentos e tamanho do método SQL. O recibo e todas as asserções de bloqueio permanecem.

O trecho de validação do vínculo do autor foi separado do SQL de sequência/digest, sem mudar o SQL final montado. Hash desta migration ainda não implantada: 67424d8158f78886a716b37998026fabed35edc9cce9c30db07f37524311dc90 → eaeb4147658fd8e5c9bf25272c34bf5ed3113cf603856854906620f128d92e91. Comparação dos três comandos montados normalizados confirmou igualdade; nenhuma FK, trigger ou capacidade foi removida. Revalidação do novo SHA obrigatória; os exemplos da suíte principal ainda não representam aprovação integral.


## Persistência validada e próximo incremento de interface — 18/11/2026

6a8b9c72112cd36500c4f4429203b51da1fbb0d7 / CI 44220513593: 730 exemplos Rails principais e 14 concorrentes, 250 Vue e 96/96 Chrome aprovados, zero falhas, pendências ou erros externos. Os 16 exemplos do ledger foram também reexecutados no banco separado criado pela recarga do schema; não são 16 casos únicos adicionais. Instalação, upgrade populado, reexecução, lints, assets e bootstrap passaram. Artefato 14390294705, SHA-256 90e947cc7bdfa34bf80e08460f1ad1508cd10c22f838481394e95554794d79d6; 120 capturas verificadas. Migration exata eaeb4147658fd8e5c9bf25272c34bf5ed3113cf603856854906620f128d92e91. Nenhuma execução local ou em produção.

Próximo incremento preparado: API autenticada de lista/detalhe/criação/revisão/histórico/exportação/simulação, editor nativo em popup com abas, importação JSON local, filtros/paginação e navegação por rota existente. Não é outro cadastro de filas/unidades. Reutiliza as políticas, escopos, auditoria, diálogos e resolução nativa de conflitos. Filas válidas nesta versão são de voz e da mesma unidade; o servidor valida as referências, independentemente do formulário.

Listagem retorna metadados autorizados, até 100 itens por página (editor usa 20). Histórico usa 20 revisões por página. Definição somente no detalhe/exportação autorizados. Parâmetros ivr_draft, ivr_preview e ivr_simulation são integralmente filtrados dos logs. Exportação identifica a revisão e seu checksum; o autor histórico é identificado pelo ID registrado, sem inventar nome ou expor e-mail. A unidade e a fotografia corporativa não podem ser reclassificadas pela API.

Erro de rede após envio preserva corpo, destino e UUID originais; campos ficam bloqueados para a repetição segura. Conflito exige carregar e revisar o estado atual antes de nova gravação. Importação/JSON pendente não substitui silenciosamente o grafo. Troca de conta/ator/perfil desmonta o editor e invalida respostas atrasadas. Simulação tem resultado local explícito e nunca produz chamada ou comando externo. Arquivar/restaurar cria revisão local, sem alegar rollback PABX.

Provas preparadas: APIs com banco real, permissões, filtros, paginação, revisão e repetição, três corridas HTTP reais (revisão, UUID e revogação após lock), Vue focado e 12 cenários Chrome adicionais. Quatro contas sintéticas exclusivas mantêm os dados dos 96 cenários anteriores intactos. Novo gate exige 108/108, desktop 1440/celular 390 e claro/escuro. Os resultados antigos não comprovam estes incrementos ainda não executados. Não foram alterados critérios, dependências ou permissões reais.

Permanecem pendentes áudio/mídia, calendários/horários, roteamento entre unidades, DAC, capacidades efetivas do fornecedor, aprovação/publicação/ACK/rollback e homologação externa. A conclusão do editor local não representa conclusão de URA ou das etapas 0–8.


## Primeiro gate da API/editor e lint — 18/11/2026

804413eca5cf5cad4cab4b18b4e7ad3d1d8544f2 / CI 44230570088: 762 exemplos Rails principais, 17 concorrentes (incluindo as três novas corridas HTTP reais), 16 reexecuções do ledger no schema recarregado e 290 Vue passaram, zero falhas/pendências/erros. Frontend lint aprovado. Artefato 14395428784, SHA-256 2c2a3020f962700551ca56dc8c719499240ee38dbce19169722477ac5511c45a. Os 108 Chrome não executaram: 29 infrações Ruby bloquearam o gate.

Correções restritas aos diagnósticos: extração da validação da página de histórico e da simulação de revisão; separação do despacho/preparação da sessão HTTP concorrente sem alterar barreiras ou locks; where qualificado do alias SQL, alinhamentos, guard clauses, Array.new para contagens positivas, parsed_body e keywords diretas. A asserção de criação sai do let e permanece em exemplo explícito adicional; nenhuma asserção foi retirada. Nenhuma configuração de lint foi alterada. Nova CI obrigatória antes de aceitar editor/importação/exportação/Chrome.


## Complemento de aceite local em preparação

O Word complementar, seção 5, exige visualizar rascunho e diagrama (D01 distingue isso das figuras 4/13 do painel PABX). O editor ganha um mapa somente de leitura derivado do mesmo grafo editável: entrada, teclas, destinos de timeout/tentativas, fila lógica e término. Destino ainda não preenchido fica pendente; nenhum fallback é inventado. Não há modelo paralelo, comando ou publicação. Três Vue específicos e asserções nos quatro projetos Chrome devem conferir o mapa.

O cenário real de arquivos é ampliado para importar JSON válido pelo input de arquivo, além da rejeição do inválido e da aplicação manual de JSON. Após arquivamento, deve executar a restauração como revisão 4 e conferir que a revisão 1 continua acessível. As 108 identidades permanecem, sem remoção de asserções; o novo SHA precisa provar essas ampliações. Não atribuir ao SHA anterior a interface e os testes ainda preparados.


## Chrome da API/editor: causas observadas e correções

4d06013ff56b51aa2b7d486bc2a91aa5921355f4 / CI 44233151968: 763 Rails principais + 17 concorrentes, 16 reexecuções no schema recarregado, 290 Vue, ambos os lints, migrations, assets e bootstrap real aprovados. Chrome 100/108: os 96 anteriores e os quatro casos novos de isolamento corporativo/URLs/elegibilidade passaram. Oito falhas restantes são os mesmos dois caminhos nos quatro projetos; não foram marcadas como aprovação. Artefato 14397725189, SHA-256 1fcd3b2a8cbfb045dcbd8c8f312846c13ce5898fa7815ffdc1c50c825da9b1af.

O primeiro caso parou ao localizar o nome exato Tecla DTMF: o label continha também o select e suas opções. Separar label e select com for/id também nos destinos lógicos e de contingência preserva as regras e oferece nome acessível inequívoco. Dois Vue devem verificar a associação ao controle real, o nome e a edição.

O segundo caso passou as páginas de 20/3 registros e falhou no Voltar: router.replace havia substituído a entrada da lista. A navegação de filtros/páginas passa a usar router.push; manter guarda de navegação, filtros e revisão. Novo Vue com histórico real em memória prova o retorno à primeira página filtrada. O Chrome continua exigindo o Voltar real, sem trocar a asserção por recarga.

O próximo incremento também inclui mapa de destinos, importação de arquivo válido, restauração efetiva e correção separada da ordem de observações do supervisor. O gate exige 112 Chrome (108 preservados + quatro de revogação sem recarga); os dez exemplos Vue adicionais devem passar nativamente. Nenhum teste foi desligado ou substituído por simulação operacional.


## Gate de 31d57172 e identidade da simulação

31d571727427bce5245486f0ef747dce7adf3d8e / CI 44236825274: 763 Rails principais, 17 concorrentes, 16 reexecuções no schema recarregado e 300 Vue aprovados, zero falhas/pendências/erros. Os dez novos Vue passaram, incluindo reprodução da navegação/labels e ordem das observações. Frontend lint aprovado. Chrome 112 não executou porque restaram três infrações Ruby: ABC no seed sintético ampliado e alinhamentos no exemplo de paginação. Separar o pacote de sessão do seed e construir os atributos do exemplo antes do construtor; manter valores e asserções. Artefato 14398792040, SHA-256 24bcc9150ab20a6188253dce05546eb97e6f644adb644efe169d811dcb859c07.

Revisão adicional do editor identificou que editar somente o DTMF podia manter o resultado anterior visível. O fingerprint passa a incluir os dígitos, e editar o campo descarta a simulação anterior, inclusive ao voltar ao valor original. Os quatro cenários reais de URA devem comprovar esse descarte sem trocar as provas de simulação, gravação, importação ou exportação. Cada nova simulação continua reautorizada pelo servidor.


## Observação real do navegador — 71841f76

CI 44239525292: 763 Rails principais, 17 concorrentes, 16 reexecuções do ledger e 300 Vue aprovados; zero infrações Ruby novas. Assets e bootstrap/15 cards aprovados. Chrome 100/112, sem skips/flaky/erros externos. Os 96 anteriores e quatro de isolamento permanecem aprovados; oito casos novos pararam em espera de resposta e quatro no teste de tema. Artefato 14399618889, SHA-256 0c54d256e7fccdbecf4d7eb624c2d0eb3ecb04590a203bc0c619195814d79f05.

Duas causas de observação confirmadas no código e relatórios: a fixture serve a interface em 5386 e encaminha /api ao Rails 5387; os probes diretos usam 5387, mas as respostas da página têm origem 5386. Os predicados novos passam a exigir a origem real configurada do navegador, o mesmo pathname de conta/recurso e método; status, conflitos, identidade e persistência reais continuam obrigatórios. Metadados de origem/pathname/método/status são preservados por cenário, sem headers, querystrings ou payloads.

O campo usa field-base com transition-colors duration-[0.25s]. A leitura imediatamente após trocar .dark capturava a cor inicial antes da transição. A prova agora aguarda as animações do próprio elemento terminarem e exige cor diferente; ao restaurar o tema exige a cor original. Registra ambas as cores e captura o mapa após a restauração. Nenhum CSS, transição, componente, API ou critério foi substituído; não usar sleep fixo ou desabilitar animações para aprovar o teste. A nova execução deve provar os 112 cenários completos.
