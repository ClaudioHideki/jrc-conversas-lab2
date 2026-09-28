# Integração Softphone — preparação da lab.3

Estado atual em 25/09/2026: as correções abaixo foram incorporadas ao candidato LAB3 universal, junto ao provisionamento descrito em `SERVER-PROVISIONING.md`. Foram aprovados 128 testes; EXE e imagem lab.3 foram gerados e validados localmente, sem publicação/deploy. As contagens e pendências do registro de 24/09 abaixo representam aquela etapa anterior.

Data: 24/09/2026. Branch: `codex/softphone-desktop-windows`. Base: `caded81ab541db77c576d08da6dbdf3dfe231bfc`.

Checkpoint preservado: `v4.16.2-jrc-softphone-desktop-lab.2`. Próxima tag proposta: `v4.16.2-jrc-softphone-desktop-lab.3`. Nesta etapa somente fontes/testes/documentação foram alterados; nenhum commit, build de EXE/imagem, push, Release ou deploy foi realizado. Compose, Dokploy, banco, schema e migrations não foram alterados.

## Diagnóstico comprovado

1. A instalação identificada em execução usa `JRC Softphone Validation/resources/app.asar`, sob `AppData/Local/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Local`. Seu `src/policy.cjs` não inclui `extension` na lista exata de campos aceitos. Executar esse validador isoladamente sobre um estado da lab.2 retorna `false`; remover apenas `extension` retorna `true`. O validador da árvore atual aceita o estado completo. O main/floating dessa instalação também são anteriores aos fontes atuais. SHA-256 do policy instalado: `f174ffdbf473feaa409eac179eb8dea0e2f65cebfeeea6b24ee4340a7e668a2c`.
2. O caminho de notificação criava artificialmente um estado de chamada recebida. Assim, a janela antiga podia aparecer com o chamador, mas rejeitava os estados reais posteriores: registro, atendimento e término. Isso explica a janela presa em incoming mesmo com SIP/áudio funcionais. O preload antigo já expõe os comandos; não há evidência suficiente para afirmar que todo clique deixava de chegar ao SipClient. Não foi atribuída a falha à imagem do LAB sem evidência.
3. Na árvore atual, `showFloatingWindow(state)` era usado diretamente como callback de menu/notificação. Electron entrega um MenuItem/Event nessa posição, sobrescrevendo o snapshot com um objeto que não é estado SIP. Removido esse parâmetro: somente o canal de estado validado atualiza o snapshot.
4. A janela abria automaticamente apenas por incoming. Acrescentada abertura no primeiro registro bem-sucedido por sessão autenticada; logout libera o gatilho para o próximo login. Atualizações normais não reabrem uma janela que o usuário ocultou.
5. O watch do bridge ficava preso ao primeiro escopo Vue consumidor. Desmontar esse escopo encerrava o watch, enquanto o flag de instalação permanecia ativo. O watch agora pertence à sessão singleton, com cleanup no shutdown e reinstalação no login.
6. Digitação local não atualizava o destino Web; usar o teclado podia sobrescrever o valor digitado. Adicionado comando restrito `setDestination` no bridge existente. O listener da janela também solicita o snapshot atual ao ficar pronto, evitando depender de um único evento inicial.

## Implementação e limites

- Main Electron continua carregando o JRC; fechar/minimizar preserva seu renderer.
- Janela flutuante continua sendo HTML local sem SIP.js, credenciais, mídia ou conexão de rede. Seus comandos são validados por payload, webContents e mainFrame antes do encaminhamento ao renderer JRC.
- `useSipWebphone.js` mantém seu único `const client = new SipClient(...)`. `SipClient.js` e `SipRegisterer.js` não foram alterados. Os únicos construtores de UserAgent/Registerer continuam nesse SipClient.
- Estado flutuante: ramal, registro, destino, chamada, duração, mute/hold, transferência e erro sanitizado. Senha/username SIP não são enviados nos snapshots.
- Discagem, answer/reject/BYE, mute local, hold/resume SIP e DTMF continuam utilizando os mesmos métodos do Webphone. Transferências preservam `*3 + destino + #` e `*4 + destino + #`; sem códigos adicionais de conclusão/cancelamento e sem música local de espera.
- Fechar a janela flutuante apenas oculta. Incoming restaura/foca. Fim de chamada retorna à tela ociosa. Sair solicita shutdown/unregister e aguarda confirmação, mantendo o timeout de três segundos já existente.
- Download Web no header via `JRC_SOFTPHONE_DOWNLOAD_URL`, vazio por padrão. Aceita URL HTTPS absoluta sem userinfo; oculto sem URL válida e no Desktop já instalado. Não há hospedagem fictícia nem binário publicado.

