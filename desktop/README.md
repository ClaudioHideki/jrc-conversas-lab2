# JRC Softphone Desktop — rodada de correção

Cliente Electron do softphone existente. Reutiliza o frontend do JRC, a API de credenciais e o SIP.js 0.21.2; não cria outro backend, registro de histórico ou protocolo de telefonia. A interface é carregada do servidor configurado. O instalador sozinho não disponibiliza as alterações Web desta worktree no servidor.

## Estado do candidato LAB3 universal

Em 25/09/2026, o candidato completo com bridge, controles, download Web e provisionamento universal passou em **128 testes** (16 Desktop, 24 provisionamento, 88 Webphone/bridge/download), ESLint e `git diff --check`. O instalador NSIS e a imagem Docker local `v4.16.2-jrc-softphone-desktop-lab.3` foram gerados e validados; a lab.2 foi preservada. Não houve publicação ou deploy. Binários, caches e relatórios temporários não fazem parte dos fontes versionados.

O ASAR extraído do instalador contém os fontes atuais, sem URL fixa de cliente ou credenciais. Homologação nativa Windows/PABX continua pendente. Veja `SERVER-PROVISIONING.md` para o funcionamento e `LAB3-VALIDATION.md` para o diagnóstico da integração. O histórico abaixo registra as primeiras tentativas, anteriores ao candidato atual.

## Histórico da preparação inicial

Na preparação local de 24/09/2026, as dependências Desktop foram instaladas com pnpm **10.2.0**, versão fixada também pelo projeto JRC. O lockfile `desktop/pnpm-lock.yaml` foi criado e preservado. Electron **44.4.5** foi confirmado no pacote e no arquivo de versão do runtime baixado; electron-builder **26.0.12** foi confirmado no pacote e na execução do build. A série Electron está suportada conforme https://releases.electronjs.org/releases/stable e https://releases.electronjs.org/schedule. Nenhuma dependência geral do JRC foi atualizada.

Os 14 testes Desktop simulados, 67 testes Web/softphone, lint e `git diff --check` passaram. O build NSIS com `--publish never` foi tentado, mas falhou por espaço insuficiente em `C:` durante o download adicional do Electron. Não foram gerados ASAR ou instalador, nem feitos release, imagem, push ou deploy. Nenhum executável do aplicativo/instalador foi aberto. A integração nativa continua pendente de homologação.

O pnpm global 11.25.0 bloqueou a dependência Git transitiva de `@electron/rebuild`; use o pnpm 10.2.0 fixado neste pacote (`corepack pnpm` ou `npx --yes pnpm@10.2.0`). A instalação informou dependências transitivas depreciadas e ignorou o script de `electron-winstaller`, relacionado a Squirrel; o alvo utilizado aqui é NSIS.

## Configuração e autenticação

Sem servidor configurado, o Desktop abre uma página **local** com **Endereço do JRC Conversas** e **Conectar**. Não há servidor de LAB/cliente embutido ou fallback. Com origem salva válida, carrega esse JRC; após login/registro SIP, abre automaticamente a janela Softphone, preservando a LAB3.

O formulário exige HTTPS. Normaliza caixa/porta padrão e descarta caminho, query e fragmento **antes de carregar e salvar**. Recusa usuário/senha na URL, HTTP, outros esquemas e URLs inválidas. A exceção de desenvolvimento existente continua exclusiva do aplicativo não empacotado com `--development` e host loopback; HTTP nunca é salvo pelo provisionamento.

Somente `{ "origin": "https://servidor-configurado" }` é salvo em `softphone-server.json`. Antes de adquirir o lock de instância única, o código fixa `userData` em `path.join(app.getPath('appData'), 'JRC Softphone')`: normalmente `%APPDATA%\JRC Softphone` no Windows. A gravação usa substituição atômica por arquivo temporário no mesmo diretório. Nenhum caminho de usuário é codificado. O antigo diretório `jrc-softphone-desktop` não é lido, mesclado nem apagado; se só ele tiver configuração, informe a origem uma vez no formulário.

