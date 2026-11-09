# Voz V4 — fontes, identidades e limites

Data: 09/11/2026. Base preservada: `0163e1ee324e0f0de46ed6dc0b869afb3dbc9895`. Branch: `codex/voz-v4-20261109`.

| Dado/ação | Fonte efetiva | Regra |
|---|---|---|
| Registro, chamada e áudio | `useSipWebphone` → singleton `SipClient`/SIP.js existente | O shell não cria outro socket, peer connection ou elemento de áudio |
| Credencial/ramal de saída | `SipCredentialsAPI.getMine`, autorização existente | Nenhum caller ID livre ou ramal do mockup fixado no produto |
| Identidade local | SIP Call-ID (`session.request.callId`, fallback `session.id`) | Não é identidade de cliente nem prova de CallSession persistida |
| Identidade persistida | `CallSession` por Account + provider + external_session_id exatos | Browser somente consulta registros autorizados; não inventa sessão ou evento do PABX |
| Contato/empresa | Contato vinculado da mesma Account; alternativamente telefone externo exato e único | Ramal e SIP URI não viram telefone de cliente; ambiguidade não seleciona o primeiro |
| Conversa selecionada | ID próprio do WhatsApp/e-mail/CallSession | Seleção B nunca substitui o destinatário dos controles da chamada A |
| Fila/agente | `current_queue` / `CallLeg.account_user` persistidos | Ausência fica indisponível; não inferir fila pelo nome do ramal |
| Cronômetro | Evento SIP conectado / `answered_at` para registro persistido | Tempo de tentativa não é tempo de conversação |
| Observações | PATCH existente `/api/v1/accounts/:account_id/jrc_contact_center/call_sessions/:id/observations` | `operate?`, escopo da chamada, texto até 1000 e lock_version obrigatório; conflito 409 |
| Revisões | GET no mesmo caminho, `limit` 1–100, cursor `before_id` | Histórico por Account/chamada, paginação decrescente; nenhuma rota de editar/excluir revisão |
| Presença | AgentStateManager + AccountUser.availability na mesma transação | Pausa local altera elegibilidade nativa; não é confirmação de presença no PABX |
| ACW | QualificationManager / regras de tabulação existentes | Encerrar ligação não finaliza atendimento; pendência impede elegibilidade indevida |
| Gravação | Sem projeção autoritativa de gravação em tempo real nesta candidata | Mostrar “Sem confirmação de gravação”; não afirmar “Gravando” |
| Bloqueios | `contact.blocked` autorizado | Não equivaler cadastro bloqueado a diagnóstico financeiro/jurídico de um serviço |

## Contrato ainda necessário com a telefonia

`JrcPabxAdapter` mantém `external_api: pending_contract` e `event_schema: proposed`. Deve-se comprovar que o identificador entregue pelo provedor corresponde ao SIP Call-ID consultado. Sem essa prova, o estado correto é “Aguardando identificação do atendimento no servidor”. O browser não cria CallSession para disfarçar a lacuna.

Hold e transferência usam o serviço SIP já existente. Conferência permanece desabilitada com motivo explícito. Homologar comandos, destinos autorizados, pernas e gravação com o contrato real do PABX; um mock de sucesso não confirma telefonia.

## Persistência e compatibilidade

Migration aditiva `20261109150000_create_jrc_contact_center_call_observations.rb`: tabela de revisões, FK composta Account/chamada, FK de autor com nullify na exclusão de usuário, índices de paginação/unicidade e limite de texto no PostgreSQL. A nota atual continua no metadata para compatibilidade com binários anteriores.

Writer grava nota e revisão sob o mesmo lock/transação. Repetição sem mudança não cria revisão nem incrementa versão. Uma falha ao gravar revisão desfaz também a nota. Revisões são somente leitura na aplicação; isso não equivale a armazenamento imutável contra um administrador do banco. Não se reconstrói histórico anterior à implantação nem se inventa autoria antiga.

Rollback de aplicação pode conservar a tabela aditiva; binário anterior continua lendo a nota atual. Escritas pelo binário antigo não produzem revisões: registrar essa limitação se houver rollback. Down/up da migration é ensaiado exclusivamente no banco descartável da CI, antes dos testes. Nenhuma migration foi aplicada no servidor neste trabalho.

## Isolamento e privacidade

Notas e contexto sensível exigem permissão operacional. Projeção somente visual não inclui `attendance_observations`. Histórico retorna somente revisão, versão, autor técnico e data; não retorna credenciais, gravações ou URLs assinadas. Rascunhos ficam em memória, particionados por Account/usuário/atendimento ou sessão SIP; logout/troca de conta limpam a memória. Recarregar totalmente o navegador perde rascunhos não salvos — a interface não deve chamá-los de persistidos.
