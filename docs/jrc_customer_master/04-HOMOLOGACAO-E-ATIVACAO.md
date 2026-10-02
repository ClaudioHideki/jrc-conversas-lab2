# Homologacao e ativacao por Account

**PENDENTE neste ambiente. Execute primeiro no laboratorio com banco de teste e backup conferido.**
Nao ha autorizacao implicita para production, drop, reset, migracao de servidores ou troca de imagem Docker.
Os comandos abaixo sao roteiro para o operador, nao comandos executados no banco do usuario.

## 1. Preparar

Confirme que o codigo implantado corresponde a fonte oficial 80f7305; mudancas feitas no Git depois dela precisam de nova conciliacao.
Extraia o candidato em outra pasta, preserve o original e o banco. Use a infraestrutura existente apenas apos backup e verificacao de compatibilidade.
Use Ruby 3.4.4 e a versao Node declarada nos arquivos de versao/engines do projeto, sem editar Gemfile ou lockfiles para contornar o ambiente.
Instale as dependencias com os lockfiles oficiais. Nesta execucao local havia Ruby 3.3.8 e Node 22.16.0; isso NAO homologou o runtime alvo.
Deixe `jrc_customer_master` desligada durante a preparacao.

## 2. Adicionar schema (somente TEST/laboratorio primeiro)

As tres migrations novas sao:

- `20261002170000_extend_jrc_customer_master.rb`: campos e estruturas complementares.
- `20261002171000_guard_jrc_customer_master_tenants.rb`: indices e FKs compostas de Account.
- `20261002172000_link_jrc_customer_master_operations.rb`: company_id em Tickets/Projects e protecoes comerciais adicionais.

Confira `bundle exec rails db:migrate:status` contra o banco selecionado. Aplique migrations pelo procedimento normal do projeto no banco correto, nunca com reset/drop.
As FKs antigas nao foram alteradas. Algumas FKs novas sao NOT VALID: restringem novas escritas e sua validacao de historico e uma etapa separada.
Se um indice CONCURRENTLY ficar invalido por interrupcao, a rotina recusa a repeticao cega: o DBA deve revisar o indice antes de tentar novamente.
As migrations nao fazem backfill e nao tem rollback destrutivo. Nao edite schema.rb manualmente; qualquer dump deve vir do Rails no ambiente correto.

## 3. Revisar e aplicar dados

Em manutencao, para a conta escolhida (substitua 123 pelo ID real):

```sh
ACCOUNT_ID=123 bundle exec rails jrc:customer_master:backfill
```

Revise `conflicts`, `organizations`, `contacts_linked`, `leads_linked`, `crm_links` e o `digest`. Um arquivo MAPPINGS opcional e um objeto JSON de organization_id para company_id, ambos verificados na mesma Account.
Nunca use o ID da empresa operadora como company_id de cliente. Conflitos devem ser decididos por um responsavel; nao remova documentos ou historicos para fazer o script passar.

```sh
ACCOUNT_ID=123 APPLY=1 REVIEWED_SHA256=DIGEST_REVISADO bundle exec rails jrc:customer_master:backfill
```

Se usar MAPPINGS, forneca o mesmo arquivo tanto na previa quanto na aplicacao. O digest tem de corresponder a previa atual.
Aplique somente sem conflitos. Gere NOVA previa e repita quando surgirem vinculos resolviveis apos o estagio anterior.
Em seguida:

```sh
ACCOUNT_ID=123 bundle exec rails jrc:customer_master:backfill_operations
ACCOUNT_ID=123 APPLY=1 REVIEWED_SHA256=DIGEST_OPERACIONAL_REVISADO bundle exec rails jrc:customer_master:backfill_operations
ACCOUNT_ID=123 bundle exec rails jrc:customer_master:backfill_operations
```

Revise empresa candidata, evidencia, row ID, lock_version e conflitos. Novos dados/titulos/versoes podem invalidar o plano: nesse caso, nada da aplicacao e confirmado e a previa deve ser refeita.
Projetos internos e contatos provisorios sem evidencia continuam sem empresa; nao sao automaticamente classificados como clientes.
Depois da aplicacao, a previa operacional deve ficar sem `pending`/`conflicts`. Uma etapa pode revelar nova evidencia para outro registro; repita a previa ate estabilizar.

