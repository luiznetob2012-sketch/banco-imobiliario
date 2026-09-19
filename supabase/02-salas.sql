-- BANCO SUPER IMOBILIÁRIO — ETAPA 2
-- Executar somente depois da criação das cinco tabelas da etapa 1.
-- As operações são feitas por RPC, sem liberar escrita direta nas tabelas.

CREATE OR REPLACE FUNCTION public.bi_criar_sala(p_nome text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_usuario uuid := auth.uid();
  v_nome text := btrim(p_nome);
  v_codigo text;
  v_partida uuid;
  v_jogador uuid;
  v_tentativa integer;
BEGIN
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'Faça login no aplicativo antes de criar uma sala.';
  END IF;
  IF v_nome IS NULL OR char_length(v_nome) NOT BETWEEN 1 AND 40 THEN
    RAISE EXCEPTION 'Informe um nome de 1 a 40 caracteres.';
  END IF;

  FOR v_tentativa IN 1..10 LOOP
    v_codigo := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    BEGIN
      INSERT INTO public.bi_partidas (codigo, anfitriao_id)
      VALUES (v_codigo, v_usuario)
      RETURNING id INTO v_partida;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      -- Código já existente: tentar outro.
      NULL;
    END;
  END LOOP;

  IF v_partida IS NULL THEN
    RAISE EXCEPTION 'Não foi possível gerar um código. Tente novamente.';
  END IF;

  INSERT INTO public.bi_jogadores
    (partida_id, usuario_id, nome, posicao_entrada)
  VALUES (v_partida, v_usuario, v_nome, 1)
  RETURNING id INTO v_jogador;

  RETURN jsonb_build_object(
    'partida_id', v_partida,
    'codigo', v_codigo,
    'jogador_id', v_jogador
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.bi_entrar_sala(p_codigo text, p_nome text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_usuario uuid := auth.uid();
  v_nome text := btrim(p_nome);
  v_codigo text := upper(btrim(p_codigo));
  v_partida public.bi_partidas%ROWTYPE;
  v_jogador uuid;
  v_posicao integer;
BEGIN
  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'Faça login no aplicativo antes de entrar.';
  END IF;
  IF v_nome IS NULL OR char_length(v_nome) NOT BETWEEN 1 AND 40 THEN
    RAISE EXCEPTION 'Informe um nome de 1 a 40 caracteres.';
  END IF;
  IF v_codigo IS NULL OR v_codigo !~ '^[A-F0-9]{6}$' THEN
    RAISE EXCEPTION 'Código inválido.';
  END IF;

  -- Bloqueio da partida impede que entradas simultâneas superem seis jogadores.
  SELECT * INTO v_partida
  FROM public.bi_partidas AS p
  WHERE p.codigo = v_codigo
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sala não encontrada.';
  END IF;

  -- Um participante existente pode retornar com sua mesma sessão.
  SELECT j.id, j.posicao_entrada INTO v_jogador, v_posicao
  FROM public.bi_jogadores AS j
  WHERE j.partida_id = v_partida.id AND j.usuario_id = v_usuario;

  IF v_jogador IS NOT NULL THEN
    RETURN jsonb_build_object(
      'partida_id', v_partida.id,
      'codigo', v_partida.codigo,
      'jogador_id', v_jogador,
      'posicao_entrada', v_posicao
    );
  END IF;

  IF v_partida.status <> 'aguardando' THEN
    RAISE EXCEPTION 'Esta partida já começou ou foi encerrada.';
  END IF;

  SELECT count(*)::integer INTO v_posicao
  FROM public.bi_jogadores AS j
  WHERE j.partida_id = v_partida.id;

  IF v_posicao >= v_partida.max_jogadores THEN
    RAISE EXCEPTION 'A sala está cheia.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.bi_jogadores AS j
    WHERE j.partida_id = v_partida.id AND lower(j.nome) = lower(v_nome)
  ) THEN
    RAISE EXCEPTION 'Este nome já está sendo usado na sala.';
  END IF;

  v_posicao := v_posicao + 1;
  INSERT INTO public.bi_jogadores
    (partida_id, usuario_id, nome, posicao_entrada)
  VALUES (v_partida.id, v_usuario, v_nome, v_posicao)
  RETURNING id INTO v_jogador;

  RETURN jsonb_build_object(
    'partida_id', v_partida.id,
    'codigo', v_partida.codigo,
    'jogador_id', v_jogador,
    'posicao_entrada', v_posicao
  );
END;
$$;

-- Funções acessíveis só depois de login, inclusive login anônimo.
REVOKE ALL ON FUNCTION public.bi_criar_sala(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bi_entrar_sala(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bi_criar_sala(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_entrar_sala(text, text) TO authenticated;

-- Nenhum SELECT/INSERT/UPDATE/DELETE direto nas cinco tabelas foi liberado.
-- A etapa 3 fará leitura controlada da sala, lançamento de dados e ordem oculta.
