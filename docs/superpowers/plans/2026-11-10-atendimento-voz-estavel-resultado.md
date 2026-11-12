# Atendimento integrado — resultado do incremento de 10/11/2026

Estado: **candidata local; não liberada para produção**. Não houve push, merge, imagem nova, deploy, migration produtiva, chamada real, disparo, pareamento ou alteração de credenciais neste incremento. Branef, GLPI e GoPure foram preservados.

## Referências e reconciliação

- LAB2: `ClaudioHideki/jrc-conversas-lab2`, base `d8a83b824b11cc68ddbbce7c79681f368051fb70`, branch `codex/atendimento-voz-estavel-20261110`.
- Broker: `ClaudioHideki/BrokerJRCIA`, base `29095bea35702893e1a5b80f5131bdd13b901a7e`, branch `codex/atendimento-compat-evolution-20261110`.
- As duas referências `main` foram consultadas novamente ao final do trabalho e permaneciam nesses SHAs. Não foi aplicada integração cega nem reset. O diretório `tmp/` preexistente do Broker foi preservado.
- O navegador de produção chegou a carregar e-mail RH e quatro conversas da caixa Welton. Essa observação não comprova completude do histórico nem corrige a demora intermitente relatada.

## Código implementado

### Lista conjunta e WhatsApp

`InboxList.vue`: a revalidação periódica deixou de esvaziar imediatamente as permissões de caixas compartilhadas. Somente conversas anteriormente admitidas, com a mesma identidade de conversa, caixa, responsável e time, permanecem visíveis durante a consulta. Novas conversas ou alterações de atribuição aguardam autorização atualizada; erro, revogação e troca de Account fecham o acesso. Isso não amplia permissões de agentes.

`HoyaInboxWorkspace.vue`: sentinela de rolagem no contêiner existente, com o botão de carregar mais preservado. Voz, caixas WhatsApp e e-mail continuam juntos; não foram criadas três abas. Um contador reativo do pedido pai impede a corrida entre a liberação do loading no Vuex e a próxima página. Respostas de gerações antigas não decrementam os pedidos da Account atual.

Os quatro carregamentos iniciais de conversas, escopo compartilhado, chamadas e contexto passaram a ter timeout de 30 segundos. O erro segue para a interface existente de falha/tentar novamente, sem transformar timeout em lista vazia bem-sucedida e sem repetir operações de escrita. Isso limita o spinner indefinido; não demonstra, por si só, a causa da lentidão no servidor.

### Voz no Atendimento

- `GlobalVoiceBar.vue`: barra compacta persistente, preservando a sessão SIP e sua identidade enquanto o agente navega. Exibe a recusa também depois do término da tentativa.
- `InboxVoicePanel.vue`: controles compactos com nomes acessíveis, teclado DTMF e transferência em sobreposição, sem empurrar a área de trabalho. Conferência indisponível foi retirada dessa barra compacta.
- `OutboundVoiceDialog.vue`: discador numérico, correção do número, ramal autorizado somente leitura e detalhes opcionais recolhidos. O motivo não impede mais iniciar a chamada. A ação continua explícita no botão Ligar. Há explicações para sessão já ativa, ramal indisponível, restrição de acesso e tabulação pendente. Guards de Account, registro e exclusão mútua permanecem.
- Traduções novas em português brasileiro e inglês. Nenhuma permissão administrativa foi concedida para contornar o erro de estrutura.

### Diagnóstico SIP

`SipClient.js`: o estado Terminated emitido pelo sip.js podia sobrescrever a recusa específica com uma mensagem genérica. A ordem real da dependência instalada é Terminated antes de onReject. O desfecho passou a ser correlacionado por sessão, com WeakMap, geração e fallback em microtask. CANCEL seguido de 487 não vira falsa recusa; callbacks antigos não interferem na sessão nova; disconnect invalida os callbacks pendentes. Somente o código numérico é exibido, sem cabeçalhos nem credenciais.

Não foi capturada resposta SIP real da tentativa externa do usuário. O código HTTP 403 mostrado nos prints vem de `JrcServiceDesk::StructureController#context`, que autoriza administração de estrutura; ele não é prova de SIP 403 nem da rota do PABX. O erro `configuration_missing` do histórico é uma configuração de CDR independente da discagem. O usuário não possui acesso ao painel do PABX. Rota externa, classe de serviço, tronco e entrada/DID permanecem sem verificação; não foram alterados.

