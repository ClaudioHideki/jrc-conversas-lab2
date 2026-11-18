# Rascunhos locais de URA: contrato interno separado do PABX

Estado: proposta técnica para o próximo incremento, ainda não implementada. Prioridade atual: concluir a validação do checkpoint cf040419.

## Requisito e código auditado

Os dois Word, seção de URAs, exigem rascunho, importação/exportação JSON versionada, referências autorizadas, simulação DTMF e bloqueio de loops sem saída. As figuras 4/13 são painel técnico, não um editor de URA. O catálogo visual ivrBuilder não constitui persistência nem simulação.

Existem Unit, Queue, RoutingRule e IvrEvent, mas não há entidade nativa de rascunho/versionamento de fluxo. RoutingRule e IvrEvent não devem ser usados como depósito de JSON de outro domínio. A API/configuração do fornecedor não define publicação ou formato de fluxo. Não declarar um esquema interno como contrato PABX.

## Proposta aditiva

- Reutilizar Current.account, ModulePolicy.configure?, AccessScope/OrganizationalScope e AuthorityTransaction; nenhum novo papel ou grant automático. Unidade do rascunho imutável e pertencente ao escopo atual. Cada referência a fila é revalidada dentro do escopo na gravação e simulação.
- Acrescentar rascunhos locais e revisões imutáveis em tabelas próprias, sem outro cadastro de usuários/equipes/filas. Conta e unidade protegidas por FKs compostas; não alterar migrations históricas. Antes de qualquer nova migration, auditar colisões e ampliar somente a lista exata de hashes revisados do gate.
- Contrato JSON interno explícito v1 para menus DTMF, encaminhamento lógico a fila e término. Nenhum destino HTTP, código executável ou comando externo. Tempos/tentativas operacionais devem ser preenchidos explicitamente nos exemplos sintéticos; não presumir limites ou compatibilidade do fornecedor.
- Validar formato, IDs únicos, destinos existentes, opções DTMF exclusivas e caminhos sem saída. Simulação determinística e limitada retorna apenas percurso local/destino lógico; nunca uma chamada, ACK ou estado aplicado.
- Salvamento com revisão esperada, transação e idempotência. Rejeição não substitui a versão anterior; conflitos preservam o rascunho no editor. Histórico permanece imutável; arquivamento local não exclui revisões.
- Reutilizar a proteção append-only existente e o dumper PostgreSQL em lib/jrc_postgres_schema_dumper.rb, que já preserva funções/triggers/checks. Provar imutabilidade SQL, recarga do schema e ciclo de conta; não copiar o schema inteiro com divergências históricas.
- Reutilizar diálogos, listas, paginação, campos e navegação do Control Desk. A listagem externa continua separada de rascunhos locais. Áudio, calendário, DAC e publicação não serão apresentados como suportados antes dos contratos correspondentes.

## Aceite antes de considerar implementado

Rails/PostgreSQL reais em banco descartável: criação/edição/histórico, JSON inválido, ciclos, fila estrangeira/inativa, conta/unidade negadas, permissão revogada, concorrência e idempotência, FKs e exclusão de conta. Vue e Chrome: criar/importar/revisar/simular/exportar/recarregar, erro e conflito, desktop/celular claro/escuro, sem chamadas externas. Preservar integralmente os 96 cenários atuais e todos os gates.

## Limite externo

Publicação, homologação de voz/codec, aplicação/rollback PABX e aprovação de uma versão executável continuam bloqueados até contrato real. Uma simulação local aprovada não libera produção nem substitui o fornecedor.

## Primeiro subincremento preparado

IvrGraphSchema usa o JSONSchemer 0.2.24 já fixado no projeto. IvrGraph/Paths verificam identidade atual, elegibilidade, escopo, filas ativas da mesma unidade, IDs e DTMF exclusivos e saída alcançável em todos os nós. IvrSimulator reautoriza a cada uso, não guarda dígitos na trilha e não cria CallSession, Command ou EventInbox. Os limites de 128 nós/opções DTMF de até doze teclas, 1 MiB de definição e 256 passos/128 dígitos são proteções computacionais locais, não capacidades do PABX. A versão local inicial aceita destinos de fila na mesma unidade; expansão de roteamento entre unidades permanece requisito futuro, sem concessão implícita de escopo.

Estão preparados testes Rails com banco nativo para JSON inválido, versão estrita, caracteres de controle, ciclos, opções, referências, conta/unidade, reutilização após revogação e ausência de operações externas. Persistência de rascunhos/revisões, API, importação/exportação e interface ainda não foram implementadas; o núcleo não é anunciado como funcionalidade já disponível ao operador. Nenhuma migration nova foi criada nesta fase.
