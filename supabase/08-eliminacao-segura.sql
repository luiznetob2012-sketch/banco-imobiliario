-- ETAPA 08: ELIMINACAO MANUAL + AUDIO POR DESTINATARIO
-- Executar somente depois da etapa 07; preserva partidas, saldos e historico.
-- Interface nova requer esta migracao; nao usar v4 para eliminar jogadores.
BEGIN;

ALTER TABLE public.bi_jogadores
  ADD COLUMN IF NOT EXISTS eliminado boolean NOT NULL DEFAULT false;
ALTER TABLE public.bi_jogadores
  ADD COLUMN IF NOT EXISTS eliminado_em timestamptz;

ALTER TABLE public.bi_eventos DROP CONSTRAINT IF EXISTS bi_eventos_tipo_check;
ALTER TABLE public.bi_eventos ADD CONSTRAINT bi_eventos_tipo_check
  CHECK (tipo IN ('prender','perder_jogada','soltar','eliminado'));

-- As atualizacoes de saldo e o registro financeiro pertencem a mesma
-- transacao no PostgreSQL. Qualquer erro no gatilho desfaz os dois.
CREATE OR REPLACE FUNCTION public.bi_impedir_transacao_eliminado()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.status IN ('pendente','concluida') THEN
    IF EXISTS (SELECT 1 FROM public.bi_jogadores j
      WHERE j.partida_id=NEW.partida_id AND j.usuario_id=auth.uid()
      AND j.eliminado) THEN
      RAISE EXCEPTION 'Voce foi eliminado e nao pode realizar operacoes.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.bi_jogadores j
      WHERE j.partida_id=NEW.partida_id AND j.eliminado
      AND (j.id=NEW.pagador_id OR j.id=NEW.recebedor_id)) THEN
      RAISE EXCEPTION 'Jogador eliminado nao pode pagar nem receber.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS bi_transacao_sem_eliminados ON public.bi_transacoes;
CREATE TRIGGER bi_transacao_sem_eliminados
BEFORE INSERT OR UPDATE ON public.bi_transacoes
FOR EACH ROW EXECUTE FUNCTION public.bi_impedir_transacao_eliminado();

CREATE OR REPLACE FUNCTION public.bi_bloquear_conta_eliminada()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF OLD.eliminado AND
    (NEW.saldo IS DISTINCT FROM OLD.saldo OR
     NEW.preso IS DISTINCT FROM OLD.preso OR
     NEW.turnos_prisao IS DISTINCT FROM OLD.turnos_prisao) THEN
    RAISE EXCEPTION 'Conta eliminada: movimentacoes bloqueadas.';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS bi_conta_eliminada_bloqueada ON public.bi_jogadores;
CREATE TRIGGER bi_conta_eliminada_bloqueada
BEFORE UPDATE ON public.bi_jogadores
FOR EACH ROW EXECUTE FUNCTION public.bi_bloquear_conta_eliminada();

CREATE OR REPLACE FUNCTION public.bi_bloquear_inventario_eliminado()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_jogador uuid;
BEGIN
  v_jogador := CASE WHEN TG_OP='DELETE' THEN OLD.jogador_id ELSE NEW.jogador_id END;
  IF EXISTS(SELECT 1 FROM public.bi_jogadores j
    WHERE j.id=v_jogador AND j.eliminado) THEN
    RAISE EXCEPTION 'Jogador eliminado: cadastro bloqueado.';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$$;
DROP TRIGGER IF EXISTS bi_inventario_conta_ativa ON public.bi_inventario;
CREATE TRIGGER bi_inventario_conta_ativa
BEFORE INSERT OR UPDATE OR DELETE ON public.bi_inventario
FOR EACH ROW EXECUTE FUNCTION public.bi_bloquear_inventario_eliminado();