### Tabulação opcional por empresa

`AcwPolicy`: campo aditivo `voice_required`, padrão true para preservar empresas existentes. Clientes antigos que atualizam somente limites preservam a opção salva. Tipos inválidos são rejeitados. O merge ocorre dentro do lock da Account e mantém os demais settings.

`QualificationManager`: modo opcional deixa de criar novas obrigações automáticas; obrigações anteriores não são apagadas. A tabulação iniciada manualmente continua exigindo motivo e resultado. `CallJourney` não deixa o agente preso em chamada quando a tabulação é opcional, nem inventa disponibilidade: aguarda confirmação do provedor como unavailable.

O editor aparece no Atendimento somente com capacidade `configure` autorizada pelo backend. O backend mantém a política de acesso. Não foi criada migration: usa settings JSON existentes. **RSpec Rails ainda precisa validar callbacks, transações e autorização reais.** O fluxo rico de voz continua dependente das capacidades Contact Center existentes; a fachada independente completa e o histórico CDR por cliente não estão concluídos neste incremento.

### Broker / Evolution

`qr-events.ts`: suporte ao envelope `documentWithCaptionMessage` nas duas rotinas existentes de desembrulhamento limitado. Preserva identidade, direção, ordem e descritor de mídia. O formato foi confirmado no código da Evolution pinada. Três regressões verificam entrada, envelope aninhado de saída e a preservação da restrição de mídia histórica.

Não mudou a engine produtiva, sessão, webhook, outbox ou política KEEP. Não foi habilitado histórico de grupos/mídia indiscriminadamente. Histórico completo do celular, mídia histórica e mídia de grupos ao vivo continuam pendências próprias; essa pequena correção não os implementa.

## Testes e evidências

Evidências brutas locais: `.superpowers/sdd/2026-11-10-atendimento-voz-estavel/` no LAB2 e `.superpowers/sdd/atendimento-compat-20261110/` no Broker. Esses diretórios são ignorados pelo Git; o pacote de entrega contém uma seleção sem segredos.

| Verificação | Resultado e limite |
| --- | --- |
| Vitest LAB2 afetado, nove arquivos | 129 testes aprovados, nenhuma falha na execução final registrada no JSON do pacote |
| SIP e discador após revisão | 13 aprovados, nenhuma falha |
| Minitest da política real, sem Rails | 5 testes, 16 assertions, nenhuma falha/erro; não comprova ActiveRecord, PostgreSQL ou callbacks |
| Sintaxe Ruby dos sete arquivos alterados | Aprovada; RSpec de jornada opcional escrito, mas execução Rails permanece bloqueada |
| ESLint do conjunto alterado | 0 erros, 32 warnings; baseline dos mesmos arquivos: 2 erros, 30 warnings. Warnings incluem formatação de tags e chaves i18n dinâmicas; não são apresentados como lint sem avisos |
| E2E notebook + mobile | 8 aprovados com componentes reais compilados e adaptadores sintéticos. Navegação fora do Atendimento, retorno, DTMF, discador e tabulação. Não é homologação SIP ou WhatsApp real |
| Build do laboratório frontend | Aprovado; é build do fixture, não build integral do produto |
| Build integral LAB2 | Não executado até o fim: disco local insuficiente e indisponibilidade do Docker; gate permanece pendente |
| RSpec Rails com PostgreSQL/Redis | Não executado com sucesso; ver bloqueio abaixo |
| RuboCop local | Runner falhou antes de analisar: gem `racc` ausente no GEM_PATH de lint. Não é aprovação |
| Broker regressões de mensagens/provedores | 266 testes aprovados em 15 arquivos após RED de 3 falhas |
| Broker typecheck e build | Aprovados; Vite avisou sobre chunks acima de 500 kB |
| Broker suíte ampla | 4.305 aprovados, 2 testes falhos, 3 pendentes, total 4.310; 3 arquivos com falha, incluindo falha de coleta/artefato. JSON success=false apesar de o processo retornar código 0. Não aprovada |
| Suíte integral LAB2 | Interrompida por limite local de recursos após execução prolongada; sem total confiável, não aprovada |
| CI, imagem e runtime do candidato | Não publicados/não executados neste incremento |

