'use strict';
// Complemento da interface v2: o aviso vale para QUALQUER operacao financeira
// concluida na sala, e nao apenas para dinheiro recebido pelo usuario.
// Substitui o observador antigo, chamado automaticamente por refresh().
function tocarCaixaRegistradora() {
  if (!soundOn || document.hidden) return;
  try {
    const Audio = window.AudioContext || window.webkitAudioContext;
    if (!Audio) return;
    audio ||= new Audio();
    if (audio.state !== 'running') return;
    const now = audio.currentTime + 0.015;
    const coin = (frequency, delay, length, volume, waveform = 'sine') => {
      const tone = audio.createOscillator();
      const envelope = audio.createGain();
      const start = now + delay;
      tone.type = waveform;
      tone.frequency.setValueAtTime(frequency, start);
      tone.frequency.exponentialRampToValueAtTime(frequency * 1.05, start + length);
      envelope.gain.setValueAtTime(0.0001, start);
      envelope.gain.exponentialRampToValueAtTime(volume, start + 0.008);
      envelope.gain.exponentialRampToValueAtTime(0.0001, start + length);
      tone.connect(envelope);
      envelope.connect(audio.destination);
      tone.start(start);
      tone.stop(start + length + 0.01);
    };
    // Clique da caixa, seguido de duas moedas metalicas: "ca-ching".
    coin(460, 0, 0.075, 0.085, 'triangle');
    coin(1080, 0.085, 0.28, 0.15);
    coin(1580, 0.185, 0.38, 0.12);
  } catch (error) {
    console.warn('Som de transacao indisponivel:', error);
  }
}

// O navegador exige interacao para liberar audio. Em visitas subsequentes,
// o primeiro toque na interface reativa o audio se o usuario deixou o som ligado.
window.addEventListener('pointerdown', () => {
  if (!soundOn) return;
  try {
    const Audio = window.AudioContext || window.webkitAudioContext;
    if (!Audio) return;
    audio ||= new Audio();
    if (audio.state === 'suspended') audio.resume().catch(() => {});
  } catch (_) { /* Sem audio neste dispositivo. */ }
}, { passive: true });

chime = tocarCaixaRegistradora;
watchCredits = async function observarTransacoes() {
  if (!room || !state || !Array.isArray(state.historico)) return;
  const key = P + 'transacoes-' + room + '-' + state.meu_jogador_id;
  const previousRaw = localStorage.getItem(key);
  const previous = new Map();
  if (previousRaw !== null) {
    try {
      const saved = JSON.parse(previousRaw);
      if (Array.isArray(saved)) {
        for (const item of saved) {
          if (Array.isArray(item) && typeof item[0] === 'string') {
            previous.set(item[0], item[1]);
          }
        }
      }
    } catch (_) { /* Dados antigos invalidos: reinicializa a linha de base. */ }
  }
  const firstVisit = previousRaw === null;
  const fresh = [];
  // bi_painel expoe as 40 transacoes recentes, inclusive cobrancas pendentes.
  // Uma cobranca so soa quando passar de pendente para concluida.
  for (const transaction of state.historico) {
    if (!transaction || typeof transaction.id !== 'string') continue;
    const oldStatus = previous.get(transaction.id);
    if (!firstVisit && transaction.status === 'concluida' && oldStatus !== 'concluida') {
      fresh.push(transaction);
    }
    previous.set(transaction.id, transaction.status);
  }
  // Mantem memoria dos IDs anteriores para nao repetir avisos quando o
  // historico gira e um item deixa de aparecer nas ultimas 40 operacoes.
  localStorage.setItem(key, JSON.stringify([...previous].slice(-250)));
  if (!fresh.length) return;
  // Em lote, reproduz um toque e exibe o total para evitar sobreposicao.
  if (soundOn && !document.hidden) {
    tocarCaixaRegistradora();
    notice(fresh.length === 1
      ? '💰 Transacao concluida: ' + money(fresh[0].valor) + ' · ' + fresh[0].de + ' → ' + fresh[0].para
      : '💰 ' + fresh.length + ' transacoes concluidas na sala.');
  }
};