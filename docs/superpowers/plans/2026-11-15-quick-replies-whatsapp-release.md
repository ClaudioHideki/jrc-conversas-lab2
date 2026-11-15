# Respostas rápidas e percurso WhatsApp — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans para executar os incrementos nesta sessão. Passos usam checkboxes; revisão independente ao fechar.

**Goal:** concluir o aceite das respostas rápidas e comprovar visibilidade, durabilidade e mídias antes da publicação no Grupo JRC.
**Architecture:** preservar LAB2 55da80eb já produtivo, incorporar a frente 93aa727d descendente e corrigir os defeitos reproduzidos nos testes. Broker c3bae632 permanece referência e só recebe alteração funcional se um defeito for reproduzido; laboratório e leitura produtiva têm provas distintas.
**Tech Stack:** Rails/PostgreSQL/Redis/ActiveStorage, Vue/Vitest, Chrome/Playwright, Broker TypeScript/Evolution/S3.
**Spec:** docs/adr/20261115-respostas-rapidas-catalogo-aprovacoes.md, regras de domínio do LAB2/Broker e pedido explícito de correção/publicação de15/11.

## Global Constraints

- Preservar dados, sessões, engine, permissões, histórico e atualizações concorrentes. Main somente fast-forward após gates; sem force/reset/clean.
- Backup/dump/restore e rotinas agregadas dessa natureza fora do escopo.
- Não fazer replay cego, parear números ou ativar captura por inferência. Envio real exige destino e caixa definidos.
- Minhas respeita membership e a política: pessoais/compartilhadas não se confundem com distribuição exclusiva/URA/supervisão.
- Não tratar aceite em banco sintético como prova de zero perda do WhatsApp ou cópia completa do celular.

## Review Focus

- Perda de resposta após COMMIT deve reutilizar a mesma intenção/mensagem e não duplicar o anexo.
- Mudança de agente, Account ou caixa deve invalidar dados tardios e negar acesso cruzado.
- Importação em temas diferentes não deve reutilizar acidentalmente a mesma chave de evento da fixture.
- Modelo compartilhado e arquivo enviado devem ter custódias independentes.
- Cronologia e paginação de Minhas devem preservar a origem da conversa e não ocultar dados por filtros incorretos.

### Task 1: Corrigir a aceitação real das respostas rápidas

Files: teste authorityLifecycle.spec.js; harness approval_browser.spec.cjs da branch CI publicada; contrato script/jrc_runtime_contract_test.py e seu teste se necessário.

- [x] Reconciliar main55 e frente93aa; preservar as branches e as duas correções publicadas posteriormente a410.
- [x] Ler RED do Chrome43753740260: criação retorna201 e teste esperava200; API nativa usa status:created.
- [x] Ler tentativa Chrome43756413162 e frontend43759971323; registrar a segunda falha sem aprovar os cenários não executados.
- [x] Conferir RED JSDOM da CI 43759971323 e incorporar a correção publicada 2be22e86, sem mudar o Dialog de produção. Vue completo passou504/504 após as regressões adicionais.
- [x] Preservar exatamente201 no harness seguinte e revisar isolamento de eventos por tema, mantendo a proteção contra duplicação. Chrome ainda requer nova execução integral no candidato final.
- [ ] Executar Vue, Rails/PostgreSQL, concorrência, lint, build e Chrome desktop/mobile claro/escuro, preservando IDs, anexos e negativas.

### Task 2: Comprovar Minhas, ACK e mídias no percurso integrado

Files: fixtures e runners existentes labs/history-sync-lab2 nos dois produtos; specs jrc_history_sync_v2, conversations_member_inboxes e integração history-sync-operational-lab2.

- [ ] Executar testes contra o candidato LAB2 e Broker exatos em infraestrutura descartável, incluindo texto, imagem/legenda, áudio, PDF, grupos, concorrência e ACK perdido.
- [ ] Comparar IDs da origem/Broker/JRC e checksum dos bytes, em duas Accounts isoladas, incluindo membro e agente sem acesso à outra caixa.
- [ ] Ler estado produtivo autorizado por metadados: vínculos, filas, recibos e contagens, sem payloads nem reprocessamento.
- [ ] Qualquer defeito funcional encontrado recebe RED, correção mínima e novo GREEN antes da próxima etapa.

### Task 3: Publicar e conferir

- [ ] Revisar diff integral e novidades remotas, incluindo uma revisão independente da segurança/compatibilidade.
- [ ] CI e imagem no SHA exato, sem reutilizar o verde de55/410 para o novo candidato.
- [ ] Promover e atualizar apenas Grupo JRC quando gates aprovados; preservar Broker se não houver mudança necessária.
- [ ] Conferir Rails/Sidekiq, migrations, saúde e interface; registrar separado qualquer teste físico que dependa de amostras reais.
- [ ] Atualizar CONTINUE-AQUI.md, TASKS.md, evidências e relatório final.

## Ledger

Pre-flight: Tasks1/2 compartilham o candidato LAB2; a suite integrada deve usar exatamente a candidata validada. Task3 consome SHA/digest e não aprova outro código por data/branch.
Ruling: a autorização de correção/testes/publicação já foi dada pelo usuário; a execução prossegue sem nova aprovação de um plano equivalente.
Ruling: o retorno201 é um contrato legítimo; não alterar a API para mascarar expectativa incorreta. O erro foi observado no Chrome com Rails real.
Ruling: Docker local está parado; a infraestrutura descartável deve ser retomada de modo controlado ou executada no runner isolado, sem usar bancos produtivos para testes.
Ruling: Docker retomado somente localmente; o Rails antigo recusou Ruby3.4.4 contra Gemfile3.4.12. Manter o runtime correto, sem diminuir a versão exigida para obter um passe artificial.
Ruling: três P2 reproduzidos receberam correção e revisão independente: identidade do anexo, substituição de arquivo de catálogo e limite nativo de texto. A admissão de fontes exige lista explícita, comparação contra 2be22e86 e oito fingerprints da revisão; nunca admitir tudo encontrado por git diff.