Na suíte ampla do Broker, uma falha registrou ENOSPC em vez do limite esperado de verificação, e duas ocorreram em verificações de artefatos/PDF de auditoria. A seleção por nomes não excluiu o arquivo preexistente `recovery.test.mjs`: ele executou operações de recuperação com fixtures locais sintéticas. Isso contrariou a exclusão pretendida do escopo e não será repetido neste incremento. Não houve uso de banco real, backup de produção, dump real ou restore real. Não foi alterada essa funcionalidade para fazer o teste passar.

Os testes RED/GREEN locais estão discriminados nos logs: estabilidade da lista, corrida da paginação, discador, DTMF, tabulação, timeout e ordem SIP. A revisão independente encontrou duas falhas P2 (paginação e ciclo SIP), corrigidas e exercitadas novamente. A revisão final do delta SIP não encontrou novo P1/P2 demonstrável, usando stubs; não substitui chamada real.

## Bloqueios do ambiente local

O Docker inicialmente permitiu criar recursos descartáveis exclusivos do teste, mas depois passou a devolver HTTP 500. O schema foi carregado apenas em banco de teste. A primeira tentativa RSpec não carregou as gems de teste por BUNDLE_WITHOUT; após corrigir os flags, o novo runner travou na extração de fonte. Nenhuma execução Rails completa foi aprovada.

Recursos exclusivos criados: rede `jrc-atendimento-voz-20261110`; containers `jrc-atendimento-pg-20261110`, `jrc-atendimento-redis-20261110`, `jrc-atendimento-rails-20261110` e `jrc-atendimento-runner-20261110`. Não foi reiniciado o Docker, pois há aplicações locais de outros trabalhos. A remoção desses recursos não foi confirmada e deve ser feita posteriormente somente pelos nomes exatos, preservando os demais containers/volumes. O arquivo temporário local base.tar deste incremento foi removido após validar seu caminho; nenhum código ou dado de cliente foi removido.

O disco C: chegou a aproximadamente 85 MiB livres, recuperando cerca de 198 MiB com a remoção desse único tar temporário. Isso é capacidade da máquina de desenvolvimento, não diagnóstico de espaço do servidor JRC.

A inspeção nativa do navegador foi interrompida pela ferramenta: não conseguiu confirmar a URL corrente no Windows para aplicar suas regras. Não houve acesso alternativo para contornar o bloqueio. O resultado de Computer Use foi encerrado formalmente.

## Pendências e próximos critérios de aceite

1. Recuperar recursos do ambiente de desenvolvimento sem afetar aplicações de outros trabalhos. Executar RSpec completo de voz e autorização com PostgreSQL/Redis; incluir modo opcional, troca de Account e preservação de obrigações antigas.
2. Executar build integral LAB2 e CI no SHA candidato, RuboCop e regressões integrais. A workflow existente foi estendida para a nova branch, a política standalone e os arquivos Ruby modificados; isso é preparação de CI, não CI aprovada.
3. Capturar o código SIP real de uma tentativa explicitamente autorizada depois de instalar o diagnóstico corrigido. Só então correlacionar com administrador do PABX: permissão de saída do ramal, formato esperado do destino, rota/tronco e entrada/DID. Não usar o HTTP 403 de estrutura como substituto dessa evidência.
4. Concluir a configuração/contrato de CDR, identidade de múltiplas pernas e histórico do cliente. Não deduplicar somente por uniqueid nem prometer gravação sem evidência do provedor.
5. Homologar a sessão da Gabriela por meios autorizados; não houve login como ela. Confirmar vínculos por IDs antes de escolher a rota entre Evolution externa e Broker; não desconectar ou migrar por semelhança de nomes.
6. Desenvolver e homologar a captura histórica completa separadamente: chats, contatos, grupos e mídias, identidade, deduplicação, progresso durável, importação silenciosa e custódia privada KEEP. Rolagem do que o JRC já armazenou não equivale a ter importado tudo do celular.
7. Somente após esses gates, revisar publicação das duas candidatas e homologação física. Não gerar uma imagem de produção com o rótulo de 100% funcional a partir destas evidências parciais.

Conclusão: correções concretas de frontend, diagnóstico SIP e contrato aditivo de tabulação foram implementadas e testadas nos níveis descritos. A causa real da discagem externa e a homologação Rails/produção permanecem abertas. O sistema produtivo não recebeu essas alterações neste incremento.
