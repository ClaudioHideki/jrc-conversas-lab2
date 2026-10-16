# Plano: mapa de relações Customer360

Spec: `../specs/2026-10-16-customer-relationships-design.md`. Execução local autorizada; sem push/imagem/deploy.

1. [x] Testes RED com contexto Customer360 real, isolamento e limites.
2. [x] Implementar serviço de projeção somente leitura e endpoint `companies/:id/relationships`, usando autorização/escopo atuais.
3. [x] Testes de requisição: acesso permitido e Account estrangeira/caixa invisível.
4. [x] Testes RED da interface sob demanda e troca de contexto; implementar componente no overview e ligação à lista existente.
5. [x] RSpec focal (15), Vitest (8), lint e diff; evidência em `docs/validation/2026-10-16-customer-relationships.md`. Revisão e ajuste de tarefas sem permissão concluídos, sem publicar.

Contrato JSON v1: root (key), groups [{kind,total,has_more,nodes:[{key,id,display_id,title,status,created_at}]}], edges [{source,target,relation:'customer_context'}], generated_at e sample_limit. Conteúdo dos registros não integra a projeção. Cada grupo contém até 10 nós.
