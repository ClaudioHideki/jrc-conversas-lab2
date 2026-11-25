# Entrega transacional dos eventos nativos do NICO

Estado: preparação privada para validação nativa. Não aplicada ao produto nem a bancos.

O adaptador de encerramento reutiliza `CreateTicketWorkflowService`. Esse serviço chama a captura nativa do NICO após sua própria transação. Quando uma transação externa do Control Desk ainda está aberta, enfileirar imediatamente pode anteceder a confirmação do chamado e de seu recibo.

Foram conferidos os 54 arquivos nativos de modelos, serviços e jobs do Helpdesk NICO no produto `a90ab9d41056fa2b44c7a678cda7889072e3b263`. As diferenças físicas do checkout original são apenas CRLF. Não há extensão Enterprise correspondente nesses caminhos.

A proposta registra uma intenção técnica de entrega junto ao evento, na mesma transação. Sua confirmação solicita o `EventJob` já existente. O monitor nativo recupera somente intenções registradas por uma captura atual. O estado de negócio e a autoridade continuam no `Event`, no ator original e nas políticas nativas, revalidadas pelo worker.

A nova tabela não recebe dados históricos. Uma chave composta impede ligar uma intenção ao evento de outra conta; uma restrição única impede várias intenções para o mesmo evento. Chaves e índices usam as APIs Rails já adotadas pelas migrations nativas. Não são alteradas migrations publicadas, SQLs históricos, estados de aprovação, poderes ou concessões.

Eventos antigos sem uma nova captura não recebem intenções nem são liberados pelo monitor. A primeira preparação, que recuperava diretamente todos os eventos detectados, foi rejeitada por esse risco. Seu código e manifesto foram preservados em um patch de revisão fora do produto.

O envio se adia se uma transação envolvente ainda estiver aberta, inclusive em callbacks antecipados de transações não compartilháveis. A intenção persistida permite recuperação posterior. Falhas conhecidas de transporte deixam o evento pendente e geram diagnóstico contendo apenas IDs e a classe do erro. Erros de programação não são tratados como indisponibilidade Redis.

As intenções não têm API pública, não criam um cadastro comercial paralelo e não concedem acesso ao NICO, ao chamado ou ao cliente. O modelo `Event` e seus dados de origem permanecem intactos. Políticas interrompidas e eventos terminais continuam fora da recuperação. Exclusões nativas de conta/evento mantêm suas cascatas; não há remoção de dados existentes nesta preparação.

São obrigatórias provas de instalação, atualização populada, reexecução e recarga do schema; vínculo e unicidade no PostgreSQL; commit, rollback e recuperação com Redis real; compatibilidade dos testes NICO afetados; e integração com o chamado e com o ator original. Os testes de falha de transporte são injeções identificadas e não constituem homologação externa.

Esta preparação apoia a figura 10 dos dois Word. Não comprova o cenário completo de destinos independentes nem encerra a figura ou a Parte 1. A tabela técnica não substitui os recibos operacionais por destino que ainda precisam ser integrados. PABX, canais e fornecedores externos permanecem sujeitos aos contratos e autorizações correspondentes.
