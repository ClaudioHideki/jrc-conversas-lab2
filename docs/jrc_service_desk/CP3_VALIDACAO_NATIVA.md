# CP3 - Pendências nativas acumuladas

**PENDENTE — validação nativa em ambiente Docker/local**

Nenhuma aprovação de Rails/ActiveRecord/RSpec/Featurable/SQL/Vitest foi inferida do aceite para
continuar o CP3. Nenhuma migration foi executada nesta rodada. Os roteiros anteriores
`CP2_VALIDACAO_NATIVA.md` e os specs CP1/CP2 permanecem intactos.

## Ambiente correto

Node 24.13.0, Ruby 3.4.4, pnpm 10.2.0, Bundler 2.5.16 e dependências exatas dos lockfiles.
Usar banco/Redis exclusivos de teste e conferir destino/backup antes de qualquer preparação.
Não alterar manifests, runtimes ou lockfiles para mascarar falha. Nenhum comando abaixo
constitui autorização para remover dados existentes.

## CP1 e CP2 - continuam pendentes

Carregar Rails/ActiveRecord/namespaces; Zeitwerk; Featurable; specs de models, policies,
services e constraints; migrations reais e rollback somente vazio; isolamento por Account
/unidade; revogação/concorrência; snapshots e integridade. Executar o roteiro CP2 já incluído.
O `db/schema.rb` permanece o anterior, pois o CP2 entregou migrations ainda não aplicadas.
Deixar o Rails gerar o schema no teste adequado, nunca editá-lo manualmente.

## CP3 - comandos de verificação frontend

Dentro da cópia de teste Linux/Docker correta, após preparar dependências com lockfiles:

```sh
pnpm exec vitest run app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__ app/javascript/dashboard/__tests__/serviceDeskFeatureFlag.spec.js
```

```sh
pnpm exec eslint app/javascript/dashboard/routes/dashboard/serviceDesk app/javascript/dashboard/api/serviceDesk.js app/javascript/dashboard/api/serviceDeskClient.js app/javascript/dashboard/components-next/sidebar/Sidebar.vue app/javascript/dashboard/routes/dashboard/dashboard.routes.js app/javascript/dashboard/i18n/locale/pt_BR/index.js app/javascript/dashboard/i18n/locale/pt/index.js app/javascript/dashboard/i18n/locale/en/index.js
```

```sh
pnpm exec vite build
```

`contracts.spec.js` usa 100 casos compartilhados que foram executados isoladamente em Node;
isso não aprova sua execução pelo Vitest. `components.spec.js`, `views.spec.js` e
`routing.spec.js` requerem Vue/Vitest e não foram executados no ambiente desta entrega.
Os doubles/fixtures dos testes são sintéticos, exclusivos dos specs; não são dados reais da tela.

## Smoke a registrar

1. Flag false: sem item Service Desk; URL profunda negada/redirecionada; demais itens, rotas e telas preservados.
2. Flag true, ainda sem API CP4: estrutura em estado PENDENTE PARA CP4, não tabela vazia confirmada ou KPIs zerados.
3. Leitura controlada em testes de frontend: confirmar matriz, colunas, labels, grupos, abas, formulário e teclado.
4. Backend/contexto negado: nenhuma informação reaproveitada; administrador sem unidade não ganha acesso.
5. Troca Account/usuário/unidade, flag revogada, respostas fora de ordem e falha de rede: apagar estado e impedir resposta obsoleta.
6. Pendência vs vazio vs erro/403/404: mensagens distintas; repetir não amplia filtro nem escopo.
7. Formulário: não assume unidade, não envia requisição de escrita e perde rascunho ao sair/refresh; salvar/criar desabilitados.
8. PT-BR/PT/EN e fallback nativo; modo claro/escuro; larguras 1440, 1024, 768 e 390; teclado e rolagem de tabelas.
9. Navegar Cockpit, conversas/canais, CRM, campanhas, NICO, Calling, Email/Calls Center, contatos e empresas antes/depois.
10. Conferir bundle/imports e requisitos nativos antes de considerar o frontend operacional.

Não se exige que uma API CP4 inexistente tenha sucesso no smoke CP3: nesse caso o resultado
correto é indisponibilidade explícita e ausência de dados fictícios. O ciclo real de persistir,
consultar, filtrar, atualizar e conferir KPIs continua PENDENTE PARA CP4 e validações posteriores.

## Limitações observadas nesta rodada

Node disponível 22.16.0 e Ruby 3.3.8. `pnpm`, `bundle`, Vitest e lint/build do projeto não
ficaram disponíveis. Os comandos pnpm terminaram com executável ausente (127), antes de rodar
qualquer suite. Não foram instaladas novas dependências na aplicação.

Verificações isoladas/estáticas são evidências parciais, não substitutos de Vue compilado,
Rails, RSpec, PostgreSQL ou navegação real. Registrar runtime, comandos, códigos de saída,
falhas e hash do pacote testado. Nenhum resultado ausente deve ser marcado aprovado.

**CP4 NÃO INICIADO.**
