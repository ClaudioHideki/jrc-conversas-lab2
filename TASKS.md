<!-- jrc-operational-init:v1 -->
# Backlog operacional — JRC Conversas LAB2 — Grupo JRC

- Contact Center / Chamada ativa usa os controles do softphone para a sessão SIP deste navegador. Um atendimento selecionado exige correspondência de conta, provedor e identificador da sessão. A Central de Relatórios reúne Atendimento, CRM, Service Desk e Projetos com os filtros, exportações e regras de acesso de cada módulo. Validação local com 109 testes Vue e SIP e Chrome com chamadas sintéticas, abas e diálogos. O painel de ramais é mantido no repositório separado do monitor.

- [x] **SD-SAVE-403-20261123 — implementação e validação locais:** Causa comprovada na API isolada, `IntakeRuleApplication#record_sla!` na linha 28 da base b6cfb57 exigia permissão manual para aplicar SLA publicado. Persistência compartilhada, autorização manual preservada e frontend mantém formulário após 403. 1.068 cenários Rails cobertos com revalidação dos 19 de abertura após corrigir a expectativa nativa 404; 22 concorrentes e 1.153 Vue aprovados, além de 74 verificações finais direcionadas. Sem push, merge ou deploy; homologação produtiva pendente. [Relatório](docs/jrc_consolidation/service-desk-save-403-validacao-20261123.md); [ADR0009](docs/adr/0009-sla-publicado-na-criacao-autorizada.md).

  Ajuste final de destinatários: fila padrão de serviço inativa não antecede o destino interno válido; destinatários exigem autenticação nativa ativa. 176 Rails e 87 Vue revalidados, incluindo 25 casos de abertura e escolhas de outras equipes/filas, padrão desabilitado, replay e negação de destinos inválidos. Sem exceções por usuário ou novas permissões.

- [x] **ABERTURA-AGENTES-20261119:** Publicado o produto ab6bba04 sobre a imagem f494fd38. Abertura interna em nome próprio sem dependência do diretório comercial, escolha de destinatários de outros departamentos da unidade e recuperação de rota com nova autorização. 51 testes Vue locais, CI44573517512 e build44577404793 aprovados; 1309 exemplos Rails principais, concorrência de 21 + 2 + 2 exemplos, 1622 testes frontend e 24 cenários de navegador. Digest `51eda0b1` conferido diretamente no GHCR, linux/amd64 e revisão exata; smokes antes/depois da publicação. Sem implantação ou mudança de permissões produtivas; aceite da sessão do Ronald pendente após atualização. [Imagem e evidências](docs/jrc_consolidation/abertura-chamados-agentes-release-20261119.md); [ADR0008](docs/adr/0008-abertura-interna-por-destinatario.md).

- [x] **INBOX-RESPONSIVO-20261118:** Publicado o produto f494fd38 sobre a base e6bd4cc9, preservando o runtime d3d66232. Layout compacto, contexto em popup e Ampliar conversa com rascunho preservado. 200 testes locais, quatro resoluções Chrome e build44363528959 aprovados; 2759 testes frontend, 168 Rails e smokes antes/depois da publicação. Digest e1502e54 confirmado diretamente no GHCR, linux/amd64 e revisão exata. Corrigido o hostname do espelho Ubuntu que havia interrompido o primeiro build, sem remover gates. Sem implantação. [Evidências e imagem](docs/jrc_consolidation/inbox-responsive-release-20261118.md); [ADR0007](docs/adr/0007-visualizacao-responsiva-da-conversa.md).

- [ ] **OPUS-MIME-20261117:** Alinhar Marcel/Broker em LIVE e histórico com assinatura Ogg/Opus, mantendo envelope/hash. RED44154858796:74/75 nativos; correção e GREEN pendentes. Base runtime6886261 + main89779191 preservadas. Ver ADR0006. Sem deploy ou novo envio real nesta etapa.

## Estado vigente — publicação de 16/11/2026

- [x] **RETENTION-RELEASE-20261116:** Proteção de histórico/recibos, main funcionald468, imagem e deploy Grupo JRC concluídos; [evidências e digests](docs/jrc_consolidation/release-20261116-result.md).
- [x] **CLOCK-FIXTURES / RELEASE-LINT / CLOUD-REPLY-20261116:** CI final e construção aprovadas sem afrouxar escopo por conta ou assertions. Smokes da imagem por digest aprovados.
- [x] **PROPOSTA-POPUP / SEGMENTO-20261116:** Incrementos preservados na imagem consolidada e implantada.
- [ ] **ACCEPTANCE-20261116:** Entrega física, grupos, distribuição e mídia antiga permanecem pendentes. Capabilities200 e Minhas25→34 confirmam etapas específicas, não sincronização integral.

