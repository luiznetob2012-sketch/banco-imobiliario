# Regras aprovadas — banco digital simplificado

> Especificação funcional. Este documento NÃO instala funções no Supabase e NÃO transforma o `index.html` atual em multiplayer. **Não executar os arquivos SQL 04 e 05 até consolidar e revisar a versão final.**

## Sala e partida
- 2 a 6 jogadores, saldo inicial de R$ 15.000 cada, acessando pelo próprio celular.
- Tabuleiro, dados e ordem de jogo ficam fora do app, administrados manualmente pela mesa; nenhuma tela de lançamento de dados ou controle automático dos turnos.
- Ao iniciar a partida, o sistema sorteia **um jogador** para ser banqueiro; o banqueiro também joga normalmente, com saldo pessoal separado do banco.
- Todos veem os saldos da sala e o histórico de transações atualizado nos seus celulares.

## Banco (não é a conta pessoal do banqueiro)
- Entradas: pagamentos feitos por jogadores ao banco (por exemplo, compra, multas ou notícias negativas, conforme carta).
- Saídas operadas pelo banqueiro: pagamentos de bônus e notícias positivas e salário **de R$ 2.000 apenas ao jogador que passou pela linha de início**, mediante seleção individual do beneficiário.
- Não debitar o saldo pessoal do banqueiro ao pagar em nome do banco.

## Operações de cada jogador
- Consultar saldos e histórico.
- Transferir valor para outro jogador, debitando uma conta e creditando a outra numa única operação validada no servidor.
- Cobrar aluguel de outro jogador; pagador confirma a cobrança.
- Pagar ao banco com valor e motivo; abate somente o saldo do pagador.
- **Hipotecar tudo ao banco**: opção visível aos jogadores, mas a regra de avaliação, o valor a creditar e o tratamento dos bens ainda precisam de confirmação. Não publicar uma implementação que invente os valores ou transfira dinheiro no sentido errado.
- **Pagar fiança — R$ 500**: aparece quando o próprio jogador está preso; ele confirma o pagamento ao banco, seu saldo diminui R$ 500, a prisão termina imediatamente e a operação é registrada no histórico. Validar saldo e impedir segundo pagamento pela mesma prisão.

## Operações exclusivas do banqueiro
- Pagar jogadores em nome do banco (bônus e notícias positivas; informar motivo).
- Liberar salário de passagem: selecionar individualmente quem passou pelo início e creditar exatamente R$ 2.000. Não premiar todos automaticamente; proteger contra repetição de requisição.
- **Prender jogador**: selecionar participante e aplicar prisão de **três jogadas desse participante**, sem alterar o saldo. Exibir estado `Preso — faltam 3 jogadas` a todos.
- **Atualizar a contagem da prisão manualmente** quando a jogada do preso for perdida (3 → 2 → 1 → 0); ao zerar, libertar automaticamente. Não usar cronômetro nem contar jogadas dos demais jogadores. O banqueiro pode corrigir um erro de contagem com registro no histórico.

## Segurança e consistência
- Ações exclusivas do banqueiro devem verificar sua identidade no servidor; outras pessoas não podem liberar bônus nem prender terceiros.
- Fiança só pode ser paga pelo próprio preso e não deve ser debitada duas vezes em cliques repetidos.
- Cada movimento financeiro deve ser atômico, validado quanto a saldo e registrado. Os jogadores não recebem permissão para editar as tabelas de saldo diretamente.
- Revisar as funções SQL dos passos 04 e 05 antes de executá-las em conjunto com prisão, fiança e hipoteca. O frontend atual é de um único navegador; o multiplayer ainda precisa ser construído e testado.
