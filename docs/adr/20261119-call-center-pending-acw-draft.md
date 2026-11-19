# Respostas e motivo ainda pendentes no pós-atendimento

Status: backend, interface integrada ao Hoya e testes preparados; não commitados, não executados nativamente e sem homologação Chrome ainda.

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
