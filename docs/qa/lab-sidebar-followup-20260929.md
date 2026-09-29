# Correção complementar do menu e Cockpit — 29/09/2026

Base: `b336217a8900cf849ed3d5042376a219cff0967e`, branch `codex/lab-homologacao-20260929`. Working tree limpo antes desta rodada. Fetch confirmou a mesma revisão remota antes do commit.

## Causas e correções

- O cabeçalho expansível era simultaneamente RouterLink e emissor de toggle. Fechar CRM podia iniciar navegação para a página inicial do módulo; abrir podia produzir duas navegações. Agora grupos usam botão nativo, com `aria-expanded`, e somente a abertura de outro módulo navega uma vez. Links sem filhos continuam links. O redirecionamento específico para Conversas não se repetiu na sessão atual do LAB; a dupla função foi comprovada no código e eliminada em testes com Vue Router real.
- O grupo fechado mantinha seu filho ativo visível por `isExpanded || hasActiveChild`. Agora o grupo inteiro recolhe, preservando a página atual. Retornar ao módulo pela navegação reabre o grupo, inclusive após a primeira troca; removido o watcher limitado a uma execução.
- Uma sobreposição em degradê acima do perfil cobria os últimos 32px do menu, escurecendo textos e ícones brancos. Removida sem alterar a scrollbar aprovada.
- Ícones indisponíveis na barra compacta ainda usavam branco 40% com opacidade 60%. Agora usam o token claro `sidebar.muted`, mantendo a indisponibilidade e sem liberar ações.
- O título do Cockpit herdava branco do header, mas recebia uma regra explícita escura de `h1` na tipografia base. Aplicado branco diretamente ao título; textos auxiliares usam `text-white/90`, existente na paleta do projeto. Sem alteração global de cores.
- Atualizada a expectativa antiga de cor da linha de árvore no teste de subgrupos; ela ainda esperava o token anterior à correção já publicada.

## Validação

- 473 testes Vitest / 28 arquivos aprovados na regressão de Service Desk, autenticação, sidebar e CRM.
- Após o ajuste final de reabertura, reexecutados os 30 testes / 7 arquivos do sidebar: aprovados.
- Cinco novos cenários com Vue Router real: fechar pelo cabeçalho, fechar pelo chevron, reabrir/retornar, abrir com uma só navegação, modo compacto habilitado/desabilitado.
- Preview local com componentes reais e dados sintéticos: título `rgb(255,255,255)` nos temas claro e escuro; itens primários brancos, secundários `rgb(219,234,254)`, indisponíveis `rgb(184,207,229)`, opacidade 1. CRM recolhe sem deixar filho residual e mantém a página Funil. Times/Etiquetas recolhem. A bolinha da etiqueta conserva a cor própria.
- Frontend Vite aprovado em 4m32s. Nenhuma versão, lockfile, Dockerfile ou migration alterados.
- ESLint nos cinco arquivos preexistentes alterados: 42 erros / 1 aviso antes e depois, sem aumento; novo teste sem erros/avisos. Dívida preexistente não corrigida em massa.
- `git diff --check` aprovado.
- Nenhuma alteração Ruby nesta rodada; os 405 exemplos RSpec e Zeitwerk referidos na entrega anterior são evidência da base, não uma nova execução.

## Service Desk — Claudio

A sessão real de Claudio na Account 1 foi consultada pela URL operacional e retornou `service-desk-access?reason=denied`. Isso comprova a negativa atual, mas não identifica isoladamente qual requisito falta. Solicitado diagnóstico Rails somente leitura de feature flag, AccountUser, capabilities e vínculos de unidade. A inicialização anteriormente apresentada pelo usuário concedeu vínculo a Thiago (AccountUser 15); não comprova vínculo de Claudio.

Não foram criados, alterados, ativados ou removidos AccountUser, UnitMembership, capabilities, roles, feature flags, unidades ou permissões. Não há bypass por administrador. Acesso de Claudio permanece pendente do diagnóstico e de eventual autorização específica posterior.

## Limites

Sem deploy, mudanças de Compose/ENV do LAB, migrations no LAB, Projetos ou GoPure. A auditoria ampla anterior continua com pendências manuais; esta correção não declara homologação completa da plataforma. A publicação terá tag inédita `sha-<commit>` no workflow oficial, com digest registrado na entrega externa após o build.
