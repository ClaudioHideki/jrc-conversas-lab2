# Respostas e motivo ainda pendentes no pós-atendimento

Status: rascunhos validados emee689703/CI44470340154 com1310Rails distintos+16schema,619Vue,160Chrome e240capturas verificadas. Aviso de navegação e rótulos traduzidos na revisão estão preparados em incremento separado; aceite integral do Word continua aberto.

## Contexto e referência

A figura 9 exige conservar respostas não concluídas e separar o fim da chamada da conclusão do formulário. A implementação existente já possui Qualification, seus campos manuais e o snapshot de regras no evento nativo de entrada em ACW. O endpoint update conclui o atendimento; não serve para salvar respostas incompletas.

## Incremento preparado

Uma operação draft aditiva no mesmo recurso reutiliza a autorização operacional atual, o vínculo do usuário autenticado, os escopos nativos de voz/conversa e o mutex de Account. O serviço recarrega e bloqueia a linha da própria conta/membership, rejeita conclusão anterior e ciclo antigo da conversa e exige uma revisão do estado manual. Nenhum account_user_id, unit_id ou tempo recebido do cliente concede acesso ou altera a origem.

A revisão considera identidade, origem, início, estado terminal, motivo, resultado, notas e limite efetivo. Exclui updated_at, overdue e exceeded_seconds, que mudam em consultas do relógio. Não concede autorização. Alterações concorrentes de respostas exigem recarga/revisão; consultas periódicas de tempo não criam conflitos artificiais.

O motivo aplica o limite a partir do snapshot original, na precedência aprovada fila → equipe → geral; conflitos no mesmo nível continuam bloqueados. Regras novas não são aplicadas retroativamente a atendimentos legados. Started_at, duração final, conclusão, disponibilidade, chamada e snapshot não são reescritos. A ultrapassagem do tempo conserva o rascunho e não provoca conclusão ou distribuição de chamadas.

O log de auditoria usa o armazenamento Audited existente e registra somente as revisões anterior/posterior e a identidade nativa do ator/registro/conta. Não copia notas nem respostas no log. Falha da auditoria desfaz a escrita. Repetição sem mudança manual não gera um segundo evento de alteração.

A conclusão existente mantém seu contrato sem token. O cliente novo poderá enviar expected_draft_revision ao endpoint de conclusão para impedir que respostas antigas substituam um rascunho mais recente; essa verificação ocorre dentro da mesma autoridade transacional e não muda o serviço legado. Repetição de uma conclusão já gravada permanece idempotente.

## Critérios ainda não comprovados

Há cenários de serviço e HTTP (incluindo documentos/campos malformados, privacidade após perda de unidade e ciclo WhatsApp), além de três cenários com espera real por lock SQL preparados para persistência, snapshot/precedência, conflito, relógio, isolamento, acesso negado, limites, auditoria e repetição. A interface preparada reutiliza o formulário operacional e controles explícitos de conflito, com testes Vue preparados no alvo existente e em um arquivo de componentes. Faltam a execução desses testes e a homologação Chrome em quatro combinações de viewport/tema. Os três cenários SQL foram acrescentados ao suite já restrito ao banco corporate_gratuity_disposable; sua limpeza ocorre somente após finalizar os próprios workers e somente na conta sintética. Os resultados de d9f977e5 não validam este incremento.

Não há migration, catálogo paralelo de motivos, credencial, comando ou integração PABX nova. Templates/campos dinâmicos de formulário e automações por destino continuam pendências independentes das figuras 9/10. A preparação deste backend não encerra essas figuras ou as 23 referências.

## Respostas incompletas e conflitos de regra

O rascunho pode preservar respostas ainda sem motivo usando o limite padrão capturado. Isso não altera o validador da precedência nem permite concluir sem campos obrigatórios. Limpar um motivo em um rascunho não reescreve seu snapshot. Conflitos de regras e mudança de ciclo são diferenciados de stale_configuration_revision; a interface não apresenta esses casos como se bastasse reaplicar uma versão manual. Não há retry automático.

A proteção de notes já existe no inicializador nativo filter_parameter_logging.rb do SHA c0e20792 (SHA-256 a1ef3e420252b50adb64e18e40ca63819c0972e5899211358519366afa9af515). O incremento não muda configuração global de logs; prepara um teste sobre o filtro Rails carregado para comprovar a remoção das notas do payload registrado.

## Controles reais e fronteira da prova visual

