-- BANCO SUPER IMOBILIARIO - ETAPA 4: MODO SIMPLES
-- Execute APOS as etapas 1, 2 e 3. Nao apaga saldos, jogadores ou historico.
-- Valores monetarios aqui sao em REAIS INTEIROS (15000, 2000 etc).
-- ATENCAO: o frontend multiplayer ainda precisa ser conectado a estas RPCs.

-- Identifica o banqueiro da partida; o sorteio acontece ao iniciar.
ALTER TABLE public.bi_partidas
  ADD COLUMN IF NOT EXISTS banqueiro_id uuid;

-- Identificador por clique evita credito duplicado por falha de rede/reenvio.
ALTER TABLE public.bi_transacoes
  ADD COLUMN IF NOT EXISTS chave_operacao uuid;
CREATE UNIQUE INDEX IF NOT EXISTS bi_transacoes_chave_operacao_unica
  ON public.bi_transacoes (partida_id, chave_operacao)
  WHERE chave_operacao IS NOT NULL;

-- Desliga o fluxo de dados digitais. A tabela bi_dados e seus registros antigos
-- permanecem intactos; as funcoes antigas deixam de ser chamadas por usuarios.
REVOKE ALL ON FUNCTION public.bi_iniciar_dados(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bi_lancar_dados(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bi_estado_sala(uuid) FROM PUBLIC, anon, authenticated;

-- 1. O anfitriao inicia quando o grupo estiver completo; o banco e sorteado
-- entre TODOS os participantes, inclusive o proprio anfitriao.
CREATE OR REPLACE FUNCTION public.bi_iniciar_simples(p_partida uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_sala public.bi_partidas%ROWTYPE;
  v_qtd integer;
  v_banqueiro uuid;
  v_nome text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id = p_partida FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sala nao encontrada.'; END IF;
  IF v_sala.anfitriao_id <> auth.uid() THEN RAISE EXCEPTION 'Somente o anfitriao inicia a partida.'; END IF;
  IF v_sala.status <> 'aguardando' THEN RAISE EXCEPTION 'Esta sala ja foi iniciada. Crie outra para um novo jogo.'; END IF;
  SELECT count(*) INTO v_qtd FROM public.bi_jogadores WHERE partida_id = p_partida;
  IF v_qtd < 2 OR v_qtd > v_sala.max_jogadores THEN
    RAISE EXCEPTION 'A sala deve ter entre 2 e % jogadores.', v_sala.max_jogadores;
  END IF;
  SELECT id, nome INTO v_banqueiro, v_nome
  FROM public.bi_jogadores WHERE partida_id = p_partida
  ORDER BY pg_catalog.random() LIMIT 1;
  UPDATE public.bi_partidas SET banqueiro_id = v_banqueiro,
    status = 'jogando', ordem_revelada = false WHERE id = p_partida;
  RETURN jsonb_build_object('status','jogando','banqueiro_id',v_banqueiro,
    'banqueiro_nome',v_nome,'jogadores',v_qtd);
END;
$$;

-- 2. Painel de todos: saldos gerais, banqueiro, cobrancas recebidas e historico.
-- Nunca publica dados de lancamentos: dados e ordem ficam fora do app.
CREATE OR REPLACE FUNCTION public.bi_estado_simples(p_partida uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_sala public.bi_partidas%ROWTYPE;
  v_eu uuid;
  v_jogadores jsonb;
  v_pendentes jsonb;
  v_historico jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id = p_partida;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sala nao encontrada.'; END IF;
  SELECT id INTO v_eu FROM public.bi_jogadores
  WHERE partida_id = p_partida AND usuario_id = auth.uid();
  IF v_eu IS NULL THEN RAISE EXCEPTION 'Voce nao participa desta sala.'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',j.id,'nome',j.nome,'saldo',j.saldo,
    'banqueiro',j.id = v_sala.banqueiro_id,
    'preso',j.preso,'turnos_prisao',j.turnos_prisao
  ) ORDER BY j.posicao_entrada),'[]'::jsonb) INTO v_jogadores
  FROM public.bi_jogadores j WHERE j.partida_id = p_partida;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'valor',t.valor,'descricao',t.descricao,
    'cobrador',r.nome,'criada_em',t.criada_em
  ) ORDER BY t.criada_em),'[]'::jsonb) INTO v_pendentes
  FROM public.bi_transacoes t
  JOIN public.bi_jogadores r ON r.id = t.recebedor_id
  WHERE t.partida_id = p_partida AND t.pagador_id = v_eu AND t.status = 'pendente';
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'valor',t.valor,'tipo',t.tipo,'status',t.status,
    'descricao',t.descricao,'de',p.nome,'para',r.nome,'criada_em',t.criada_em
  ) ORDER BY t.criada_em DESC),'[]'::jsonb) INTO v_historico
  FROM (SELECT * FROM public.bi_transacoes WHERE partida_id = p_partida
        ORDER BY criada_em DESC, id DESC LIMIT 30) t
  LEFT JOIN public.bi_jogadores p ON p.id = t.pagador_id
  LEFT JOIN public.bi_jogadores r ON r.id = t.recebedor_id;
  RETURN jsonb_build_object('partida_id',v_sala.id,'codigo',v_sala.codigo,
    'status',v_sala.status,'meu_jogador_id',v_eu,
    'sou_anfitriao',v_sala.anfitriao_id = auth.uid(),
    'sou_banqueiro',v_sala.banqueiro_id = v_eu,
    'banqueiro_id',v_sala.banqueiro_id,'jogadores',v_jogadores,
    'cobrancas_recebidas',v_pendentes,'historico',v_historico);
