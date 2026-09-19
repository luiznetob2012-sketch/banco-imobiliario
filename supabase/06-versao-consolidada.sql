-- BANCO SUPER IMOBILIARIO — VERSAO CONSOLIDADA (ETAPA 06)
-- Executar UMA VEZ apos as etapas 01 (tabelas), 02 (salas) e 03 (dados).
-- NAO executar os arquivos experimentais 04 e 05: este arquivo os substitui.
-- Esta migracao nao exclui jogadores, saldos nem transacoes existentes.
-- IMPORTANTE: o frontend multiplayer ainda precisa ser construido e conectado.
-- Moeda: reais inteiros (15000 = R$ 15.000). O banco e virtual, sem saldo limitado.
BEGIN;

ALTER TABLE public.bi_partidas ADD COLUMN IF NOT EXISTS banqueiro_id uuid;
ALTER TABLE public.bi_transacoes ADD COLUMN IF NOT EXISTS chave_operacao uuid;
CREATE UNIQUE INDEX IF NOT EXISTS bi_transacoes_chave_unica
  ON public.bi_transacoes(partida_id, chave_operacao)
  WHERE chave_operacao IS NOT NULL;

-- Aceitar tambem operacoes de pagamento ao banco e hipoteca no historico.
ALTER TABLE public.bi_transacoes DROP CONSTRAINT IF EXISTS bi_transacoes_tipo_check;
ALTER TABLE public.bi_transacoes ADD CONSTRAINT bi_transacoes_tipo_check
  CHECK (tipo IN ('transferencia','aluguel','compra','noticia','multa',
                 'fianca','bonus','ajuste','banco','hipoteca'));

