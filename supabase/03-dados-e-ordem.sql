-- BANCO SUPER IMOBILIÁRIO — ETAPA 3
-- Execute APÓS as etapas 1 (tabelas) e 2 (salas).
-- A entrada na sala NUNCA determina a ordem de jogo.
-- Cada pessoa registra seus dois dados físicos. Nenhum resultado dos outros
-- nem a ordem definitiva são expostos antes de TODOS concluírem os desempates.
-- O SQL Editor executa isto como administrador; não rode a partir do navegador.

-- 1. Somente o anfitrião pode encerrar as inscrições e abrir os lançamentos.
CREATE OR REPLACE FUNCTION public.bi_iniciar_dados(p_partida uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_sala public.bi_partidas%ROWTYPE;
  v_total integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Entre no aplicativo antes de iniciar.';
  END IF;

  SELECT * INTO v_sala
  FROM public.bi_partidas
  WHERE id = p_partida
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sala não encontrada.';
  END IF;
  IF v_sala.anfitriao_id <> auth.uid() THEN
    RAISE EXCEPTION 'Somente o anfitrião pode iniciar os dados.';
  END IF;
  IF v_sala.status <> 'aguardando' THEN
    RAISE EXCEPTION 'Os dados já foram iniciados ou a partida foi encerrada.';
  END IF;

  SELECT count(*)::integer INTO v_total
  FROM public.bi_jogadores
  WHERE partida_id = p_partida;

  IF v_total < 2 OR v_total > v_sala.max_jogadores THEN
    RAISE EXCEPTION 'É necessário ter de 2 a % jogadores.', v_sala.max_jogadores;
  END IF;

  UPDATE public.bi_partidas
  SET status = 'dados', ordem_revelada = false
  WHERE id = p_partida;

  RETURN jsonb_build_object('status', 'dados', 'jogadores', v_total, 'rodada', 1);
END;
$$;

-- 2. Cada participante só pode lançar por si; o bloqueio da sala evita
--    condições de corrida no instante do último lançamento.
CREATE OR REPLACE FUNCTION public.bi_lancar_dados(
  p_partida uuid,
  p_dado_1 integer,
  p_dado_2 integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_sala public.bi_partidas%ROWTYPE;
  v_jogador uuid;
  v_rodada integer;
  v_apto boolean;
  v_pendentes integer;
  v_empates boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Entre no aplicativo antes de lançar.';
  END IF;
  IF p_dado_1 IS NULL OR p_dado_2 IS NULL
     OR p_dado_1 NOT BETWEEN 1 AND 6 OR p_dado_2 NOT BETWEEN 1 AND 6 THEN
    RAISE EXCEPTION 'Cada dado precisa ter um valor de 1 a 6.';
  END IF;

  SELECT * INTO v_sala
  FROM public.bi_partidas
  WHERE id = p_partida
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sala não encontrada.';
  END IF;
  IF v_sala.status NOT IN ('dados', 'desempate') THEN
    RAISE EXCEPTION 'A sala não está recebendo lançamentos.';
  END IF;

  SELECT id INTO v_jogador
  FROM public.bi_jogadores
  WHERE partida_id = p_partida AND usuario_id = auth.uid();

  IF v_jogador IS NULL THEN
    RAISE EXCEPTION 'Você não participa desta sala.';
  END IF;

  IF v_sala.status = 'dados' THEN
    v_rodada := 1;
    v_apto := true;
  ELSE
    SELECT coalesce(max(rodada), 1) + 1 INTO v_rodada
    FROM public.bi_dados
    WHERE partida_id = p_partida;

    -- Só repete quem ainda divide exatamente a mesma sequência de resultados
    -- com pelo menos outra pessoa. Outros grupos já resolvidos não relançam.
    WITH historicos AS (
      SELECT j.id,
        coalesce(array_agg(d.total ORDER BY d.rodada)
          FILTER (WHERE d.id IS NOT NULL), ARRAY[]::integer[]) AS sequencia
      FROM public.bi_jogadores j
      LEFT JOIN public.bi_dados d
        ON d.partida_id = j.partida_id AND d.jogador_id = j.id
        AND d.rodada < v_rodada
      WHERE j.partida_id = p_partida
      GROUP BY j.id
    ), grupos_empatados AS (
      SELECT sequencia FROM historicos
      WHERE cardinality(sequencia) = v_rodada - 1
      GROUP BY sequencia HAVING count(*) > 1
    )
    SELECT EXISTS (
      SELECT 1 FROM historicos h
      JOIN grupos_empatados e ON e.sequencia = h.sequencia
      WHERE h.id = v_jogador
    ) INTO v_apto;
  END IF;

  IF NOT v_apto THEN
    RAISE EXCEPTION 'Você não precisa lançar nesta rodada de desempate.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.bi_dados
    WHERE partida_id = p_partida AND jogador_id = v_jogador
      AND rodada = v_rodada
  ) THEN
    RAISE EXCEPTION 'Você já lançou nesta rodada.';
  END IF;

  INSERT INTO public.bi_dados
    (partida_id, jogador_id, rodada, dado_1, dado_2)
  VALUES (p_partida, v_jogador, v_rodada, p_dado_1, p_dado_2);

  -- Contar apenas as pessoas obrigadas a lançar na rodada atual.
  IF v_rodada = 1 THEN
    SELECT count(*)::integer INTO v_pendentes
    FROM public.bi_jogadores j
    LEFT JOIN public.bi_dados d
      ON d.partida_id = j.partida_id AND d.jogador_id = j.id
      AND d.rodada = v_rodada
    WHERE j.partida_id = p_partida AND d.id IS NULL;
  ELSE
    WITH historicos AS (
      SELECT j.id,
        coalesce(array_agg(d.total ORDER BY d.rodada)
          FILTER (WHERE d.id IS NOT NULL), ARRAY[]::integer[]) AS sequencia
      FROM public.bi_jogadores j
      LEFT JOIN public.bi_dados d
        ON d.partida_id = j.partida_id AND d.jogador_id = j.id
        AND d.rodada < v_rodada
      WHERE j.partida_id = p_partida
      GROUP BY j.id
    ), grupos_empatados AS (
      SELECT sequencia FROM historicos
      WHERE cardinality(sequencia) = v_rodada - 1
      GROUP BY sequencia HAVING count(*) > 1
    )
    SELECT count(*)::integer INTO v_pendentes
    FROM historicos h
    JOIN grupos_empatados e ON e.sequencia = h.sequencia
    LEFT JOIN public.bi_dados d
      ON d.partida_id = p_partida AND d.jogador_id = h.id
      AND d.rodada = v_rodada
    WHERE d.id IS NULL;
  END IF;

  IF v_pendentes > 0 THEN
    RETURN jsonb_build_object(
      'status', v_sala.status, 'rodada', v_rodada,
      'faltam', v_pendentes, 'ordem_revelada', false
    );
  END IF;

  -- O último participante chegou: verificar empates com a sequência completa.
  -- A comparação de arrays do PostgreSQL é elemento a elemento.
  WITH historicos AS (
    SELECT j.id,
      coalesce(array_agg(d.total ORDER BY d.rodada)
        FILTER (WHERE d.id IS NOT NULL), ARRAY[]::integer[]) AS sequencia
    FROM public.bi_jogadores j
    LEFT JOIN public.bi_dados d
      ON d.partida_id = j.partida_id AND d.jogador_id = j.id
    WHERE j.partida_id = p_partida
    GROUP BY j.id
  )
  SELECT EXISTS (
    SELECT 1 FROM historicos
    GROUP BY sequencia HAVING count(*) > 1
  ) INTO v_empates;

  IF v_empates THEN
    UPDATE public.bi_partidas
    SET status = 'desempate', ordem_revelada = false
    WHERE id = p_partida;

    RETURN jsonb_build_object(
      'status', 'desempate', 'rodada', v_rodada + 1,
      'faltam', 0, 'ordem_revelada', false
    );
  END IF;

  -- Ordem só é gravada quando NENHUM empate restar.
  WITH historicos AS (
    SELECT j.id,
      coalesce(array_agg(d.total ORDER BY d.rodada)
        FILTER (WHERE d.id IS NOT NULL), ARRAY[]::integer[]) AS sequencia
    FROM public.bi_jogadores j
    LEFT JOIN public.bi_dados d
      ON d.partida_id = j.partida_id AND d.jogador_id = j.id
    WHERE j.partida_id = p_partida
    GROUP BY j.id
  ), classificados AS (
    SELECT id,
      row_number() OVER (ORDER BY sequencia DESC)::integer AS ordem
    FROM historicos
  )
  UPDATE public.bi_jogadores AS j
  SET ordem_jogo = c.ordem
  FROM classificados AS c
  WHERE j.id = c.id AND j.partida_id = p_partida;

  UPDATE public.bi_partidas
  SET status = 'jogando', ordem_revelada = true
  WHERE id = p_partida;

  RETURN jsonb_build_object(
    'status', 'jogando', 'rodada', v_rodada,
    'faltam', 0, 'ordem_revelada', true
  );
END;
$$;

-- 3. Leitura controlada: só participantes veem a sala.
--    Antes da classificação, somente os próprios dados são revelados.
CREATE OR REPLACE FUNCTION public.bi_estado_sala(p_partida uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_sala public.bi_partidas%ROWTYPE;
  v_meu_jogador uuid;
  v_rodada integer;
  v_necessarios integer := 0;
  v_concluidos integer := 0;
  v_jogadores jsonb;
  v_meus_dados jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Entre no aplicativo antes de consultar uma sala.';
  END IF;

  SELECT * INTO v_sala FROM public.bi_partidas WHERE id = p_partida;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sala não encontrada.';
  END IF;

  SELECT id INTO v_meu_jogador FROM public.bi_jogadores
  WHERE partida_id = p_partida AND usuario_id = auth.uid();
  IF v_meu_jogador IS NULL THEN
    RAISE EXCEPTION 'Você não participa desta sala.';
  END IF;

  IF v_sala.status = 'dados' THEN
    v_rodada := 1;
    SELECT count(*)::integer INTO v_necessarios
    FROM public.bi_jogadores WHERE partida_id = p_partida;
  ELSIF v_sala.status = 'desempate' THEN
    SELECT coalesce(max(rodada), 1) + 1 INTO v_rodada
    FROM public.bi_dados WHERE partida_id = p_partida;

    WITH historicos AS (
      SELECT j.id,
        coalesce(array_agg(d.total ORDER BY d.rodada)
          FILTER (WHERE d.id IS NOT NULL), ARRAY[]::integer[]) AS sequencia
      FROM public.bi_jogadores j
      LEFT JOIN public.bi_dados d
        ON d.partida_id = j.partida_id AND d.jogador_id = j.id
        AND d.rodada < v_rodada
      WHERE j.partida_id = p_partida
      GROUP BY j.id
    ), grupos_empatados AS (
      SELECT sequencia FROM historicos
      WHERE cardinality(sequencia) = v_rodada - 1
      GROUP BY sequencia HAVING count(*) > 1
    )
    SELECT count(*)::integer INTO v_necessarios
    FROM historicos h
    JOIN grupos_empatados e ON e.sequencia = h.sequencia;
  ELSE
    v_rodada := NULL;
  END IF;

  IF v_rodada IS NOT NULL THEN
    SELECT count(*)::integer INTO v_concluidos
    FROM public.bi_dados
    WHERE partida_id = p_partida AND rodada = v_rodada;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'jogador_id', j.id,
    'nome', j.nome,
    'saldo', j.saldo,
    'preso', j.preso,
    'turnos_prisao', j.turnos_prisao,
    'ja_lancou', CASE WHEN v_rodada IS NULL THEN NULL ELSE EXISTS (
      SELECT 1 FROM public.bi_dados d
      WHERE d.partida_id = p_partida AND d.jogador_id = j.id
        AND d.rodada = v_rodada
    ) END,
    'deve_lancar', CASE WHEN v_sala.status = 'dados' THEN true
      WHEN v_sala.status = 'desempate' THEN EXISTS (
        WITH historicos AS (
          SELECT j2.id,
            coalesce(array_agg(d2.total ORDER BY d2.rodada)
              FILTER (WHERE d2.id IS NOT NULL), ARRAY[]::integer[]) AS sequencia
          FROM public.bi_jogadores j2
          LEFT JOIN public.bi_dados d2
            ON d2.partida_id = j2.partida_id AND d2.jogador_id = j2.id
            AND d2.rodada < v_rodada
          WHERE j2.partida_id = p_partida
          GROUP BY j2.id
        )
        SELECT 1 FROM historicos h
        WHERE h.id = j.id AND cardinality(h.sequencia) = v_rodada - 1
          AND (SELECT count(*) FROM historicos h2
               WHERE h2.sequencia = h.sequencia) > 1
      ) ELSE false END,
    'ordem_jogo', CASE WHEN v_sala.ordem_revelada THEN j.ordem_jogo ELSE NULL END
  ) ORDER BY
    CASE WHEN v_sala.ordem_revelada THEN j.ordem_jogo ELSE NULL END NULLS LAST,
    lower(j.nome)), '[]'::jsonb)
  INTO v_jogadores
  FROM public.bi_jogadores j
  WHERE j.partida_id = p_partida;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'rodada', d.rodada, 'dado_1', d.dado_1,
    'dado_2', d.dado_2, 'total', d.total
  ) ORDER BY d.rodada), '[]'::jsonb)
  INTO v_meus_dados
  FROM public.bi_dados d
  WHERE d.partida_id = p_partida AND d.jogador_id = v_meu_jogador;

  RETURN jsonb_build_object(
    'partida_id', v_sala.id,
    'codigo', v_sala.codigo,
    'status', v_sala.status,
    'sou_anfitriao', v_sala.anfitriao_id = auth.uid(),
    'meu_jogador_id', v_meu_jogador,
    'max_jogadores', v_sala.max_jogadores,
    'ordem_revelada', v_sala.ordem_revelada,
    'rodada', v_rodada,
    'precisam_lancar', v_necessarios,
    'ja_lancaram', v_concluidos,
    'jogadores', v_jogadores,
    'meus_dados', v_meus_dados
  );
END;
$$;

-- Os dados das tabelas continuam inacessíveis diretamente ao navegador.
REVOKE ALL ON FUNCTION public.bi_iniciar_dados(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bi_lancar_dados(uuid, integer, integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bi_estado_sala(uuid)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.bi_iniciar_dados(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_lancar_dados(uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_estado_sala(uuid) TO authenticated;

-- IMPORTANTE: ainda faltam a lógica de transferências, a integração do site,
-- e os testes reais com dois ou mais celulares. Não considere o app pronto.
