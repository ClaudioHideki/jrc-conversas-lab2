# Duração e verificação atuais na biblioteca

Estado: implementação preparada; validação nativa e Chrome pendentes.

As figuras 6 e 16 exigem duração obtida do arquivo. A biblioteca passa a acrescentar `technical_verification` aos metadados da versão, mantendo os campos legados de prontidão/publicação. Esse resumo seleciona a tentativa mais recente da versão exata. Uma tentativa atual indisponível ou inválida não reutiliza metadados de outra tentativa limpa.

A consulta segue a relação autorizada de `AudioLibraryAccess`, por conta e unidade. O carregamento em lote usa o padrão nativo `DISTINCT ON` da versão mais recente, aplicado também à inspeção. Não é criada permissão nem um caminho público para bytes. A prévia e o download continuam sujeitos à reautorização e integridade no servidor.

A interface apresenta duração apenas para a observação válida com milissegundos positivos e representáveis sem arredondamento indevido no JavaScript. Arquivos menores que um segundo conservam a fração; ausência de dados não vira `00:00`. A duração também aparece no celular e nos detalhes. Ao iniciar outra inspeção, o resumo apresentado é invalidado; somente o resultado da mesma conta, unidade, ativo, versão e hash pode atualizá-lo. Eventos de outro contexto não afetam a seleção atual.

Foram preparados cinco casos de API com banco e ferramentas nativas, um caso de consulta em lote e onze casos Vue (oito da lista/detalhes e três de propagação de inspeções). O caso de lote usa três arquivos reais sintéticos para detectar consultas por registro; não representa homologação de escala. Os quatro cenários Chrome existentes de upload agora exigem a mesma duração exata da inspeção persistida na lista e no painel, em desktop e celular, claro e escuro. Ainda não há resultados desse incremento.

Nenhuma migration ou SQL histórico é alterado. O scanner da CI usa definições sintéticas; não comprova cobertura antimalware operacional nem homologação externa. Gravação, geração Nico, vínculos e publicação PABX continuam separados da duração técnica.
