# Provisionamento universal do Desktop — revisão de 25/09/2026

Escopo: fontes e testes na branch `codex/softphone-desktop-windows`. Após aprovação do provisionamento, o candidato LAB3 universal foi gerado e validado localmente em 25/09/2026. O novo instalador contém este formulário e a imagem local lab.3 contém os fontes atuais. A lab.2 foi preservada. Nenhum artefato foi publicado e nenhum deploy foi realizado.

## Comportamento anterior auditado

- `serverConfig` priorizava variável `JRC_SOFTPHONE_URL`, depois `--server-url=`, depois origem salva. Sem nenhum valor válido, a inicialização exibia erro e encerrava.
- Não havia fallback fixo do LAB no código empacotado. URLs completas de argumentos podiam ser carregadas, embora somente a origem fosse salva.
- O arquivo ficava no `app.getPath('userData')` padrão, sem padronização explícita entre nomes de execução. Foram encontrados arquivos `softphone-server.json` tanto em `JRC Softphone` quanto em `jrc-softphone-desktop` na pasta de dados do usuário. Nenhum deles foi alterado nesta etapa.
- O autostart guardava a origem também nos argumentos. Não havia formulário nem troca controlada de ambiente.

## Fluxos implementados

1. Sem origem canônica/argumento explícito: abrir somente a página local de configuração, com campo **Endereço do JRC Conversas** e **Conectar**. Nenhum renderer remoto/SIP é criado nessa etapa.
2. Ao confirmar: validar HTTPS, remover caminho/query/fragmento, normalizar a origem, salvar e carregar o JRC escolhido. Login e credenciais continuam sendo responsabilidade do JRC. O primeiro registro SIP abre o Softphone sem precisar receber ou originar chamada.
3. Próxima execução: ler a origem salva, ignorando variáveis/argumentos antigos que tentem substituir a configuração. Início com Windows usa a mesma fonte, sem URL no registro de autostart.
4. Troca pela bandeja: aguardar o shutdown do SipClient existente e encerrar o renderer anterior. Limpar a sessão anterior antes de salvar/carregar a nova origem. Não há duas janelas remotas JRC vivas simultaneamente. A tela local de configuração e a janela flutuante não instanciam SIP.
5. Sem ACK em três segundos (servidor na tela de login, frontend sem bridge, travamento ou rede): destruir o renderer anterior e fechar suas conexões antes de prosseguir. Isso impede UserAgent/Registerer anterior vivo no Desktop; não equivale a confirmação remota de unregister no PABX indisponível. A política/tempo de expiração de Contact precisa de homologação real.
6. Falha de limpeza/storage: não carregar nem salvar a origem nova; permitir nova tentativa. Falha de gravação: não carregar um ambiente não persistido. Informar a mesma origem apenas restaura o JRC atual, sem derrubar SIP.

## Configuração única

Diretório definido antes do lock de instância: `path.join(app.getPath('appData'), 'JRC Softphone')`, aplicado por `app.setPath('userData', ...)`.

Windows normalmente resolve para `%APPDATA%\JRC Softphone\softphone-server.json`. O caminho real é resolvido pelo Electron para o usuário/OS atual, inclusive seu ambiente de execução; não há caminho fixo de DEV03.

```json
{"origin":"https://servidor-configurado"}
```

O domínio acima ilustra o formato; não é default do aplicativo. Persistência atômica via `softphone-server.json.tmp` seguida de rename. O arquivo canônico é a única fonte lida nas próximas execuções. A cópia antiga em `jrc-softphone-desktop` permanece intocada e ignorada, sem migração automática de origem potencialmente ambígua.

Não se salvam usuário, senha, query, token, cookie, sessão JRC ou credenciais SIP. Sessão Web permanece em memória, sem `persist:`. A troca limpa storage/cookies, conexões, cache e cache de autenticação HTTP. Configuração local inválida abre o formulário; não há fallback para outro ambiente.

CLI/env continuam aceitos somente como provisionamento explícito na ausência da configuração salva; o modo de desenvolvimento loopback anterior é preservado, sem persistência de HTTP. O formulário e o aplicativo empacotado só aceitam HTTPS.

## Segurança