-- Cadastro OPCIONAL. Uma hipoteca financeira nao altera automaticamente o cadastro:
-- o usuario pode editar seus bens; nao criamos uma avaliacao ficticia de cartas.
CREATE TABLE IF NOT EXISTS public.bi_inventario (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partida_id uuid NOT NULL REFERENCES public.bi_partidas(id) ON DELETE CASCADE,
  jogador_id uuid NOT NULL,
  cidade varchar(100) NOT NULL CHECK (length(btrim(cidade)) > 0),
  propriedade varchar(100) NOT NULL DEFAULT '',
  casas integer NOT NULL DEFAULT 0 CHECK (casas BETWEEN 0 AND 99),
  hoteis integer NOT NULL DEFAULT 0 CHECK (hoteis BETWEEN 0 AND 99),
  criada_em timestamptz NOT NULL DEFAULT now(),
  atualizada_em timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (partida_id,jogador_id)
    REFERENCES public.bi_jogadores(partida_id,id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS bi_inventario_jogador_idx
  ON public.bi_inventario(partida_id,jogador_id);

CREATE TABLE IF NOT EXISTS public.bi_eventos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partida_id uuid NOT NULL REFERENCES public.bi_partidas(id) ON DELETE CASCADE,
  autor_usuario_id uuid NOT NULL REFERENCES auth.users(id),
  jogador_id uuid NOT NULL,
  tipo text NOT NULL CHECK (tipo IN ('prender','perder_jogada','soltar')),
  descricao text NOT NULL,
  criada_em timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (partida_id,jogador_id)
    REFERENCES public.bi_jogadores(partida_id,id)
);
CREATE INDEX IF NOT EXISTS bi_eventos_partida_idx
  ON public.bi_eventos(partida_id,criada_em DESC);
ALTER TABLE public.bi_inventario ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bi_eventos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.bi_inventario, public.bi_eventos
  FROM PUBLIC, anon, authenticated;

-- Remover acesso aos antigos dados digitais; nunca mais controlaremos turnos aqui.
REVOKE ALL ON FUNCTION public.bi_iniciar_dados(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_lancar_dados(uuid,integer,integer)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_estado_sala(uuid) FROM PUBLIC,anon,authenticated;

-- Se os scripts experimentais 04/05 foram executados por engano, retirar o acesso
-- a todas as RPCs anteriores; as novas abaixo formam um conjunto consistente.
DO $revogar$
DECLARE v_assinatura text;
BEGIN
  FOREACH v_assinatura IN ARRAY ARRAY[
    'public.bi_iniciar_simples(uuid)',
    'public.bi_estado_simples(uuid)',
    'public.bi_transferir_simples(uuid,uuid,bigint,text)',
    'public.bi_cobrar_simples(uuid,uuid,bigint,text)',
    'public.bi_responder_cobranca(uuid,boolean)',
    'public.bi_bonus_passagem(uuid,uuid,uuid)',
    'public.bi_movimento_banco(uuid,uuid,bigint,text)',
    'public.bi_pagar_banco(uuid,bigint,text,uuid)'
  ] LOOP
    IF pg_catalog.to_regprocedure(v_assinatura) IS NOT NULL THEN
      EXECUTE 'REVOKE ALL ON FUNCTION ' || v_assinatura ||
              ' FROM PUBLIC,anon,authenticated';
    END IF;
  END LOOP;
END;
$revogar$;

-- 1. Iniciar jogo: so o anfitriao, sorteio entre TODOS os jogadores.
CREATE OR REPLACE FUNCTION public.bi_iniciar_partida(p_partida uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE;
        v_total integer; v_banqueiro uuid; v_nome text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sala nao encontrada.'; END IF;
  IF v_sala.anfitriao_id <> auth.uid() THEN
    RAISE EXCEPTION 'Somente o anfitriao inicia a partida.'; END IF;
  IF v_sala.status <> 'aguardando' THEN
    RAISE EXCEPTION 'A partida ja foi iniciada.'; END IF;
  SELECT count(*) INTO v_total FROM public.bi_jogadores WHERE partida_id=p_partida;
  IF v_total < 2 OR v_total > v_sala.max_jogadores THEN
    RAISE EXCEPTION 'Sao necessarios de 2 a % jogadores.',v_sala.max_jogadores;
  END IF;
  SELECT id,nome INTO v_banqueiro,v_nome FROM public.bi_jogadores
    WHERE partida_id=p_partida ORDER BY pg_catalog.random() LIMIT 1;
  UPDATE public.bi_partidas SET status='jogando', banqueiro_id=v_banqueiro,
    ordem_revelada=false WHERE id=p_partida;
  RETURN jsonb_build_object('status','jogando','banqueiro_id',v_banqueiro,
    'banqueiro_nome',v_nome,'total_jogadores',v_total);
END;
$$;

-- 2. Consulta segura pelo participante. Tela atualiza a cada poucos segundos;
-- nao requer SELECT nas tabelas e nao revela ordem, dados ou credenciais.
CREATE OR REPLACE FUNCTION public.bi_painel(p_partida uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_eu uuid;
        v_jogadores jsonb; v_cobrancas jsonb; v_historico jsonb;
        v_bens jsonb; v_eventos jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sala nao encontrada.'; END IF;
  SELECT id INTO v_eu FROM public.bi_jogadores
    WHERE partida_id=p_partida AND usuario_id=auth.uid();
  IF v_eu IS NULL THEN RAISE EXCEPTION 'Voce nao participa desta partida.'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',j.id,'nome',j.nome,'saldo',j.saldo,
    'banqueiro',j.id=v_sala.banqueiro_id,
    'preso',j.preso,'jogadas_restantes',j.turnos_prisao)
    ORDER BY j.posicao_entrada),'[]'::jsonb) INTO v_jogadores
  FROM public.bi_jogadores j WHERE j.partida_id=p_partida;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'valor',t.valor,'motivo',t.descricao,'de',c.nome,
    'criada_em',t.criada_em) ORDER BY t.criada_em),'[]'::jsonb)
  INTO v_cobrancas FROM public.bi_transacoes t
  JOIN public.bi_jogadores c ON c.id=t.recebedor_id
  WHERE t.partida_id=p_partida AND t.pagador_id=v_eu AND t.status='pendente'
    AND t.tipo='aluguel';
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'tipo',t.tipo,'status',t.status,'valor',t.valor,
    'descricao',t.descricao,'de',coalesce(p.nome,'Banco'),
    'para',coalesce(r.nome,'Banco'),'criada_em',t.criada_em)
    ORDER BY t.criada_em DESC),'[]'::jsonb) INTO v_historico
  FROM (SELECT * FROM public.bi_transacoes WHERE partida_id=p_partida
        ORDER BY criada_em DESC,id DESC LIMIT 40) t
  LEFT JOIN public.bi_jogadores p ON p.id=t.pagador_id
  LEFT JOIN public.bi_jogadores r ON r.id=t.recebedor_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',i.id,'cidade',i.cidade,'propriedade',i.propriedade,
    'casas',i.casas,'hoteis',i.hoteis)
    ORDER BY i.cidade,i.propriedade),'[]'::jsonb) INTO v_bens
  FROM public.bi_inventario i WHERE i.partida_id=p_partida AND i.jogador_id=v_eu;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'tipo',e.tipo,'descricao',e.descricao,'criada_em',e.criada_em)
    ORDER BY e.criada_em DESC),'[]'::jsonb) INTO v_eventos
  FROM (SELECT * FROM public.bi_eventos WHERE partida_id=p_partida
        ORDER BY criada_em DESC,id DESC LIMIT 20) e;
  RETURN jsonb_build_object('partida_id',v_sala.id,'codigo',v_sala.codigo,
    'status',v_sala.status,'meu_jogador_id',v_eu,
    'sou_anfitriao',v_sala.anfitriao_id=auth.uid(),
    'sou_banqueiro',v_sala.banqueiro_id=v_eu,
    'banqueiro_id',v_sala.banqueiro_id,'jogadores',v_jogadores,
    'cobrancas',v_cobrancas,'historico',v_historico,
    'meus_imoveis',v_bens,'eventos',v_eventos);
