# Cronologia do histórico WhatsApp — incremento de correção

> Execução inline na continuação autorizada do plano de sincronização. Não inclui publicação, pareamento, replay ou migração produtiva.

**Objetivo:** manter a ordem cronológica do histórico já persistido e limitar a visão pessoal às caixas das quais o usuário é membro, sem alterar atribuição, status, SLA, bots ou credenciais.

**Base:** LAB2 126d251dd5d5179783706f4934ba4fabc9d12b19. GitHub main conferida em 11/11: nove commits atrás desta candidata. Broker 1fed8ffcc68859c717f64a8aae50f29e8345e05b preservado.

**Arquitetura:** o importador existente já bloqueia a conversa e grava mensagem e recibo na mesma transação. Avançar apenas last_activity_at para a mensagem histórica mais recente; nunca retroceder nem emitir callbacks. Ordenar empates por ID para manter páginas determinísticas quando várias conversas têm a mesma data.

**Visibilidade:** o parâmetro opcional `inbox_scope=member` restringe a consulta antes da paginação. Minhas caixas e Minhas e compartilhadas usam esse modo e incluem o histórico persistido por padrão; filtros explícitos de andamento/pendência continuam disponíveis. Filas `assigned_only`, prova de ausência de roteamento, permissões de backend e a visão administrativa Todas são preservadas. A resposta inclui as caixas de que o usuário é membro para filtrar também os eventos realtime. Clientes legados sem o parâmetro conservam o contrato anterior.

**Limites:** este incremento não captura dados ausentes nem habilita grupos/mídias no importador v1. A sessão real do Welton no Broker estava desconectada na consulta de 11/11. Não substituir a engine, não utilizar a Evolution externa e não executar backup/dump/restore.

## Tarefas e aceite

- [x] Reproduzir importação histórica que deixa last_activity_at antigo; incluir replay e chegada fora de ordem.
- [x] Corrigir avanço monotônico sob o lock já existente, sem callbacks nem alteração das demais propriedades.
- [x] Usar desempate estável por ID, consistente com a interface. Teste Rails de paginação preparado; execução ainda pendente.
- [x] Reproduzir/corrigir escopo pessoal, estados omitidos, entrada realtime de caixa não membro e perda do filtro explícito `open` na URL.
- [x] Executar 65 testes JS em cinco arquivos, zero falhas/skips; ESLint focal com exit 0.
- [x] Executar dois harnesses Ruby com classes reais e fronteiras simuladas: 3 casos de relógio e 2 de ordenação. Sintaxe dos sete arquivos Ruby verificada.
- [x] Revisão independente do diff: nenhum P1/P2 restante no recorte revisado. Enterprise::ConversationFinder preservado.
- [x] Executar regressão Rails focal em PostgreSQL/Redis reais e temporários: 59 exemplos em sete arquivos, zero falhas, zero pendências e zero erros fora dos exemplos. Inclui Finder OSS/Enterprise, roteamento, visibilidade exclusiva, escopo pessoal e importação histórica; banco produtivo não utilizado.
- [x] Executar build frontend: exit 0 com 4096 MiB, valor já definido no Dockerfile; 5639 módulos transformados, 364 entradas de manifesto/10 entrypoints, nenhum arquivo ou import referenciado ausente. Tentativa inicial de 2560 MiB falhou com heap out of memory; evidência preservada. A suíte Rails completa e E2E não foram executadas neste incremento.
- [x] Registrar checkpoint, resultados e lacunas. Sem commit/publicação/deploy deste incremento.

## Revisão de riscos

1. Importação antiga depois de mensagem live: a data recente não pode regredir.
2. Recibo repetido: nenhuma mensagem duplicada nem callback novo.
3. Conversa resolvida/atribuída: status, responsável, time e updated_at preservados.
4. Empates em limites de página: nenhum registro omitido em uma fotografia estável.
5. Revogação de tenant/inbox: escopo e locks existentes preservados.

Histórico completo exige incremento separado e versionado de captura, grupos, mídias, identidade, checkpoint e recibos. Aumentar uma quota de distribuição não executa esse trabalho.

## Checkpoint em 11/11/2026