O fixture Chrome acrescenta dois fluxos em quatro projetos (desktop 1440 px e celular 390 px, claro/escuro), mantendo os 152 casos anteriores e exigindo 160 no gate. Usa PendingQualificationForm e QualificationDraftReview extraídos do Hoya, o composable operacional e APIs Rails autenticadas com PostgreSQL descartável. Não monta o workspace Hoya inteiro nem conecta SIP/PABX. Os cenários ainda estão preparados, sem resultado executado. Motivo/respostas privados não são copiados para a projeção compartilhada de agente/supervisor; os identificadores e o bloqueio pendente continuam presentes.

A persistência é explícita: respostas gravadas são recuperadas na API; texto digitado depois da última gravação permanece só na memória do atendimento. Não há autosave, armazenamento local ou garantia de recuperação de texto não salvo após fechar/recarregar a página. Revisão/aviso para navegação fora do atendimento e formulários dinâmicos são critérios separados ainda abertos. Perda de autoridade elimina o estado privado da interface.

## Proteção de navegação — próximo incremento preparado

QualificationDraftNavigation reutiliza o Dialog nativo e os guards Vue Router. Permanecer cancela a navegação e conserva a edição; Sair sem salvar exige confirmação e só descarta a memória local ao desmontar o atendimento. O servidor, a última gravação e o ACW pendente não são alterados. Alteração de parâmetros nativos é revisada; mudanças somente de query não são bloqueadas. Gravação em andamento impede saída; beforeunload usa o aviso do navegador sem notas privadas e sem substituir os listeners de telefonia. Troca de autoridade invalida uma revisão aberta. Não há autosave ou comando PABX.

Nove testes unitários do controle, um cenário Chrome por viewport/tema e integração no Hoya/fixture estão preparados para o próximo SHA (164 casos Chrome, preservando os160). Não pertencem à CI 44466663154 do SHA34f58253, que ainda valida o incremento de gravação. A homologação do workspace Hoya inteiro e formulários dinâmicos continuam separadas.

## Primeira execução dos rascunhos — SHA34f58253

CI44466663154 aprovou1310Rails distintos (1146principais,79concorrência,85corporativos), mais16schema separados, e619Vue. Os17casos de QualificationDraft,22da API de autoridade,12de ACW/WhatsApp e14da suíte de locks de equipe passaram; as contagens desses arquivos são subconjuntos dos1310, não casos adicionais. Zero falhas, pendências ou erros fora dos exemplos. O gate parou em12infrações novas Ruby (alinhamento e bloco de rotas); build e160Chrome não foram executados. Evidência em acw_draft_lint_20261119.json. Correção mínima ee689703 não inclui a navegação preparada.

## Aceite funcional dos rascunhos — SHAee689703

CI44470340154 e job135377969079 concluíram com sucesso. 1310Rails distintos,16schema separados,619Vue e160Chrome (40em cada viewport/tema), sem falhas, pendências, erros externos ou novas infrações Ruby. Artefato14505548543, SHA-256dc114469f7607a8de6c4c8c4d0cd14daebd7c9c55f2e74be788eaf160c2ca721,240capturas verificadas. Amostras do rascunho e conflito revisadas visualmente em1440/claro e390/escuro; nota longa não transborda horizontalmente. A prova Chrome usa controles/composable reais e APIs/banco reais em harness, não o shell Hoya inteiro ou SIP.

A revisão visual encontrou o código conhecido order exibido sem tradução. O próximo incremento reutiliza acwLabels já utilizado no histórico, sem alterar códigos do servidor. Há três regressões Vue preparadas para tradução, códigos desconhecidos e chaves herdadas; a asserção Chrome existente é reforçada em português. O helper de rótulos permanece intocado.


## Aceite da navegação e rótulos — SHAa8c6c78d

CI44478139924/job135403565966 aprovou1310Rails distintos,16schema separados,631Vue e164Chrome (41em cada projeto), sem falhas, pendências, erros externos ou novas infrações Ruby. Artefato14508877245, SHA-2562a9053f743b87677aefbc1229d764ea110981d1f54ddb6acf0af6d3a1fb9d786;244capturas verificadas. Build fresco e bootstrap15cards/zeroerros aprovados.

Foram revisados os PNGs do diálogo em1440e390, claro eescuro: texto e botões legíveis e contidos. A revisão de conflito no celular/escuro exibe Consulta de pedido em português, mantendo o valor canônico order. Cancelar a navegação/aviso do navegador preserva o texto; descarte é explícito; navegação após salvar e recarga recuperam a versão no banco. Não há autosave, comando externo ou conclusão automática. Esta prova usa o harness e APIs/banco reais; não demonstra o shell Hoya completo ou encerra templates/formulários/automações.
