# Regras combinadas — banco digital simplificado

> Especificação funcional atualizada. Este documento NÃO instala funções no Supabase e NÃO transforma o `index.html` atual em multiplayer. **Não executar os arquivos SQL 04 e 05 até consolidar e revisar a versão final.**

## Sala e partida
- 2 a 6 jogadores, saldo inicial de R$ 15.000 cada, acessando pelo próprio celular.
- Tabuleiro, dados e ordem de jogo ficam fora do app, administrados manualmente pela mesa; nenhuma tela de lançamento de dados ou controle automático de turnos.
- Ao iniciar a partida, o sistema sorteia um participante para ser banqueiro; ele continua jogando normalmente, com saldo pessoal separado do banco.
- Todos consultam os saldos da sala e histórico de operações atualizado nos celulares.

## Banco (não é a conta pessoal do banqueiro)
- Entradas: pagamentos feitos por jogadores ao banco, incluindo compras, multas, notícias negativas e fiança. Dinheiro enviado ao banco NÃO é enviado ao banqueiro.
- Saídas: bônus, notícias positivas e salário de R$ 2.000 **somente** para o participante que passou pelo início. Pagamentos do banco não debitam o saldo pessoal do banqueiro.
- Em hipotecas, o banco PAGA o jogador e não recebe dele. Não confundir hipoteca com 'pagar ao banco'.
- Banco pode ser tratado como contraparte do histórico sem exigir controle de caixa finito, salvo decisão futura expressa.

## Operações de cada jogador
- Consultar saldos e histórico.
- Transferir para outro jogador: débito/crédito em uma única operação no servidor.
- Cobrar aluguel: o pagador confirma antes do débito.
- Pagar ao banco: selecionar valor e motivo; debitar apenas a própria conta.
- **Hipotecar**: apresentar duas opções, 'Hipotecar tudo' e 'Hipotecar algumas coisas'. Ambas são operações separadas de pagar ao banco e **creditam** a conta do jogador com dinheiro do banco.
  - 'Hipotecar algumas coisas': jogador seleciona ou descreve os bens a hipotecar (ex.: terreno, casa e/ou hotel) e **digita manualmente o valor total**; antes de confirmar, a tela exibe que o banco pagará esse valor ao jogador.
  - 'Hipotecar tudo': jogador indica que está hipotecando todos os bens elegíveis e confirma um valor total de hipoteca; **não calcular automaticamente** valores sem tabela de avaliação aprovada pelo grupo. Quando existir cadastro de bens, permitir consultar a lista sem exigir seu preenchimento.
  - Ambas registram no histórico modalidade, valor, jogador e descrição de bens se informada. Exigir valor positivo, confirmação e operação atômica; não inventar preço de casa/terreno/hotel nem regras de juros, resgate, devolução de propriedade ou perda de posse.
  - Cadastro de bens é opcional e não constitui prova automática de titularidade nem garantia de validação do valor da hipoteca. Evitar que o mesmo bem seja hipotecado novamente sem regra posterior de quitação/controle definida.
- Pagar fiança de R$ 500: somente o próprio jogador preso, debitando sua conta para o banco e libertando-o imediatamente, sem dupla cobrança.

## Registro opcional de bens (acessível a todos os jogadores)
- Adicionar uma área separada **'Meus imóveis'**, totalmente opcional; não bloquear início da partida nem transações se não houver cadastro.
- O próprio jogador pode cadastrar quantos registros de propriedades/cidades precisar, informando o **nome da cidade ou propriedade**, quantidade de **casas** e quantidade de **hotéis**; permitir zero em ambas, editar e excluir registros próprios. Uma mesma pessoa pode ter várias cidades/propriedades.
- Mostrar por jogador seus registros e um resumo de casas/hotéis; não atribuir valor financeiro automático ao cadastro e não alterar saldo ao registrar/editar/excluir.
- Acesso por sala: outros participantes podem consultar os registros para conferir o jogo; somente o autor modifica seus próprios bens; o banco não assume controle automático da posse.
- Se futuramente associar registros a hipotecas, guardar sinalização de 'hipotecado' e bloquear duplicação, somente após confirmação das regras de resgate e avaliação. Não supor que 'hipotecar tudo' converta quantidades em dinheiro automaticamente.

## Operações exclusivas do banqueiro
- Pagar jogadores em nome do banco: bônus e notícias positivas com motivo; não descontar sua conta pessoal.
- Crédito de passagem: escolher individualmente quem passou pelo início e dar exatamente R$ 2.000; proteger contra requisição repetida.
- Prender jogador: selecionar participante e marcar 3 jogadas desse participante sem jogar; prisão não movimenta dinheiro.
- Marcar manualmente uma jogada perdida por vez (3 → 2 → 1 → 0), soltando automaticamente ao zerar. Nunca contar jogadas dos demais; permitir correção auditada pelo banqueiro.

## Segurança e desenvolvimento
- Validar no servidor identidade de participantes, papeis, saldos e mudanças; clientes não editam tabelas financeiras diretamente. Registrar operações financeiras atômicas e impedir duplicação por reenvio.
- Cada jogador só altera os próprios registros opcionais; verificação de dono e partida precisa ocorrer no servidor.
- **Estado atual:** os arquivos 04 e 05 existentes NÃO contemplam integralmente hipotecas, inventário, prisão e fiança; NÃO executá-los como se fossem a versão consolidada. O `index.html` do GitHub ainda é a versão local, não o frontend multiplayer. A próxima etapa é gerar código consolidado, revisar e testar antes de solicitar execução no Supabase.
