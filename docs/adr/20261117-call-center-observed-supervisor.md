# Supervisor: separar eventos locais de demonstrações visuais

Status: correção preparada; validação nativa/Chrome pendente.

## Evidência

SupervisorPage usa a API SupervisorSnapshot real, mas mantém valores, personagens e listas de contactCenterVisualCatalog no cabeçalho VisualShowcasePage. A indicação de demonstração não deve converter esse conteúdo ilustrativo em dados operacionais. O catálogo visual é preservado para as demais referências; a tela nativa deve apresentar somente suas fontes autorizadas.

## Decisão

- Contagens de agentes/espera somente após resposta válida da API atual. Zero confirmado não vira ausência de dados. Durante carga, erro ou revogação, apresentar ausência de leitura, sem restaurar dados da conta anterior.
- SLA e taxa de abandono permanecem pendentes: não inventar fórmula, limiar ou percentual. A taxa ilustrativa 2,8% e SLA 91,2% não aparecem na tela nativa.
- Filas mostram seu estado cadastral retornado pelo servidor. Remover o limiar visual arbitrário de três chamadas para classificar operação normal/atenção.
- Reutilizar o componente visual com opção explícita de mostrar apenas o resumo. A opção padrão preserva todos os outros chamadores e catálogos. A página nativa usa resumo e não selo de demonstração; suas listas abaixo já usam a API real.
- Falha no polling descarta o snapshot anterior. Uma nova leitura bem-sucedida limpa o erro; respostas da conta anterior não são aplicadas. Nada nesta alteração confirma dados no PABX.

## Aceite

Testes Vue de carga, zero, contagens positivas, erro/recuperação e troca de conta, preservação da apresentação padrão do componente compartilhado e Chrome real nos quatro projetos. Não modificar APIs, permissões, banco, fórmula de SLA ou operações externas.
