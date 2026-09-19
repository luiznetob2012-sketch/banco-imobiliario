-- BANCO SUPER IMOBILIARIO - ETAPA 5 (COMPLEMENTO EM PREPARACAO)
-- NAO EXECUTAR AINDA: a mecanica de hipotecas esta sendo definida.
-- Executar somente DEPOIS de 04-banco-simples.sql, quando a etapa 5 estiver completa.
-- O banco e uma entidade virtual: pagar ao banco NAO credita a conta pessoal do banqueiro.
-- Valores monetarios em reais inteiros, conforme etapas anteriores.

CREATE OR REPLACE FUNCTION public.bi_pagar_banco(
  p_partida uuid,
  p_valor bigint,
  p_descricao text,
  p_chave uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_sala public.bi_partidas%ROWTYPE;
  v_eu uuid;
  v_existente public.bi_transacoes%ROWTYPE;
  v_saldo bigint;
  v_id uuid;
  v_motivo text := nullif(btrim(p_descricao), '');
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Entre no aplicativo antes de pagar.';
  END IF;
  IF p_valor IS NULL OR p_valor < 1 OR p_valor > 1000000000 THEN
    RAISE EXCEPTION 'Informe um valor valido.';
  END IF;
  IF v_motivo IS NULL OR char_length(v_motivo) > 160 THEN
    RAISE EXCEPTION 'Informe o motivo (ate 160 caracteres).';
  END IF;
  IF p_chave IS NULL THEN
    RAISE EXCEPTION 'Identificador da operacao obrigatorio.';
  END IF;

  -- Serializa as movimentacoes desta partida, incluindo pagamentos simultaneos.
  SELECT * INTO v_sala FROM public.bi_partidas
  WHERE id = p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status <> 'jogando' THEN
    RAISE EXCEPTION 'Partida nao iniciada.';
  END IF;

  SELECT id INTO v_eu FROM public.bi_jogadores
  WHERE partida_id = p_partida AND usuario_id = auth.uid();
  IF v_eu IS NULL THEN
    RAISE EXCEPTION 'Voce nao participa desta sala.';
  END IF;

  -- Reenviar o mesmo clique/UUID nunca desconta duas vezes.
  SELECT * INTO v_existente FROM public.bi_transacoes
  WHERE partida_id = p_partida AND chave_operacao = p_chave;
  IF FOUND THEN
    IF v_existente.solicitante_id <> auth.uid()
       OR v_existente.pagador_id IS DISTINCT FROM v_eu
       OR v_existente.recebedor_id IS NOT NULL
       OR v_existente.valor <> p_valor
       OR v_existente.descricao IS DISTINCT FROM left('Pagamento ao banco: ' || v_motivo, 160)
       OR v_existente.tipo <> 'transferencia'
       OR v_existente.status <> 'concluida' THEN
      RAISE EXCEPTION 'Identificador ja usado em outra operacao.';
    END IF;
    RETURN jsonb_build_object('transacao_id',v_existente.id,'repetida',true);
  END IF;

  UPDATE public.bi_jogadores SET saldo = saldo - p_valor
  WHERE id = v_eu AND partida_id = p_partida AND saldo >= p_valor
  RETURNING saldo INTO v_saldo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Saldo insuficiente.';
  END IF;

  INSERT INTO public.bi_transacoes
    (partida_id,pagador_id,recebedor_id,valor,tipo,status,descricao,solicitante_id,chave_operacao)
  VALUES
    (p_partida,v_eu,NULL,p_valor,'transferencia','concluida',
     left('Pagamento ao banco: ' || v_motivo,160),auth.uid(),p_chave)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('transacao_id',v_id,'meu_saldo',v_saldo,'repetida',false);
END;
$$;

REVOKE ALL ON FUNCTION public.bi_pagar_banco(uuid,bigint,text,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.bi_pagar_banco(uuid,bigint,text,uuid)
  TO authenticated;

-- PENDENTE: funcao de hipotecar terreno/casa/hotel e hipotecar tudo.
-- Definir primeiro: valor da hipoteca, regras para construcoes, e se
-- 'hipotecar tudo' inclui todos os bens cadastrados ou itens marcados.
-- A interface multiplayer ainda nao esta conectada e nao deve ser anunciada como pronta.
