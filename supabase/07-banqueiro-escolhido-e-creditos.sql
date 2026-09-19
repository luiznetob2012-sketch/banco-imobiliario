-- ETAPA 07: BANQUEIRO ESCOLHIDO + AVISOS DE RECEBIMENTO
-- Executar APOS 06-versao-consolidada.sql. Nao exclui partidas nem saldos.
-- A escolha ocorre na sala antes de iniciar e somente pelo anfitriao.
BEGIN;

CREATE OR REPLACE FUNCTION public.bi_escolher_banqueiro(p_partida uuid, p_jogador uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_nome text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sala nao encontrada.'; END IF;
  IF v_sala.anfitriao_id <> auth.uid() THEN
    RAISE EXCEPTION 'Somente quem criou a sala pode definir o banqueiro.'; END IF;
  IF v_sala.status <> 'aguardando' THEN
    RAISE EXCEPTION 'O banqueiro nao pode ser alterado depois do inicio.'; END IF;
  SELECT nome INTO v_nome FROM public.bi_jogadores
    WHERE id=p_jogador AND partida_id=p_partida;
  IF NOT FOUND THEN RAISE EXCEPTION 'Escolha um participante desta sala.'; END IF;
  UPDATE public.bi_partidas SET banqueiro_id=p_jogador WHERE id=p_partida;
  RETURN jsonb_build_object('banqueiro_id',p_jogador,'banqueiro_nome',v_nome);
END;
$$;

-- Substitui APENAS a funcao que antes sorteava o banqueiro.
-- Agora nao permite comecar sem escolha explicita do anfitriao.
CREATE OR REPLACE FUNCTION public.bi_iniciar_partida(p_partida uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_total integer; v_nome text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sala nao encontrada.'; END IF;
  IF v_sala.anfitriao_id <> auth.uid() THEN
    RAISE EXCEPTION 'Somente o anfitriao inicia a partida.'; END IF;
  IF v_sala.status <> 'aguardando' THEN
    RAISE EXCEPTION 'Esta partida ja foi iniciada.'; END IF;
  SELECT count(*)::integer INTO v_total FROM public.bi_jogadores
    WHERE partida_id=p_partida;
  IF v_total < 2 OR v_total > v_sala.max_jogadores THEN
    RAISE EXCEPTION 'Sao necessarios de 2 a % jogadores.',v_sala.max_jogadores; END IF;
  IF v_sala.banqueiro_id IS NULL THEN
    RAISE EXCEPTION 'Escolha um banqueiro antes de iniciar.'; END IF;
  SELECT nome INTO v_nome FROM public.bi_jogadores
    WHERE id=v_sala.banqueiro_id AND partida_id=p_partida;
  IF NOT FOUND THEN RAISE EXCEPTION 'O banqueiro escolhido nao esta nesta sala.'; END IF;
  UPDATE public.bi_partidas
    SET status='jogando',ordem_revelada=false WHERE id=p_partida;
  RETURN jsonb_build_object('status','jogando',
    'banqueiro_id',v_sala.banqueiro_id,'banqueiro_nome',v_nome,
    'total_jogadores',v_total);
END;
$$;

-- A propria pessoa consulta SOMENTE os creditos concluidos em seu favor.
-- Nenhum outro participante consegue consultar seus creditos por esta RPC.
-- Sem SELECT direto nas tabelas; o navegador guarda os ids ja vistos.
CREATE OR REPLACE FUNCTION public.bi_meus_creditos(p_partida uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_eu uuid; v_creditos jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  SELECT id INTO v_eu FROM public.bi_jogadores
    WHERE partida_id=p_partida AND usuario_id=auth.uid();
  IF v_eu IS NULL THEN RAISE EXCEPTION 'Voce nao participa desta partida.'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'valor',t.valor,'descricao',t.descricao,'criada_em',t.criada_em)
    ORDER BY t.criada_em DESC,t.id DESC),'[]'::jsonb)
  INTO v_creditos FROM (
    SELECT id,valor,descricao,criada_em
    FROM public.bi_transacoes
    WHERE partida_id=p_partida AND recebedor_id=v_eu AND status='concluida'
    ORDER BY criada_em DESC,id DESC LIMIT 80
  ) t;
  RETURN v_creditos;
END;
$$;

REVOKE ALL ON FUNCTION public.bi_escolher_banqueiro(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_iniciar_partida(uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_meus_creditos(uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.bi_escolher_banqueiro(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_iniciar_partida(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_meus_creditos(uuid) TO authenticated;
COMMIT;