-- O banqueiro ativo confirma derrota manualmente, nunca pelo saldo zero.
-- Nao se pode eliminar o proprio banqueiro ate o anfitriao substitui-lo.
CREATE OR REPLACE FUNCTION public.bi_marcar_eliminado(p_partida uuid,p_jogador uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_eu uuid;
        v_alvo public.bi_jogadores%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status<>'jogando' THEN
    RAISE EXCEPTION 'Partida nao esta em andamento.';
  END IF;
  SELECT id INTO v_eu FROM public.bi_jogadores
    WHERE partida_id=p_partida AND usuario_id=auth.uid() AND NOT eliminado;
  IF v_eu IS NULL OR v_sala.banqueiro_id IS DISTINCT FROM v_eu THEN
    RAISE EXCEPTION 'Somente o banqueiro ativo pode eliminar jogadores.';
  END IF;
  SELECT * INTO v_alvo FROM public.bi_jogadores
    WHERE id=p_jogador AND partida_id=p_partida FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Jogador nao encontrado na sala.'; END IF;
  IF v_alvo.id=v_sala.banqueiro_id THEN
    RAISE EXCEPTION 'Escolha outro banqueiro antes de eliminar o atual.';
  END IF;
  IF v_alvo.eliminado THEN
    RETURN jsonb_build_object('eliminado',true,'jogador_id',v_alvo.id,'repetida',true);
  END IF;
  UPDATE public.bi_transacoes SET status='cancelada'
    WHERE partida_id=p_partida AND status='pendente'
      AND (pagador_id=p_jogador OR recebedor_id=p_jogador);
  UPDATE public.bi_jogadores
    SET eliminado=true,eliminado_em=now(),preso=false,turnos_prisao=0
    WHERE id=p_jogador AND partida_id=p_partida;
  INSERT INTO public.bi_eventos(partida_id,autor_usuario_id,jogador_id,tipo,descricao)
    VALUES(p_partida,auth.uid(),p_jogador,'eliminado',
      v_alvo.nome||' foi marcado como eliminado pelo banqueiro.');
  RETURN jsonb_build_object('eliminado',true,'jogador_id',v_alvo.id,'repetida',false);
END;
$$;

-- O anfitriao pode nomear outro banqueiro que ainda esteja jogando.
CREATE OR REPLACE FUNCTION public.bi_trocar_banqueiro(p_partida uuid,p_novo uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_sala public.bi_partidas%ROWTYPE; v_nome text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Entre no aplicativo.'; END IF;
  SELECT * INTO v_sala FROM public.bi_partidas WHERE id=p_partida FOR UPDATE;
  IF NOT FOUND OR v_sala.status<>'jogando' THEN
    RAISE EXCEPTION 'Troca permitida apenas durante a partida.';
  END IF;
  IF v_sala.anfitriao_id<>auth.uid() THEN
    RAISE EXCEPTION 'Somente o anfitriao pode substituir o banqueiro.';
  END IF;
  SELECT nome INTO v_nome FROM public.bi_jogadores
    WHERE id=p_novo AND partida_id=p_partida AND NOT eliminado;
  IF NOT FOUND THEN RAISE EXCEPTION 'Escolha um jogador ativo da sala.'; END IF;
  UPDATE public.bi_partidas SET banqueiro_id=p_novo WHERE id=p_partida;
  RETURN jsonb_build_object('banqueiro_id',p_novo,'banqueiro_nome',v_nome);
END;
$$;

-- Apenas participantes podem saber quem foi eliminado. Nao expor tabela.
CREATE OR REPLACE FUNCTION public.bi_status_eliminacao(p_partida uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(
      SELECT 1 FROM public.bi_jogadores
      WHERE partida_id=p_partida AND usuario_id=auth.uid()
  ) THEN RAISE EXCEPTION 'Voce nao participa desta partida.'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'eliminado',eliminado,'eliminado_em',eliminado_em)
    ORDER BY posicao_entrada),'[]'::jsonb)
  INTO v_result FROM public.bi_jogadores WHERE partida_id=p_partida;
  RETURN v_result;
END;
$$;

-- IDs reais de pagador/recebedor, sem confiar em nomes que podem coincidir.
-- NULL identifica o banco virtual. Historico restrito a participantes.
-- Nenhum dado financeiro e modificado por esta funcao de leitura.
CREATE OR REPLACE FUNCTION public.bi_sons_partida(p_partida uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS(
      SELECT 1 FROM public.bi_jogadores
      WHERE partida_id=p_partida AND usuario_id=auth.uid()
  ) THEN RAISE EXCEPTION 'Voce nao participa desta partida.'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'pagador_id',t.pagador_id,'recebedor_id',t.recebedor_id,
    'status',t.status,'criada_em',t.criada_em)
    ORDER BY t.criada_em DESC,t.id DESC),'[]'::jsonb)
  INTO v_result FROM (
    SELECT id,pagador_id,recebedor_id,status,criada_em
    FROM public.bi_transacoes WHERE partida_id=p_partida
    ORDER BY criada_em DESC,id DESC LIMIT 80
  ) t;
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.bi_marcar_eliminado(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_trocar_banqueiro(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_status_eliminacao(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bi_sons_partida(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.bi_marcar_eliminado(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_trocar_banqueiro(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_status_eliminacao(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bi_sons_partida(uuid) TO authenticated;
COMMIT;