END;
$$;

-- 3. Pagamento voluntario: somente o proprio pagador pode enviar dinheiro.
CREATE OR REPLACE FUNCTION public.bi_transferir_simples(
  p_partida uuid,p_destino uuid,p_valor bigint,p_descricao text DEFAULT 'Transferencia'
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_eu uuid; v_saldo bigint; v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  IF p_valor IS NULL OR p_valor < 1 OR p_valor > 1000000000 THEN
    RAISE EXCEPTION 'Informe um valor valido.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id = p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status <> 'jogando' THEN RAISE EXCEPTION 'Partida nao iniciada.'; END IF;
  SELECT id INTO v_eu FROM public.bi_jogadores
    WHERE partida_id=p_partida AND usuario_id=auth.uid();
  IF v_eu IS NULL THEN RAISE EXCEPTION 'Voce nao participa desta sala.'; END IF;
  IF p_destino IS NULL OR p_destino=v_eu OR NOT EXISTS
    (SELECT 1 FROM public.bi_jogadores WHERE partida_id=p_partida AND id=p_destino)
    THEN RAISE EXCEPTION 'Destinatario invalido.'; END IF;
  UPDATE public.bi_jogadores SET saldo=saldo-p_valor
    WHERE id=v_eu AND partida_id=p_partida AND saldo>=p_valor
    RETURNING saldo INTO v_saldo;
  IF NOT FOUND THEN RAISE EXCEPTION 'Saldo insuficiente.'; END IF;
  UPDATE public.bi_jogadores SET saldo=saldo+p_valor
    WHERE id=p_destino AND partida_id=p_partida;
  INSERT INTO public.bi_transacoes
    (partida_id,pagador_id,recebedor_id,valor,tipo,status,descricao,solicitante_id)
  VALUES (p_partida,v_eu,p_destino,p_valor,'transferencia','concluida',
    left(coalesce(nullif(btrim(p_descricao),''),'Transferencia'),160),auth.uid())
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('transacao_id',v_id,'meu_saldo',v_saldo);
END;
$$;

-- 4. Cobrar: cria pedido, sem retirar dinheiro ate o pagador confirmar.
CREATE OR REPLACE FUNCTION public.bi_cobrar_simples(
  p_partida uuid,p_pagador uuid,p_valor bigint,p_descricao text DEFAULT 'Aluguel'
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_eu uuid; v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  IF p_valor IS NULL OR p_valor < 1 OR p_valor > 1000000000 THEN
    RAISE EXCEPTION 'Informe um valor valido.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status <> 'jogando' THEN RAISE EXCEPTION 'Partida nao iniciada.'; END IF;
  SELECT id INTO v_eu FROM public.bi_jogadores WHERE partida_id=p_partida
    AND usuario_id=auth.uid();
  IF v_eu IS NULL THEN RAISE EXCEPTION 'Voce nao participa desta sala.'; END IF;
  IF p_pagador IS NULL OR p_pagador=v_eu OR NOT EXISTS
    (SELECT 1 FROM public.bi_jogadores WHERE partida_id=p_partida AND id=p_pagador)
    THEN RAISE EXCEPTION 'Pagador invalido.'; END IF;
  INSERT INTO public.bi_transacoes
    (partida_id,pagador_id,recebedor_id,valor,tipo,status,descricao,solicitante_id)
  VALUES (p_partida,p_pagador,v_eu,p_valor,'aluguel','pendente',
    left(coalesce(nullif(btrim(p_descricao),''),'Aluguel'),160),auth.uid())
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('cobranca_id',v_id,'status','pendente');
END;
$$;

-- 5. Pagar/recusar cobranca: somente o pagador responde; uma vez so.
CREATE OR REPLACE FUNCTION public.bi_responder_cobranca(
  p_transacao uuid,p_aceitar boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_t public.bi_transacoes%ROWTYPE; v_sala public.bi_partidas%ROWTYPE;
        v_eu uuid; v_saldo bigint;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  IF p_aceitar IS NULL THEN RAISE EXCEPTION 'Informe a resposta.'; END IF;
  -- Localizar a partida e bloquear todas as movimentacoes nela.
  SELECT partida_id INTO v_t.partida_id FROM public.bi_transacoes WHERE id=p_transacao;
  IF v_t.partida_id IS NULL THEN RAISE EXCEPTION 'Cobranca nao encontrada.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=v_t.partida_id FOR UPDATE;
  SELECT * INTO v_t FROM public.bi_transacoes WHERE id=p_transacao FOR UPDATE;
  IF v_sala.status <> 'jogando' OR v_t.status <> 'pendente'
    OR v_t.tipo <> 'aluguel' THEN RAISE EXCEPTION 'Cobranca nao esta pendente.'; END IF;
  SELECT id INTO v_eu FROM public.bi_jogadores
    WHERE partida_id=v_t.partida_id AND usuario_id=auth.uid();
  IF v_eu IS NULL OR v_t.pagador_id<>v_eu THEN
    RAISE EXCEPTION 'Somente o pagador pode responder.'; END IF;
  IF NOT p_aceitar THEN
    UPDATE public.bi_transacoes SET status='recusada' WHERE id=p_transacao;
    RETURN jsonb_build_object('status','recusada');
  END IF;
  UPDATE public.bi_jogadores SET saldo=saldo-v_t.valor
    WHERE id=v_eu AND partida_id=v_t.partida_id AND saldo>=v_t.valor
    RETURNING saldo INTO v_saldo;
  IF NOT FOUND THEN RAISE EXCEPTION 'Saldo insuficiente.'; END IF;
  UPDATE public.bi_jogadores SET saldo=saldo+v_t.valor
    WHERE id=v_t.recebedor_id AND partida_id=v_t.partida_id;
  UPDATE public.bi_transacoes SET status='concluida' WHERE id=p_transacao;
  RETURN jsonb_build_object('status','concluida','meu_saldo',v_saldo);
END;
$$;

-- 6. Botao + R$ 2.000: SOMENTE o banqueiro credita o jogador que passou
-- pela partida. Uma chave UUID diferente para cada passagem; repetir o MESMO
-- clique com a MESMA chave nao duplica o pagamento. Nao paga todos juntos.
CREATE OR REPLACE FUNCTION public.bi_bonus_passagem(
  p_partida uuid,p_jogador uuid,p_chave uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_banqueiro uuid;
        v_existente uuid; v_saldo bigint; v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  IF p_chave IS NULL THEN RAISE EXCEPTION 'Identificador da operacao obrigatorio.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status <> 'jogando' THEN RAISE EXCEPTION 'Partida nao iniciada.'; END IF;
  SELECT id INTO v_banqueiro FROM public.bi_jogadores
    WHERE partida_id=p_partida AND usuario_id=auth.uid();
  IF v_banqueiro IS NULL OR v_sala.banqueiro_id IS DISTINCT FROM v_banqueiro
    THEN RAISE EXCEPTION 'Somente o banqueiro pode dar bonus.'; END IF;
  SELECT id INTO v_existente FROM public.bi_transacoes
    WHERE partida_id=p_partida AND chave_operacao=p_chave;
  IF v_existente IS NOT NULL THEN
    RETURN jsonb_build_object('transacao_id',v_existente,'repetida',true);
  END IF;
  IF p_jogador IS NULL OR NOT EXISTS
    (SELECT 1 FROM public.bi_jogadores WHERE partida_id=p_partida AND id=p_jogador)
    THEN RAISE EXCEPTION 'Jogador invalido.'; END IF;
  UPDATE public.bi_jogadores SET saldo=saldo+2000
    WHERE id=p_jogador AND partida_id=p_partida RETURNING saldo INTO v_saldo;
  INSERT INTO public.bi_transacoes
    (partida_id,pagador_id,recebedor_id,valor,tipo,status,descricao,solicitante_id,chave_operacao)
  VALUES (p_partida,NULL,p_jogador,2000,'bonus','concluida',
    'Passou pelo inicio (+R$ 2.000)',auth.uid(),p_chave)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('transacao_id',v_id,'saldo_jogador',v_saldo,'repetida',false);
END;
$$;

-- 7. Noticias e outros bonus/multas administrados pelo banqueiro.
-- Valor positivo credita; negativo debita somente se houver saldo.
CREATE OR REPLACE FUNCTION public.bi_movimento_banco(
  p_partida uuid,p_jogador uuid,p_variacao bigint,p_motivo text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_banqueiro uuid; v_saldo bigint;
        v_id uuid; v_tipo text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  IF p_variacao IS NULL OR p_variacao=0 OR p_variacao < -1000000000
     OR p_variacao > 1000000000 THEN RAISE EXCEPTION 'Valor invalido.'; END IF;
  IF p_motivo IS NULL OR char_length(btrim(p_motivo)) NOT BETWEEN 1 AND 160
     THEN RAISE EXCEPTION 'Informe o motivo (ate 160 caracteres).'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status <> 'jogando' THEN RAISE EXCEPTION 'Partida nao iniciada.'; END IF;
  SELECT id INTO v_banqueiro FROM public.bi_jogadores
    WHERE partida_id=p_partida AND usuario_id=auth.uid();
  IF v_banqueiro IS NULL OR v_sala.banqueiro_id IS DISTINCT FROM v_banqueiro
    THEN RAISE EXCEPTION 'Somente o banqueiro pode movimentar o banco.'; END IF;
  UPDATE public.bi_jogadores SET saldo=saldo+p_variacao
    WHERE id=p_jogador AND partida_id=p_partida AND saldo >= -p_variacao
    RETURNING saldo INTO v_saldo;
  IF NOT FOUND THEN RAISE EXCEPTION 'Jogador invalido ou saldo insuficiente.'; END IF;
  v_tipo := CASE WHEN p_variacao > 0 THEN 'bonus' ELSE 'noticia' END;
  INSERT INTO public.bi_transacoes
    (partida_id,pagador_id,recebedor_id,valor,tipo,status,descricao,solicitante_id)
  VALUES (p_partida,
    CASE WHEN p_variacao < 0 THEN p_jogador ELSE NULL END,
    CASE WHEN p_variacao > 0 THEN p_jogador ELSE NULL END,
    abs(p_variacao),v_tipo,'concluida',btrim(p_motivo),auth.uid())
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('transacao_id',v_id,'saldo_jogador',v_saldo);
END;
$$;

-- Apenas RPCs explicitamente autorizadas ficam disponiveis aos jogadores.
REVOKE ALL ON FUNCTION public.bi_iniciar_simples(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_estado_simples(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_transferir_simples(uuid,uuid,bigint,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_cobrar_simples(uuid,uuid,bigint,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_responder_cobranca(uuid,boolean) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_bonus_passagem(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_movimento_banco(uuid,uuid,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.bi_iniciar_simples(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_estado_simples(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_transferir_simples(uuid,uuid,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_cobrar_simples(uuid,uuid,bigint,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_responder_cobranca(uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_bonus_passagem(uuid,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_movimento_banco(uuid,uuid,bigint,text) TO authenticated;
-- As 5 tabelas seguem com RLS ligado e sem leitura/escrita direta.
