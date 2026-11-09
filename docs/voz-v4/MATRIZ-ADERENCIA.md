# Matriz de aderência — Voz V4

**Legenda:** IMPLEMENTADO = código presente; TESTADO_LOCAL = regressão sintética executada; CI_APROVADO = somente no SHA/run explicitado em TESTES-E-EVIDENCIAS; PARCIAL = falta parte do requisito; PENDENTE = aceite não executado. Nenhuma linha abaixo significa IMPLANTADO ou HOMOLOGADO_COM_PABX.

## Documento Word — seção 11 (12 critérios)

| ID | Critério | Estado e evidência |
|---|---|---|
| D11.01 | Voz seleciona cliente e dados da ligação | IMPLEMENTADO/TESTADO_LOCAL: CallWorkspace + CustomerContext; vínculo real SIP/PABX pendente |
| D11.02 | Trocar WhatsApp/e-mail sem perder chamada | TESTADO_LOCAL: E2E WhatsApp B/ligação A; e-mail tem regressão de composição, não ensaio físico |
| D11.03 | Barra global acessível durante ligação | TESTADO_LOCAL: GlobalVoiceBar fora RouterView, E2E responsivo |
| D11.04 | Lista Voz compacta sem supervisão | IMPLEMENTADO: InboxChannelGroups preserva item de atendimento, sem painel gerencial |
| D11.05 | Cinco abas de Voz | TESTADO_LOCAL: HoyaInboxWorkspace.spec + E2E |
| D11.06 | Atribuição, Adiar, Finalizar no cabeçalho | PARCIAL: Finalizar separado e ACW; atribuição/adiamento Voz ainda requerem comandos/contrato autorizados |
| D11.07 | Encerrar telefonia não encerra atendimento | TESTADO_LOCAL: endCall SIP independente; Qualification mantém fluxo |
| D11.08 | Pós-atendimento antes de finalizar | TESTADO_LOCAL e Rails: useAttendanceClosing/QualificationManager |
| D11.09 | Disponibilidade/pausas no mesmo controle | IMPLEMENTADO: VoicePresenceControl e transação AgentStateManager/AccountUser; PABX não confirmado |
| D11.10 | Alertas de restrições contextuais | PARCIAL: contact.blocked; não há projeção completa financeira/jurídica de serviço |
| D11.11 | Cliente 360° lateral sincronizado | TESTADO_LOCAL: seleção scoped e resposta tardia; E2E A/B |
| D11.12 | Mesmo workspace, sem call center paralelo | IMPLEMENTADO: Dashboard/Hoya existentes, mesma navegação |

## Documento Word — seção 17 (10 critérios)

| ID | Critério | Estado e evidência |
|---|---|---|
| D17.01 | Popup não inicia ligação ao abrir | TESTADO_LOCAL: OutboundVoiceDialog.spec/E2E |
| D17.02 | Sem chamada, superfícies coerentes | TESTADO_LOCAL: idle sem timer/controles; registro histórico não vira chamada ativa |
| D17.03 | Contato, telefone, fila/ramal, motivo, notas | PARCIAL: pesquisa por telefone/contato único, ramal próprio readonly, motivo obrigatório; busca textual/seleção de outras rotas autorizadas pendentes |
| D17.04 | Pré-preenchimento vindo do contato | PARCIAL: openEmbeddedSoftphone pré-preenche telefone; contexto completo depende da identidade autorizada |
| D17.05 | Ligar apresenta Chamando | TESTADO_LOCAL: sem connected otimista; falha preserva popup |
| D17.06 | Cronômetro após conexão real | IMPLEMENTADO/TESTADO_LOCAL: SIP established/answered_at; ensaio físico pendente |
| D17.07 | Conexão real habilita barra/controles | IMPLEMENTADO; transporte/áudio real PENDENTE |
| D17.08 | Centro abre cliente efetivamente chamado | PARCIAL: resolve registro autorizado exato e permite Abrir ligação; correlação externa/autoseleção sem roubar contexto requer homologação |
| D17.09 | Falha/cancelamento sem chamada fantasma | TESTADO_LOCAL: estados SIP e popup; timeouts reais PENDENTES |
| D17.10 | Encerrar conectada leva ao ACW | TESTADO_LOCAL/Rails; ciclo real completo PENDENTE |

## Documento Word — seção 20 (11 critérios)

| ID | Critério | Estado e evidência |
|---|---|---|
| D20.01 | Controles distinguíveis | TESTADO_LOCAL: capturas e utilitários Tailwind no painel de telefonia |
| D20.02 | Mudo/espera persistentes | TESTADO_LOCAL: aria-pressed vinculado ao estado SIP confirmado, sem falso sucesso |
| D20.03 | Feedback imediato de pressão | IMPLEMENTADO: active translate/shadow, 100–150 ms |
| D20.04 | Sem animação lenta decorativa | IMPLEMENTADO: transições limitadas; motion-reduce |
| D20.05 | Desligar destacado | TESTADO_LOCAL: botão vermelho global, guarda própria mesmo com hold pendente |
| D20.06 | DTMF 3x4 com pressão | TESTADO_LOCAL: 12 teclas/E2E, teclado físico e foco |
| D20.07 | Tom corresponde à tecla real | PARCIAL: pressKey recebe tecla correta nos testes; tom/recepção PABX não homologados |
| D20.08 | Estados refletidos pela telefonia | IMPLEMENTADO/TESTADO_LOCAL; todos os eventos externos ainda PENDENTES de prova física |
| D20.09 | Atalhos ignoram digitação | TESTADO_LOCAL: textarea/input/contenteditable, modifiers, repeat, Esc sem hangup |
| D20.10 | Legibilidade, teclado, além de cor | PARCIAL: focus/aria/texto/pressões responsivas; zoom 200%/leitor de tela não homologados |
| D20.11 | Visual tátil somente na telefonia | IMPLEMENTADO: classes locais nos controles; módulos preservados |