## Validação automatizada

Comandos na raiz do worktree:

```powershell
node desktop/test/desktop.test.cjs
$env:TZ='UTC'
node node_modules/vitest/vitest.mjs run --config desktop/test/webphone.vitest.config.mjs --no-cache --no-coverage
git diff --check
```

O teste integrado usa UI/preload/main/policy/composable/SipClient/SipRegisterer reais e substitui apenas Electron nativo e a fronteira SIP.js/rede/mídia. Conta instâncias e registros. Cobre registro antes de qualquer chamada, tray com argumentos nativos, hide, discagem, incoming, answer, reject, hangup, mute/unmute, hold/resume, DTMF 0–9/*/#, ambas as transferências, duração, sincronização, troca de view, logout/relogin, shutdown e rejeição de comandos não autorizados. Testes Web existentes e condicionamento do download também são executados.

O sandbox bloqueou inicialmente o subprocesso esbuild (`spawn EPERM`); os testes foram executados com a permissão necessária para iniciar esse processo local, sem instalar dependências. O teste de abertura no primeiro registro falhou antes da correção, confirmando o defeito.

Resultado final: **102 testes aprovados** — 16 Desktop/Node e 86 Vitest em 12 arquivos (67 Webphone existentes, 10 integração Desktop/Web e 9 download). ESLint nos 12 arquivos JS/Vue/configuração alterados passou com `--max-warnings 0`. `git diff --check` passou. Os testes não executam o instalador ou o aplicativo instalado; o layout Rails de configuração recebeu revisão estática, sem inicializar Rails/banco.

## Arquivos alterados

| Área | Arquivos |
| --- | --- |
| Janela/IPC | `desktop/src/main.cjs`, `desktop/src/preload.cjs`, `desktop/src/policy.cjs`, `desktop/floating/app.js`, `desktop/floating/index.html` |
| Sessão Web compartilhada | `app/javascript/dashboard/routes/dashboard/webphone/useSipWebphone.js` |
| Download no header | `app/javascript/dashboard/components-next/layout/JrcTopBar.vue`, `SoftphoneDownload.vue` (novo, mesmo diretório), `app/views/layouts/vueapp.html.erb`, `.env.example` |
| Texto solicitado | `app/javascript/dashboard/i18n/locale/en/settings.json`, `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` (somente a nova ação) |
| Testes/configuração | `desktop/test/desktop.test.cjs`, `desktop/test/webphone.vitest.config.mjs`, `desktop/test/electronHarness.cjs` (novo, extraído do teste existente), `desktop/test/floating.integration.spec.js` (novo), `app/javascript/dashboard/components-next/layout/SoftphoneDownload.spec.js` (novo) |
| Documentação | `desktop/README.md`, `desktop/LAB3-VALIDATION.md` (novo) |

Estado Git ao concluir: 14 arquivos rastreados modificados e 5 novos, todos dentro do escopo acima; sem staging/commit. HEAD continua `caded81ab541db77c576d08da6dbdf3dfe231bfc`. Artefatos, node_modules, instaladores e caches não foram adicionados. `git diff --stat` considera apenas os arquivos rastreados; arquivos novos constam no `git status`.

## Validação posterior obrigatória

É necessário gerar e instalar futuramente um EXE compatível, além de publicar o frontend corrigido, mediante autorização. Um deploy somente Web não atualiza os arquivos dentro do ASAR da instalação antiga.

Homologar em Windows/PABX: login → REGISTER → janela ociosa; ambas as janelas ocultas; incoming/ringtone/foco; discagem, áudio bidirecional e todos os controles; DTMF reconhecido pelo PABX; transferências *3/*4; hold/resume e música remota; fechar/reabrir; logout e saída/unregister. Testes simulados não comprovam transporte real, política de foco do Windows ou RTP/áudio.

A garantia de sessão única refere-se às duas interfaces dentro do mesmo Desktop. Um navegador independente com o mesmo ramal ainda pode registrar separadamente, conforme a política do PABX já documentada no README. A arquitetura de coexistência entre navegador e Desktop não foi alterada nesta correção.