## Registro anterior da preparação (histórico)

- [ ] **ENCERRAMENTO-ENVIO-20261117:** Corrigir o cliente HTTP que rejeita a intenção manual antes do POST na imagem 68862610 já implantada. Dois cenários de formulário com cliente real reproduziram zero envios, com e sem motivo. Preservar o encerramento sem requisitos extras, tempo/SLA reais e confirmações independentes; concluir testes e nova imagem sobre a base publicada. [ADR0005](docs/adr/0005-encerramento-manual-sem-bloqueio-sla.md).

- [x] **ENCERRAMENTO-LIVRE-SLA-20261117:** Publicado o produto 68862610 sobre a imagem a5d5e1a. Encerramento manual por funcionários com acesso ao chamado sem requisitos extras; tempo real e SLA configurado preservados, cálculo pendente quando não há configuração válida. CI44139348538 e build44142694078 aprovados; 29 testes Vue locais, suíte principal Rails1303, frontend1617 na integração/2757 no build e24 cenários de navegador. Digest53b9ebc6 conferido diretamente no GHCR, linux/amd64 e revisão exata confirmados; smokes antes/depois da publicação aprovados. Sem implantação. [Evidências e imagem](docs/jrc_consolidation/encerramento-livre-sla-release-20261117.md); [ADR0005](docs/adr/0005-encerramento-manual-sem-bloqueio-sla.md).

- [x] **CHAMADOS-PROJETOS-20261117:** Publicado o produto a5d5e1a sobre a imagem d468beb8. Escolha de empresa/unidade e destinatário elegível na abertura interna; criação por agentes habilitados respeitando negações explícitas; projetos somente do responsável/participante, administradores veem toda a conta; indicadores corrigidos e encerrados em popup paginado. CI44095082428 e build44098840211 aprovados; 97 testes locais, suíte principal Rails1299, frontend1615 na integração/2755 no build e24 cenários de navegador. Digest7fbe9fc9 confirmado diretamente no GHCR, linux/amd64 e label da revisão conferidos; smokes antes/depois da publicação aprovados. Sem implantação. [Resultado e referência exata](docs/jrc_consolidation/chamados-projetos-release-20261117.md); [ADR0004](docs/adr/0004-chamados-destinatarios-projetos-escopo.md).

- [ ] **CLOUD-REPLY-FIXTURE-20261116:** O build `43981129768`, job `133697571732`, SHA `1ea2f455`, encontrou RED de 1/168 exemplos no reply Cloud (`incoming_message_whatsapp_cloud_service_spec.rb:346`). A fixture criava a conversa sem conta explícita, divergindo da caixa/contato, e o clock corretamente escopado por conta recusou a mensagem recebida. Adicionada somente `account: whatsapp_channel.account` nessa conversa, preservando as assertions de conteúdo e referências da resposta e sem alterar a factory global ou o produto. Os 11 exemplos Cloud entram também no gate inicial CSAT/clock/Webhooks, elevando o mínimo de 28 para 39. Artifact RED `14282453508`; aguardar GREEN de CI e nova construção autorizada, pois o build foi interrompido antes de publicar imagem.

- [ ] **RELEASE-LINT-20261116:** SHA `3d30b82f` aprovou o gate curto Rails (28 + 33 + 74 + 6 + 439 + 156 + 38 exemplos) e Broker/Flow (4 + 1.023 + 4 Rails, 164 frontend). O gate Projetos `43976142193`, job `133680673748`, passou 2 + 1.294 + 21 + 2 exemplos Rails e bloqueou no RuboCop `--only Lint`: 1.096 arquivos inspecionados, somente três ocorrências de `Lint/AmbiguousBlockAssociation`, nas assertions de retenção e de pontuação de relacionamento. Adicionados apenas parênteses explícitos para os três argumentos com bloco, sem alterar expectativas, produto ou regras do gate. Artifact RED `14281770697`; aguardar nova CI no SHA corrigido antes de liberar a imagem.

- [ ] **CLOCK-FIXTURES-20261116:** O refresh do relógio preserva a associação compartilhada e atributos pendentes, mantendo a leitura por `account_id` + `conversation_id`. CI `43973873010`, SHA `ddc7bfd8`, aprovou CSAT/clock 8, retenção 33, nativo 74, badges 6, genéricos 439, histórico/mídias/Minhas/outbound 156 e busca 38, todos sem falhas. O gate amplo `43974827085`, job `133675987354`, identificou 20 falhas em 1.023 exemplos: a fixture de `Webhooks::Trigger` criava a conversa em conta diferente da caixa/mensagem. Corrigida somente essa fixture com conta explícita e incluídos seus 20 exemplos no gate curto CSAT/clock, agora mínimo 28. Não alterar a factory global de conversas nem afrouxar o filtro de conta do produto. Concluir CI no SHA corrigido antes de liberar a imagem; nenhuma validação física ou implantação é inferida desses testes.

