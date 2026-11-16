# Candidata de respostas rápidas e percurso WhatsApp — 2026-11-15

## Escopo e base

Preservar a base completa LAB2 55da80eb e incorporar a frente de respostas rápidas até 2be22e86, sem reescrever commits, migrations ou funcionalidades. A publicação no Grupo JRC foi autorizada pelo usuário, condicionada à conclusão dos testes. Broker c3bae632 só recebe alteração funcional se um defeito específico for reproduzido.

## Defeitos e correções

1. Chrome 43753740260: criação de política devolve 201; o teste esperava 200. Preservar o contrato legítimo. Chrome 43756413162: cenários claro/escuro reutilizavam o mesmo evento; o backend recusou corretamente o segundo cadastro. Isolar os eventos da fixture; não remover a proteção.
2. O novo cenário authorityLifecycle do commit004319 falhou no JSDOM porque HTMLDialog.close não existe nesse ambiente. A correção publicada2be22e86 modela o ciclo nativo no teste, sem alterar o Dialog produtivo.
3. CatalogImport mantinha documento/mapeamentos anteriores ao rejeitar ou ler outro arquivo. Limpar os três valores ao iniciar a seleção; bloquear prévia durante leitura; tratar rejeição/erro sem reaproveitar o arquivo anterior; descartar leitura fora de ordem.
4. Picker podia baixar um PDF substituído depois da prévia, usando os metadados antigos. Passar revision+attachment_id; capturar o blob sob lock após conferir ambas as identidades; baixar os bytes desse blob imutável. Consumidores legados sem identidade explícita continuam compatíveis. A troca do modelo não altera os bytes de uma imagem já revisada e armazenada localmente.
5. Envio direto ignorava o limite do ReplyBox. Reutilizar maxLength no picker, após inclusão da assinatura, e conferir o limite equivalente por canal no servidor em unidades UTF-16. Conteúdo excedente permanece editável; nenhuma mensagem é criada. Janela, confirmação, ator, revisão, idempotência e regras de anexo continuam obrigatórios.

## Testes e revisão até este checkpoint

- Vue inicial:496/496. RED dirigido:4 falhas reproduzindo catálogo/anexo e1 falha de limite. GREEN dirigido:19/19. Regressão ampliada com contrato da API:504/504 em40 arquivos.
- CI RED43762809955, produto173d539b:380 exemplos Rails,3 falhas,0 pendentes. Dois cenários demonstraram HTTP200 indevido para identidade antiga do anexo; o terceiro expôs uma fixture que tentava configurar360dialog, corrigida para Cloud sintética sem sincronização/validação externa.
- CI dirigida43763516449, produto dac23cac:1 exemplo,1 falha,0 pendentes. O limite não era validado antes da janela. A fixture de entrada também passou a especificar a mesma Account; não confundir erro de fixture com entrega real.
- Revisão independente: três P2 originais corrigidos; nenhuma nova falha P1/P2/P3 comprovada nas fontes revisadas. Revisão estática/Node não substitui GREEN Rails/Chrome.
- Contrato de runtime passou e suas15 negativas recusam arquivos ausentes/adulterados. A lista é fixa e mantém o assert de conjunto exato. Os manifestos derivados preservam base, proveniência e conjunto de módulos; apenas fingerprints necessários foram regenerados.
- Nenhuma migration nova ou alteração de dependência, Dockerfile produtivo, engine, credencial ou política de retenção.

## Gates restantes

Atualização: no produto1224ea08, a CI43765226812 comprovou380 exemplos Rails/504 Vue; Chrome43766707410 aprovou13/13 sem skips/flaky e assets novos; laboratório43768493424 aprovou63 exemplos Rails e dois E2Es com IDs/bytes privados, ACK perdido, indisponibilidade e Minhas entre duas Accounts por cenário. Broker:100 regressões unitárias dirigidas aprovadas, sem alteração de código. Essas evidências não comprovam sessão real nem histórico completo do celular.

