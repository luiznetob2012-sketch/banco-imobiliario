# Banco Super Imobiliário — multiplayer simplificado

## Situação da implantação

O usuário executou com sucesso as etapas SQL 01, 02, 03 e 06. Não execute os antigos rascunhos 04 e 05. O jogo já abriu em dois aparelhos, mas ainda precisa de testes completos de movimentações.

**Nova alteração solicitada:** o banqueiro deixa de ser sorteado. O grupo decide quem será, e o anfitrião seleciona essa pessoa antes de iniciar o jogo. Cada celular ganha botão opcional para ativar/desativar um aviso sonoro quando receber dinheiro. Não há garantia de som em segundo plano, tela bloqueada ou sem uma ativação prévia pelo usuário.

- SQL NOVO: [`supabase/07-banqueiro-escolhido-e-creditos.sql`](supabase/07-banqueiro-escolhido-e-creditos.sql). Executar uma vez DEPOIS de 06; substitui a antiga função de sorteio, cria escolha controlada pelo anfitrião e consulta protegida de créditos.
- Frontend v2 preparado: [`jogar-v2.html`](jogar-v2.html) e [`app-v2.js`](app-v2.js). O código novo mantém sala, saldos, operações, aluguel, imóveis, prisão e fiança e adiciona escolha do banqueiro e avisos de créditos.
- **Não migrar para v2 antes de executar a etapa 07.** O endereço de entrada [`iniciar.html`](iniciar.html) continua apontando para a interface anterior até a etapa 07 ser confirmada. Não substituir `index.html` antigo de um único aparelho.

## Regras

- De 2 a 6 jogadores, cada um começa com R$ 15.000. Dados, tabuleiro e turnos são físicos.
- O grupo escolhe o banqueiro; somente o anfitrião confirma essa escolha no aplicativo e inicia a partida. O banqueiro também é jogador, com saldo pessoal separado do banco.
- Saldos e histórico são atualizados aproximadamente a cada 3,5 segundos com a página em primeiro plano.
- Jogadores transferem, cobram aluguel com confirmação do pagador, pagam ao banco, hipotecam tudo ou algumas coisas com valores manuais, pagam fiança de R$ 500 se presos e registram opcionalmente cidades, casas e hotéis.
- Banqueiro paga bônus/notícias e salário individual de R$ 2.000, prende por 3 jogadas e registra jogadas perdidas manualmente.
- Sons são opt-in por dispositivo e limitados às notificações de créditos concluídos em favor do usuário; não são push notifications e podem não tocar quando o navegador estiver em segundo plano.
- Valores financeiros são inteiros em reais. Hipotecas não avaliam bens automaticamente; o grupo confere as cartas e os registros físicos.

## Para continuar

1. Executar apenas o SQL 07 e verificar `Success. No rows returned`.
2. Apontar `iniciar.html` para `jogar-v2.html` quando o SQL estiver instalado; testar numa **sala nova**, pois partidas iniciadas anteriormente já tiveram banqueiro atribuído.
3. Recarregar os celulares. Escolher o banqueiro antes de iniciar; cada pessoa toca em **Ativar som** no seu próprio aparelho e mantém a página aberta.
4. Testar envio de R$ 100 entre dois aparelhos e recebimento do som; revisar aluguel, bônus, operações de prisão e reconexão.

Nunca publicar senhas, `service_role` nem `sb_secret_`. O frontend contém somente URL e publishable key públicas, e a autorização financeira deve permanecer nas funções protegidas do Supabase.
