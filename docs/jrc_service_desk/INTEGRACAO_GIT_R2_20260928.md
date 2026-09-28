# Integração Git do Service Desk R2 — 28/09/2026

Esta integração consolida duas linhas oficiais e o candidato R2. É um checkpoint local para revisão, sem push, publicação de imagem, migration de produção ou habilitação de contas reais. Projetos não foi integrado: a exclusão foi confirmada expressamente pelo solicitante.

## Origem e base

- ZIP: `JRC-CONVERSAS-SERVICE-DESK-CANDIDATO-HOMOLOGACAO-20260928-R2.zip`.
- SHA-256 conferido: `a5bdc624fd677dc82afd2d236decdd5503800a77bd12f8ba82c1480a04dcd3a8`.
- Repositório: `https://github.com/ClaudioHideki/jrc-conversas-nico-v12-2-7-comercial-integrado.git`.
- Checkout inicialmente consultado: branch limpa `codex/jrc-broker-modules-20260924`, HEAD `239c8358666289846e6e0112ea6c38eccfd956ba`.
- HEAD remoto padrão, confirmado antes do fetch: `main`, `62c14af884c7f45fa640345556f2ffecc22113d8`. Não foi usado isoladamente como base de integração.
- Fetch explícito de todas as branches oficiais efetuado.
- Base QR/Broker: `origin/codex/jrc-qr-pair-status-20260925`, `61b120ab71db8c67484e5de9d5dfae9cbdff9eb2`.
- Base CRM/softphone: `origin/codex/softphone-desktop-windows`, `f58970d922565ac4322e41a8a4dac3d59ae9033d`.
- Ancestral comum dessas linhas: `1409f1c70e0c9e195154de59cba77e0401cda464`.
- Branch própria: `codex/service-desk-candidato-r2-20260928`.

O merge preserva as duas histórias como pais do commit. Nenhum checkout anterior foi substituído. O ZIP é um snapshot completo de uma base antiga, portanto não foi copiado sobre o repositório inteiro.

## Reconciliação

Comparação por conteúdo antes de aplicar o candidato:

| Referência | Idênticos ao ZIP | Diferentes | Somente Git | Somente ZIP |
|---|---:|---:|---:|---:|
| main | 9.378 | 16 | 0 | 333 |
| QR/Broker | 9.332 | 62 | 153 | 333 |
| CRM/softphone | 9.336 | 58 | 58 | 333 |

Os 333 novos arquivos do candidato pertencem ao Service Desk e seus testes/documentos. Arquivos presentes somente no Git foram preservados. Ausência no ZIP não foi interpretada como exclusão. As diferenças fora da entrega não substituíram as versões oficiais mais recentes.

### Conflitos resolvidos

1. **Workflow GHCR legado:** a linha Broker deixou a publicação manual; a linha softphone acrescentou `publish_lab3` e gatilho por tags. Preservados o acionamento manual e a opção `publish_lab3`, incluindo sua expressão de tags. O gatilho automático legado por tags não foi reintroduzido. Nenhum workflow foi executado.
2. **Sidebar:** mantidas as entradas Broker e Flows, acrescentando as entradas operacionais e estruturais do Service Desk e seus controles de acesso. Mantidos os demais módulos.
3. **Rotas frontend:** mantidos os imports e registros de Broker/Flows; acrescentadas as rotas Service Desk. Rotas backend e traduções foram reconciliadas em três vias contra a base do candidato.
4. **Feature flag:** colisão real no bit 256. A resolução foi autorizada explicitamente e está descrita abaixo.
5. **Dockerfile antigo no ZIP:** preservado integralmente o Dockerfile da linha Broker, incluindo limite de compilação gRPC, `GIT_SHA` e normalização CRLF dos entrypoints. As alterações de empacotamento do ZIP não substituíram esses ajustes; requisitos e versões permaneceram intactos.

