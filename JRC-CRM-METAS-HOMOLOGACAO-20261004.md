# Homologação — CRM Metas

## Estado do teste

| Área | Resultado esperado após esta atualização |
| --- | --- |
| Criação da meta | Mantida |
| Publicação | Mantida |
| Dashboard consolidado | Mantido |
| Distribuição por vendedor | Evoluída com seletor, inclusão/remoção, sem limite artificial de 8 e peso proporcional |
| Ranking por vendedor | Evoluído com forecast e ritmo esperado |
| Pipeline | Mantido e com cobertura percentual |
| Forecast | Mantido e com cobertura percentual |
| Gap | Mantido e transformado em ação operacional |
| Meta por produto | Produtos ativos disponíveis em seletor, com inclusão/remoção e distribuição |
| Próximas ações | Evoluída para ações executáveis |
| NICO aplicado às metas | Integrado via prompt contextual e rastreável |

## Casos de teste
1. Criar meta de R$ 500.000 no mês atual.
2. Entrar em distribuição por vendedor e confirmar carregamento dos usuários elegíveis.
3. Confirmar soma exata da distribuição e pesos proporcionais.
4. Entrar em Produtos e confirmar carregamento dos produtos ativos.
5. Publicar a meta.
6. Abrir Próximas ações e verificar prioridade, motivo, valor e registros.
7. Em Pipeline, abrir Ver oportunidades.
8. Em vendedor abaixo do ritmo, abrir carteira e conferir filtro por responsável.
9. Em oportunidade parada, usar Criar atividade e confirmar Negócio pré-selecionado.
10. Usar Analisar com NICO e confirmar abertura do painel com o contexto da recomendação.
