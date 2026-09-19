'use strict';
/*
 * Som real de caixa registradora (MP3), sem bipes sintetizados.
 * Audio: "Cash Register Purchase", Zott820, CC0, disponibilizado no
 * pacote SoundMonster: https://github.com/jonjonsson/SoundMonster
 * Origem/licenca: https://freesound.org/people/Zott820/sounds/209578/
 * O arquivo e carregado em MP3, compativel com os navegadores moveis.
 * O som e opt-in: navegadores exigem um toque do usuario para desbloquear.
 */
(() => {
  const source = 'https://raw.githubusercontent.com/jonjonsson/SoundMonster/main/Public%20domain/money%20cash%20register%20purchase.mp3';
  const original = document.getElementById('sound');
  if (!original) return;
  // Substitui o botao para retirar o listener legado, que tocava dois bipes.
  const button = original.cloneNode(true);
  original.replaceWith(button);
  const test = document.createElement('button');
  test.id = 'test-money-v4';
  test.type = 'button';
  test.textContent = '💵 Ouvir som real';
  button.insertAdjacentElement('afterend', test);
  const audioElement = document.createElement('audio');
  audioElement.src = source;
  audioElement.preload = 'auto';
  audioElement.setAttribute('aria-hidden', 'true');
  audioElement.style.display = 'none';
  document.body.appendChild(audioElement);

  // Cada abertura de pagina requer uma interacao para habilitar som no celular.
  // Nao manter um estado de "ligado" que esteja bloqueado pelo navegador.
  soundOn = false;
  let unlocked = false;
  let lastPlayedAt = 0;
  let initializedRoom = null;
  let previous = new Map();
  const baselineKey = roomId => P + 'cash-v4-' + roomId;
  function setLabel() {
    button.textContent = unlocked && soundOn ? '🔔 Som de dinheiro ligado' : '🔕 Ativar som de dinheiro';
    button.setAttribute('aria-pressed', String(unlocked && soundOn));
    test.textContent = '💵 Ouvir som real';
  }
  function describeError(error) {
    const code = audioElement.error?.code;
    if (code) return 'Arquivo MP3 indisponivel (erro de audio ' + code + '). Confira a internet.';
    if (error?.name === 'NotAllowedError') return 'Seu navegador bloqueou audio automatico. Toque em Ativar som novamente.';
    return 'Nao foi possivel tocar o MP3. Verifique volume, modo silencioso e conexao.';
  }
  function playNow(force = false) {
    if (!force && (!soundOn || !unlocked || document.hidden)) return Promise.resolve(false);
    try {
      // O play() precisa ser invocado SINCRONAMENTE dentro do toque no iOS.
      // Nao usar await/resume de AudioContext antes desta chamada.
      audioElement.pause();
      audioElement.currentTime = 0;
      audioElement.volume = 1;
      const started = audioElement.play();
      return Promise.resolve(started).then(() => {
        lastPlayedAt = Date.now();
        return true;
      }).catch(error => {
        if (!force) {
          unlocked = false;
          soundOn = false;
          setLabel();
          notice(describeError(error), true);
        }
        return false;
      });
    } catch (error) {
      if (!force) notice(describeError(error), true);
      return Promise.resolve(false);
    }
  }

  button.addEventListener('click', () => {
    if (soundOn && unlocked) {
      soundOn = false;
      unlocked = false;
      localStorage.setItem(P + 'sound', '0');
      audioElement.pause();
      setLabel();
      return;
    }
    // Chamada direta no evento click: desbloqueio de reproducao mobile.
    playNow(true).then(ok => {
      unlocked = ok;
      soundOn = ok;
      localStorage.setItem(P + 'sound', ok ? '1' : '0');
      setLabel();
      if (!ok) notice(describeError(), true);
    });
  });
  test.addEventListener('click', () => {
    // Reproducao explicita independente do estado dos avisos.
    playNow(true).then(ok => {
      if (!ok) notice(describeError(), true);
    });
  });
  audioElement.addEventListener('error', () => {
    if (soundOn) notice(describeError(), true);
  });
  setLabel();

  // O app original chamava esta funcao para tocar os bipes recebidos.
  // A substituicao elimina o sintetizador anterior.
  chime = () => { void playNow(); };

  // Reaproveita o historico seguro de 40 operacoes concluida(s) no painel.
  // Toca para todos da sala (pagador, recebedor e outros), sem popup a cada
  // credito, sem duplicar uma transacao que ja apareceu.
  watchCredits = async function observarTransacoes() {
    if (!room || !state || !Array.isArray(state.historico)) return;
    const key = baselineKey(room + '-' + state.meu_jogador_id);
    if (initializedRoom !== key) {
      initializedRoom = key;
      previous = new Map();
      try {
        const cached = JSON.parse(localStorage.getItem(key) || 'null');
        if (Array.isArray(cached)) for (const [id, status] of cached) {
          if (typeof id === 'string') previous.set(id, status);
        }
      } catch (_) { /* Dados locais antigos: recriar baseline. */ }
    }
    const hasBaseline = localStorage.getItem(key) !== null;
    let total = 0;
    const now = Date.now();
    for (const tx of state.historico) {
      if (!tx || typeof tx.id !== 'string') continue;
      const old = previous.get(tx.id);
      if (hasBaseline && tx.status === 'concluida' && old !== 'concluida'
          && now - Date.parse(tx.criada_em) < 120000) total++;
      previous.set(tx.id, tx.status);
    }
    try { localStorage.setItem(key, JSON.stringify([...previous].slice(-250))); }
    catch (_) { /* Sem armazenamento, continua exibindo os saldos. */ }
    if (total && soundOn && unlocked && !document.hidden) {
      // Um unico efeito para o lote de atualizacao evita sobreposicoes.
      void playNow();
    }
  };
})();