Diferenças de CRLF/LF foram normalizadas para a comparação em três vias. Acentos UTF-8 foram conferidos no diff final. O schema foi gerado pelo Rails após migrations reais; preservada a expressão preexistente equivalente do índice de Flows, evitando alteração textual sem relação com Service Desk.

## Migração de bits autorizada

| Feature | Coluna | Posição final | Máscara | Default |
|---|---|---:|---:|---|
| jrc_service_desk | feature_flags_ext_1 | 9 | 256 | false |
| jrc_flows | feature_flags_ext_1 | 10 | 512 | false, preservado |
| jrc_broker | feature_flags_ext_1 | 11 | 1024 | false, preservado |

A posição 11 foi verificada como livre nas duas branches consolidadas e na main. Além da conferência do código, a migration verifica a ocupação do bit no banco antes de modificar qualquer Account.

`20260925185900_relocate_jrc_broker_feature_flag.rb`:

- Transação de migration com lock exclusivo de `accounts`.
- `up`: se a máscara 1024 já estiver ocupada em qualquer Account, recusa a operação. Para Broker ON, grava `(flags | 1024) & ~256`; para Broker OFF, não altera a linha.
- Todos os outros bits e a coluna primária `feature_flags` permanecem intactos. O bit de Service Desk termina desligado.
- `down`: transfere 1024 para 256. Se 256 tiver sido habilitado posteriormente como Service Desk, recusa o rollback em vez de reinterpretar essa autorização como Broker ou apagá-la.
- Nenhuma atualização de defaults, seeds, roles ou InstallationConfig acompanha a transferência.
- Testes cobrem as 1.024 combinações dos bits anteriores, um bit alto independente, Broker ON/OFF, Flows, Service Desk OFF, roundtrip e destino ocupado nas duas direções.

**Operação futura:** a troca do significado de um bit exige interromper escritores antigos durante migration e atualização da aplicação/workers. Não executar esta migration com releases antigos e novos atendendo simultaneamente. Rollback após habilitar Service Desk depende de decisão operacional explícita; não é automático. Nenhuma dessas ações foi feita em produção nesta etapa.

### Migrations incluídas

1. `20260925185900_relocate_jrc_broker_feature_flag.rb` — nova reconciliação de dados autorizada.
2. `20260925190000_add_jrc_service_desk_reference_keys.rb` — índices auxiliares para integridade por Account.
3. `20260925190100_create_jrc_service_desk_core.rb` — estrutura, chamados, histórico, SLA e vínculos.
4. `20260928120000_add_jrc_service_desk_lifecycle.rb` — políticas/versionamento, transições, ciclos, relógios e pausas.

As migrations estruturais recusam rollback destrutivo quando existem dados operacionais. O roundtrip foi ensaiado somente em banco vazio descartável. O teste de transferência de bits usa exclusivamente Accounts de fixtures no banco descartável.

## Correções identificadas na execução nativa

- **Navegação SuperAdmin:** Administrate enumerava `service_desk_initializations` como recurso de índice, embora só existam ações vinculadas à conta. Isso quebrava o layout das telas. Acrescentada a exclusão dessa ação no menu genérico, mantendo o acesso pelo detalhe da Account, com regressão de navegação testada.
- **Vitest de rotas:** o candidato assumia que a primeira rota tinha `children`; R2 introduziu antes dela a tela de administração estrutural. O teste agora seleciona a rota operacional pelo caminho e aceita rotas sem filhos.
- **Mensagens de pendência:** expectativas de CP3 ainda buscavam texto técnico de CP4 removido nas traduções atuais. Mantida a verificação de indisponibilidade, botão desabilitado e ausência de falso sucesso.
- **Fixture de feature flags:** corrigidos dois rótulos corrompidos no baseline de teste; nenhum identificador ou bit antigo foi removido da verificação.
- **Políticas:** mantida a proibição de mudar status sem política publicada. O teste do presenter agora espera a negação nessa situação.
- **Histórico imutável:** o teste distingue payload inválido de tentativa válida de alterar uma versão somente de leitura, confirmando que o digest persistido permanece original.
- **Semântica de status:** o teste confirma a recusa do modelo e usa alteração SQL explícita apenas na fixture para verificar que o serviço também rejeita uma mudança externa.
- **Autenticação no controller:** as fixtures usam os headers reais de DeviseTokenAuth e removem também `Authorization` ao testar acesso anônimo. Não foram desativados callbacks de autenticação/autorização.
- **Paginação CRM:** a fixture herdada criava contatos sem identidade; a listagem nativa exige contato resolvido. A fixture agora usa e-mails, preservando os 31 nomes e valores de ordenação empatados. Nenhuma alteração na regra de contatos.

