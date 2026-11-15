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

- Rails/PostgreSQL/Redis no SHA corrigido, incluindo concorrência, acesso negado, cópia privada, intenção durável e ACK perdido.
- Chrome desktop/mobile, claro/escuro, com assets compilados do mesmo produto e os13 cenários previstos, sem cenários omitidos.
- E2E Broker c3bae632→Rails/Sidekiq do candidato→MinIO com comparação independente de IDs e bytes, mídia, grupos, retry e recibos. O laboratório antigo3.4.4 não aprova o runtime3.4.12.
- CI consolidada, smoke da imagem Alpine, SHA/digest, novidades remotas e revisão do diff antes da promoção/aplicação autorizada.
- Leitura produtiva distingue membership, atribuição exclusiva e compartilhamento. Histórico importado não ativa URA nem troca responsáveis. Membros não ganham acesso a outras caixas/Accounts.

## Limites operacionais

Banco, ACK e checksum sintéticos não provam equivalência com todo o histórico do celular. A disponibilidade dos eventos do WhatsApp, mídias antigas e ownership efetivo da sessão exigem homologação própria. Não ativar captura produtiva, conectar números, enviar testes reais nem reprocessar UNKNOWN por inferência. KEEP deve ser preservado. Backup/dump/restore e comandos agregados que os acionem permanecem fora do escopo.

A publicação, o deploy e o aceite físico são estados distintos e ainda não são declarados concluídos neste checkpoint. Atualizar as evidências do SHA final ao término.
