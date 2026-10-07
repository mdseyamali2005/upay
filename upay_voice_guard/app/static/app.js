/* ═══════════════════════════════════════════════════════════════
   upay Voice Guard — Interactive Call Logic
   Handles session state, keypad, web speech TTS/STT, and UI
   ═══════════════════════════════════════════════════════════════ */

let sessionId = null;
let timerInterval = null;
let callStartTime = null;

// DOM Elements
const screenLanding = document.getElementById('screen-landing');
const screenCall = document.getElementById('screen-call');
const btnStartCall = document.getElementById('btn-start-call');
const btnEndCall = document.getElementById('btn-end-call');
const callTimerEl = document.getElementById('call-timer');
const voiceWave = document.getElementById('voice-wave');
const chatArea = document.getElementById('chat-area');

const keypadSection = document.getElementById('keypad-section');
const keypadInput = document.getElementById('keypad-input');
const keypadBackspace = document.getElementById('keypad-backspace');
const keypadSend = document.getElementById('keypad-send');

const speechSection = document.getElementById('speech-section');
const speechInput = document.getElementById('speech-input');
const speechSend = document.getElementById('speech-send');

const settingsToggle = document.getElementById('btn-settings-toggle');
const settingsPanel = document.getElementById('settings-panel');
const limitInput = document.getElementById('limit-input');
const btnSetLimit = document.getElementById('btn-set-limit');
const limitStatus = document.getElementById('limit-status');

// ── Web Speech Synthesis (TTS) via backend endpoint ──
async function speak(text) {
  voiceWave.classList.add('speaking');
  try {
    const res = await fetch('/tts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text })
    });
    if (!res.ok) throw new Error('TTS error');
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const audio = new Audio(url);
    
    // Cleanup old audio object URLs if necessary, but browsers GC them when audio is gone
    audio.onended = () => {
      voiceWave.classList.remove('speaking');
      URL.revokeObjectURL(url);
    };
    audio.onerror = () => {
      voiceWave.classList.remove('speaking');
      URL.revokeObjectURL(url);
    };
    audio.play();
  } catch (err) {
    console.error(err);
    setTimeout(() => voiceWave.classList.remove('speaking'), 2000);
  }
}

// ── Audio Beep for Keypad ──
function playKeyTone() {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(650, ctx.currentTime);
    gain.gain.setValueAtTime(0.08, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.1);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.1);
  } catch (e) { }
}

// ── Call Timer ──
function startTimer() {
  callStartTime = Date.now();
  timerInterval = setInterval(() => {
    const diff = Math.floor((Date.now() - callStartTime) / 1000);
    const mins = String(Math.floor(diff / 60)).padStart(2, '0');
    const secs = String(diff % 60).padStart(2, '0');
    callTimerEl.textContent = `${mins}:${secs}`;
  }, 1000);
}

function stopTimer() {
  if (timerInterval) clearInterval(timerInterval);
  callTimerEl.textContent = '00:00';
}

// ── Chat UI ──
function appendMessage(sender, text, tagText = '', isWarning = false) {
  const msgDiv = document.createElement('div');
  msgDiv.className = `msg ${sender}`;

  const avatar = document.createElement('div');
  avatar.className = 'msg-avatar';
  if (sender === 'agent') {
    const logoImg = document.createElement('img');
    logoImg.src = '/static/upay-logo.png';
    logoImg.alt = 'upay';
    logoImg.className = 'avatar-logo-img';
    avatar.appendChild(logoImg);
  } else {
    avatar.textContent = '👤';
  }

  const bubble = document.createElement('div');
  bubble.className = `msg-bubble ${isWarning ? 'warning' : ''}`;

  if (tagText) {
    const tag = document.createElement('span');
    tag.className = 'msg-tag';
    tag.textContent = tagText;
    bubble.appendChild(tag);
    bubble.appendChild(document.createElement('br'));
  }

  const textNode = document.createTextNode(text);
  bubble.appendChild(textNode);

  msgDiv.appendChild(avatar);
  msgDiv.appendChild(bubble);
  chatArea.appendChild(msgDiv);
  chatArea.scrollTop = chatArea.scrollHeight;
}

