<!-- jrc-operational-init:v1 -->
# Roadmap operacional — JRC Conversas LAB2 — Grupo JRC

Referência inicial: INIT solicitado pelo usuário em 2026-11-13. É uma trilha documental Brownfield, não uma declaração de conclusão do produto.

## Fase 1: Fundação e alinhamento de contexto

- [x] Identificar o projeto e preservar as regras existentes em AGENTS.md.
- [x] Organizar o domínio em docs/domain/ e a arquitetura em docs/architecture/.
- [x] Configurar o pipeline documental de tarefas em TASKS.md e o registro ADR.
- [ ] Revisar os mapas iniciais com os responsáveis do projeto e manter as fontes atualizadas.

## Fase 2: Operação e desenvolvimento ativo

- Manual de Cultura JRC: candidata local com portal HTTPS próprio, ciência por versão, administração e arquivos privados. [Homologação](docs/jrc_consolidation/manual-de-cultura-homologacao-20261123.md).

- [x] Validar localmente a abertura interna com SLA publicado, autorização manual preservada e rascunho mantido após recusa de operação. 1.068 cenários Rails cobertos com revalidação direcionada, 22 concorrentes e 1.153 Vue aprovados. Publicação e homologação permanecem pendentes de autorização posterior; ver SD-SAVE-403-20261123 em TASKS.md.

  Ajuste final validado com 176 Rails e 87 Vue: escolha de responsável de outras equipes/filas, independência de padrões inválidos, autenticação ativa do destinatário e nenhuma substituição silenciosa.

- [x] Validar e publicar a abertura interna por destinatário de outros departamentos da unidade e recuperação da rota de criação (ADR0008), preservando a imagem responsiva f494fd38. Produto ab6bba04; [evidências](docs/jrc_consolidation/abertura-chamados-agentes-release-20261119.md). Implantação e aceite permanecem separados.

- [x] Validar e publicar a visualização responsiva de mensagens, com editor adaptável e botão Ampliar conversa (ADR0007). Produto f494fd38; [evidências](docs/jrc_consolidation/inbox-responsive-release-20261118.md). Implantação permanece separada.

- [ ] Corrigir e publicar a passagem da intenção de encerramento manual pelo cliente HTTP real, sobre a imagem 68862610, preservando as regras da ADR0005.

- [x] Validar e publicar o encerramento manual sem requisitos extras, com tempo e SLA reais preservados (ADR0005), sobre a imagem a5d5e1a. Produto 68862610, digest 53b9ebc6; [evidências](docs/jrc_consolidation/encerramento-livre-sla-release-20261117.md). Implantação permanece separada.

- [x] Validar e publicar o incremento de destinatários de chamados, indicadores e projetos por responsável/participante (ADR0004), preservando a imagem funcional d468beb8. Produto a5d5e1a, digest7fbe9fc9; [evidências](docs/jrc_consolidation/chamados-projetos-release-20261117.md). Implantação permanece separada.

- [ ] Reconciliar conversas por caixa e a política de acesso Minhas/compartilhadas/exclusivas.
- [ ] Manter homologação de voz, histórico e mídias distinta de teste sintético e de publicação.
- [ ] Registrar critério de aceite, teste pertinente e evidência de cada alteração funcional autorizada.

## Fase 3: Estabilização e manutenção

- [ ] Documentar casos de borda comprovados e dependências operacionais.
- [ ] Otimizar rotinas repetitivas somente após medir a necessidade.
- [ ] Revisar proveniência, isolamento e versões a cada candidata de release.

Veja [TASKS.md](TASKS.md). Roadmaps e planos anteriores continuam válidos no seu escopo.

## Publicação integrada — 16/11/2026

- [x] LAB2d468 e Broker publicados e implantados após CI/E2E, preservando os incrementos já aprovados. Recibos de persistência e retenção conferidos no schema/runtime.
- [ ] Aceite físico e reconciliação de grupos, distribuição e acervo antigo. Não inferir completude a partir de conexão ativa, capability ou HTTP200.

[Recibo da publicação](docs/jrc_consolidation/release-20261116-result.md). Esse resultado atualiza a situação dos incrementos descritos abaixo sem apagar suas evidências intermediárias.

### Incremento autorizado de 16/11/2026

Detalhes da proposta passam a abrir em popup sobre a lista, mantendo ações e rascunhos. Exigir testes de abertura/fechamento e preservação das permissões, além da identidade da nova imagem. [Decisão e aceite](docs/adr/20261116-proposta-popup.md).

Remover o filtro visual de segmento em todos os módulos consumidores e gerar uma nova imagem candidata sobre o código da última publicação. Preservar cadastros e permissões; exigir testes e identidade do artefato no SHA alterado. Escopo e aceite: [ADR](docs/adr/20261116-remocao-filtro-segmento.md).

Concluído: produto `c8efa1d6`, CI `43941168985` aprovada e imagem publicada por digest em 16/11/2026. O incremento entrega a remoção visual e o artefato; não inclui implantação no servidor.


### Incremento autorizado de 15/11/2026

Respostas rápidas contextuais e configuração/importação da Central de Aprovações evoluem os módulos existentes. Aceite exige testes nativos e interface real em desktop/celular, claro/escuro. A importação não ativa regras, não cria aprovadores por nome e mantém integrações não mapeadas como pendências explícitas.

Release funcional `5c3fb7f` publicada e implantada no Grupo JRC após CI 49/49, Chrome 13/13 e testes integrados privados. Runtime, API, migrations e interface foram conferidos. O aceite operacional de histórico, autoridade e mídias continua parcial; a validação física foi adiada pelo usuário. Detalhes e evidências em `CONTINUE-AQUI.md` e `docs/jrc_consolidation/quick_replies_whatsapp_release_20261115.md`.
