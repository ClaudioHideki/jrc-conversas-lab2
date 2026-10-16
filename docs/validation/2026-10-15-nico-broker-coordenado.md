# Candidato NICO e Broker coordenados — 15/10/2026

Branch de testes: `codex/nico-broker-coordenado-20261015`. Base de produção preservada: `b58e093dd3a32fe97829a4566660b83ee48b9eca`. Este desenvolvimento não altera a branch do outro desenvolvedor nem instala uma imagem no servidor.

## Comportamento

NICO consulta e executa ferramentas permitidas ao operador da Account. Em uma conversa vinculada ao Broker, um envio público prepara uma prévia com destinatário, conteúdo e consequência: assumir a conversa e pausar o bot. A confirmação grava uma intenção durável. O worker aguarda a confirmação do Broker e revalida o acesso e o destinatário antes de criar uma Message pública, uma vez, pelo canal existente da central. A conversa permanece humana.

O worker usa leases no PostgreSQL e realiza HTTP fora das transações da aplicação. Uma falha depois da criação da Message reconcilia o mesmo registro; não recria a mensagem. O recibo consulta o status atual da Message e distingue registro na central de entrega/leitura informada pelo canal. NICO não inicia uma segunda conexão WhatsApp.

É possível cancelar antes de criar a Message. O cancelamento invalida o lease local antes de liberar a intenção remota. O Broker conserva uma marca por request_id para que uma solicitação de pausa atrasada não reabra a operação. Se a pausa já ocorreu, o cancelamento preserva humano; não retoma o bot. Uma mensagem já registrada não é apresentada como desfeita por esse cancelamento.

Não há migração de senhas ou importação de todos os usuários para o Broker. A Account mantém identidade, permissões, usuários e caixas no JRC. A credencial de integração da Account permanece no backend.

## Banco e configuração

- Nova migração Rails: `20261015130000_create_nico_broker_send_operations`.
- Aplicação Rails e Sidekiq precisam usar o mesmo candidato e o banco já migrado.
- A integração requer também o candidato Broker com o contrato de tomada coordenada e a migração `0062_nico_takeover_operations`.
- Configuração de controle Broker por Account: origem aprovada, organização, revisão do destino e credencial de serviço. O alvo pode ser um vínculo QR ou um vínculo/registro nativo real compatível. A credencial nativa flow/outbound isolada não concede controle NICO. Não enviar esses segredos ao navegador ou ao modelo.
- O runtime NICO separado não foi alterado neste incremento.

## Habilitar uma Account

No terminal do serviço Rails da instalação escolhida, para a Account 3:

```sh
bundle exec rails runner 'a = Account.find(3); a.with_lock { a.update!(custom_attributes: a.custom_attributes.merge("nico_enabled" => true)) }; puts "NICO habilitado na Account #{a.id}"'
```

Substituir 3 pelo ID da Account desejada, por exemplo 4. O comando preserva os outros atributos. A Account precisa estar ativa; configure o provedor/modelo e limites próprios em Inteligência Artificial. A habilitação não concede novos acessos às caixas ou módulos e não ativa um chatbot automaticamente.

No serviço **NICO runtime** escolhido, a variável `NICO_ALLOWED_ACCOUNTS` também precisa listar os IDs autorizados, por exemplo `1,3,4` se essas três Accounts utilizarem essa implantação. Preservar os IDs atendidos e reimplantar somente o runtime candidato após salvar o Environment; não exige reconstruir a imagem. Não usar `*`. Em modo `provider`, cada Account utiliza sua própria configuração de provedor enviada pelo backend Rails.

Quando Rails e Sidekiq utilizam `NICO_RUNTIME_ROUTES`, incluir cada Account nesse mapa com o endpoint e o nome da variável privada de token correspondente. Uma Account ausente do mapa não utiliza outro runtime como fallback. A flag no banco, o roteamento do Rails/Sidekiq e a lista do runtime são controles distintos. Nenhuma habilitação para as Accounts 3/4 nem alteração de runtime foi aplicada no servidor neste incremento.

Para consultar, sem alterar:

```sh
bundle exec rails runner 'a = Account.find(3); puts({account_id: a.id, nico_enabled: a.custom_attributes["nico_enabled"]}.to_json)'
```

## Evidências e limites

As regressões originais demonstraram ausência da prévia coordenada, estado de entrega congelado, envio tardio depois de cancelamento e erro HTTP 500 quando o Broker não respondia. Foram acrescentados testes Rails/PostgreSQL e de interface para esses comportamentos, preservando os fluxos anteriores de ferramentas, delegação e QR.

Verificação local consolidada: **120 exemplos Rails/PostgreSQL em 11 arquivos, sem falhas**, incluindo ferramentas/delegação/histórico, envio coordenado e as rotas QR e Account existentes. A fonte dos 12 arquivos Ruby alterados/novos foi comparada por SHA-256 com o volume testado, sem divergência. A interface NICO passou **83 testes em oito arquivos**. Os seis arquivos novos passaram no RuboCop (dois alinhamentos corrigidos); ESLint dos arquivos UI alterados encerrou sem erros.

Essa evidência antecede o complemento de autoridade no commit e sobrevivência do ledger, ainda em validação focal. O primeiro teste concorrente do complemento confirmou RED real: uma Message foi criada enquanto a alteração de role do operador estava aberta em outra conexão. Os demais casos da primeira rodada pararam em limpeza de fixture e não são evidência semântica; resultados novos serão registrados após a correção. Consulte o [desenho do gate e ciclo de vida](../superpowers/specs/2026-10-15-nico-send-commit-gate-design.md).