- As validações de remetente, frame, origem, permissão de áudio e navegação existentes foram preservadas.
- Setup é HTML local, CSP sem rede/subframes, `contextIsolation`/sandbox/webSecurity ativos, Node e webviews desativados, permissões negadas.
- Preload exclusivo de setup expõe somente ler configurações e enviar URL. Os handlers verificam webContents, mainFrame e URL exata do arquivo local. Conteúdo remoto e janela flutuante não podem ler/alterar o servidor por esses canais.
- ACK de shutdown não solicitado não encerra o aplicativo; ACK de troca e ACK de saída têm tratamentos distintos.
- Código de `SipClient`, `SipRegisterer` e bridge Web LAB3 não foi alterado nesta etapa. A troca reutiliza o comando de shutdown existente. O teste integrado verifica hangup, unregister e stop antes da próxima instância de renderer/registro.
- Nenhuma URL LAB/GoPure/cliente foi incorporada aos arquivos destinados ao pacote. O único URL literal no package.json é o localhost do script de desenvolvimento já existente.

## Arquivos desta etapa

- Alterados: `desktop/src/main.cjs`, `desktop/src/policy.cjs`, `desktop/package.json`, `desktop/README.md`.
- Novos: `desktop/src/server-settings.cjs`, `desktop/src/setup-preload.cjs`, `desktop/setup/index.html`, `desktop/setup/app.js`, `desktop/SERVER-PROVISIONING.md`.
- Testes: `desktop/test/electronHarness.cjs`, `desktop/test/desktop.test.cjs`, `desktop/test/floating.integration.spec.js`, novo `desktop/test/server-settings.test.cjs`.
- `setup/**/*` adicionado à lista de empacotamento, reutilizando o CSS local já incluído da janela flutuante. Nenhuma dependência adicionada.

As demais alterações presentes no git status são as correções LAB3 anteriores, preservadas. Banco/schema/migrations, Compose/Dokploy, workflows e produção não foram alterados.

## Validação

Resultados em 25/09/2026: **16/16 testes Desktop**, **24/24 testes de provisionamento** e **88/88 testes Webphone/download/integração em 12 arquivos** aprovados. A suíte de provisionamento inclui compatibilidade do autostart antigo com argumentos de URL. ESLint dos arquivos JS/Vue alterados/novos passou com zero warnings; `git diff --check` passou. `git diff HEAD -- db` vazio, sem alterações de schema/migrations.

Os builds posteriores à implementação concluíram com exit code 0. O ASAR extraído do instalador final corresponde aos 11 arquivos-fonte esperados, incluindo setup, persistência, policy e bridge. SHA-256 do EXE universal: `18b4e604c426e6a587d1e1f049840d7372a56dc9e1d266da680eceb58b3beb06`. Image ID local lab.3: `sha256:90b3d8af0271614eabfd72bc328226e07dfdd06390210fef5fa4af3eaba38bec`. Foram comparados 31 arquivos dentro da imagem e conferidos o manifesto Vite de 253 entradas e seus assets. Os artefatos permanecem locais e não fazem parte deste versionamento. Os fontes funcionais não foram alterados após esses builds; somente esta documentação foi atualizada para registrar o resultado.

```powershell
node desktop/test/desktop.test.cjs
node desktop/test/server-settings.test.cjs
$env:TZ='UTC'
node node_modules/vitest/vitest.mjs run --config desktop/test/webphone.vitest.config.mjs --no-cache --no-coverage
git diff --check
```

Testes de política/lifecycle cobrem primeira execução, origem HTTPS e normalização, persistência/reinicialização, config inválida, prioridade da fonte canônica, URLs proibidas, remetentes IPC não autorizados, shutdown antes da troca, timeout, limpeza, falhas de gravação, seleção da mesma origem, fechar/restaurar e saída. Os testes integrados exercitam formulário/preloads/main/composable/SipClient/SipRegisterer reais com Electron e fronteira SIP.js simulados: escolher servidor → login/registro → janela abre; trocar de servidor durante chamada → BYE/unregister/stop → novo ambiente com somente um Registerer ativo. Toda a suíte LAB3 anterior é preservada.

Validação real posterior: primeira instalação em Windows, caminho efetivo do Electron fora do ambiente de testes, reinicialização/autostart, login e chamadas nos dois ambientes, microfone, rede indisponível durante unregister e Contact/expiração no PABX. Nenhum aplicativo/instalador foi executado ou instalado nesta etapa.
