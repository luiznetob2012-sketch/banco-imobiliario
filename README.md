# Banco Super Imobiliário — multiplayer simplificado

## Situação da implantação

O usuário informou que executou com sucesso as etapas SQL 01, 02, 03, 06 e 07 no Supabase e abriu o aplicativo em dois aparelhos. Não execute os rascunhos SQL 04 e 05. A escolha do banqueiro agora é feita pelo grupo e registrada pelo anfitrião antes de iniciar; não há sorteio. O multiplayer ainda precisa de validação completa de todas as operações.

**Entrada recomendada:** [`iniciar.html`](iniciar.html), que aponta para [`jogar-v4.html`](jogar-v4.html). Não abra `jogar.html` (antigo) nem `jogar-v2.html` ou `jogar-v3.html` (efeitos de áudio antigos). `index.html` é o protótipo original de um único aparelho.

## Som de dinheiro V4

- A V4 substitui os bipes/oscilladores das versões anteriores por **um arquivo MP3 de gravação de caixa registradora**. Veja o [arquivo responsável](som-dinheiro-real-v4.js) e os [créditos e licenças](docs/creditos-audio.md).
- Cada usuário toca em **Ativar som de dinheiro** no próprio aparelho; o botão toca imediatamente uma amostra para validar a reprodução no celular. O botão **Ouvir som real** também permite um teste manual. Se o áudio não começar, o site mostra erro em vez de afirmar que funcionou.
- O histórico de até 40 transações é consultado a cada ~3,5 segundos com a página ativa. Cada nova movimentação concluída detectada na sala gera um efeito; cobranças ainda pendentes não geram som. Não há pop-up sonoro para cada crédito.
- Não são notificações push. A reprodução sem gesto prévio, com página em segundo plano, tela bloqueada, volume zero ou modo silencioso pode ser bloqueada pelo dispositivo; portanto não afirmar compatibilidade universal sem teste real em Android e iPhone.
- O MP3 vem de uma fonte externa no repositório SoundMonster; exige rede. Se necessário futuramente, hospedar uma cópia licenciada no próprio repositório para remover dependência externa.

## Regras e testes

- De 2 a 6 jogadores, R$ 15.000 por jogador; dados, tabuleiro e turnos são físicos.
- O anfitrião escolhe um dos jogadores para ser banqueiro antes de iniciar. A conta pessoal do banqueiro é separada do banco virtual.
- Jogadores transferem, cobram aluguel com aceite, pagam ao banco, hipotecam tudo ou parcialmente por valores manuais, pagam fiança de R$ 500 quando presos e podem cadastrar imóveis opcionalmente.
- O banqueiro paga bônus e R$ 2.000 individualmente para quem passou pelo início, administra prisão de três jogadas com contagem manual.
- Para testar o áudio: atualizar ambos os celulares para `jogar-v4.html`, tocar em Ativar som de dinheiro e confirmar se a amostra toca; com os dois na mesma sala, transferir R$ 100 e conferir saldos, histórico e áudio nos dois aparelhos.

Somente URL e chave **publishable** públicas do Supabase estão no frontend; jamais adicionar `service_role`, `sb_secret_` ou senhas. As autorizações e as alterações financeiras são responsabilidade das RPCs protegidas do Supabase.