O complemento de commit/ciclo de vida passou **18 exemplos Rails/PostgreSQL, sem falhas**, com duas conexões reais nas corridas de revogação e grants. A execução do coordenador registrou 54,27 s de exemplos + 19,48 s de boot, exit0, em `nico-gate-root-final.log`. Cobriu drift de origem/organização/revisão/credencial/Binding, usuário desconfirmado versus offline, cleanup após revogação/NICO desabilitado e sobrevivência do ledger após exclusão de Command/User/Message. O corte ainda antecede a composição completa de OwnershipHooks e o resolver nativo comum.

NicoTakeovers/captureTakeover e a autorização de controle do Broker já são genéricos para BROKER/CENTRAL. O RED separado demonstrou seis falhas funcionais em oito exemplos de pin da Inbox/fallback nativo, com notas privadas e caixas sem vínculo preservadas. Quatro casos adicionais também falharam funcionalmente: faltava prévia coordenada BROKER/CENTRAL e divergências de canal/versão eram aceitas. Após a correção, **Gate18 + Binding12 passaram juntos: 30 exemplos, 0 falhas**, 88,22 s de exemplos + 20,78 s de boot, exit0, em `nico-native-gate-green.log`, DB isolado `jrc_nico_gate_test`. O resolver usa a credencial de controle por Account e o vínculo/registro nativo real, compartilhando `0062` sem inventar instância QR. Registro/controle ausente, expirado ou divergente fecha o envio; credencial nativa expirada não libera FREEZE. Essa evidência focal antecede a validação da árvore composta final.

Este protocolo coordena o envio público de Message. Alterações de status, time e responsável por outras ferramentas NICO ainda seguem seus próprios guards; o recibo de Message não prova a coordenação dessas ações. A próxima fase exige uma regra e contrato explícitos para esses controles, sem presumir que todo modo ou ferramenta Broker já está coordenado.

Commits, CI e digests do incremento coordenado serão registrados na entrega após a revisão. Não existe homologação de Chatwoot externo nesta etapa: o usuário informou que a instalação ainda não está disponível. A jornada física nas aplicações do servidor será executada com as imagens candidatas, após preparar o ambiente isolado e as caixas de teste.

Fechamento local da árvore composta: Gate18 + Binding12 passaram novamente juntos, **30 exemplos, 0 falhas**, no banco descartável autorizado `jrc_nico_gate_test`, após os ajustes mínimos de organização dos métodos. Os dez arquivos do gate NICO passaram no RuboCop sem ocorrências. O primeiro ensaio desse fechamento utilizou por engano o banco de módulos, fora do opt-in NICO e com uma versão antiga da tabela local; não é registrado como execução aprovada nem motivou alteração no produto. O CI candidato usa banco novo e aplica todas as migrations.

No CI composto de74bfc5e, a suite NICO executou150 exemplos;19 falharam porque faltava FRONTEND_URL no Environment do workflow. A origem HTTPS sintética já utilizada no laboratório e na suite Flow foi incluída no CI NICO, sem alterar os guards do produto. Flow/QR encerrou100 exemplos e os efeitos da conversa38, sem failures/pending. O primeiro build app passou pelos gates e parou no download da base Node: o ECR retornou HTTP429. O Dockerfile candidato passa a obter as mesmas bases pelo mirror.gcr.io; os digests Node26eb49fb e Rubybf74912a foram verificados por leitura no registry e permanecem idênticos, sem atualizar versões. O próximo commit candidato e a nova imagem devem comprovar o fechamento;74bfc5e não foi publicado como app.

A imagem app de `bbed688578c4956697d54d0c731d2301140940da` foi publicada em `ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:2a867cbcc78e1469dbac171048f45839aa812f9c541be6aafe8d2cacd3d876de`. O workflow38821752233 passou1207 testes de interface, verificou118 arquivos de produto e os componentes nativos, e conferiu SHA interno, label e plataforma linux/amd64 antes e depois do push. A leitura independente do registry confirmou digest e label da revisão. Nenhuma implantação foi aplicada ao servidor.

O CI NICO desse corte passou147 de150 exemplos. Os três casos de SendReplyJob estavam dentro da transação externa dos fixtures: o novo guard de envio externo recusava a execução antes de alcançar a lógica NICO. Foram extraídos para `spec/jobs/send_reply_job_nico_composition_spec.rb`, sem transação externa, em PostgreSQL descartável com opt-in e limpeza restrita. Não foi flexibilizado o guard nem alterado produto. O RED focal restante revelou que o assert legado apagava a incerteza na segunda entrega: o caminho composto agora deduplica essa chamada e preserva Turn unknown. O teste exige unknown após a primeira tentativa e após a repetição, entrega única e delegação needs_human/delivery_unknown, conforme o contrato de resultado incerto do NICO. O fechamento local registrou **3 exemplos, 0 falhas**,10,85s de exemplos e25,06s de boot, em `nico-native-delivery-final.log`.

O complemento modifica somente specs, workflow e este registro, todos excluídos pelo `.dockerignore`; os arquivos executados pela aplicação permanecem idênticos ao commit da imagem bbed688. Não é necessária outra imagem para essa correção de harness. O registro final da entrega deve informar separadamente o SHA da imagem e o SHA/CI de validação dos150 exemplos.