// ── State Handler ──
function updateInputState(expect, digits = null) {
  keypadInput.value = '';
  speechInput.value = '';

  if (expect === 'keypad') {
    keypadSection.classList.remove('hidden');
    speechSection.classList.add('hidden');
    keypadInput.placeholder = digits ? `${digits} সংখ্যার PIN/নম্বর দিন...` : 'পরিমাণ/নম্বর দিন...';
  } else if (expect === 'speech') {
    speechSection.classList.remove('hidden');
    keypadSection.classList.add('hidden');
    speechInput.focus();
  } else {
    keypadSection.classList.add('hidden');
    speechSection.classList.add('hidden');
  }
}

// ── API Interactions ──
async function startSession() {
  try {
    const res = await fetch('/session/start', { method: 'POST' });
    const data = await res.json();
    sessionId = data.session_id;

    screenLanding.classList.remove('active');
    screenCall.classList.add('active');
    chatArea.innerHTML = '';
    startTimer();

    appendMessage('agent', data.say, data.expect === 'keypad' ? '🔑 Keypad required' : '🗣️ Speech');
    speak(data.say);
    updateInputState(data.expect, data.digits);
  } catch (err) {
    alert('Failed to connect to backend server. Make sure server is running.');
  }
}

async function sendInput(kind, value) {
  if (!sessionId) return;
  if (!value && kind === 'keypad') return;

  const displayTag = kind === 'keypad' ? '🔢 Keypad input' : '🗣️ Speech input';
  appendMessage('user', value || '(empty)', displayTag);

  try {
    const res = await fetch(`/session/${sessionId}/input`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ kind, value })
    });

    const data = await res.json();
    const isWarning = data.say.includes('সতর্কতা');

    appendMessage('agent', data.say, data.expect === 'keypad' ? '🔑 Keypad required' : data.expect === 'speech' ? '🗣️ Speech' : '🏁 Call End', isWarning);
    speak(data.say);

    if (data.end) {
      updateInputState('none');
      setTimeout(showCallEndedOverlay, 2500);
    } else {
      updateInputState(data.expect, data.digits);
    }
  } catch (err) {
    appendMessage('agent', 'Error communicating with server.');
  }
}

function showCallEndedOverlay() {
  stopTimer();
  const overlay = document.createElement('div');
  overlay.className = 'call-ended-overlay';
  overlay.innerHTML = `
    <h2>কলটি শেষ হয়েছে</h2>
    <p>ধন্যবাদ, upay Voice Guard ব্যবহার করার জন্য।</p>
    <button class="btn-new-call" id="btn-restart">নতুন কল শুরু করুন</button>
  `;
  document.body.appendChild(overlay);

  document.getElementById('btn-restart').addEventListener('click', () => {
    overlay.remove();
    screenCall.classList.remove('active');
    screenLanding.classList.add('active');
  });
}

function endCall() {
  stopTimer();
  screenCall.classList.remove('active');
  screenLanding.classList.add('active');
  sessionId = null;
}

// ── Event Listeners ──
btnStartCall.addEventListener('click', startSession);
btnEndCall.addEventListener('click', endCall);

// Keypad buttons
document.querySelectorAll('.kp').forEach(btn => {
  btn.addEventListener('click', () => {
    playKeyTone();
    keypadInput.value += btn.getAttribute('data-val');
  });
});

keypadBackspace.addEventListener('click', () => {
  playKeyTone();
  keypadInput.value = keypadInput.value.slice(0, -1);
});

keypadSend.addEventListener('click', () => {
  const val = keypadInput.value.trim();
  if (val) sendInput('keypad', val);
});

keypadInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    const val = keypadInput.value.trim();
    if (val) sendInput('keypad', val);
  }
});

// Speech section
speechSend.addEventListener('click', () => {
  const val = speechInput.value.trim();
  if (val) sendInput('speech', val);
});

speechInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    const val = speechInput.value.trim();
    if (val) sendInput('speech', val);
  }
});

// Quick buttons
document.querySelectorAll('.quick-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    const sayText = btn.getAttribute('data-say');
    sendInput('speech', sayText);
  });
});

// Settings / Limit Panel
settingsToggle.addEventListener('click', async () => {
  settingsPanel.classList.toggle('hidden');
  if (!settingsPanel.classList.contains('hidden')) {
    try {
      const res = await fetch('/limit');
      const data = await res.json();
      limitInput.value = data.limit;
    } catch (e) { }
  }
});

btnSetLimit.addEventListener('click', async () => {
  const newLimit = parseInt(limitInput.value, 10);
  if (isNaN(newLimit) || newLimit < 100 || newLimit > 50000) {
    limitStatus.style.color = '#EF4444';
    limitStatus.textContent = 'সীমা ১০০ থেকে ৫০,০০০ টাকার মধ্যে হতে হবে';
    return;
  }
  try {
    const res = await fetch('/limit', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ limit: newLimit })
    });
    if (res.ok) {
      limitStatus.style.color = '#22C55E';
      limitStatus.textContent = 'সীমা সফলভাবে আপডেট হয়েছে!';
      setTimeout(() => { limitStatus.textContent = ''; }, 3000);
    }
  } catch (err) {
    limitStatus.style.color = '#EF4444';
    limitStatus.textContent = 'আপডেট ব্যর্থ হয়েছে';
  }
});

// ══════════════════════════════════════════════════════════════
//  Web Speech Recognition (STT) — Browser-side, no API key
// ══════════════════════════════════════════════════════════════
const btnMic = document.getElementById('btn-mic');
const micStatus = document.getElementById('mic-status');
let recognition = null;
let isListening = false;

const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

if (SpeechRecognition) {
  recognition = new SpeechRecognition();
  recognition.lang = 'bn-BD';
  recognition.continuous = false;
  recognition.interimResults = true;
  recognition.maxAlternatives = 1;

  recognition.onstart = () => {
    isListening = true;
    btnMic.classList.add('recording');
    micStatus.classList.remove('hidden');
    micStatus.classList.add('listening');
    micStatus.textContent = '🎙️ শুনছি...';
  };

  recognition.onresult = (event) => {
    let transcript = '';
    for (let i = event.resultIndex; i < event.results.length; i++) {
      transcript += event.results[i][0].transcript;
    }
    speechInput.value = transcript;

    // If the result is final, auto-send
    if (event.results[event.results.length - 1].isFinal) {
      const finalText = transcript.trim();
      if (finalText) {
        micStatus.textContent = '✅ পাওয়া গেছে!';
        micStatus.classList.remove('listening');
        setTimeout(() => {
          sendInput('speech', finalText);
          micStatus.classList.add('hidden');
        }, 400);
      }
    }
  };

  recognition.onerror = (event) => {
    isListening = false;
    btnMic.classList.remove('recording');
    micStatus.classList.remove('listening');
    if (event.error === 'no-speech') {
      micStatus.textContent = '😶 কোনো কথা শোনা যায়নি। আবার চেষ্টা করুন।';
    } else if (event.error === 'not-allowed') {
      micStatus.textContent = '🚫 মাইক্রোফোন ব্যবহারের অনুমতি দিন।';
    } else {
      micStatus.textContent = `⚠️ ত্রুটি: ${event.error}`;
    }
    setTimeout(() => micStatus.classList.add('hidden'), 3000);
  };

  recognition.onend = () => {
    isListening = false;
    btnMic.classList.remove('recording');
  };

  btnMic.addEventListener('click', () => {
    if (isListening) {
      recognition.stop();
    } else {
      speechInput.value = '';
      recognition.start();
    }
  });
} else {
  // Browser doesn't support Speech Recognition — hide mic button
  btnMic.style.display = 'none';
  console.log('Web Speech Recognition API not available in this browser.');
}
