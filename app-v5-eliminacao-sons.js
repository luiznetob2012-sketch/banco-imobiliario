'use strict';
/* Extensao V5: depende dos arquivos app-v2.js, som-dinheiro-real-v4.js
 * e das RPCs instaladas por supabase/08-eliminacao-segura.sql.
 * Nunca decide permissao no navegador: o PostgreSQL valida todas as acoes.
 */
(() => {
  const style = document.createElement('style');
  style.textContent = '.player.eliminated{opacity:.57;filter:grayscale(1)}.player.eliminated .balance{color:#c5c8d0}.lost-label{color:#ffb4b4;border:1px solid #a85c65;border-radius:99px;padding:3px 9px;font-size:.75rem;font-weight:800;display:inline-block;margin-left:6px}.blocked-account{padding:16px;background:#3b2734;color:#ffe4e7;border:1px solid #a85c65;border-radius:12px;margin:18px 0}.v5-admin{display:flex;gap:9px;flex-wrap:wrap;margin:15px 0}.v5-admin button{background:#593f52}';
  document.head.appendChild(style);
  const oldRender = render;
  render = function renderV5() {
    oldRender();
    if (!state) return;
    const flags = new Map((state.jogadores || []).map(p => [p.id, !!p.eliminado]));
    const cards = document.querySelectorAll('#app .grid .player');
    state.jogadores.forEach((player, index) => {
      if (!flags.get(player.id) || !cards[index]) return;
      cards[index].classList.add('eliminated');
      cards[index].querySelector('strong')?.insertAdjacentHTML('beforeend', '<span class="lost-label">ELIMINADO</span>');
      cards[index].querySelector('small')?.remove();
    });
    if (state.status !== 'jogando') return;
    const mine = state.jogadores.find(j => j.id === state.meu_jogador_id);
    if (mine?.eliminado) {
      const tabs = document.querySelector('#app .tabs');
      if (tabs && !document.querySelector('#app .blocked-account')) tabs.insertAdjacentHTML('beforebegin', '<div class="blocked-account"><strong>☠️ Você foi eliminado.</strong><br>Seu saldo e histórico continuam disponíveis. Não é mais possível realizar transações ou alterar imóveis.</div>');
      document.querySelectorAll('#app button[data-action]').forEach(button => {
        if (!['copy', 'leave'].includes(button.dataset.action)) button.disabled = true;
      });
    }
    const activeOthers = state.jogadores.filter(p => !p.eliminado && p.id !== state.banqueiro_id);
    if (state.sou_banqueiro && !mine?.eliminado && activeOthers.length) {
      const panel = [...document.querySelectorAll('#app h2')].find(el => el.textContent.trim() === 'Painel do banco');
      if (panel) {
        const controls = document.createElement('div');
        controls.className = 'v5-admin';
        controls.innerHTML = '<button type="button" data-v5="eliminate">☠️ Marcar jogador eliminado</button>';
        panel.insertAdjacentElement('afterend', controls);
      }
    }
    if (state.sou_anfitriao && state.jogadores.some(p => !p.eliminado && p.id !== state.banqueiro_id)) {
      const controls = document.createElement('div');
      controls.className = 'v5-admin';
      controls.innerHTML = '<button type="button" data-v5="newBank">🏦 Trocar banqueiro</button>';
      document.querySelector('#app .grid')?.insertAdjacentElement('afterend', controls);
    }
  };
  const originalRefresh = refresh;
  refresh = async function refreshV5() {
    const ok = await originalRefresh();
    if (!ok || !state || !room) return ok;
    try {
      const flags = await rpc('bi_status_eliminacao', {p_partida:room});
      const eliminated = new Map(flags.map(row => [row.id, row.eliminado]));
      state.jogadores.forEach(player => { player.eliminado = eliminated.get(player.id) === true; });
      render();
    } catch (error) {
      notice('Não foi possível atualizar o estado de eliminação: ' + error.message, true);
    }
    return ok;
  };
  // Identidade, nao nome de exibicao: evita escolher alguem eliminado mesmo
  // que dois participantes tenham o mesmo nome.
  users = function activeUsers(exceptMe=false,filter=null) {
    return (state?.jogadores || []).filter(j => !j.eliminado && (!exceptMe || j.id !== state.meu_jogador_id) && (!filter || filter(j)))
      .map(j => `<option value="${safe(j.id)}">${safe(j.nome)}${j.banqueiro ? ' 🏦' : ''}</option>`).join('');
  };
  document.querySelector('#app').addEventListener('click', event => {
    const button = event.target.closest('button[data-v5]');
    if (!button || !state || busy) return;
    event.preventDefault();event.stopPropagation();
    const active = state.jogadores.filter(j => !j.eliminado);
    if (button.dataset.v5 === 'eliminate') {
      const eligible = active.filter(j => j.id !== state.banqueiro_id);
      if (!eligible.length) { notice('Nenhum jogador disponível.', true);return; }
      modal('Marcar derrota / eliminar jogador', '<p>Somente após o grupo confirmar que a pessoa perdeu todos os recursos. Saldo zero isoladamente não elimina.</p><label>Quem foi eliminado?</label><select required name="target">' + eligible.map(j => `<option value="${safe(j.id)}">${safe(j.nome)}</option>`).join('') + '</select>', async form => {
        const selected = String(form.get('target'));
        const name = state.jogadores.find(j => j.id === selected)?.nome || 'o jogador';
        if (!confirm(`Eliminar ${name}? Esta ação bloqueará pagamentos, recebimentos e cadastro de imóveis dessa pessoa.`)) return false;
        return rpc('bi_marcar_eliminado', {p_partida:room,p_jogador:selected});
      });
    } else if (button.dataset.v5 === 'newBank') {
      const eligible = active.filter(j => j.id !== state.banqueiro_id);
      if (!eligible.length) return;
      modal('Trocar banqueiro', '<p>Escolha um participante ativo para administrar o banco.</p><label>Novo banqueiro</label><select required name="target">' + eligible.map(j => `<option value="${safe(j.id)}">${safe(j.nome)}</option>`).join('') + '</select>', async form => {
        if (!confirm('Confirmar a troca do banqueiro?')) return false;
        return rpc('bi_trocar_banqueiro', {p_partida:room,p_novo:String(form.get('target'))});
      });
    }
  }, true);

  // Mantem o MP3 REAL da V4, que ja foi confirmado pelo usuario no celular.
  // A saida usa a mesma gravacao em tom mais grave (playbackRate = 0.72).
  // Usar o MESMO elemento audio que foi desbloqueado por toque na V4 evita
  // criar um segundo player bloqueado por navegadores moveis.
  const moneyPlayer = document.querySelector('audio[aria-hidden="true"]');
  function playSide(side) {
    if (!soundOn || document.hidden) return;
    if (moneyPlayer) moneyPlayer.playbackRate = side === 'out' ? 0.72 : 1;
    chime();
  }
  const audition = document.createElement('button');
  audition.type = 'button';audition.id = 'test-debit-v5';
  audition.textContent = '💸 Testar som de saída';
  document.querySelector('#test-money-v4')?.insertAdjacentElement('afterend', audition);
  audition.addEventListener('click', () => {
    if (!soundOn) { notice('Ative o som neste aparelho primeiro.');return; }
    playSide('out');
  });
  let previousRoom = null;
  let previous = new Map();
  watchCredits = async function observeMyTransactions() {
    if (!room || !state || !state.meu_jogador_id) return;
    const key = P + 'roles-v5-' + room + '-' + state.meu_jogador_id;
    if (previousRoom !== key) {
      previousRoom = key;previous = new Map();
      try {const stored=JSON.parse(localStorage.getItem(key)||'null');if(Array.isArray(stored)) stored.forEach(pair => {if(typeof pair[0]==='string')previous.set(pair[0],pair[1]);});}catch (_){}
    }
    const existed = localStorage.getItem(key) !== null;
    const movements = await rpc('bi_sons_partida', {p_partida:room});
    const fresh = [];
    for (const tx of movements) {
      const old = previous.get(tx.id);
      if (existed && tx.status === 'concluida' && old !== 'concluida' && Date.now() - Date.parse(tx.criada_em) < 120000) fresh.push(tx);
      previous.set(tx.id, tx.status);
    }
    try {localStorage.setItem(key, JSON.stringify([...previous].slice(-250)));}catch (_){}
    if (!soundOn || document.hidden) return;
    const me = state.meu_jogador_id;
    const bank = state.banqueiro_id;
    // Cada dispositivo ouve somente aquilo que envolve SUA conta pessoal
    // ou, se e banqueiro, o lado do banco virtual. Outros nao ouvem.
    for (const tx of fresh.slice(0,5)) {
      if (tx.recebedor_id === me) playSide('in');
      else if (tx.pagador_id === me) playSide('out');
      else if (bank === me && tx.pagador_id === null && tx.recebedor_id) playSide('out');
      else if (bank === me && tx.recebedor_id === null && tx.pagador_id) playSide('in');
    }
  };
})();