'use strict';
// Complemento da interface V3. Nenhuma alteracao em saldos ou no Supabase.
// Substitui o aviso antigo de credito e o botao antigo de som.
(function () {
  const oldButton = document.getElementById('sound');
  if (!oldButton) return;
  const soundButtonElement = oldButton.cloneNode(true);
  oldButton.replaceWith(soundButtonElement); // Remove o listener antigo que emitia somente dois bipes.
  const testButton = document.createElement('button');
  testButton.id = 'test-money-sound';
  testButton.type = 'button';
  testButton.textContent = '💸 Testar som de dinheiro';
  soundButtonElement.insertAdjacentElement('afterend', testButton);

  let cashContext = null;
  function context() {
    const AudioClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioClass) return null;
    cashContext ||= new AudioClass();
    return cashContext;
  }

  function playCashRegister(ctx) {
    const when = ctx.currentTime + 0.02;
    // Estalo da gaveta de caixa: ruido breve e seco.
    const noiseBuffer = ctx.createBuffer(1, Math.max(1, Math.floor(ctx.sampleRate * 0.10)), ctx.sampleRate);
    const channel = noiseBuffer.getChannelData(0);
    for (let i = 0; i < channel.length; i += 1) channel[i] = (Math.random() * 2 - 1) * Math.exp(-i / (ctx.sampleRate * 0.015));
    const click = ctx.createBufferSource();
    click.buffer = noiseBuffer;
    const clickVolume = ctx.createGain();
    clickVolume.gain.value = 0.20;
    click.connect(clickVolume);
    clickVolume.connect(ctx.destination);
    click.start(when);

    // Badaladas metalicas descendentes: 'ca-ching' em vez do bipe anterior.
    const bell = (frequency, delay, duration, volume) => {
      const start = when + delay;
      const oscillator = ctx.createOscillator();
      const envelope = ctx.createGain();
      oscillator.type = 'triangle';
      oscillator.frequency.setValueAtTime(frequency, start);
      oscillator.frequency.exponentialRampToValueAtTime(frequency * 0.88, start + duration);
      envelope.gain.setValueAtTime(0.0001, start);
      envelope.gain.exponentialRampToValueAtTime(volume, start + 0.008);
      envelope.gain.exponentialRampToValueAtTime(0.0001, start + duration);
      oscillator.connect(envelope);
      envelope.connect(ctx.destination);
      oscillator.start(start);
      oscillator.stop(start + duration + 0.02);
    };
    bell(1120, 0.05, 0.29, 0.20);
    bell(1650, 0.17, 0.48, 0.15);
    bell(2360, 0.18, 0.39, 0.065);
  }

  async function playMoney(force = false) {
    if (!force && (!soundOn || document.hidden)) return false;
    try {
      const ctx = context();
      if (!ctx) return false;
      if (ctx.state !== 'running') await ctx.resume();
      if (ctx.state !== 'running') return false;
      playCashRegister(ctx);
      return true;
    } catch (error) {
      console.warn('Não foi possível tocar o som de dinheiro:', error);
      return false;
    }
  }

  // Reaproveita o estado persistido do aplicativo, mas elimina o bip antigo.
  chime = function () { void playMoney(); };
  soundButtonElement.addEventListener('click', async () => {
    soundOn = !soundOn;
    localStorage.setItem(P + 'sound', soundOn ? '1' : '0');
    soundButton();
    if (!soundOn) { notice('Som desligado neste aparelho.'); return; }
    const ok = await playMoney(true); // Interacao direta desbloqueia o audio no celular.
    notice(ok ? 'Som de dinheiro ativado! 💸' : 'Áudio bloqueado pelo navegador. Confira o volume e toque em Testar som.', !ok);
  });
  testButton.addEventListener('click', async () => {
    const ok = await playMoney(true);
    notice(ok ? 'Teste do som de dinheiro reproduzido. 💸' : 'Não foi possível reproduzir. Verifique volume, modo silencioso e permissões do navegador.', !ok);
  });
  soundButton();

  // Escuta o historico da sala, nao apenas dinheiro recebido na propria conta.
  // A consulta bi_painel ja traz as ultimas 40 operacoes e e atualizada pelo app.
  watchCredits = async function observeEveryCompletedTransaction() {
    if (!room || !state || !Array.isArray(state.historico)) return;
    const storageKey = P + 'money-v3-' + room + '-' + state.meu_jogador_id;
    const previousRaw = localStorage.getItem(storageKey);
    const previous = new Map();
    if (previousRaw !== null) {
      try {
        const parsed = JSON.parse(previousRaw);
        if (Array.isArray(parsed)) {
          for (const item of parsed) {
            if (Array.isArray(item) && typeof item[0] === 'string') previous.set(item[0], item[1]);
          }
        }
      } catch (error) { console.warn('Histórico local de sons foi reiniciado:', error); }
    }
    const initial = previousRaw === null;
    const newTransactions = [];
    for (const tx of state.historico) {
      if (!tx || typeof tx.id !== 'string') continue;
      const priorStatus = previous.get(tx.id);
      if (!initial && tx.status === 'concluida' && priorStatus !== 'concluida') newTransactions.push(tx);
      previous.set(tx.id, tx.status);
    }
    localStorage.setItem(storageKey, JSON.stringify([...previous].slice(-250)));
    if (!soundOn || document.hidden || newTransactions.length === 0) return;
    // Um efeito por operacao concluida, com intervalo para evitar sobreposicao.
    newTransactions.slice(0, 6).forEach((tx, index) => {
      window.setTimeout(() => { void playMoney(); }, index * 750);
    });
  };
})();