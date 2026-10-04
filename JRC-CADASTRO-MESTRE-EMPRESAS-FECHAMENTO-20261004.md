# JRC Conversas — Fechamento do Cadastro Mestre de Empresas

Data do candidato: 2026-10-04
Base integrada: `JRC-CONVERSAS-LAB2-CADASTRO-MESTRE-CRM-ESTRUTURA-ORGANIZACIONAL-INTEGRADO-20261004.zip`
SHA-256 da base: `00cd3bd85263b404315de0e2a3e8e1af2ed1b6ccf96fce08ee1b2f7e79ff5783`

## Decisão arquitetural preservada

- Cadastro Mestre continua sendo a única fonte de Empresa/Cliente do JRC Conversas.
- CRM, Service Desk, Projetos e demais módulos continuam referenciando a mesma linha da tabela `companies`.
- Estrutura Organizacional interna continua separada do cadastro de clientes.
- Nenhuma Empresa paralela foi criada no CRM.
- Funis e Etapas não fazem parte deste pacote; ficam para o próximo bloco funcional.

## Evoluções aplicadas

- Código interno automático da empresa no padrão `EMP-000001`, derivado do ID estável da empresa.
- CNPJ/CPF continua normalizado e com prevenção de duplicidade por conta.
- Relacionamento principal preservado e adição de relacionamentos secundários.
- Tags livres de classificação adicionadas à empresa.
- Porte passou a usar catálogo controlado: MEI, ME, EPP, Médio porte e Grande porte.
- Origem passou a usar catálogo controlado para indicadores.
- Segmento passou a usar taxonomia parametrizada por conta, com ativação/inativação e reutilização no formulário de Empresa.
- Segmentos já existentes são migrados para a nova taxonomia durante a migration.
- Auditoria de criado por e atualizado por foi adicionada à própria ficha, mantendo a auditoria transacional já existente.
- Busca de empresas passa a aceitar também o código interno.
- Visão 360º reorganizada em grupos funcionais: Visão 360º, Cadastro, Relacionamento, Comercial, Operação e Atendimento.
- A Visão 360º recebeu indicadores adicionais: valor de oportunidades abertas, MRR de contratos ativos, SLA vencido, última conversa e próxima atividade.
- Relacionamento principal, relacionamentos secundários, tags, responsável e status ficam visíveis no cabeçalho da ficha.

## Migration adicionada

`db/migrate/20261004170000_complete_jrc_customer_master_company_profile.rb`

A migration adiciona somente campos/tabela necessários ao fechamento do Cadastro Mestre. Não remove colunas nem tabelas existentes. O rollback é deliberadamente bloqueado para evitar descarte acidental de dados empresariais.

## Segurança e compatibilidade

- Código da empresa é único por conta.
- Criado por/atualizado por usam referência opcional a usuários e ficam nulos se o usuário for removido.
- Segmentos são isolados por conta.
- Relacionamentos secundários não podem repetir o relacionamento principal.
- Porte e Origem aceitam apenas valores do catálogo quando alterados.
- A navegação 360º continua respeitando as capacidades e filtros de visibilidade já existentes.
- Métricas de Service Desk/CRM/Projetos são calculadas somente sobre registros visíveis para o usuário autenticado.

## Validações executadas neste ambiente

- Sintaxe Ruby dos arquivos alterados/adicionados: OK.
- Sintaxe JavaScript dos scripts alterados: OK.
- Extração e validação sintática dos blocos `<script setup>` dos componentes Vue alterados: OK.
- Comparação com o ZIP-base: nenhum arquivo da base removido.

## Homologações ainda obrigatórias

Este pacote continua sendo candidato. Antes de produção, executar no LAB:

1. PostgreSQL migration completa e verificação dos índices/constraints.
2. Rails/RSpec completo, incluindo os specs novos de Empresa e Taxonomia.
3. Build Vue/Vite e lint do frontend.
4. Testes em navegador da ficha de Empresa e da página de Segmentos.
5. Teste Docker/imagem GHCR.
6. Smoke test dos módulos Cadastro Mestre, CRM, Service Desk, Projetos e Minha Agenda.

## Itens deliberadamente não incluídos

- Mesclagem automática de empresas duplicadas: permanece evolução futura e deve exigir revisão explícita.
- Funis e Etapas: próximo bloco funcional do CRM, sem alteração neste candidato.
