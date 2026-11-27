# Campanhas do GoPure no JRC Conversas

**Estado** — Aceita
**Data** — 27 de novembro de 2026

## Contexto

O arquivo validado do GoPure corresponde ao commit `543937c6ffd8`. O JRC Conversas parte de `b2aaf1b4` e já tem filtros do Cadastro Mestre, controles de aprovação e proteção contra duplicidade no Broker.

## Decisão

Integrar o assistente, listas CSV e salvas, seleção confirmada de destinatários, templates Meta, janelas de envio, exclusão e relatório de recibos. Preservar os filtros e as permissões do JRC. A sincronização de templates do módulo usa a API Cloud oficial e mantém o catálogo anterior se qualquer página falhar. A seleção usa uma assinatura do público e referências da própria conta. A revisão guarda a configuração aprovada e a definição do template.

## Validação e publicação

O banco descartável testa a instalação das migrações e as suítes Rails e Vue usam dados sintéticos. O workflow de imagem exige o resultado de Campanhas sobre o SHA exato, junto aos gates do produto. A publicação usa somente a tag imutável da branch com o mesmo SHA da main. A imagem anterior permanece disponível por digest. A implantação e o aceite com envios reais ficam fora dessa publicação.
