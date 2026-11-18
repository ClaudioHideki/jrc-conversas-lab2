# Contato 360º nativo a partir de uma chamada explicitamente vinculada

Estado: preparado na cópia temporária; nenhum aceite Rails/Vue/Chrome deste incremento ainda.
Figura 21 permanece parcial. Não conecta Qualidade legada por coincidência numérica de IDs.

## Reuso e autorização

CustomerContext.for_call só oferece directory.contact_id para o contato explícito e já autorizado da chamada, após ContactDirectory.find do Cadastro Mestre. São mantidos DirectoryPolicy, conta atual, usuário ativo e cobertura corporativa existentes. Direitos configurar/operar do Call Center não se convertem em contact_manage. Falta da feature/permissão ou registro não acessível remove a entrada, preservando o contexto básico que o Call Center já podia consultar. Telefone único/ambíguo nunca cria esse vínculo. Não há endpoint, migration, contato, carteira ou permissão paralela.

LinkedContactMaster carrega ContactDetailsDialog por importação assíncrona somente após clique. Exige correspondência entre a chamada, o contato autorizado e a entrada nativa de diretório. Troca de conta/chamada/contato e retirada de operar fecham o popup e invalidam carregamentos antigos. O painel nativo continua reautorizando cada chamada e invalidando seu próprio contexto após perfil/escopo. Atualização confirmada ou fechamento provoca somente uma leitura nova do cliente; o rascunho da ocorrência/retorno não é reiniciado. Falhas limpam o cliente antigo e mostram erro; respostas anteriores à navegação são descartadas. Nenhuma mensagem ou ação operacional é enviada.

Na rota com callId selecionado, CallExperiencePage apresenta o workspace real, sem uma segunda chamada de demonstração acima dele. A referência visual identificada permanece na rota sem seleção. Falha de contexto não substitui uma chamada selecionada por dados de exemplo.

## Provas preparadas

Cinco novos exemplos de serviço Rails: vínculo explícito autorizado; feature ausente; telefone único sem vínculo; configurar/operar sem direito do Cadastro Mestre; retirada da permissão com histórico da chamada preservado. Dezesseis Vue (incluindo dois do componente compartilhado para preservar o padrão e a opção de nova aba): oito da entrada/modal, três de atualização sem perda do rascunho/resposta antiga/erro e três de referência versus chamada real. Mocks Vue não constituem homologação.

Os quatro novos cenários de navegador preservam os 112 existentes (116 obrigatórios). Usam novas contas, atores e dados sintéticos próprios, no mesmo ambiente descartável já protegido. O operador tem papel agent e somente contact_manage/view/operate, sem administrar/configurar. Há empresa/unidade A e B, fonte corporativa explícita A, contato e chamada B atribuída ao mesmo ator mas negada pelo escopo, e conta estrangeira. O administrador sintético GROUP é usado apenas para a retirada controlada de contact_manage, com revisão nativa e nova conferência de acesso.

O fixture importa módulos Vuex e rotas reais do Cadastro Mestre somente quando a resposta autêntica da conta habilita a feature. Getters de conta/papel derivam exclusivamente das respostas reais de conta/perfil; não há alias ou resposta substituta de API. A propriedade de autenticação sintética continua idêntica, acessada com Reflect.get para resolver a infração anterior no fixture, sem imprimir ou arquivar o valor. O material é privado, temporário e excluído dos artefatos como antes.

O Chrome deverá conferir popup, gravação/reabertura de Cargo pelo endpoint nativo, rascunho mantido, dados B/conta estrangeira negados, candidato por telefone sem entrada e retirada de permissão fechando/retirando o acesso, preservando o contexto básico autorizado da chamada. As cores computadas de superfície/texto e capturas em 1440/390 px, claro/escuro, são provas obrigatórias. Somente resultados do SHA que contiver este código poderão dar aceite.

## Limites

Sem PABX/provedor externo, NICO, scanner ou envio real. A correlação de Qualidade legada, a identificação manual de candidatos e a integração adicional de ações CRM/Service Desk/Projetos permanecem requisitos separados; não inferir correspondência de IDs. A figura inteira e as 23 referências continuam abertas. Nenhum acesso de usuário real foi alterado.

O link nativo de tela completa ganha uma opção openFullPageInNewTab, falsa por padrão e ativada somente pelo chamador de atendimento, com noopener/noreferrer. Preserva o comportamento dos outros módulos e evita substituir a página com o rascunho. Dois Vue específicos verificam os dois contratos e o gate os inclui expressamente. O navegador deste incremento verifica destino, target e rel reais; não considerar isso prova de toda a edição do módulo na página independente. Essa homologação ampliada permanece separada.


## Resultado nativo de 65ecefbe e limite real da evidência visual

CI 44295927524 aprovada: 865 principais + 23 concorrentes + 85 corporativos = 973 Rails únicos, 16 reexecuções do ledger, 337 Vue e 116 Chrome; zero falhas, pendências, skips, flaky ou erros externos. Os 15 cards no bootstrap, lints sem novas infrações, migrations/SQL/schema reload e assets foram aprovados. Artefato 14424903824, SHA-256 c65d38a4a3ead9d412fa8a3aa1987b63df1633f6cd50c0c8d16a8bd31d478c8d. Os 164 hashes de capturas foram conferidos.

O navegador comprovou persistência/reabertura do Cargo, preservação do rascunho, APIs negadas por empresa/unidade/conta, candidato por telefone sem vínculo e retirada de contact_manage sem remover a autorização básica da chamada. A superfície real da visão geral teve cores computadas diferentes e legíveis nos dois temas. Isso não prova a navegação completa em uma nova aba.

As quatro capturas do formulário foram efetivamente revisadas e todas mostram a recarga nativa Carregando depois do salvamento. Não dar aceite visual final com essas imagens. A próxima validação aguardará o Cargo persistido e ausência do estado de carregamento, conferirá novamente contenção e capturará visão geral e formulário. O cabeçalho também passa a reutilizar callStateLabels para não exibir connected em inglês; um Vue adicional e os quatro Chrome verificam o rótulo existente Falando. Sem nova tradução, troca de estado ou alteração de regras.

O próximo checkpoint inclui esse QA necessário e o incremento de revisão ACW já preparado, ambos explicitamente identificados. Exigirá 350 Vue, 120 Chrome (os 116 anteriores preservados e quatro novos), 875 principais + 24 concorrentes + 85 corporativos esperados, mais as 16 reexecuções. Não reutilizar o aceite de 65ecefbe para o código novo.