## Prompt de engenharia — V01 a V30

| ID | Resultado verificável | Estado |
|---|---|---|
| V01 | GlobalVoiceBar idle sem tempo ou controles falsos | TESTADO_LOCAL |
| V02 | CustomerContext por vínculo/telefone único; resumo e lateral | TESTADO_LOCAL/Rails; inbound físico PENDENTE |
| V03 | Desconhecido mantém registro/notas, sem contato fictício | TESTADO_LOCAL |
| V04 | Ambiguidade explícita, sem escolher primeiro | TESTADO_LOCAL/Rails |
| V05 | Ramal/URI/telefone: validação de formato e escopo | TESTADO_LOCAL/Rails |
| V06 | Consulta idempotente por provider/ID; browser não cria sessão | PARCIAL: correspondência com PABX real não comprovada |
| V07 | Chamada A/WhatsApp B com retorno autorizado | TESTADO_LOCAL/E2E |
| V08 | Controles fora RouterView ao trocar abas | IMPLEMENTADO/TESTADO_LOCAL; fluxo físico multiaba central PENDENTE |
| V09 | Popup preserva seleção/rascunho; busy não é dismissible | TESTADO_LOCAL/E2E e regressão da revisão |
| V10 | Chamando sem cronômetro conectado | TESTADO_LOCAL/E2E |
| V11 | Estados SIP de erro/cancelamento, sem rediscagem cega | TESTADO_LOCAL; operadora/PABX PENDENTE |
| V12 | Guards de pending/ownership e idempotência de operações existentes | PARCIAL: ACK perdido/resultado incerto no PABX requer ensaio real |
| V13 | Mute chama serviço existente e mostra estado confirmado | TESTADO_LOCAL; microfone/áudio real PENDENTE |
| V14 | Hold pendente/falha não promove sucesso, hangup independente | TESTADO_LOCAL; hold real PENDENTE |
| V15 | Transferência existente com modo/capacidade; conferência explicitamente indisponível | PARCIAL; conferência PENDENTE de implementação/contrato |
| V16 | DTMF chama pressKey com a tecla, sem repetição automática | TESTADO_LOCAL; receptor real PENDENTE |
| V17 | Fim SIP e registro/ACW separados | TESTADO_LOCAL/Rails; evento remoto real PENDENTE |
| V18 | Qualification exige campos/estado/versão e persiste | TESTADO_LOCAL/Rails |
| V19 | Salvar/reler/revisões/cursor/409/rollback e rede | TESTADO_LOCAL/Rails; sem histórico retroativo inventado |
| V20 | Geração e identidades descartam respostas atrasadas/outro tenant | TESTADO_LOCAL/Rails |
| V21 | Pausa altera elegibilidade nativa sem desligar SIP; ACW mantém bloqueio | TESTADO_LOCAL/Rails; presença no PABX não comprovada |
| V22 | Timer singleton, duração a partir de answered_at, remount preserva | TESTADO_LOCAL |
| V23 | Máquina SIP existente e fim terminal de polling | PARCIAL: reconnect e eventos antigos reais PENDENTES |
| V24 | Ownership existente e bloqueio de segunda chamada/Account diferente | PARCIAL: duas abas reais no PABX PENDENTES |
| V25 | API direta, Account, assignment e operate? negam acesso | TESTADO_LOCAL/Rails; auditoria completa de comandos físicos PENDENTE |
| V26 | Erro/desconhecido de cliente/gravação explícitos | PARCIAL: feed autoritativo de restrições/gravação PENDENTE |
| V27 | Digitação/modifiers/repeat/Esc e foco não disparam telefone | TESTADO_LOCAL |
| V28 | Seis resoluções (320/390/768/1366/1440/1920) e capturas sintéticas | PARCIAL: zoom 200%, leitor de tela e telefonia mobile real não homologados |
| V29 | Falha de CRM/cliente mantém CallSession e notas autorizadas | TESTADO_LOCAL |
| V30 | Build/gates existentes e regressão WhatsApp/SIP/contexto | PARCIAL: ensaio operacional completo WhatsApp/e-mail/Broker não realizado nesta entrega |

## Gates de publicação

Não há atalho entre IMPLEMENTADO → TESTADO_LOCAL → CI_APROVADO → IMAGEM_PUBLICADA → IMPLANTADO → HOMOLOGADO_COM_PABX. Conferir os registros de SHA/run/digest em RELEASE.json. Produção e sessões foram preservadas. A matriz possui pendências internas e externas explícitas; a candidata não é declarada Voz V4 100% homologada.
