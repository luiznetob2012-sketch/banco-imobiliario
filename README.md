# Banco Super Imobiliário — modo simples multiplayer

## Estado atual

O `index.html` da raiz ainda é um protótipo para **um aparelho**; não há sincronização real entre celulares nesta interface. Não anunciar o multiplayer como pronto. O usuário já executou as etapas SQL 01 (tabelas), 02 (salas) e 03 (dados antigos), mas o grupo decidiu não usar dados nem turnos digitais.

**ÚNICA próxima migração: [`supabase/06-versao-consolidada.sql`](supabase/06-versao-consolidada.sql).** Ela inclui as funcionalidades combinadas e desativa as funções de dados digitais, sem excluir saldos. Os scripts 04 e 05 eram rascunhos e **não devem ser executados**. A etapa 06 está no GitHub, mas ainda não foi executada ou testada no Supabase do usuário.

## Regras do banco

- Entre 2 e 6 jogadores com R$ 15.000 iniciais cada. Cada um usa seu celular; dados, tabuleiro e ordem são físicos.
- Ao iniciar a partida, o anfitrião aciona um sorteio de banqueiro entre todos os participantes. O banqueiro continua com sua conta pessoal separada do banco virtual.
- Todos veem saldos e histórico. Cada jogador pode transferir, solicitar aluguel com confirmação do pagador, pagar ao banco, hipotecar tudo ou algumas coisas (descrevendo bens e digitando o valor), pagar fiança de R$ 500 caso esteja preso e cadastrar opcionalmente cidade, imóvel, casas e hotéis.
- Banqueiro pode pagar bônus/notícias positivas, conceder individualmente R$ 2.000 ao jogador que passou pelo início e controlar prisão por 3 jogadas do preso (contagem manual).
- Hipoteca paga do banco para o jogador; cadastro de imóveis não altera saldos. O sistema não avalia imóveis nem impede automaticamente hipotecas repetidas sobre o mesmo bem: a mesa confere as cartas físicas.

Leia a [especificação completa](docs/regras-banco-simplificado.md).

## Próximas ações

1. Abrir `supabase/06-versao-consolidada.sql`, copiar seu conteúdo inteiro e executar em uma única consulta no Supabase SQL Editor. Confirmar o resultado; se houver erro, trazer a mensagem exata.
2. Construir nova interface com autenticação anônima e chamadas às funções `bi_criar_sala`, `bi_entrar_sala`, `bi_iniciar_partida`, `bi_painel`, `bi_operar`, `bi_responder_aluguel`, `bi_controlar_prisao`, `bi_pagar_fianca`, `bi_salvar_imovel`, `bi_excluir_imovel`.
3. Conectar frontend com **Project URL e chave publishable/anon**, nunca senha do banco, `service_role` ou chave secreta. Atualizar painel automaticamente via consultas periódicas; as tabelas seguem protegidas e sem SELECT direto.
4. Testar autenticação, permissões, operações concorrentes e reconexão em 2 celulares e depois em até 6. Só então publicar o novo frontend via GitHub Pages.

**Valores do SQL são inteiros em reais** (`15000` e `2000`), diferentemente do frontend antigo, que usa centavos. Não conectar o código antigo às RPCs sem ajustar unidades.
