# Auditoria administrativa do Call Center por conta e unidade

Status: aceita para implementação incremental sob a autorização de continuidade de 17/11/2026; ainda depende dos testes do novo SHA.

## Fontes e checkpoint preservado

806327269f896ea124cdbc17f7ceceea176124e8: CI 44080303193, 428 Rails principais + 3 de concorrência, 185 Vue e 56 Chrome aprovados, sem pendências. Artefato 14328051243, SHA-256 13c6e396909eb5d19b729105d9bc8f6e41d3df880415a1552f5e041c65d21854; 52 capturas verificadas. O opt-in de revisão do perfil e as permissões nativas permanecem preservados.

A consulta genérica de auditorias nativa é limitada por Account/administrador e não conhece a unidade. Acrescentar logs com dados de unidades sem proteger essa consulta criaria uma via alternativa de exposição. Não criar outra tabela de auditoria nem usar o inbox de eventos PABX para simular mudanças locais.

## Contrato e armazenamento antes da implementação

Reutilizar Audited.audit_class, já configurado para a edição instalada, e os callbacks transacionais. Audited 5.4.1 preenche request_uuid a partir do contexto nativo ou de UUID novo; referência: https://github.com/collectiveidea/audited/blob/v5.4.1/lib/audited/audit.rb. Nenhuma nova dependência, migration ou alteração de SQL é necessária.

Registrar criação, alteração e retirada de Unit, Queue e QueueMembership com ator, Account, tipo/ID, antes/depois de campos permitidos e escopos corporativos observados. Ler a versão anterior sob lock da linha dentro da transação; alterações sem diferença não criam falso evento. Falha/rollback da mutação não mantém auditoria de sucesso. Settings arbitrários, segredos, payloads, transcrições e descrições não são copiados. Alteração em settings não expostos recebe apenas sinalizador de conteúdo omitido.

Marcador próprio separa estes eventos das demais auditorias. A consulta CC também pode apresentar a trilha de capacidades CustomRole já existente; ela é global da Account e não aparece a quem tem cobertura corporativa restrita. O endpoint genérico nativo aplicará o mesmo filtro somente às famílias de eventos CC, preservando as auditorias de outros módulos.

## Autorização e visibilidade

Consulta e detalhe exigem audit? existente. Exportação exige adicionalmente reports? existente, sem criar grants. A visibilidade intersecta Account, AccessScope nativo, unidade/fila atuais e os escopos corporativos antes/depois. Uma mudança entre unidades não permite ao usuário de apenas uma delas ler os dados da outra. Eventos não mapeados não viram concessão de unidade. Sob cobertura restrita, histórico de objeto sem vínculo atual verificável permanece indisponível; não inferir autoridade apenas pelo log.

Nenhuma mutação de auditoria será exposta. Os novos endpoints GET configuration_audits, GET configuration_audits/:id e GET configuration_audits/export são contratos aditivos. A consulta antiga administration/audit de eventos PABX permanece disponível sem mudança de formato. A interface terá Configurações e Eventos PABX, preservando o acesso anterior.

Filtros de datas no fuso da Account, recurso, operação, ator, unidade e correlação são aplicados depois da autorização. Paginação limitada a 100 linhas. Exportação síncrona limitada a 1000 linhas; acima disso, pedir filtros mais restritos, sem truncar silenciosamente. Reutilizar OperationalCsv para neutralizar fórmulas. Não retornar e-mails, tokens ou settings arbitrários.

## Critérios e testes previstos

Rails/PostgreSQL: antes/depois e ator/correlação, segredo omitido, rollback, ausência de falso evento, conta estrangeira, unidade negada, mudança de unidade, ausência de audit, exportação sem reports, filtros, paginação, datas inválidas, limite de exportação e proteção da consulta genérica. Preservar os testes de perfis e os três de concorrência.

Vue: filtros/paginação, detalhe em popup, erro sem lista vazia fictícia, exportação negada/erro e resposta obsoleta descartada ao desmontar. Chrome real nas quatro combinações 1440/390, claro/escuro: alteração local persistida e auditada, consulta/detalhe/exportação, negações de conta/unidade/permissão e integridade do arquivo. Manter os 56 cenários anteriores.

## Limites explícitos

Auditoria de operações locais não é ACK de PABX. Não publicar, sincronizar externamente ou marcar um comando como aplicado. Acesso a gravações, retenção, auditoria de escuta/download e a homologação PABX/Supabase/NICO continuam nas etapas posteriores. Herança e elegibilidade terão contratos e testes separados; este incremento não concede acesso nem altera o cadastro de usuários/equipes.

A consulta administrativa respeita também a feature flag nativa audit_logs. Sem ela, a UI informa indisponibilidade e a API não retorna registros; o catálogo de eventos PABX anterior permanece disponível sob sua própria permissão. Nenhuma flag real é ativada por este incremento. Os fixtures habilitam explicitamente audit_logs apenas na conta sintética.

A inspeção dos controladores mostrou que a autorização do registro e a validação de fila ativa precedem a gravação sem bloquear seus vínculos. O incremento também revalidará essas condições depois de bloquear a linha e as referências locais, em transação, para impedir edição fora do escopo após transferência concorrente ou inscrição em fila desativada durante a requisição. Usar locks locais ordenados e FOR NO KEY UPDATE nos pais para preservar compatibilidade com FKs. Parâmetros públicos não mudam. Dois testes HTTP/PostgreSQL com barreiras, sem sleeps, devem provar as corridas no banco descartável de concorrência. A proteção existente de perfis não é removida.

O BaseController CC propaga request.request_id no contexto request-local do Audited e restaura o valor anterior no ensure. Isso garante correlação com a requisição sem alterar Current ou callbacks globais. A API pública de contexto está em https://github.com/collectiveidea/audited/blob/v5.4.1/lib/audited/sweeper.rb.

## Evidência do primeiro checkpoint e interface

- Backend 67a8576157014c4108f2a20f0109f5a52922465d, CI 44093912707: 462 exemplos Rails mais 5 de concorrência, zero falhas/pendências/erros; 185 Vue. Gate interrompido por 15 infrações novas de lint. Artefato 14332293316, SHA-256 fb18c185e7e39230dc9c56eb0b2ce224dbc404ce86987a13292844a7715af8c1. Build/Chrome não executados nesse SHA.
- Correção mantém os contratos: helpers de snapshot e detecção SQL, yield no serviço, escopo de rotas aditivo separado e formatação dos specs. Nenhuma regra desativada.
- Interface usa filtros na URL, prévia, popup, histórico completo do recurso autorizado e CSV verificado por SHA-256 antes do download. Troca de conta descarta respostas e nomes anteriores. Eventos PABX continuam em aba separada.
- Operadores da homologação são fixtures sintéticos explícitos com cobertura da unidade A; não recebem configurar/administrar. Nenhuma concessão em ambientes existentes.
- Próximo gate exige 64 cenários Chrome (os 56 anteriores mais oito), onze testes Vue novos e nova execução nativa. Conclusão da Parte 1 permanece aberta.