- [ ] **RETENTION-RELEASE-20261116:** Pedido posterior autoriza concluir testes, imagens, main e deploy Grupo JRC. Consolidou a retirada de filtros de segmento e o popup de propostas; preserva a frente Call Center em WIP fora desta release. ADR0003 protege destruição de histórico antes de efeitos, sem apagar recibos/KEEP. RED inicial:21 exemplos/16 falhas; primeira correção:22 exemplos/1 falha adicional comprovada em AccountDeletionService,21 aprovados incluindo corrida PostgreSQL. Correção final e CI em andamento. Aceite físico WhatsApp continua separado.

- [ ] **WHATSAPP-RELIABILITY-20261116:** Candidata de estados outbound honestos e recibo LIVE imutável, mídia em custódia privada, reuso estrito LIVE/V2 e clocks separados para cronologia/não lidas. Desenho: [ADR0002](docs/adr/0002-recibo-live-custodia-broker.md); execução: [plano local](docs/jrc_consolidation/live_ingress_receipt_plan_20261116.md). Usuário autorizou branch de testes no GitHub Actions; CI e E2E sintético em fechamento, sem merge/imagens/deploy/envio físico. Helper e componente de publicação passaram 10/10 localmente; runtime Rails3.4.12 e build elegível devem ser verificados na CI. Lifecycle hard delete permanece gate de release; a autoridade de bots legados não foi removida por suposição.
- [ ] **PROPOSTA-POPUP-20261116:** Detalhes comerciais em popup nativo, com X/Esc/fundo e preservação do rascunho. 46 testes locais aprovados; concluir CI e imagem. Escopo: [ADR](docs/adr/20261116-proposta-popup.md).

Publicação encerrada; as pendências operacionais continuam em A fazer. Consulte os recibos e limites em CONTINUE-AQUI.md.

Nenhuma execução funcional é iniciada por este bootstrap. As frentes já em andamento permanecem nos planos/checkpoints existentes.

## A fazer (To Do)

- [ ] **WHATSAPP-OPS-20261115:** Reconciliar autoridade legada por conversa,acesso ao storage e escopo dos grupos antes de novos testes físicos/replay. Não modificar permissões ou eliminar registros por suposição.

- [ ] **DOC-01:** Revisar os termos de [glossary.md](docs/domain/glossary.md) com o responsável pelo domínio.
- [ ] **DOC-02:** Conferir [system-overview.md](docs/architecture/system-overview.md) e as versões com o ambiente efetivo quando houver acesso autorizado.
- [ ] **OPS-01:** Reconciliar conversas por caixa e a política de acesso Minhas/compartilhadas/exclusivas.
- [ ] **OPS-02:** Manter homologação de voz, histórico e mídias distinta de teste sintético e de publicação.

## Concluído (Done)

- Na lista de Contatos, o nome e a ação de perfil abrem a janela com opções, edição e confirmação de exclusão para administradores. O relatório de Agentes ordena as métricas pelo valor numérico e mantém registros sem medição ao final. O discador usa os controles da sessão SIP local durante a ligação. Validação local com 144 testes Vue e 24 cenários Voz V4 no Chrome, com chamadas simuladas. A ordenação, a edição e a exclusão com confirmação também foram validadas no Chrome com dados fictícios.

- Contatos exibe os atalhos de conversa no WhatsApp, ligação pelo softphone, perfil e exclusão individual. A confirmação de exclusão usa a permissão nativa da conta. A barra superior usa o discador e os controles da sessão SIP, com espera e transferência conforme o provedor.

- O HTML do relatório gerencial usa a capa JRC de Operações & Relacionamento, com a origem da exportação e a data da extração, cartões coloridos e grades responsivas. A média de SLA aceita segundos decimais serializados como texto e considera relógios concluídos. Validação offline em Chrome e Edge entre 320 e 1.907 px, com filtros, CSV, temas e média de resolução.

- Relatório gerencial do Service Desk inicia com os chamados nativos do JRC e abertura original a partir de 2026. O HTML exportado mostra a média com eventos reais de fechamento e ordena os chamados pendentes pela idade crescente na data da extração.

- Manual de Cultura com visual azul-claro, arte do Grupo JRC e leitura paginada do PDF protegido. Em Projetos e Tarefas, o upload preserva a gravação do Active Storage após o commit. A visualização e o download verificam o acesso ao projeto e mostram uma mensagem quando o objeto está ausente. Os arquivos já ausentes no projeto 181 exigem os originais ou uma cópia.