END;
$$;

-- 3. Todas as movimentacoes passam por UMA transacao atomica, serializada
-- pelo bloqueio da sala. Banco representado por pagador/recebedor NULL.
-- Acoes: transferir, cobrar, pagar_banco, hipotecar_tudo, hipotecar_algumas,
-- banco_paga, salario. Hipotecas usam valor digitado pelo jogador.
-- Uma chave UUID nova por clique e a MESMA chave em uma repeticao de rede.
CREATE OR REPLACE FUNCTION public.bi_operar(
  p_partida uuid,p_acao text,p_alvo uuid,p_valor bigint,
  p_motivo text,p_chave uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_eu uuid; v_existente public.bi_transacoes%ROWTYPE;
        v_valor bigint; v_motivo text; v_descricao text; v_tipo text;
        v_pagador uuid; v_recebedor uuid; v_status text := 'concluida';
        v_saldo bigint; v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  IF p_chave IS NULL THEN RAISE EXCEPTION 'Identificador de operacao obrigatorio.'; END IF;
  IF p_acao IS NULL OR p_acao NOT IN
    ('transferir','cobrar','pagar_banco','hipotecar_tudo',
     'hipotecar_algumas','banco_paga','salario') THEN
    RAISE EXCEPTION 'Operacao desconhecida.';
  END IF;
  v_valor := CASE WHEN p_acao='salario' THEN 2000 ELSE p_valor END;
  IF v_valor IS NULL OR v_valor < 1 OR v_valor > 1000000000 THEN
    RAISE EXCEPTION 'Informe valor entre R$ 1 e R$ 1 bilhao.';
  END IF;
  IF p_acao='salario' AND p_valor IS NOT NULL AND p_valor<>2000 THEN
    RAISE EXCEPTION 'O salario de passagem e sempre R$ 2.000.';
  END IF;
  v_motivo := nullif(pg_catalog.btrim(p_motivo),'');
  IF v_motivo IS NOT NULL AND char_length(v_motivo)>140 THEN
    RAISE EXCEPTION 'Motivo deve ter ate 140 caracteres.';
  END IF;
  IF p_acao IN ('pagar_banco','hipotecar_tudo','hipotecar_algumas','banco_paga')
     AND v_motivo IS NULL THEN RAISE EXCEPTION 'Informe o motivo ou os bens.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status <> 'jogando' THEN
    RAISE EXCEPTION 'A partida nao esta em andamento.'; END IF;
  SELECT id INTO v_eu FROM public.bi_jogadores
    WHERE partida_id=p_partida AND usuario_id=auth.uid();
  IF v_eu IS NULL THEN RAISE EXCEPTION 'Voce nao participa desta partida.'; END IF;
  IF p_acao IN ('banco_paga','salario') AND
     v_sala.banqueiro_id IS DISTINCT FROM v_eu THEN
    RAISE EXCEPTION 'Apenas o banqueiro pode pagar em nome do banco.';
  END IF;
  IF p_acao IN ('transferir','cobrar','banco_paga','salario') THEN
    IF p_alvo IS NULL OR NOT EXISTS(SELECT 1 FROM public.bi_jogadores
       WHERE id=p_alvo AND partida_id=p_partida) THEN
      RAISE EXCEPTION 'Selecione um jogador da sala.';
    END IF;
    IF p_acao IN ('transferir','cobrar') AND p_alvo=v_eu THEN
      RAISE EXCEPTION 'Nao e possivel cobrar/transferir para si.';
    END IF;
  ELSIF p_alvo IS NOT NULL THEN
    RAISE EXCEPTION 'Esta operacao nao aceita jogador de destino.';
  END IF;
  v_tipo := CASE p_acao
    WHEN 'transferir' THEN 'transferencia'
    WHEN 'cobrar' THEN 'aluguel'
    WHEN 'pagar_banco' THEN 'banco'
    WHEN 'hipotecar_tudo' THEN 'hipoteca'
    WHEN 'hipotecar_algumas' THEN 'hipoteca'
    ELSE 'bonus' END;
  v_descricao := CASE p_acao
    WHEN 'transferir' THEN 'Transferencia: '||coalesce(v_motivo,'entre jogadores')
    WHEN 'cobrar' THEN 'Aluguel: '||coalesce(v_motivo,'cobranca')
    WHEN 'pagar_banco' THEN 'Pagamento ao banco: '||v_motivo
    WHEN 'hipotecar_tudo' THEN 'Hipoteca de tudo: '||v_motivo
    WHEN 'hipotecar_algumas' THEN 'Hipoteca parcial: '||v_motivo
    WHEN 'banco_paga' THEN 'Banco paga: '||v_motivo
    WHEN 'salario' THEN 'Passagem pelo inicio: R$ 2.000' END;
  v_descricao := left(v_descricao,160);
  v_pagador := CASE p_acao
    WHEN 'transferir' THEN v_eu WHEN 'cobrar' THEN p_alvo
    WHEN 'pagar_banco' THEN v_eu ELSE NULL END;
  v_recebedor := CASE p_acao
    WHEN 'transferir' THEN p_alvo WHEN 'cobrar' THEN v_eu
    WHEN 'pagar_banco' THEN NULL
    WHEN 'hipotecar_tudo' THEN v_eu
    WHEN 'hipotecar_algumas' THEN v_eu ELSE p_alvo END;
  IF p_acao='cobrar' THEN v_status:='pendente'; END IF;
  SELECT * INTO v_existente FROM public.bi_transacoes
    WHERE partida_id=p_partida AND chave_operacao=p_chave;
  IF FOUND THEN
    IF v_existente.solicitante_id<>auth.uid()
       OR v_existente.pagador_id IS DISTINCT FROM v_pagador
       OR v_existente.recebedor_id IS DISTINCT FROM v_recebedor
       OR v_existente.valor<>v_valor OR v_existente.tipo<>v_tipo
       OR v_existente.descricao IS DISTINCT FROM v_descricao THEN
      RAISE EXCEPTION 'Identificador ja utilizado em outra operacao.';
    END IF;
    RETURN jsonb_build_object('transacao_id',v_existente.id,
      'status',v_existente.status,'repetida',true);
  END IF;
  IF v_status='concluida' AND v_pagador IS NOT NULL THEN
    UPDATE public.bi_jogadores SET saldo=saldo-v_valor
      WHERE id=v_pagador AND partida_id=p_partida AND saldo>=v_valor
      RETURNING saldo INTO v_saldo;
    IF NOT FOUND THEN RAISE EXCEPTION 'Saldo insuficiente.'; END IF;
  END IF;
  IF v_status='concluida' AND v_recebedor IS NOT NULL THEN
    UPDATE public.bi_jogadores SET saldo=saldo+v_valor
      WHERE id=v_recebedor AND partida_id=p_partida;
  END IF;
  INSERT INTO public.bi_transacoes
    (partida_id,pagador_id,recebedor_id,valor,tipo,status,
     descricao,solicitante_id,chave_operacao)
  VALUES (p_partida,v_pagador,v_recebedor,v_valor,v_tipo,v_status,
          v_descricao,auth.uid(),p_chave) RETURNING id INTO v_id;
  RETURN jsonb_build_object('transacao_id',v_id,'status',v_status,'repetida',false);
END;
$$;

-- 4. O pagador aceita ou recusa o aluguel. Nunca descontar duas vezes.
CREATE OR REPLACE FUNCTION public.bi_responder_aluguel(p_transacao uuid,p_aceitar boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_t public.bi_transacoes%ROWTYPE; v_sala public.bi_partidas%ROWTYPE;
        v_eu uuid;
BEGIN
  IF auth.uid() IS NULL OR p_aceitar IS NULL THEN
    RAISE EXCEPTION 'Entre e informe a resposta.'; END IF;
  SELECT partida_id INTO v_t.partida_id FROM public.bi_transacoes WHERE id=p_transacao;
  IF v_t.partida_id IS NULL THEN RAISE EXCEPTION 'Cobranca inexistente.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=v_t.partida_id FOR UPDATE;
  SELECT * INTO v_t FROM public.bi_transacoes WHERE id=p_transacao FOR UPDATE;
  SELECT id INTO v_eu FROM public.bi_jogadores
    WHERE partida_id=v_t.partida_id AND usuario_id=auth.uid();
  IF v_eu IS NULL OR v_t.pagador_id IS DISTINCT FROM v_eu THEN
    RAISE EXCEPTION 'Apenas o pagador pode responder.'; END IF;
  IF v_t.tipo<>'aluguel' THEN RAISE EXCEPTION 'Nao e uma cobranca de aluguel.'; END IF;
  IF v_t.status<>'pendente' THEN
    IF (p_aceitar AND v_t.status='concluida') OR
       (NOT p_aceitar AND v_t.status='recusada') THEN
      RETURN jsonb_build_object('status',v_t.status,'repetida',true);
    END IF;
    RAISE EXCEPTION 'Esta cobranca ja foi respondida.';
  END IF;
  IF v_sala.status<>'jogando' THEN RAISE EXCEPTION 'Partida nao iniciada.'; END IF;
  IF NOT p_aceitar THEN
    UPDATE public.bi_transacoes SET status='recusada' WHERE id=p_transacao;
    RETURN jsonb_build_object('status','recusada','repetida',false);
  END IF;
  UPDATE public.bi_jogadores SET saldo=saldo-v_t.valor
    WHERE id=v_eu AND partida_id=v_t.partida_id AND saldo>=v_t.valor;
  IF NOT FOUND THEN RAISE EXCEPTION 'Saldo insuficiente.'; END IF;
  UPDATE public.bi_jogadores SET saldo=saldo+v_t.valor
    WHERE id=v_t.recebedor_id AND partida_id=v_t.partida_id;
  UPDATE public.bi_transacoes SET status='concluida' WHERE id=p_transacao;
  RETURN jsonb_build_object('status','concluida','repetida',false);
END;
$$;

-- 5. Banqueiro prende ou registra UMA jogada perdida de cada vez.
-- O sistema NAO adivinha turnos; com 0 jogadas restantes solta automaticamente.
CREATE OR REPLACE FUNCTION public.bi_controlar_prisao(
 p_partida uuid,p_jogador uuid,p_acao text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_eu uuid;
        v_nome text; v_preso boolean; v_faltam integer; v_desc text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  IF p_acao NOT IN ('prender','perder_jogada') OR p_acao IS NULL THEN
    RAISE EXCEPTION 'Acao de prisao invalida.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status<>'jogando' THEN
    RAISE EXCEPTION 'Partida nao iniciada.'; END IF;
  SELECT id INTO v_eu FROM public.bi_jogadores
    WHERE partida_id=p_partida AND usuario_id=auth.uid();
  IF v_eu IS NULL OR v_sala.banqueiro_id IS DISTINCT FROM v_eu THEN
    RAISE EXCEPTION 'Somente o banqueiro controla a prisao.'; END IF;
  SELECT nome,preso,turnos_prisao INTO v_nome,v_preso,v_faltam
    FROM public.bi_jogadores WHERE id=p_jogador AND partida_id=p_partida;
  IF NOT FOUND THEN RAISE EXCEPTION 'Jogador nao encontrado.'; END IF;
  IF p_acao='prender' THEN
    IF v_preso THEN RAISE EXCEPTION 'Jogador ja esta preso.'; END IF;
    v_faltam:=3; v_preso:=true; v_desc:=v_nome||' foi preso por 3 jogadas.';
  ELSE
    IF NOT v_preso OR v_faltam<=0 THEN
      RAISE EXCEPTION 'Jogador nao esta preso.'; END IF;
    v_faltam:=v_faltam-1; v_preso:=(v_faltam>0);
    v_desc:=CASE WHEN v_faltam=0 THEN v_nome||' cumpriu a prisao e foi solto.'
      ELSE v_nome||' perdeu uma jogada; faltam '||v_faltam||'.' END;
  END IF;
  UPDATE public.bi_jogadores SET preso=v_preso,turnos_prisao=v_faltam
    WHERE id=p_jogador AND partida_id=p_partida;
  INSERT INTO public.bi_eventos(partida_id,autor_usuario_id,jogador_id,tipo,descricao)
    VALUES(p_partida,auth.uid(),p_jogador,
      CASE WHEN p_acao='prender' THEN 'prender'
           WHEN v_faltam=0 THEN 'soltar' ELSE 'perder_jogada' END,v_desc);
  RETURN jsonb_build_object('preso',v_preso,'jogadas_restantes',v_faltam);
END;
$$;

-- 6. Fianca: somente o proprio preso, sempre R$ 500, sem duplicacao por chave.
CREATE OR REPLACE FUNCTION public.bi_pagar_fianca(p_partida uuid,p_chave uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_eu uuid;
        v_preso boolean; v_id uuid; v_anterior public.bi_transacoes%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_chave IS NULL THEN
    RAISE EXCEPTION 'Entre e informe a chave da operacao.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status<>'jogando' THEN RAISE EXCEPTION 'Partida nao iniciada.'; END IF;
  SELECT id,preso INTO v_eu,v_preso FROM public.bi_jogadores
    WHERE partida_id=p_partida AND usuario_id=auth.uid();
  IF v_eu IS NULL THEN RAISE EXCEPTION 'Voce nao participa da sala.'; END IF;
  SELECT * INTO v_anterior FROM public.bi_transacoes
    WHERE partida_id=p_partida AND chave_operacao=p_chave;
  IF FOUND THEN
    IF v_anterior.solicitante_id<>auth.uid() OR v_anterior.pagador_id<>v_eu
       OR v_anterior.tipo<>'fianca' OR v_anterior.valor<>500 THEN
      RAISE EXCEPTION 'Identificador ja usado em outra operacao.'; END IF;
    RETURN jsonb_build_object('status','liberto','repetida',true);
  END IF;
  IF NOT v_preso THEN RAISE EXCEPTION 'Voce nao esta preso.'; END IF;
  UPDATE public.bi_jogadores SET saldo=saldo-500,preso=false,turnos_prisao=0
    WHERE id=v_eu AND partida_id=p_partida AND saldo>=500;
  IF NOT FOUND THEN RAISE EXCEPTION 'Saldo insuficiente para a fianca.'; END IF;
  INSERT INTO public.bi_transacoes
    (partida_id,pagador_id,recebedor_id,valor,tipo,status,
     descricao,solicitante_id,chave_operacao)
  VALUES(p_partida,v_eu,NULL,500,'fianca','concluida',
     'Fianca: libertacao imediata',auth.uid(),p_chave) RETURNING id INTO v_id;
  INSERT INTO public.bi_eventos(partida_id,autor_usuario_id,jogador_id,tipo,descricao)
    VALUES(p_partida,auth.uid(),v_eu,'soltar','Jogador pagou R$ 500 de fianca.');
  RETURN jsonb_build_object('status','liberto','transacao_id',v_id,'repetida',false);
END;
$$;

-- 7. Cadastro opcional de bens: somente o proprio jogador inclui/altera/exclui.
-- O cadastro nao calcula preco e nao dispara hipoteca ou transacao sozinho.
CREATE OR REPLACE FUNCTION public.bi_salvar_imovel(
 p_partida uuid,p_registro uuid,p_cidade text,p_propriedade text,
 p_casas integer,p_hoteis integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_eu uuid; v_sala public.bi_partidas%ROWTYPE; v_id uuid;
        v_cidade text:=nullif(btrim(p_cidade),'');
        v_nome text:=coalesce(btrim(p_propriedade),'');
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  IF v_cidade IS NULL OR char_length(v_cidade)>100 OR char_length(v_nome)>100
     THEN RAISE EXCEPTION 'Cidade obrigatoria e nomes ate 100 caracteres.'; END IF;
  IF p_casas IS NULL OR p_casas NOT BETWEEN 0 AND 99 OR
     p_hoteis IS NULL OR p_hoteis NOT BETWEEN 0 AND 99 THEN
    RAISE EXCEPTION 'Informe quantidades de 0 a 99.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status='finalizada' THEN RAISE EXCEPTION 'Sala indisponivel.'; END IF;
  SELECT id INTO v_eu FROM public.bi_jogadores
    WHERE partida_id=p_partida AND usuario_id=auth.uid();
  IF v_eu IS NULL THEN RAISE EXCEPTION 'Voce nao participa desta sala.'; END IF;
  IF p_registro IS NULL THEN
    INSERT INTO public.bi_inventario(partida_id,jogador_id,cidade,propriedade,casas,hoteis)
      VALUES(p_partida,v_eu,v_cidade,v_nome,p_casas,p_hoteis) RETURNING id INTO v_id;
  ELSE
    UPDATE public.bi_inventario SET cidade=v_cidade,propriedade=v_nome,
      casas=p_casas,hoteis=p_hoteis,atualizada_em=now()
      WHERE id=p_registro AND partida_id=p_partida AND jogador_id=v_eu
      RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Registro nao encontrado ou nao e seu.'; END IF;
  END IF;
  RETURN jsonb_build_object('imovel_id',v_id,'salvo',true);
END;
$$;

CREATE OR REPLACE FUNCTION public.bi_excluir_imovel(p_partida uuid,p_registro uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_eu uuid; v_sala public.bi_partidas%ROWTYPE; v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status='finalizada' THEN RAISE EXCEPTION 'Sala indisponivel.'; END IF;
  SELECT id INTO v_eu FROM public.bi_jogadores
    WHERE partida_id=p_partida AND usuario_id=auth.uid();
  IF v_eu IS NULL THEN RAISE EXCEPTION 'Voce nao participa desta sala.'; END IF;
  DELETE FROM public.bi_inventario
    WHERE id=p_registro AND partida_id=p_partida AND jogador_id=v_eu RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'Registro nao encontrado ou nao e seu.'; END IF;
  RETURN jsonb_build_object('excluido',true,'imovel_id',v_id);
END;
$$;

-- Apenas usuarios autenticados (inclusive login anonimo) podem invocar as RPCs.
-- Todas exigem que o auth.uid() pertença a sala; permissoes extras no servidor.
REVOKE ALL ON FUNCTION public.bi_iniciar_partida(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_painel(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_operar(uuid,text,uuid,bigint,text,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_responder_aluguel(uuid,boolean)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_controlar_prisao(uuid,uuid,text)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_pagar_fianca(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_salvar_imovel(uuid,uuid,text,text,integer,integer)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_excluir_imovel(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.bi_iniciar_partida(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_painel(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_operar(uuid,text,uuid,bigint,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_responder_aluguel(uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_controlar_prisao(uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_pagar_fianca(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_salvar_imovel(uuid,uuid,text,text,integer,integer)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_excluir_imovel(uuid,uuid) TO authenticated;
COMMIT;
-- FIM. Nenhum GRANT de SELECT/UPDATE/INSERT direto foi dado aos clientes.
