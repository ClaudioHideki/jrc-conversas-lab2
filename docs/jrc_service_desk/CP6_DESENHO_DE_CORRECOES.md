# CP6 - desenho antes das correcoes

Base unica CP5: ecc56915825205ee5d42695fe3a1350fce6d23a3f3b74e235f00776a3919e148.
Sem reconstruir checkpoints. PENDENTE - validacao nativa em Docker/servidor.

## Catalogos administrativos
Completar criar/listar/editar/ativar/desativar de Queue, Category, Priority, TicketStatus
 e Service, exclusivamente nas unidades ja autorizadas e com suas capacidades nativas.
Nenhuma exclusao fisica ou troca de Account/Unidade. Codigo e identidade ficam estaveis.
Administracao consulta inativos; seletores operacionais continuam somente ativos.
Nao mudar fase de status referenciado em versao historica; nao trocar equipe de fila em uso.
A desativacao nao reescreve tickets ou politicas; pode bloquear futuras transicoes que
requerem aquele registro ativo, e sera indicada na interface.

Reutilizar a tabela nativa audits (Audited::Audit), ja presente, para evidencia transacional
com ator real, Account associada, unidade/membership, antes/depois e chave de correlacao.
Nao criar outro banco de auditoria ou tabela RBAC. A identidade do auditable vem de um mapa
fechado de cinco classes; nunca constantize entrada do cliente.
Idempotencia: chave por Account/Unidade/ator sob o lock de Unidade ja usado no dominio;
audit request_uuid deriva desses IDs e da chave, e fingerprint distingue a intencao.
Revisao otimista: digest do registro atual, conferido sob lock. Service nao possui lock_version;
a revisao de contrato evita adicionar coluna apenas para esta interface.
Releitura: POST/PATCH -> GET recibo de auditoria -> GET registro -> comparar -> interface.
Falha de releitura/rede nao e sucesso, repetir somente a mesma intencao/chave.
Nao apagar nem permitir undo publico da auditoria.

## Sem migrations CP6 planejadas
Nenhuma tabela nova e necessaria: reutilizar catalogos CP2/CP4 e auditoria nativa.
Caso uma descoberta exija mudanca estrutural, registrar antes de implementar.

## Correcoes determinadas pelo codigo e contratos
- Nao tratar false como status inicial existente em ui_context.
- Preservar phase/position/initial no contrato de catalogos, sem campos brutos.
- CatalogView reutilizada entre rotas deve limpar recurso/preview e recarregar conforme props.
- Politica de ciclo: uma politica de servico inativo deve poder ser desabilitada por publicacao
  autorizada; ativar para servico inativo permanece negado. Sem alterar snapshots vinculados.
- Nao fabricar estado vazio/erro, nao ampliar escopo e nao alterar KPIs localmente.

A auditoria de cadastros e associada a Unit, nao a Account: o endpoint nativo de auditoria por Account nao filtra UnitMembership. Isso evita expor antes/depois de outra unidade pelo log geral. O account_id, o unit_id e o ator ficam no metadata e no recibo autorizado. Mesma tabela nativa audits; nenhum novo catalogo de auditoria ou permissao.
