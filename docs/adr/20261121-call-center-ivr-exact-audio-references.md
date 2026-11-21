# URA local: referência exata de áudio institucional

Status: implementação incremental preparada; validação nativa e Chrome deste incremento pendentes.

As figuras 5, 6 e 16 exigem reutilizar a biblioteca institucional nos fluxos de URA. O catálogo e o editor local já existem. O contrato PABX de publicação, codecs, comandos e ACKs continua indisponível; este incremento não cria esse contrato nem representa aplicação no fornecedor.

O esquema local 1 e seus snapshots permanecem intactos. A seleção explícita no menu promove o documento ao esquema interno 2, com `audio_reference` contendo somente os identificadores textuais do áudio e da versão e seu SHA-256. A ausência do vínculo continua permitida. Nada é convertido automaticamente para a versão mais recente da biblioteca. Importação, edição, exportação, histórico, simulação e remoção explícita usam o editor existente.

O servidor reautoriza conta, membro, usuário, permissão nativa `configure` e cobertura corporativa da unidade a cada operação. A permissão de revisão do Nico não concede esse acesso. O filtro de referências resolve no máximo 128 identidades por consulta em lote, confere a relação áudio/versão/unidade/conta, o hash imutável e a inspeção técnica atual. Uma inspeção antiga aprovada não substitui uma observação atual indisponível. A conferência de metadados não afirma que os bytes estejam disponíveis; a prévia reutiliza o endpoint autenticado que lê e confere os bytes e seu hash novamente.

A gravação mantém o lock nativo de autoridade antes dos locks de unidade/rascunho, revisão otimista, transação, idempotência e histórico imutável. O recibo de auditoria acrescenta apenas as identidades exatas validadas, hash e ID da observação, omitindo nome, definição, bytes, paths e URLs. Arquivar preserva a definição existente e continua possível quando a verificação atual do áudio ficou indisponível. Repetir o mesmo recibo não cria uma nova validação fictícia nem uma nova versão; toda repetição exige autoridade atual.

O seletor é parte do menu da URA e consulta as APIs da biblioteca, com busca e paginação de 20 itens. Nenhum áudio ou versão é escolhido automaticamente. O usuário pode conferir a prévia existente antes da confirmação. A troca de unidade limpa vínculos de áudio e filas no novo rascunho; respostas atrasadas e perda de acesso não substituem o contexto atual. Um vínculo salvo indisponível fica explicitamente sinalizado até revisão ou remoção pelo usuário.

Nenhuma migration, gem, pacote de mídia ou nova permissão foi necessária para este incremento. As 11 migrations e os SQLs históricos permanecem byte a byte preservados. O catálogo continua privado por unidade. Não há execução no PABX, contagem inventada de usos operacionais, exclusão de versões, síntese externa do Nico ou novo cadastro paralelo.

Critérios preparados: esquema 1 preservado; esquema 2 estrito; gravação e recarga reais; exportação/histórico; revisão e idempotência; falha de auditoria atômica; inspeção indisponível; versão nova sem redirecionamento; conta/unidade/perfil negados; consulta com 127 menus e oito versões realmente inspecionadas; prévia autenticada; remoção explícita; desktop/celular e claro/escuro. Os testes preparados não são resultados de aprovação. O relatório de execução deverá identificar o SHA produtor e os artefatos.

As 23 figuras permanecem abertas: os quatro destinos completos de áudio, usos e publicação operacional, exclusão segura, waveform e síntese externa, bem como a correção humana completa da análise do Nico, não são declarados concluídos por este vínculo local.