A origem canônica salva prevalece sobre argumentos/variáveis antigos. Para compatibilidade, `--server-url=` e `JRC_SOFTPHONE_URL` ainda podem provisionar uma instalação sem arquivo salvo (variável antes do argumento); nenhuma URL é assumida automaticamente. O início com Windows usa o executável **sem URL nos argumentos** e lê a mesma configuração. Entradas antigas de autostart habilitadas são normalizadas para remover essa cópia da origem. Desenvolvimento explícito continua permitindo seu argumento local, sem gravá-lo.

**Configurações / Alterar servidor JRC** na bandeja abre o mesmo formulário. Confirmar uma origem diferente envia o shutdown LAB3 ao renderer atual (hangup/unregister/stop), aguarda o ACK por até três segundos, destrói o renderer antigo e a janela flutuante e limpa conexões, cookies/storage, cache de autenticação HTTP e cache da sessão. Só depois salva/carrega a nova origem. Sem ACK, destruir o renderer garante ausência do antigo UserAgent local; a expiração do Contact remoto em indisponibilidade de rede depende do PABX. Falha de limpeza ou persistência impede carregar o novo ambiente. Credenciais do servidor anterior não são reaproveitadas. Detalhes e testes em `SERVER-PROVISIONING.md`.

O Desktop faz seu próprio login no JRC, pelo fluxo existente. Usa uma **sessão Electron em memória**, sem o prefixo `persist:`. Cookies, tokens e armazenamento Web não são intencionalmente persistidos pelo Desktop. **É necessário autenticar novamente após encerrar/reiniciar o processo**, inclusive no início com Windows. Ocultar/minimizar mantém o processo e a sessão em memória. Não há cofre ou arquivo adicional de credenciais SIP; o Windows/swap e políticas locais ainda fazem parte da validação do ambiente. A autenticação global do JRC não foi modificada.

Após entrada/troca de conta, o widget redireciona uma vez para `ramal_index` usando o roteador Vue, sem recarregar o renderer. No cartão do contato, **Open in JRC Conversas** abre o registro no navegador padrão através de um IPC que recebe apenas IDs. O navegador usa sua própria sessão; nenhum token é transportado no link. A tradução nova está no catálogo `en`, seguindo as regras do repositório.

## Segurança e ciclo de vida

- Instância única adquirida antes de criar janela: a segunda execução encerra e apenas restaura/foca a primeira.
- Origem configurada validada por protocolo, host e porta; navegações/redirects inesperados e subframes são bloqueados. `blob:`, `data:`, `file:` e `javascript:` não são origens navegáveis autorizadas.
- Novas janelas são negadas. Somente links sem query/hash para `/app`, conta, Ramal ou contato na origem configurada podem abrir externamente. Outros destinos e autenticação federada que saia dessa origem permanecem bloqueados; não há allowlist implícita.
- `contextIsolation`, sandbox e `webSecurity` habilitados; Node e webviews desabilitados; DevTools desabilitado no aplicativo empacotado. Isso não é uma barreira contra alguém que já controla o computador/processo.
- Ambos os handlers de permissão permitem somente mídia de áudio da janela/frame principal autorizado. Vídeo, captura de tela e permissões genéricas são negados. Erros de permissão, microfone ausente ou indisponível são apresentados pelo softphone.
- Preload limitado a avisar/limpar chamada e abrir contato. O processo principal valida remetente, frame, origem e payload, define o título, limita tamanho e frequência e rejeita IDs repetidos.
- Fechar e minimizar escondem a mesma janela. `backgroundThrottling: false` e autoplay explícito; o renderer não é destruído. Não há promessa de operação durante suspensão do Windows.
- A bandeja também abre o **controle da chamada**: uma janela local flutuante, sem navegador JRC remoto, SIP.js, `UserAgent`, credenciais ou acesso de rede. Ela só recebe estado validado do renderer principal e envia comandos validados de volta para ele. Há portanto um processo Desktop, um renderer JRC que mantém o único registro SIP e uma segunda interface de controle.
- O primeiro registro SIP bem-sucedido após login abre/foca o controle flutuante antes de qualquer chamada. Ele mostra ramal, status registrado, campo de destino e teclado; permite discar sem restaurar o JRC. Fechar esse controle somente o oculta; **Abrir Softphone** na bandeja o reabre. Chamada recebida também abre/foca o controle, com Atender e Recusar. Durante a chamada, ele mostra duração e oferece mudo, espera, DTMF, transferência e desligar. Após encerrar, volta ao estado ocioso registrado. Ao sair pelo menu, o processo pede shutdown ao renderer principal, aguarda o unregister por até três segundos e só então encerra.
- Bandeja usa `assets/tray.png`, cópia de `public/favicon-96x96.png`, com verificação `isEmpty()`.
- Falha inicial/crash: até cinco novas tentativas em 1, 5, 15, 30 e 60 segundos. Sessenta segundos de carregamento estável restauram o orçamento. Falhas repetidas não causam reload ilimitado; o menu permite tentar novamente. Sair cancela os timers. Destruição efetiva e inesperada da janela encerra o processo, evitando processo órfão sem SIP.
- AppUserModelId coincide com o instalador. A notificação nativa abre/foca o controle flutuante; falha de notificação também o abre. Atender/terminar/recusar, logout, navegação completa e crash limpam o aviso da chamada correspondente.
- Logs não recebem exceções, cabeçalhos SIP ou objetos brutos. Mensagens são sanitizadas. Logs internos de configuração do SIP.js continuam desligados.

