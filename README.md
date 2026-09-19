# Banco Super Imobiliário — multiplayer simplificado

## Estado atual

O usuário confirmou `Success. No rows returned` ao executar as etapas SQL 01, 02, 03 e a versão consolidada `supabase/06-versao-consolidada.sql` no Supabase. **Não execute os rascunhos 04 e 05.** Os dados/turnos digitais da etapa 03 foram abandonados; a etapa 06 revoga seu acesso.

**Interface multiplayer:** [`jogar.html`](jogar.html). Criada e enviada ao GitHub com sintaxe JavaScript verificada localmente. Ela ainda exige URL do projeto e chave pública publishable/anon, GitHub Pages e testes reais com vários celulares. Não anunciar como pronta. **Abra `/jogar.html`, e não a raiz**: o `index.html` continua sendo a versão antiga de um único dispositivo. O protótipo intermediário `multiplayer.html` foi descartado.

## Regras

- Entre 2 e 6 jogadores, R$ 15.000 para cada. Dados, tabuleiro e turnos totalmente físicos.
- Criar sala e entrar pelo código; o anfitrião inicia e o banqueiro é sorteado entre os participantes.
- Saldos e histórico com atualização a cada 3,5 segundos.
- Jogadores podem transferir, cobrar aluguel com aceite do pagador, pagar ao banco, hipotecar tudo/algumas coisas por valor manual, pagar fiança de R$ 500 e manter cadastro opcional de imóveis, cidades, casas e hotéis.
- Banqueiro pode pagar jogadores pelo banco, dar R$ 2.000 individualmente a quem passou pelo início, prender por três jogadas e registrar cada jogada perdida.
- Conta pessoal do banqueiro separada do banco virtual. O inventário não avalia automaticamente bens nem bloqueia hipoteca repetida: conferência manual pelos participantes.

## Para testar

1. Obter no Supabase somente **Project URL** e **publishable key** em Project Settings / API Keys (ou Connect). Não compartilhar senha Postgres, `service_role`, `sb_secret_...` nem tokens privados.
2. A página `jogar.html` possui formulário para informar essas duas informações no dispositivo. Opcionalmente preencher suas constantes `PUBLIC` com URL e chave pública para evitar digitação em cada celular.
3. Ativar GitHub Pages via Settings → Pages → Deploy from branch → `main` → `/ (root)` e abrir a URL publicada terminada em `/jogar.html`.
4. Testar dois celulares e depois seis, incluindo autenticação, saldos, aluguel confirmado, banqueiro, prisão, fiança, hipoteca, reconexão e repetição de requisições antes de jogar de verdade.
5. Só substituir `index.html` após concluir os testes e revisar cache do service worker e manifesto.

**Importante:** valores monetários SQL estão em reais inteiros (`15000`, `2000`); a antiga interface `index.html` usa centavos e não pode acessar essas RPCs sem adaptação.

[Especificação detalhada](docs/regras-banco-simplificado.md) · [SQL consolidado](supabase/06-versao-consolidada.sql).