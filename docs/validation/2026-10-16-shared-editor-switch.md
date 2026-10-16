# Editor compartilhado — switch tipado candidato

Somente branch `codex/nico-jornada-candidato-20261016`; não houve push, publicação de imagem, deploy, ativação de bot ou mudança de credencial/ENV/Compose.

O módulo NativeFlowModule carrega arquivos locais de `public/jrc-flow-editor`. Portanto, atualizar só o backend Broker não acrescentaria o editor de switch nessa central. O pacote foi reconstruído pelo script do Broker a partir do commit51dbab1f26120a0235f7e6b92ac37c1261573ba1, com `sourceCommitted:true`,198 entradas de build verificadas e scanner público sem achados. Licenças, notices e isolamento em Shadow DOM foram preservados.

Arquivos JRC alterados: pacote JavaScript e seu EDITOR-BUILD-MANIFEST, marcador nativeEditorBuild.js e os dois metadados de composição. Não se alterou a engine Ruby legado, a configuração do NICO, as permissões do usuário, o roteamento de caixa ou a base de produção do outro desenvolvedor.

## Prova local

- RED no pacote JRC anterior: teste de navegador não encontrou o novo bloco.
- GREEN após reconstruir: shared-editor, named-box, private-note-draft, typed-switch, publish-scope, shadow-css e session-close. Zero requisições externas.
- O teste cria somente um rascunho em memória, escolhe caso numérico, muda o nome, conecta à saída Fim e confirma a restrição de publicação do escopo. Nenhum POST/PUT real foi emitido.
- Manifestos de composição gerados e verificados; guard de ownership manteve o mesmo hash porque os controles de domínio não foram alterados.

## Uso e limites

Na futura homologação, o editor nativo/delegado do Broker apresentará **Decidir por vários valores**, com casos de texto, número, booleano ou nulo e uma saída padrão obrigatória. Renomear conserva a conexão; remover exige revisão da ligação antiga. A UI e o motor usam a mesma semântica verificada no Broker.

O switch do Flow legado Ruby possui outro formato (`fallback`, regras textuais por campo/operador). Esse formato permanece preservado; não importar o JSON de um para o outro sem conversão explícita. Registro/atestado da nova instalação, credenciais, scopes e teste de conversa real são etapas futuras no servidor separado. O smoke local não comprova esses vínculos nem autoriza ativação.