A matriz geral43766948449 reproduziu uma falha preexistente de isolamento em spec/models/notification_spec.rb: a consulta global incluía uma notificação fora da fixture. O teste agora inclui explicitamente um registro externo, filtra os três IDs criados em ordem embaralhada e preserva first/last originais, sem order/unscoped. A revisão independente aprovou a correção de fixture; o modelo permanece byte-idêntico à main55. A CI consolidada e a imagem precisam concluir novamente no novo SHA. Não tratar o verde anterior como execução do spec corrigido.

- Rails/PostgreSQL/Redis no SHA corrigido, incluindo concorrência, acesso negado, cópia privada, intenção durável e ACK perdido.
- Chrome desktop/mobile, claro/escuro, com assets compilados do mesmo produto e os13 cenários previstos, sem cenários omitidos.
- E2E Broker c3bae632→Rails/Sidekiq do candidato→MinIO com comparação independente de IDs e bytes, mídia, grupos, retry e recibos. O laboratório antigo3.4.4 não aprova o runtime3.4.12.
- CI consolidada, smoke da imagem Alpine, SHA/digest, novidades remotas e revisão do diff antes da promoção/aplicação autorizada.
- Leitura produtiva distingue membership, atribuição exclusiva e compartilhamento. Histórico importado não ativa URA nem troca responsáveis. Membros não ganham acesso a outras caixas/Accounts.

## Limites operacionais

Banco, ACK e checksum sintéticos não provam equivalência com todo o histórico do celular. A disponibilidade dos eventos do WhatsApp, mídias antigas e ownership efetivo da sessão exigem homologação própria. Não ativar captura produtiva, conectar números, enviar testes reais nem reprocessar UNKNOWN por inferência. KEEP deve ser preservado. Backup/dump/restore e comandos agregados que os acionem permanecem fora do escopo.

A publicação, o deploy e o aceite físico são estados distintos e ainda não são declarados concluídos neste checkpoint. Atualizar as evidências do SHA final ao término.


## Fechamento de publicação e implantação — 15/11/2026

Produto testado e implantado: `5c3fb7f700d7bb685f17292f59b873df14ddf34d`. Main promovida em fast-forward normal desde55da80eb, preservando2be22e86. Imagem GHCR por digest: `ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:e5b6c92bcbce98fdbd6014726afd719b1f5078771d01ac551d4ee9d169e1ca82`.

CI43770789984:49/49 jobs aprovados,2513 testes frontend,build e smoke Alpine. CI dirigida43770871972:404 Rails/504 Vue. Chrome43771653630:13/13,zero skips/flaky,desktop/mobile e claro/escuro. E2E43770887292:63 Rails e dois cenários Broker c3bae632→Rails/Sidekiq→MinIO privado com identidades,bytes e ACK perdido,zero falhas. Suítes sobrepostas não constituem um total único. A origem WhatsApp é sintética.

Deploy autorizado e runtime conferidos no Grupo JRC:Rails e Sidekiq retornam o mesmo git_sha;API200/filas e dados ok;336 migrations e nenhuma pendente. Somente o digest da âncora do Compose mudou. Sem mudança de ENV,recursos,credenciais,engine,sessões,retenção ou captura. Broker c3bae632 preservado,sem republicação redundante. Nenhuma migration nova.

A interface autenticada carregou Respostas Prontas e Minhas caixas/Todas e histórico. O aceite operacional permanece parcial: há pendências de autoridade/legado,storage e configuração de grupos registradas no relatório privado. A validação física foi adiada pelo usuário. Não remover atribuição de bot em lote,não ignorar autoridade,não reenviar UNKNOWN nem ativar captura por inferência. Nenhuma rotina de backup/dump/restore foi executada.

Evidências públicas de execução e limites:`docs/jrc_consolidation/quick_replies_whatsapp_release_20261115.md`. Pacote privado no output do workspace. Este checkpoint posterior é documental; não confundir seu commit com o SHA funcional da imagem acima.