## Validação e limites

Runtime nativo usado: imagem local já existente `jrc-nico-test:local`, Ruby 3.4.4, Node 24.13.0, Bundler do projeto, PostgreSQL 16 com pgvector e Redis 7.4. Nenhuma imagem foi construída ou publicada. Bases descartáveis distintas para suíte principal, concorrência, regressões e roundtrip; nenhuma porta desses bancos foi exposta.

Frontend no host: Node 24.19.0, pnpm 10.2.0 por Corepack, instalação com `--frozen-lockfile`. Nenhuma mudança em Gemfile, Gemfile.lock, package.json, pnpm-lock.yaml, .ruby-version ou .nvmrc para adequar testes. O lockfile desktop já existente na branch oficial foi preservado.

### Resultados finais

| Verificação | Resultado |
|---|---|
| RSpec Service Desk, migrations, permissões e Enterprise | 417 exemplos, zero falhas |
| RSpec concorrência real | 4 exemplos, zero falhas |
| RSpec regressões Broker/Flows/NICO/CRM/contatos | 168 exemplos, zero falhas |
| Reexecução específica da migração de bits | 4 exemplos, zero falhas; incluídos também na suíte principal |
| Ruby isolado do candidato | 85 testes, 1.607 assertions, zero falhas/skips |
| Vitest Service Desk | 405 testes, 15 arquivos, aprovados |
| Vitest regressões | 147 testes, 28 arquivos, aprovados |
| Node NICO / desktop | 31 / 40 testes, aprovados |
| Sintaxe Ruby | 190 arquivos aprovados |
| Migrations | Quatro migrations aplicadas; roundtrip completo em banco vazio aprovado |
| Zeitwerk / dependências Bundler | Aprovados |
| Build frontend teste/produção / TypeScript NICO | Aprovados |
| RuboCop do novo arquivo de migração de bits | Zero ocorrências |
| RuboCop conjunto Service Desk | 655 ocorrências em 115 arquivos inspecionados; pendente |
| ESLint conjunto Service Desk | 1.522 erros e 7 avisos em 51 arquivos inspecionados; pendente |
| Auditoria das duas linhas oficiais | 9.575 arquivos idênticos à referência escolhida, 22 reconciliados/corrigidos, zero ausentes |

A suíte histórica completa da aplicação não foi executada; a seleção cobre o módulo integrado e as regressões relacionadas. Não somar as reexecuções específicas como testes distintos.

Os resultados finais e a lista integral de arquivos acompanham o relatório externo `output/service-desk-r2-20260928`. Os documentos CP1–CP6 do pacote foram preservados como histórico; declarações antigas de testes pendentes não substituem os resultados registrados nesta integração.

**Pendências explícitas:** os linters do candidato não estão limpos; existem muitas infrações de formatação e complexidade. Não foram desativadas regras nem feita refatoração ampla silenciosa para ocultá-las. O roteiro manual HTTPS, validação visual em navegador, chamadas/WhatsApp reais e homologação operacional completa não foram executados nesta etapa. Testes automatizados não equivalem à homologação completa.

O commit é um checkpoint de integração para revisão. Push e geração/publicação de imagem dependem de nova autorização do solicitante.