- Indicadores, gráficos e exportações gerenciais do Service Desk, com recorte pela abertura original a partir de 2026. Passaram 55 exemplos Rails e 25 testes Vue. O Chrome validou o fluxo autenticado, os quatro downloads e o painel móvel em tema escuro. Chrome e Edge abriram o HTML offline com filtros. [Decisão](docs/adr/0013-indicadores-e-exportacoes-gerenciais-service-desk.md).

- Relatório gerencial do Service Desk com permissões, filtros combináveis e separação de chamados nativos, importados e de origem não classificada. Escopo inicial pela abertura original a partir de 2026. Validação local com 34 exemplos Rails e 13 testes Vue, incluindo regressões dos relatórios existentes. [Decisão](docs/adr/0012-relatorios-gerenciais-service-desk.md).

- Manual de Cultura JRC: versões e público, ciência e histórico, gestão e importação protegida implementados em branch isolada. Homologação externa e publicação permanecem como etapas separadas. [Roteiro](docs/jrc_consolidation/manual-de-cultura-homologacao-20261123.md).
- Manual de Cultura JRC em contas sem unidades vinculadas: habilitação por conta, sessão compartilhada e planilha protegida, validadas em ambiente local. [Decisão](docs/adr/0011-manual-de-cultura-escopo-da-conta.md).

- [x] **QUICK-REPLIES-RELEASE-20261115:** Produto `5c3fb7f` corrigido, testado e implantado no Grupo JRC: CI 49/49, 404 Rails/504 Vue dirigidos, 13 Chrome e dois E2Es privados; API e Rails/Sidekiq conferidos. Aceite operacional WhatsApp/storage é parcial e a validação física foi adiada pelo usuário. Evidências: `docs/jrc_consolidation/quick_replies_whatsapp_release_20261115.md`.
- [x] **RELEASE-20261114:** Base produtiva `55da80eb` preservada e consolidada na release `5c3fb7f`; imagem, versão, migrations e saúde verificadas em 15/11. Homologação física continua separada.
- [x] **GATES-20261114:** Matriz nativa `43770789984` terminou com 49/49 jobs aprovados, incluindo os gates e o upgrade populado. Nenhuma migration do produto foi modificada neste incremento.
- [x] **REMOVER-FILTRO-SEGMENTO-20261116:** Painel retirado das oito superfícies; imagem do produto `c8efa1d68e1b5706e47cd022fa8e31df1e156e6c` publicada e verificada por digest. CI `43941168985`: três jobs aprovados, 2.752 testes Vue e 168 Rails aprovados, smokes antes/depois da publicação. Implantação não realizada. Referência e limites: [ADR](docs/adr/20261116-remocao-filtro-segmento.md).

- [x] **BOOTSTRAP-01:** Identidade, stack, natureza Brownfield e fontes locais registradas.
- [x] **BOOTSTRAP-02:** Estrutura INIT, domínio, arquitetura e ADR organizados sem apagar conteúdo anterior.

## Como manter

- **CI-LIVE-20261117:** Isolar a concorrência LIVE do glob Flow/QR e executar os quatro casos no banco descartável exigido pela proteção, mantendo suites genéricas e routing. Critério de aceite: workflow Flow/QR do SHA final com zero falhas/pendências e contagem mínima preservada. Evidência inicial e limites: [registro](docs/jrc_consolidation/ci-live-runner-20261117.md); resultado remoto nos checks do commit. Alteração exclusiva de CI, sem nova imagem funcional.

Uma tarefa deve registrar problema, escopo, critério de aceite, evidência/arquivo e limite. Só mover para Concluído com a prova correspondente; não converter publicação de imagem em aceite operacional.


## Respostas rápidas e catálogo de aprovações — 2026-11-15 [WIP]

- Melhorar o atendimento nativo: acesso junto à assinatura, prévia contextual, um anexo e envio explicitamente confirmado, com intenção persistida para retry sem duplicação.
- Traduzir a Central em pt_BR e abrir configurações/edição em Dialog nativo; importar somente rascunhos inativos autorizados, com dry-run, escopo, diff, revisão de identidades e auditoria.
- Base funcional publicada preservada: `55da80eb1254aee54ee0f1fb5c42f2be46a98737`; main e ambientes existentes não são alterados.
- Evidências e limitações: `docs/adr/20261115-respostas-rapidas-catalogo-aprovacoes.md`. CI dirigida e homologação Chrome devem ser provadas sobre o SHA final. Sem publicação de imagem ou deploy nesta tarefa.
