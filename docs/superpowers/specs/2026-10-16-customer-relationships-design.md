# Mapa de relações do cliente

Entrega de leitura do programa aprovado. Reutilizar Customer360 e suas scopes de autorização. Não criar banco de grafo, outro cadastro ou executor. Desenvolvimento apenas local na candidata JRC; sem publicação ou ativação de bot.

Adicionar mapa sob demanda na Visão 360 da empresa, representando o cadastro central e os registros autorizados de conversas, CRM e módulos disponíveis. Cada grupo mostra contagem real, amostra limitada e indicação de que há mais registros. Um módulo não autorizado não aparece como zero.

O endpoint de empresa exige a mesma autorização do cadastro, filtra recursos com as mesmas capacidades de Customer360 e retorna somente identificadores, nomes/títulos, estados e datas permitidos. Não retornar mensagens, notas, documentos, tokens, payloads de integração ou dados de outro tenant. O mapa descreve relações existentes; não executa inferência e não equivale a RAG.

Limitar amostra por grupo a 10 registros recentes, com contagem e has_more. IDs do grafo são compostos por tipo e ID; números iguais de recursos diferentes não colidem. A raiz identifica a empresa autorizada. Links raiz→registro representam pertencimento ao contexto Customer360, não uma relação causal inventada.

A interface é acessível por teclado, não exige câmera/microfone nem biblioteca externa e carrega apenas quando solicitada. Troca de empresa/Account invalida resposta atrasada e limpa o mapa anterior. Ao escolher um grupo, abrir a aba já existente com a lista completa autorizada; não duplicar navegação ou alterar registros.

Testes: isolamento entre Accounts e caixas; capacidades ausentes omitidas; limite/contagem/has_more; títulos escapados pela interface; troca de contexto durante requisição; erro com recuperação e navegação para lista existente. Sem alteração de Compose, ENV ou schema.
