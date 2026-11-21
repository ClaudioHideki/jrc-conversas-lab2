# Duplicação de áudio institucional sem herdar aprovação

Status: incremento implementado para validação nativa; não é homologação do PABX.

As figuras 6 e 16 exigem duplicação com identidade própria e preservação de versões e vínculos. O catálogo, o editor e a admissão privada já existentes continuam sendo a única implementação.

`AudioCopies` reutiliza `AudioUploads`. O servidor resolve origem e unidade por `AudioLibraryAccess`; IDs recebidos não concedem acesso. A versão exata, sua identidade e SHA-256 entram no digest idempotente. A revisão continua sendo precondição e não muda a identidade de uma operação já concluída.

Uma operação nova libera bytes somente por `AudioBytes`, com inspeção atual, autorização e hash verificados. Cria novo asset, versão 1 e blob independente, submetendo os bytes novamente ao scanner/decoder existentes. Revalida origem, permissão e revisão após a inspeção, dentro da transação nativa. Não copia um estado de aprovação ou altera vínculos da origem. Reexecução conhecida retorna o recibo já gravado sem liberar ou escanear os bytes novamente.

O editor existente fixa a versão apresentada, exige revisão explícita e mantém o UUID e a intenção após resposta incerta. Não oferece upload ou microfone no modo de cópia. O histórico nativo recebe evento `copy` com somente asset, versão e SHA da origem, além do escopo e ator autorizados já existentes. Não há URL pública, credencial ou chave de storage no recibo.

Não são incluídos: cópia de gravações telefônicas, alteração de permissões, publicação no PABX, TTS, exclusão de históricos ou duplicação em lote. Formatos legados que não passam pela admissão atual permanecem bloqueados; não há conversão implícita. As figuras completas continuam parciais.

Validação exigida: serviço e API autenticada, conta/unidade, CAS e revogação após inspeção, recibos/idempotência, rollback/auditoria, concorrência real, editor Vue e Chrome com CSS real em quatro combinações de viewport/tema. Testes locais com transporte substituído não substituem essa execução.
