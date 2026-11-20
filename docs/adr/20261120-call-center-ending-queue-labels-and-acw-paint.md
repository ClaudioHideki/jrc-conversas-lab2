# Filas selecionadas e cor do prazo ACW — 20/11/2026

Status: preparado após 50d26506; não integra a CI desse SHA ainda em andamento.

A revisão visual das 12 capturas reais do SHA86c4ad53 encontrou dois desvios pequenos da figura9: chips mostravam apenas o ID da fila e a barra progress nativa ficava verde mesmo com o aviso vermelho de prazo excedido. O incremento funcional dos encerramentos já passou no banco e Chrome; este seguimento não muda essa regra.

O GET/PATCH nativo da política passa a oferecer voice_reason_queues somente ao mesmo gestor que já pode ver o catálogo global. Os nomes vêm de contact_center_access.queues filtrado exclusivamente pelos IDs já selecionados, em uma consulta limitada pelo máximo100. Não há nova rota ou leitura direta de filas sem escopo. Os nomes são metadados de exibição, fora do documento imutável, da revisão e do payload de escrita. Renomear a fila não reescreve histórico. Operador e administrador restrito à unidade continuam sem esse campo. Referências sem nome disponível conservam o ID; não se inventam nomes nem se removem seleções silenciosamente.

O composable conserva somente os nomes retornados para os IDs selecionados. Limpa nomes na carga, troca de conta, recusa de autorização e desmontagem; respostas antigas continuam descartadas pelo mecanismo de geração existente. A compatibilidade com respostas antigas sem metadados mantém o rótulo por ID. Nenhum cache global ou armazenamento do navegador é criado.

A barra progress reutiliza exclusivamente acwOverdue, acwElapsedSeconds e acwLimitSeconds. Tailwind aplica accent-n-ruby-9 ao estado excedido e accent-n-blue-9 ao estado dentro do prazo; acrescenta o nome acessível já traduzido. Não se altera cálculo, limite, snapshots, relógio, rascunho, persistência ou liberação de próxima chamada.

Preparados: um caso Rails de metadados/renomeação/imutabilidade, assertivas adicionais de acesso negado, três regressões Vue de rótulos e duas de prazo. Os 212 Chrome continuam obrigatórios; o caso nativo existente é ampliado com GET real da fila, comparação de nome, recusa ao operador e leitura da cor CSS efetiva nos quatro projetos. O cenário renomeia somente a fila sintética, com revisão nativa, para120caracteres sem espaços finais e verifica a quebra dentro do popup em390px. Nenhuma evidência anterior será atribuída ao novo código antes da CI.

Sem migração, alteração de permissões reais, PABX, publicação, build Docker ou deploy. As 23 figuras continuam parcialmente implementadas, com dependências próprias documentadas.
