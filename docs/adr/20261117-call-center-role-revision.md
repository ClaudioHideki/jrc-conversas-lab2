# Revisão esperada nos perfis do Call Center

Status: aceita para implementação incremental pela autorização de continuidade de 17/11/2026; aceite depende da CI e do Chrome do novo SHA.

## Contexto e fontes

A base fc0bf6ce preserva 424 Rails, 180 Vue e 52 Chrome na CI 43966907993. Os Word originais permanecem com hashes 5db370d9b7598a720d32f7f60eba4e22b4b61878327bd4459176ff729fe7a2c8 e 8f9300cf1940012f71be1a97903a192f7b5a18667e6da6664b9f972866e7e88b. F11 exige revisar um perfil alterado em outra sessão; o lock já aprovado impede restauração indevida de poder revogado, mas não detecta um formulário antigo.

A main foi observada em 89779191b0b4be44929a426c7a924dbcad4c3690, sem incorporá-la à branch do Call Center. Desde a referência a24adc6d, a linha principal evoluiu em módulos Broker/WhatsApp, filtros, proposta CRM, gates e documentação, com uma migration adicional de recibos live. As alterações da rodada anterior compartilham TASKS.md; a comparação não prova compatibilidade de execução futura. Não sobrescrever nenhuma das linhas. Conferir novamente a main antes de uma consolidação.

## Contrato aditivo e transação

A resposta nativa de CustomRole recebe revision: SHA-256 do identificador, Account, dados editáveis, capacidades e updated_at com precisão de microssegundos. Não é credencial nem autorização. Nenhum segredo é serializado; o token fica vinculado à versão e ao objeto.

O cliente pode enviar expected_revision na raiz do PATCH nativo. Dentro do with_lock, após as verificações de autorização/escopo/GrantGuard já existentes, a API compara a revisão com o registro recarregado. Divergência retorna 409/stale_role_revision, sem gravar nem emitir auditoria de sucesso. Revisão explicitamente vazia ou malformada retorna 428/role_revision_required. Atributos de revisão não são atribuídos ao model.

O editor do Call Center exige uma revisão carregada e sempre a envia em edição. Em conflito, conserva o rascunho, bloqueia o salvamento e oferece carregar a versão atual para comparação. Esse carregamento não grava nem substitui campos; o usuário precisa revisar novamente o diff e confirmar. Perda de acesso ou falha ao carregar mantém o bloqueio.

Compatibilidade: clientes nativos anteriores que omitem expected_revision mantêm seu contrato. Isto não promete controle otimista para esses clientes. Tornar a precondição obrigatória globalmente exige migração de todos os clientes; não alterar o contrato de outros módulos silenciosamente. O GrantGuard e o lock continuam obrigatórios mesmo para clientes anteriores. Nenhuma migration, SQL, dependência ou permissão real é alterada.

## Aceite e testes previstos antes da publicação do checkpoint

Sete exemplos Rails: versão válida; conflito preservando dados/auditoria; versão vazia; formato inválido; token de outro objeto/Account; compatibilidade legada com negação de concessão crítica; recarga/revisão explícita. Os três testes de concorrência já aprovados são preservados.

Cinco Vue verificam versão capturada após revisão, rascunho e nova revisão no conflito, recarga com falha, ausência de versão sem downgrade silencioso e payload legado sem opt-in.

Chrome mantém os 52 cenários e acrescenta o fluxo de duas sessões contra Rails/PostgreSQL reais nos quatro projetos (1440/390, claro/escuro), totalizando 56. Conferir 409, conteúdo não sobrescrito, rascunho retido, comparação, novo token, confirmação e persistência após recarga. Capturas de conflito e de re-revisão são evidências do SHA da execução. Mock de Vue não substitui Chrome nativo.

## Limites e continuidade

Não há publicação PABX, acesso externo, concessão automática, merge, Docker ou deploy. Herança de equipe, elegibilidade de novos usuários e consulta/auditoria por unidade seguem como próximos incrementos, com precedência e contratos próprios antes da implementação. Este ADR não altera a decisão histórica de 16/11 nem marca as etapas 0–2 ou a Parte 1 como concluídas.
