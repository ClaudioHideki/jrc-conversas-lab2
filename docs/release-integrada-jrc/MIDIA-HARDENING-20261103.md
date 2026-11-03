# Continuação LAB2 — custódia de arquivos, 03/11/2026

Branch preservada: codex/lab2-integral-20261102, base20e56104ec0f748b53da58edb1b639369fad0a1e. Código ainda em revisão no checkout; nenhuma destas migrations foi aplicada à produção.

## Defeitos reproduzidos e corrigidos

1. Dois scanners concorrentes: um clean antigo sobrescrevia infected novo. Teste real com PostgreSQL e barreiras:6asserções RED. Corrigido com scan_generation/token persistidos antes do I/O e conferidos no COMMIT; o resultado antigo falha com MEDIA_SCAN_CHANGED.
2. Colisão física: a chave candidata já ocupada era reutilizada. Agora a reserva é persistida e a ausência física verificada antes do primeiro PUT; colisões ficam KEEP e recebem nova geração/chave. Uma indisponibilidade mantém a obrigação para nova prévia, sem apagar bytes.
3. Mudança do destino: nomes iguais de storage apontando para outro root/bucket/endpoint podiam ser reutilizados/limpos. Fingerprint de destino imutável, excluindo credenciais rotativas, verificado na gravação e na recuperação.
4. Fila:100 falhas iniciais impediam chegar ao101º registro. checked_at é avançado nas falhas para nova rodada alcançar as demais reservas. O teste exige101registros realmente elegíveis.
5. Pós-rollback: enquanto a limpeza antiga aguardava I/O, uma nova importação podia gravar na mesma chave. RED comprovou replacement_applied nessa janela. Compensação agora usa o mesmo claim durável Account→Batch→Item→Media; gravação concorrente é recusada ou Blob já registrado preservado em KEEP.
6. SQL NULL: a CHECK anterior aceitava UNKNOWN. Teste INSERT direto sem identidade falhou em detectar restrição; migration205000 aditiva exige identidade não nula para estados ativos. Mantida204000; sua refatoração Ruby de estilo preserva o DDL funcional.
7. Contatos sem anexos: prévia fazia consulta à mídia por linha. RED com3contatos comprovou as consultas; verificação limitada aos adaptadores de anexos.
8. Recuperação antes da verificação física: causava CheckViolation interna. Agora retorna MEDIA_PREVIEW_REQUIRED e preserva a reserva.
9. UI: três estados novos apareciam vazios. RED3casos; mensagens localizadas na origem en, estados claros e ausência de ações de scan/limpeza sem elegibilidade.

## Validação final desta rodada

- Serviços de migração/mídia:65exemplos/0falhas/0pending,31.935s. Inclui SIGKILL real após PUT, com PostgreSQL vivo, callbacks de rollback ignorados e recuperação do órfão pelo ledger. Não comprova crash do host, PostgreSQL ou provider real.
- NICO após mídia:60exemplos/0falhas/0pending,62.071s. Não é homologação paga do provedor de IA ou do limite produtivo.
- Vue/parser de importação:11/11; ESLint2arquivos/0erros/0avisos.
- Ruby:11arquivos/0ocorrências, sem supressões novas para ocultar falhas.
- Editor nativo: artefato Broker ef5c5aea41b28a04b2f4e81cddca425145671ef4,216entradas commitadas/4saídas/0achados; hashes conferidos. Host Flow4/4. Não é build completo LAB2.

## Migrations e limites

203000 cria ledger;204000 adiciona identidade, ausência e geração do scanner;205000 reforça NULL-safe. Aplicadas somente ao banco local de laboratório. Down irreversível para não apagar evidência de propriedade. schema.rb permanece no prefixo202000, anterior à criação do ledger; não avançar essa versão sem incluir corretamente os guards SQL e testar schema+chain em banco novo. Nenhum dump/backup/restore foi executado.

Ainda pendentes: percurso físico deste importador com ActiveStorageS3/MinIO; teste frio do prefixo schema+203–205; integração completa de UI/rotas; suíte Rails completa, build completo e CI dos SHAs finais; checkpoint atômico LAB2 com as outras mudanças e revisão de compatibilidade para rollback do binário. Preservar as demais alterações e rotinas existentes. Não publicar esta candidata como conclusão integral.

## Evidências locais

- media-scan-concurrency-red-20261103.json — SHA256 5cd612637bee8c7bda7338f561d4a3ddb93bbf8267a9dd14254cd18533f5da2e
- media-final-fences-red-20261103.json — SHA256 050b11b4da8fb62ce404456dad1ac20544b9143776edeb52fcd0c2f6a90e1dd8
- media-nonmedia-queries-red-20261103.json — SHA256 5ff238328b4fd023cdff928dbed2abb697cc0cb61826a268977279bd5e3ce37b
- media-reserved-recovery-red-20261103.json — SHA256 c8f64daf8a5eb1fb6c7c6f4cfbbbedf27bfa804dd732833e95cd2fe9179fcc97
- media-verified-regression-20261103.json — SHA256 9e7bdfe517ae6888df30f34f34d1259b010600d38514d096b472ae4edebba2c7
- nico-after-media-regression-20261103.json — SHA256 522f1e25f664e8f091ee156aaf18a88899c17078891e63cd6015b179576ff3a3
- media-hardening-lint-clean-20261103.json — SHA256 a35a63708a1dd0a563da25fa54ae2f63b95bb13b5b5a1304c6bfe2f732b599b1
- media-ui-states-green-20261103.json — SHA256 e730cb00da0d93d371a55ef2ab2268bc807c36477a054d6e60b9ac6f44674578
- media-ui-eslint-20261103.json — SHA256 0071fbdceb10ecd551c7723763380f716f263faccc987aa26b15846e34a41cfc
