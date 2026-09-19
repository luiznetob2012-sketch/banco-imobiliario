# Banco Super Imobiliário

## Situação atual

Este repositório contém a versão inicial de banco em **um único navegador**, sem sincronização entre celulares. **Ainda não está pronto para partidas multiplayer.** Não confunda a versão anterior (`index.html`) com a futura versão conectada.

## Próxima etapa: multiplayer

Vamos usar GitHub Pages (interface) + Supabase (banco compartilhado). O projeto multiplayer precisa de `index.html`, `style.css`, `app.js`, `config.js`, `manifest.webmanifest`, `sw.js` e ícones, além da execução de um esquema SQL no Supabase. Esses novos arquivos ainda não foram publicados aqui.

1. Crie um projeto em https://supabase.com/dashboard.
2. Habilite **Authentication → Anonymous Sign-Ins** para que cada participante tenha identidade própria sem e-mail.
3. Depois de disponibilizado o SQL completo, execute-o no **SQL Editor** do Supabase; as regras financeiras e de acesso devem ficar no servidor.
4. O arquivo `config.js` conterá apenas a URL do projeto e uma chave pública **publishable/anon**. **Não inclua senhas, service_role, secret key ou tokens privados no GitHub.**
5. Com todos os arquivos devidamente enviados e o Supabase configurado, configure **Settings → Pages → Deploy from a branch → main → / (root)**.

## Regras combinadas

- Até seis jogadores, cada um começa com R$ 15.000.
- Cada jogador opera no próprio celular; cobranças de aluguel precisam de confirmação do pagador.
- **A ordem de entrada não determina os turnos.** O anfitrião encerra as inscrições; cada jogador registra a soma de dois dados físicos; apenas após todos concluírem os lançamentos e desempates a ordem é revelada.
- Prisão: três oportunidades sem jogar ou R$ 500 de fiança.

Os arquivos precisam ser adicionados ao repositório e a integração precisa ser testada antes de considerar o multiplayer funcional.
