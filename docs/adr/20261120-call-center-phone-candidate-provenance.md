# Correspondência telefônica e vínculo confirmado — 20/11/2026

Status: preparado; validação nativa e Chrome deste incremento pendentes.

A figura 21 exige identificar a fonte do contexto e não tratar um telefone como confirmação de identidade. O serviço CustomerContext já limita os candidatos aos contatos autorizados, usa o vínculo explícito da chamada para consultar o ContactDirectory e impede que uma busca telefônica abra o Cadastro Mestre. O registro nativo de ocorrência/retorno também usa somente call.contact_id. Esses controles são preservados.

O contrato legado status=identified para uma correspondência telefônica única continua válido para os consumidores existentes. O contexto da chamada recebe um campo aditivo identity_source: call_contact_link, phone_candidates, unidentified ou unavailable. A busca avulsa by_phone permanece inalterada. Não há nova API, migração, permissão ou vínculo automático.

A tela existente exibe um aviso traduzido quando uma correspondência única não tem vínculo com a chamada, inclusive no modo compacto. Nenhum cadastro paralelo é criado. O aviso não concede acesso ao Cadastro Mestre, à empresa, aos contratos ou a outro módulo. As listas continuam submetidas aos filtros nativos de conta/cobertura/permissão.

Cinco regressões Vue preparam a distinção visual, a ocorrência sem associação automática e a troca de conta/chamada com resposta antiga. Dois exemplos Rails existentes ganham assertivas da origem e da ausência de persistência. O cenário Chrome nativo do Cadastro Mestre é ampliado nas quatro combinações de tamanho/tema com consulta à API real, verificação de ausência de vínculo, geometria e captura; permanecem 212 cenários, sem substituição dos demais.

A projeção do Hoya também deixa de usar o primeiro candidato como contactId do painel 360º. Somente o vínculo nativo da chamada pode carregar esse painel; há aviso permanente na área central para o candidato, inclusive antes de abrir outras abas. A conversa de texto conserva seu remetente nativo. O Chrome existente também abre o Hoya com o mesmo banco sintético e exige Visão geral desabilitada enquanto a chamada não possui vínculo.

O incremento não integra o SHA 86c4ad53 atualmente em validação. A figura 21 permanece parcial: contexto completo de contratos e histórico, atalhos e integrações das etapas posteriores exigem os critérios próprios. Não há publicação, deploy, comandos PABX ou alterações em dados reais.