Branch local `codex/whatsapp-history-order-20261111`, base 126d251dd5d5179783706f4934ba4fabc9d12b19. Código ainda não commitado. Resultado focado: `output/evolution-direta-grupojrc-20261111/lab2-focused-after-review.json` na raiz de coordenação (nome histórico da pasta; não é teste da Evolution externa).

O usuário encerrou a investigação da Evolution externa e determinou foco no Broker JRC. A comparação anterior não comprovou recebimento das amostras na caixa 55. Nenhum novo envio, replay, pareamento, restart de sessão ou mudança produtiva foi feito neste incremento de código. Broker permanece sem alterações locais por este incremento; próxima frente exige captura durável versionada de chats/grupos/mídias, sem liberar indiscriminadamente MESSAGES_SET.

Infraestrutura local: limpeza autorizada de temporários, 17 imagens antigas de teste sem uso e compactação autorizada do VHDX Docker concluídas. A compactação reduziu o arquivo em 11.355.029.504 bytes; inventário anterior de 109 containers/85 volumes/44 imagens preservado, mesmos 15 ativos retomados. Um PostgreSQL local CRM_HUB exigiu reparo de três caminhos SQL ausentes, autorizado separadamente; o banco existente pulou a inicialização. Nenhuma alteração produtiva ou rotina de backup/dump/restore executada.

Os testes Rails inicialmente sofreram espera em p9_client_rpc na montagem Windows e um problema CRLF no bin/rails. A execução final usou uma cópia somente de código versionado e dos testes novos dentro do filesystem Linux do container descartável; normalização de bin/rails apenas nessa cópia. Corrigidos os setups dos testes: criação do usuário antes de limpar a fila de jobs; contexto via Current.account com restauração em ensure, conforme o módulo Current desta base. Implementação de produção preservada.

Evidências em output/broker-whatsapp-sync-20261111 na raiz de coordenação: lab2-rails-history-linux-result.json (59/0), lab2-rails-history-linux-execution.json, contexto SHA-256 em lab2-source-test-context.json, logs e resultados das tentativas iniciais. Não confundir testes isolados com sincronização/homologação real do WhatsApp.

Build concluído em 11/11/2026 às 17:57 UTC: Vite exit 0 em 19m28s. O plugin Ruby selecionou public/vite no worktree, apesar do outDir solicitado na CLI; manifesto e arquivos reais verificados nesse diretório. Avisos observados: chunks grandes (DashboardIcon ~14,6 MB minificado), WebphonePage importado estática e dinamicamente, fundo JRC não resolvido no build e Browserslist desatualizado. Não houve correção desses avisos nem teste visual/operacional de produção neste incremento. A imagem Docker ainda não foi criada/publicada e o código permanece sem commit.

## Continuação: receptor silencioso V2 e gates ampliados

O checkpoint acima descreve a etapa inicial; não deve ser confundido com o estado posterior. Implementado o receptor V2 local de texto/grupos com recibos transacionais, bootstrap, reuso de mensagem comprovada e proteção dos grupos no core. Documento corrente: `docs/jrc-broker/history-sync-v2.md`; checkpoint: `CONTINUE-AQUI.md`. Mídia continua não suportada no V2, sem simular ACK físico.

Regressão Rails ampliada: **228 exemplos em 15 arquivos, zero falhas/pendências**, após RED→GREEN dos achados da revisão. Inclui V1/V2, Finder OSS/Enterprise, pesquisa de contatos, exportação, merge, ContactInbox, filas e visibilidade. Spec de paginação agora `spec/finders/conversation_finder_history_order_spec.rb`, renomeado para seguir o padrão da classe. UI:65/65 em5 arquivos, ESLint7 arquivos exit0, RuboCop12 arquivos novos zero ocorrências. Lint core foi comparado ao baseline; violações de classe/métodos antigos continuam registradas. Não há declaração de lint global limpo.

Não se repetiu build frontend porque o código UI não mudou desde o build verificado. Não houve CI remota, publicação, imagem, deploy, teste com telefone, captura/replay real ou rotina excluída do escopo. O plano conjunto do Broker ainda exige captura operacional, writer/deduplicação, projeção, mídia física, progresso e E2E; essas lacunas não foram marcadas como concluídas.
