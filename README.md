# Banco Super Imobiliário — banco simples multiplayer

## Status real

O `index.html` que está na raiz é a versão antiga **de um único aparelho**. O multiplayer **ainda não está pronto nem conectado ao Supabase**. Não use essa interface para jogar em seis celulares simultaneamente.

No Supabase, foram executadas pelo usuário as etapas SQL das tabelas (etapa 1), salas (`supabase/02-salas.sql`) e dados/ordem (`supabase/03-dados-e-ordem.sql`). O grupo mudou os requisitos e não quer mais registrar dados nem controlar turnos no aplicativo. Por isso, a **nova etapa** é `supabase/04-banco-simples.sql`, a ser executada pelo usuário no SQL Editor. As funções antigas de dados digitais serão desautorizadas por essa migração; nenhuma tabela nem registro existente serão apagados.

## Regras atuais

- Até **6 jogadores**, cada um com **R$ 15.000** no início.
- Os dados, a ordem e os turnos são gerenciados **fora do aplicativo**, na mesa. Nada de formulário de dados ou classificação.
- Depois que todos entram na sala, o anfitrião toca em **Iniciar**; o servidor sorteia **um banqueiro entre os participantes**. Ele também joga normalmente.
- Painel: saldo de todos, banco responsável, cobranças pendentes, histórico de movimentações.
- Jogador pode **enviar dinheiro** do próprio saldo ou **cobrar aluguel** de outro; o pagamento da cobrança só é efetivado após confirmação do pagador.
- O banqueiro pode registrar bônus, notícias, multas e créditos/debitos do banco, além das próprias transações como jogador.
- **Passou pela partida:** somente o banqueiro pode tocar em **+ R$ 2.000** para o jogador escolhido. Não existe pagamento em massa. Cada passagem é um evento diferente; o mesmo clique retransmitido com a mesma chave UUID não duplica crédito.
- Tabuleiro, cartas, propriedade, prisão e fiança continuam inicialmente sob controle físico do grupo. Podemos adicionar atalhos bancários depois, sem tornar a interface complexa.

## Para continuar

1. Execute `supabase/04-banco-simples.sql` no SQL Editor **uma única vez** e confira o resultado. O SQL ainda não foi validado em um Supabase de testes: em caso de erro, informe a mensagem e não tente consertar às cegas.
2. Criar nova interface conectada com a URL do projeto Supabase e sua chave **publishable/anon**, nunca a senha Postgres, `service_role` ou qualquer chave secreta.
3. Implementar atualização automática do painel (consultando a função `bi_estado_simples` periodicamente ou um canal Realtime protegido), testes com dois celulares e, depois, com até seis.
4. Publicar via GitHub Pages quando a interface multiplayer estiver pronta.

**Importante:** no SQL atual os valores são inteiros em reais (ex.: `15000` e `2000`). O frontend antigo opera em centavos e **não pode ser reaproveitado para gravar saldos no Supabase sem adaptação**.