## Registro, controles e Web

`connect()` aguarda resposta final ao REGISTER. O observador acompanha também renovações automáticas do SIP.js. Perda involuntária `Registered → Unregistered` agenda reconexão; desligamento/logout bloqueiam tentativas. Rejeições 4xx finais, exceto 408/423/480, bloqueiam retry automático até ação explícita; demais falhas usam backoff de 1/2/5/10/30 segundos. `Retry-After` estabelece um prazo mínimo, inclusive após evento `online`. O watchdog cancela o transporte/REGISTER pendente antes de permitir uma nova tentativa. Respostas de agente antigo são ignoradas.

Hold/resume só altera estado/tracks após aceitação final do re-INVITE; rejeição mantém o estado confirmado. Re-INVITEs e transferências concorrentes são bloqueados. Encerrar cancela a espera da operação.

Associação preservada do código anterior:

- `immediate`: `*3` + destino + `#`;
- `supervised`: `*4` + destino + `#`.

Falha mantém o formulário; sucesso de **envio da sequência** limpa o formulário. Isso não significa confirmação de transferência no PABX. Uma sequência antiga não continua em outra chamada. Nenhum fluxo de concluir/cancelar transferência supervisionada foi inventado: é pendência de protocolo/homologação.

O Web só notifica chamadas novas quando já tem permissão e está em segundo plano. O botão **Enable call notifications** obtém permissão por gesto antecipado do usuário. Receber ligação não pede permissão; resolução tardia de permissão não exibe chamada encerrada. Exceções/rejeições da Notification API ou bridge não interrompem o SIP. O mesmo renderer escolhe um canal de aviso: Web ou Electron.

## Mesmo ramal no Web e no Desktop — bloqueio de homologação

Não foi implementada arbitragem entre clientes. Web Locks não coordenam navegadores com Electron e não protegem o REGISTER. Ambos continuam capazes de registrar o mesmo ramal; a trava Desktop impede somente outra instância do mesmo aplicativo/perfil do Windows.

Até homologar o PABX, utilizar **um cliente SIP ativo por ramal**. Para operar o Desktop, desligar o ramal em todas as abas/perfis Web, mantendo o JRC Web disponível para CRM. Atenção: abrir um contato no navegador também pode inicializar o SIP Web se o ramal não estiver previamente desligado.

O PABX pode manter vários Contacts e tocar em ambos, substituir o registro anterior ou rejeitar o novo. A integração Hodu/CDR no repositório não prova qual política está instalada. Confirmar versão/configuração e observar REGISTER/respostas/Contacts, sem registrar Authorization/cookies/tokens, antes de definir política definitiva.

Homologar em ramal de teste: abrir clientes nas duas ordens, aguardar renovação, receber/atender/recusar, originar chamadas, perder/recuperar rede e verificar CANCEL das demais pernas, estado da UI e CDR. Não alterar produção para executar esses cenários.

