# Banco Super Imobiliário — regras do modo simples

## Situação
A migração **`supabase/06-versao-consolidada.sql`** foi preparada no GitHub. **Ainda não foi executada no Supabase nem testada em uma partida real.** Os arquivos experimentais `04-banco-simples.sql` e `05-pagamentos-ao-banco.sql` foram substituídos: NÃO execute esses dois arquivos. O `index.html` atual ainda é o protótipo para um único aparelho; a interface multiplayer precisa ser conectada às novas funções.

## Jogo
- De 2 a 6 participantes, R$ 15.000 iniciais cada.
- Cada pessoa usa seu celular. Dados físicos, ordem dos jogadores e tabuleiro são controlados pela mesa, não pelo aplicativo.
- O anfitrião inicia a sala e o servidor sorteia um jogador como **banqueiro**. O banqueiro continua jogando com seu dinheiro pessoal separado do banco.
- O aplicativo mostra saldos, solicitações de aluguel e histórico; o frontend deverá atualizar automaticamente, inicialmente consultando o servidor a cada poucos segundos.

## Dinheiro
- Jogador: transferir a outro jogador; solicitar cobrança de aluguel, que o pagador aceita ou recusa; pagar ao banco informando valor e motivo; ver saldos.
- Banco é uma contraparte virtual, **não** a carteira pessoal do banqueiro e não tem saldo limitado nesta versão.
- Somente o banqueiro pode pagar bônus e notícias positivas pelo banco e creditar **R$ 2.000 individualmente** ao participante que passou pela saída. Ele escolhe a pessoa; o aplicativo não acompanha posições no tabuleiro.
- Operações usam chave única por clique para reduzir duplicações de requisição, validação de identidade e movimentação atômica no servidor.

## Hipotecas
- Cada jogador tem duas ações: **Hipotecar tudo** e **Hipotecar algumas coisas**. Em ambas, o próprio jogador descreve os bens e digita o valor total; o BANCO PAGA o valor à conta do jogador.
- O sistema não estima preços, não transfere propriedades automaticamente e não controla quitação ou juros. A descrição e o valor ficam registrados no histórico.
- **Atenção:** não há bloqueio automático de hipoteca repetida de um mesmo bem; o grupo deve conferir os bens físicos. Isso precisará de um cadastro obrigatório e de regras de resgate definidas se desejarmos impedir duplicação no futuro.

## Cadastro opcional
- Área **Meus imóveis**: cidade, nome opcional da propriedade, quantidade de casas e hotéis. Cada jogador cadastra, edita e exclui apenas registros próprios. Não precisa cadastrar nada para jogar.
- O servidor retorna ao usuário apenas seus próprios registros nesta primeira versão; os outros jogadores veem saldos e histórico financeiro. O cadastro não muda dinheiro, posse ou valor de hipoteca.

## Prisão
- Somente o banqueiro pode prender um jogador por **3 jogadas do próprio preso** e registrar manualmente uma jogada perdida por vez, de 3 para 2, 1 e 0. Em zero, o jogador é solto. Os eventos ficam registrados.
- O próprio preso pode pagar **R$ 500** ao banco e sair imediatamente, uma vez por prisão e com proteção contra reenvio da mesma operação. Se faltar saldo, a fiança é recusada.
- Correção de contagem de prisão não tem botão nesta etapa; se necessária, será uma melhoria com trilha de auditoria.

## Implantação
1. Os scripts de criação das tabelas (01), salas (02) e dados antigos (03) já foram executados pelo usuário. O script 06 desabilita o acesso dos usuários ao fluxo antigo de dados, sem apagar as tabelas ou saldos.
2. Abrir `supabase/06-versao-consolidada.sql`, copiar o arquivo inteiro e executar como uma única consulta no Supabase SQL Editor. O arquivo contém `BEGIN`/`COMMIT` para não deixar migração pela metade se houver erro.
3. A execução SQL ainda precisa ser confirmada e testada; **não anunciar o multiplayer como funcionando** antes de conectar o frontend, autenticação, URL e chave pública do projeto, e testar com dois celulares.
4. Nunca publicar senha do banco, token secreto ou chave `service_role` no GitHub. Somente a Project URL e chave publicável, quando necessária, podem ir ao código do frontend.
