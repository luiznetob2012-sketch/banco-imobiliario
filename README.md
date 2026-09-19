# Banco Super Imobiliário — multiplayer simplificado

## Situação em 18/09/2026

O usuário confirmou `Success. No rows returned` após executar as etapas 01, 02, 03 e 06 no Supabase. Os scripts experimentais **04 e 05 não devem ser executados**. Os dados/turnos digitais da etapa 03 foram abandonados; o script 06 revogou acesso às funções antigas.

**Nova interface:** [`multiplayer.html`](multiplayer.html). Foi criada e enviada ao GitHub, porém ainda exige configuração da Project URL e chave pública publishable/anon do Supabase, habilitação do GitHub Pages e testes práticos. **Ainda não anunciar como app pronto ou testado em vários celulares.** O `index.html` permanece a versão antiga, local e incompatível com multiplayer.

## Regras

- De dois a seis jogadores com R$ 15.000 iniciais; dados, ordem e tabuleiro físicos.
- O anfitrião cria a sala, jogadores entram por código e o sistema sorteia o banqueiro ao iniciar a partida.
- Saldos e histórico consultados individualmente pelo celular; atualização periódica a cada 3,5 s.
- Jogadores: transferência pessoal, cobrança de aluguel confirmada pelo pagador, pagamento ao banco, hipoteca total/parcial com valor declarado manualmente, fiança de R$ 500 quando preso, cadastro opcional de cidade/propriedade e casas/hotéis.
- Banqueiro: pagamentos em nome do banco, crédito individual de R$ 2.000 a quem passou pelo início, prisão por três jogadas e marcação manual de cada jogada perdida.
- O banco é contraparte virtual e NÃO é a conta pessoal do banqueiro. Cadastro de bens não avalia automaticamente nem bloqueia hipotecas repetidas: conferir esses casos na mesa.

## Próximos passos

1. No painel Supabase, copiar **Project URL** e **publishable key** em Project Settings / API Keys ou Connect. Nunca compartilhar nem publicar `service_role`, `sb_secret_...`, senha Postgres ou tokens privados.
2. Preencher as duas constantes públicas `PUBLIC_CONFIG` em `multiplayer.html` (ou usar o formulário de conexão por dispositivo sem publicar valores). Apenas a chave pública deve aparecer no frontend.
3. Ativar GitHub Pages no repositório, branch `main`, diretório `/ (root)`. Abrir a página `/multiplayer.html`, **não a raiz/index.html**, para testes.
4. Testar a autenticação anônima, 2 celulares e depois até 6, inclusive segurança, saldo insuficiente, confirmação de aluguel, deduplicação, reconexão e acesso exclusivo do banqueiro. Verificar compatibilidade do CDN Supabase no navegador.
5. Após aprovação prática, substituir a versão antiga do index e revisar cache do service worker/manifest.

Valores monetários do SQL estão em **reais inteiros** (`15000`, `2000`), diferentes do `index.html` antigo que usa centavos. Não reutilizar sua lógica financeira sem conversão.

Especificação funcional: [`docs/regras-banco-simplificado.md`](docs/regras-banco-simplificado.md). Migração instalada conforme confirmação do usuário: [`supabase/06-versao-consolidada.sql`](supabase/06-versao-consolidada.sql).