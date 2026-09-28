# CP6-D01 - APROVADA: inicializacao humana e autoridade estrutural

Registro: 28/09/2026. Fonte: aprovacao explicita do responsavel pelo JRC nesta conversa.
Continuidade: candidato CP6 75bf3a187e5fd98430df3148664f136177a6bf58ee18140a4511f0a1cc94e3fe.
A decisao anterior e suas alternativas permanecem como historico no documento CP6_DECISOES_PENDENTES.md.

## Regra aprovada
Funcionario JRC autorizado -> cria/configura operadora -> cria unidade -> concede primeiro
UnitMembership a um usuario cliente expressamente selecionado -> auditoria.
Depois: administrador cliente administra estrutura somente com capacidades explicitamente
concedidas. Autoridade estrutural NAO equivale a acesso operacional aos chamados.
Nao ha concessao automatica, unidade default, seed, job ou novo RBAC/autenticacao.
SD-D01..05, CP2-D01/D02 e CP4-D01 permanecem vigentes. Nenhum outro checkpoint autorizado.

## Aplicacao tecnica desta rodada
- Inicializador: sessao nativa SuperAdmin MAIS designacao nominativa protegida na configuracao
  do servidor (JRC_SERVICE_DESK_INITIALIZER_USER_IDS). Lista ausente/invalida = negar.
  Tipo de usuario, e-mail, dominio ou ser admin de uma Account nao bastam. Nao se cria/promove
  um SuperAdmin automaticamente. O responsavel pela instalacao confirma o funcionario antes
  de configurar IDs exatos; nenhum ID vem preenchido no pacote.
- Formulario manual no Super Admin da Account. POST explicito, CSRF nativo, confirmacao e
  referencia de autorizacao obrigatorias. Uma transacao cria a operadora/unidade/membership;
  nao cria AccountUser para o funcionario, nao o escolhe como destinatario e nao altera roles,
  permissoes, flags ou configuracao SLA. Recibo relido em GET apos redirecionamento.
- O destinatario e um AccountUser cliente ja existente e confirmado da mesma Account. O
  proprio ator, usuarios SuperAdmin ou designados inicializadores nao podem receber o grant
  por este fluxo. O grant nao cria capacidades: somente escopo.
- Inicializacao e destinada a estrutura SD vazia. Reexecucao idempotente nao duplica registros.
  Estrutura parcial/preexistente nao e mesclada nem apagada silenciosamente.
- Delegacao ao cliente: quatro capacidades novas e explicitas em CustomRole.permissions
  nativo, sem defaults em agent/administrator e sem nova tabela. Exigem AccountUser
  administrator nativo, role nativo valido da Account e configuracao inicial ja existente.
  O escopo e estrutural da Account, nao leitura dos chamados. Nao deriva de settings_view.
- Gestao estrutural permite operadoras, unidades e grants de usuarios clientes, sem exclusao
  fisica, mudanca de proprietario ou autoconcessao. Conceder/reativar grant a si proprio e
  negado; revogar o proprio grant e permitido com capacidade explicita.
- Auditoria Audited::Audit nativa, atomica com a escrita, autor/Account/unidade/quando/referencia
  e antes/depois. Nao registra uma ficticia membership do funcionario. Sem SQL privilegiado
  append-only garantido; a protecao e do dominio, como no CP6 anterior.
- Interfaces estruturais nao consultam Ticket, mensagens, KPIs ou SLA para exibir registros.
  A verificacao de ausencia de tickets na inicializacao e somente guarda interna.

## Validacao
PENDENTE - validacao nativa em Docker/servidor. A aprovacao da decisao nao aprova testes.
Nenhuma conta real, funcionario, papel ou grant foi configurado por esta entrega.
