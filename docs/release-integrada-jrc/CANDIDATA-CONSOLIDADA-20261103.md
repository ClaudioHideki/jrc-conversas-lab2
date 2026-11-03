# Candidata consolidada Grupo JRC — 03/11/2026

Pedido vigente autoriza publicação da imagem e atualização do Grupo JRC após validação. Branch preservada: `codex/lab2-integral-20261102`, base `20e56104ec0f748b53da58edb1b639369fad0a1e`. Produção consultada no terminal Rails: `daae59ecdbfd28008773a8adf9ec13f34ac8f486`.

## Reconciliação

O fetch habitual estava restrito a uma única branch antiga. Foram buscadas explicitamente todas as branches. Nenhuma revisão de código posterior a20e56104 foi encontrada. Atendimento, performance, Service Desk, Backoffice e Campanhas publicados já são ancestrais da candidata. Os quatro commits de26/10 estão aplicados de forma equivalente na baseDAAE; não foram reaplicados.

Preservados todos os fontes e implementações locais preexistentes: conexões, distribuição e auditoria; Central de Migração; NICO; Flow/editor nativo; media ownership/scan/compensação; ajustes de callbacks e campanhas. Não há merge automático na main.

## Novos gates de publicação

- A branch integral aciona `backoffice-flow.yml` e exige sua validação no mesmo SHA antes da publicação da imagem.
- Os três bancos descartáveis de CI e o smoke Rails/Sidekiq carregam schema e aplicam migrations pendentes sem gerar dump ou alterar fontes.
- O helper é exclusivo de Rails.test e banco com sufixo_test; verifica migrations pendentes, hash do schema e triggers/constraint de mídia.
- Incluídas regressões de migração, mídia, histórico, permissões NICO e concorrência. MinIO físico recebe bucket imprevisível por exemplo; sem storage ou credenciais produtivas.

## Evidências locais já concluídas

- Rodada final no banco frio permitido:239exemplos Rails,0falhas,0pending,147.2s +14.35s de carregamento. Inclui concorrência real, SIGKILL do worker, fencing de scan, isolamento NICO/conexões e os testes adicionais de referência entre Accounts.
- Banco criado do zero: schema202000 + migrations203000–205000; versão final20261102205000,2triggers de ownership e schema fonte inalterado.
- MinIO físico/ActiveStorage S3:4exemplos,0falhas. PUT/readback com hash, corrupção física detectada, KEEP de Blob existente, falha de transporte injetada e retry de limpeza da própria chave. Não equivale a indisponibilidade física do host S3 produtivo.
- Frontend:24arquivos,134testes aprovados. Avisos de sourcemap e ref Vue registrados, sem falhas.
- ESLint focal:0erros,12avisos. Ruby dos3gates novos:0ocorrências após estilo.
- Node:9testes aprovados (gates e timestamps).35fontes JS/JSON/Vue e296timestamps validados;7migrations novas posteriores à base.
- Revisão independente: nenhum blocker confirmado. Suspeita sobre referências estrangeiras retirada após reprodução e inspeção da herança `JrcProjects::ApplicationRecord`/`AccountScopedRecord`; guard existente retornaINVALID_DESTINATION. Regressões adicionais preservam esse contrato sem duplicar validações.

## Rodadas intermediárias que não aprovam release

-233exemplos,0falhas,9pending: banco frio inicialmente fora da whitelist de concorrência. Não contar como aprovação dos casos ignorados.
-239exemplos,12falhas: banco antigo de laboratório tinha ledger110000 mas coluna inbox_id indevidamenteNOT NULL; não representa a criação fria nem prova defeito produtivo. Banco antigo preservado para investigação.
- O teste de crash agora avança o relógio de teste até vencer a janela de5minutos da seleção periódica. Não se removeu a janela produtiva para fazer a assertion passar.
- Ruling: rodar a suíte final no banco frio explicitamente nomeado na whitelist. Evidência final e CI do candidato devem ser registradas separadamente; as rodadas acima permanecem históricas.

## Promoção e limites

Aguardar resultados finais de concorrência/CI e build/smoke da imagem exata antes de promover. Imagem anterior: `ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:bf68a7b19a2d7ad23d41f18a5370a58116aaca5c893389a873252400bd9d5eb9`.

Compose completo conferido:125linhas, imagem única por âncora, init `db:chatwoot_prepare`, Rails2CPU/3G, Sidekiq1CPU/2G, init1CPU/1G. Preservar ENV, volumes e redes. Migrations203000–205000 são irreversíveis para preservar evidência; rollback de binário exige manter o banco expandido e avaliar compatibilidade, não executar down.

Sem mensagens reais, pairing, replay deFAILED/UNKNOWN, mudança de engine Evolution, carga de clientes ou rotinas de backup/dump/restore. Integração operacional WhatsApp/CCLX, IA paga e capacidade50/400/900 continuam exigindo suas homologações próprias. Nenhum teste sintético prova essas condições.