## 4. Validar constraints e dados

Compare quantidades antes/depois de Contacts, Conversations, Messages, Tickets, Projects, Tasks, CRM, Campaigns, contratos e anexos. Confira IDs de amostras e hashes/snapshots onde aplicavel.
Valide referencias por Account e duplicates fiscais. `jrc:customer_master:backfill` inclui verificador de referencias de Tickets, Projects, Operations Links, CRM e destinatarios de campanhas.
As constraints sao globais no banco: revise os dados de TODAS as contas antes de validar, mesmo que apenas uma conta seja ativada.

```sh
CONFIRM=VALIDATE bundle exec rails jrc:customer_master:validate
```

Esse comando valida somente constraints nomeadas `jrc_master_`. Nao repara nem apaga registros conflitantes.

## 5. Testes e verificacoes reais

Execute os testes isolados do roteiro 05 e, no ambiente com Rails/PostgreSQL:

```sh
RAILS_ENV=test bundle exec rails db:prepare
bundle exec rspec spec/models/jrc_customers spec/services/jrc_customers spec/controllers/api/v1/accounts/customers
bundle exec rspec spec/services/jrc_service_desk spec/requests/api/v1/accounts/jrc_service_desk spec/requests/api/v1/accounts/jrc_operations
```

Compile a interface pelo processo existente do projeto usando as dependencias bloqueadas. Rode a suite Vue/Vitest existente e as verificacoes de lint aplicaveis, sem alterar lockfiles apenas para contornar falhas.
As tres suites Ruby preexistentes com falhas estao detalhadas no roteiro 05 e precisam de investigacao. Reproduzir falhas na base nao transforma os testes em aprovados.

Homologue com feature OFF: login/menu, nova mensagem/permissoes, grupos/leads, Cockpit, Conversas, CRM, Projetos, Agenda, Service Desk, Campanhas, NICO e PABX devem manter os fluxos atuais.
Homologue com feature ON numa conta de teste e OFF noutra: criar/buscar/editar empresa, contatos provisorios, CPF/CNPJ duplicado por tenant, enderecos, matriz/filial, roles e exportacoes/importacoes.
Teste chamado e projeto com empresa coerente e conflitante; update com lock_version vencido; replay de criacao anterior a ativacao; vinculos CRM/SD/Projetos; merge com historicos, anexos, contratos e snapshots.
Confira 360/timeline/Agenda com usuario administrador, agente, custom role restrito, unidade nao concedida, projeto privado, conversa nao acessivel e empresa de outro tenant. Listas e contadores nao devem vazar registros.
Valide Contratos COMERCIAIS separadamente da area planned do SD. A Agenda deve continuar informando tarefas SD indisponiveis.
Teste originacao, recepcao, DTMF, transferencia, registro SIP, gravacoes e os fluxos WhatsApp/e-mail/Instagram/Facebook em ambiente autorizado; nenhum desses testes foi executado aqui.

## 6. Ativar somente apos aprovacao humana

```sh
ACCOUNT_ID=123 CONFIRM=ENABLE HOMOLOGATION=APPROVED bundle exec rails jrc:customer_master:enable
```

O comando recusa backfill pendente, conflitos e constraints mestre ainda nao validadas. Nao altera outras contas.
HOMOLOGATION=APPROVED e uma declaracao do responsavel apos executar a homologacao, nao uma certificacao automatica deste pacote.

## Desativar sem perda

```sh
ACCOUNT_ID=123 CONFIRM=DISABLE bundle exec rails jrc:customer_master:disable
```

Conserve schema, IDs, novos dados e mapeamentos. Desativar a flag nao significa reverter correcoes de dados nem remover constraints; apenas recoloca os consumidores/interface no caminho legado quando aplicavel.
Nao execute rollback/drop. Se for preciso restaurar codigo ou banco, use o backup e um plano aprovado de recuperacao.
