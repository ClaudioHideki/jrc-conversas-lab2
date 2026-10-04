# JRC CRM — Metas / Próximas ações — Evolução 2026-10-04

## Objetivo
Transformar a aba **Metas → Próximas ações** de um conjunto de avisos em recomendações operacionais, rastreáveis e acionáveis, conectadas aos registros reais do CRM e ao NICO.

## Implementado

### Recomendações orientadas por dados
Cada recomendação pode trazer:
- motivo;
- prioridade (Crítica / Alta / Média / Baixa);
- valor, percentual ou quantidade impactada;
- registros que originaram a análise;
- acesso ao registro;
- criação de atividade quando existe Negócio relacionado;
- análise contextual com o NICO.

### Cobertura e forecast
O dashboard passa a informar:
- cobertura de Pipeline = Pipeline / Meta;
- cobertura de Forecast = Forecast / Meta;
- percentual esperado de execução da meta para a data atual.

### Vendedores abaixo do ritmo
O ranking passa a informar por vendedor:
- meta individual;
- realizado;
- pipeline;
- forecast;
- percentual realizado;
- percentual esperado até a data atual;
- indicador `below_pace`.

A partir da recomendação é possível abrir a carteira do vendedor (Negócios filtrados por responsável e status aberto).

### Oportunidades que exigem ação
São identificados:
- gap da meta;
- cobertura insuficiente de pipeline;
- vendedores abaixo do ritmo;
- negócios sem atividade recente;
- propostas enviadas/visualizadas com follow-up vencido;
- produtos abaixo do ritmo da meta.

### NICO
O botão **Analisar com NICO** abre o assistente com contexto numérico da meta e instrução para usar registros reais do CRM, citar a origem das recomendações e propor ações executáveis.

### Configuração de vendedores e produtos
Ao entrar nas etapas de distribuição:
- os vendedores retornados pela API ficam disponíveis em seletor, sem limite artificial de 8 pessoas;
- é possível adicionar vendedores individualmente, remover e distribuir a meta igualmente;
- os pesos iniciais são distribuídos proporcionalmente em vez de atribuir 100% a cada vendedor;
- os produtos ativos ficam disponíveis em seletor, com contador, inclusão individual ou inclusão de todos;
- produtos podem ser removidos da distribuição antes da publicação;
- respostas de API em formato de array ou `payload` são normalizadas.

## Pendências de homologação em LAB
- executar RSpec completo;
- executar Vitest da tela comercial;
- executar build Vue/Vite;
- validar no navegador com meta real e múltiplos vendedores;
- validar NICO com permissões e runtime configurados;
- validar produtos com catálogo real da conta.

## Próximo teste funcional sugerido
**CRM → Comissões**

Fluxo de homologação:
Vendedor → Venda/Pedido → Comissão → Cálculo → Aprovação → Pagamento.