## Testes disponíveis agora

Na raiz da worktree, com as dependências Web já existentes:

```powershell
node desktop/test/desktop.test.cjs
node desktop/test/server-settings.test.cjs
$env:TZ='UTC'
node node_modules/vitest/vitest.mjs run --config desktop/test/webphone.vitest.config.mjs --no-cache --no-coverage
```

Os dois primeiros comandos executam testes Node com Electron simulado, sem instalar/iniciar Electron e sem escrever no userData. O comando Vitest mantém os plugins/configuração existentes, restringe o diretório do softphone e usa PostCSS vazio apenas para testes funcionais. Isso contorna a ausência local de `postcss-import`; **não testa CSS/aparência** e não modifica a configuração de produção. `CallHistoryPanel` também permanece coberto por seus testes existentes.

Mocks validam contratos/estados, não áudio, entrega de DTMF/RTP, permissões do Windows, tray, toast ou comportamento do PABX.

Os testes de integração adicionais executam o HTML/JavaScript da janela, preload, handlers/política do processo principal, composable Web e os próprios `SipClient`/`SipRegisterer`. Electron nativo e a camada SIP.js/rede/mídia são simulados. As verificações contam UserAgent/Registerer/REGISTER e comprovam abertura antes da primeira chamada, comandos e retorno de estado; não geram chamadas reais.

## Download pelo JRC Web

`JRC_SOFTPHONE_DOWNLOAD_URL` é uma configuração de runtime do servidor Rails, exposta com escape JSON em `window.chatwootConfig.softphoneDownloadUrl`. Definir futuramente a URL pública HTTPS do instalador validado. Sem URL válida, a ação não aparece. Nenhuma URL de hospedagem foi definida e nenhum binário é incluído no frontend.

No navegador, **Baixar JRC Softphone** aparece junto ao status de disponibilidade, sem substituí-lo. A ação é omitida dentro do aplicativo já instalado, preservando a política restrita de navegação externa do Electron. URLs locais, HTTP e URLs com usuário/senha são rejeitadas. A configuração não cria Release, publica instalador nem habilita auto-update.

As correções posteriores à `lab.2` estão descritas em `LAB3-VALIDATION.md`. Exigem um futuro EXE e frontend compatíveis; atualizar apenas a imagem Web não corrige um Desktop antigo cujo validador rejeita o campo `extension`.

## Reproduzir a preparação e retomar o build

Dentro de `desktop`, usar pnpm 10.2.0 e executar `pnpm install --frozen-lockfile` nas instalações seguintes. O Electron 44 baixa o runtime sob demanda; `node node_modules/electron/install.js` concluiu esse download nesta preparação sem abrir o aplicativo. Liberar espaço suficiente no disco antes de retomar o build. A limpeza de arquivos fora do Desktop não foi realizada.

`pnpm dist:win` usa NSIS com `--publish never`. Artefato de saída: `desktop/dist/JRC-Softphone-Setup.exe`. A configuração inclui `src/**/*.cjs`, `assets/tray.png` e metadados do pacote; testes e configuração do servidor do usuário ficam fora. Após build bem-sucedido, inspecionar o ASAR e calcular tamanho/SHA-256 do instalador. Instalar ou executar o aplicativo continua sendo uma etapa separada, que exige autorização. Não há auto-update, provedor de publicação ou alteração de pipeline nesta entrega. Atualizações manuais devem manter o mesmo appId; a compatibilidade com o frontend servido deve ser validada.

Windows real: instalação, primeiro login, microfone permitido/negado/ausente/ocupado, áudio bidirecional, ringtone, fechar/minimizar/bandeja, chamada oculta, clique no toast, Focus Assist, logon automático, segunda execução, rede, suspensão/retorno, encerramento e limpeza da sessão.

PABX real: registro inicial/renovação/expiração, 401/403/503/Retry-After, queda de WSS, chamadas de entrada/saída, todos os tons DTMF, `*3`/`*4`, protocolo supervisionado, hold/resume aceito/rejeitado, fim de chamada durante operação, coexistência e CDR.
