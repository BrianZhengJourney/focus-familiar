/* ── orchestration: app switching, sandbox engine, boot ──── */

let activeApp = null;

function switchApp(id, { user = false } = {}){
  if (id === activeApp) { if (user) Sandbox.noteSwitch(); return; }
  activeApp = id;
  const app = APPS[id];
  document.querySelectorAll('.window').forEach(w => w.classList.remove('on'));
  document.getElementById(`win-${id}`).classList.add('on');
  document.querySelectorAll('.dock-app').forEach(d => d.classList.remove('active'));
  document.getElementById(`dock-${id}`).classList.add('active');
  document.getElementById('mbApp').textContent = app.name;

  // per-app live content
  if (id === 'code') typeCode();
  if (id === 'term') runTerm();
  doomscroll(id === 'x');
  playShorts(id === 'shorts');

  if (user) Sandbox.noteSwitch();
}

/* ── sandbox: a tiny live focus engine so people can play ── */
const Sandbox = {
  on: false, timer: null,
  distractSec: 0, deepSec: 0, switches: [],

  start(){
    this.on = true;
    Demo.stopAll();
    hideCards(); QuestMap.hide();
    document.getElementById('demoChrome').classList.add('on');
    Familiar.hud(true);
    setCaption('sandbox — click dock apps and watch it react · <em>R</em> restore context · <em>Q</em> quest map', 6000);
    if (!activeApp) switchApp('code');
    clearInterval(this.timer);
    this.timer = setInterval(() => this.tick(), 1000);
  },
  stop(){ this.on = false; clearInterval(this.timer); },

  noteSwitch(){
    if (!this.on) return;
    const now = Date.now();
    this.switches = this.switches.filter(t => now - t < 5000);
    this.switches.push(now);
    if (this.switches.length >= 4) {           // frantic switching → ghost
      Familiar.setState('ghost');
      document.getElementById('desktop').classList.add('glitching');
      setTimeout(() => document.getElementById('desktop').classList.remove('glitching'), 900);
      this.distractSec = Math.max(this.distractSec, 10);
    }
    this.deepSec = Math.min(this.deepSec, 3);   // switching resets momentum
  },

  tick(){
    if (!this.on || !activeApp) return;
    const kind = APPS[activeApp].kind;
    const v = document.getElementById('vignette');

    if (kind === 'deep') {
      this.deepSec++; this.distractSec = Math.max(0, this.distractSec - 2);
      Familiar.setFocus(Familiar.focus + 1.6);
      Familiar.setStreak(Familiar.streakMin + 1);          // 1 "minute" per second, demo time
      if (this.deepSec === 4) Familiar.setState(activeApp === 'paper' ? 'scholar' : 'focused');
      if (this.deepSec % 7 === 0) {
        const r = APPS[activeApp].resource;
        r && Familiar.gain(r.key, r.icon, r.label, document.getElementById(`win-${activeApp}`));
      }
      if (Familiar.streakMin === 25) toast('🔥 25-minute streak', 'the familiar hums contentedly');
      if (Familiar.streakMin === 50 && Familiar.level === 1) Familiar.levelUp();
      if (this.distractSec === 0) v.className = 'vignette';
    } else {
      this.distractSec++; this.deepSec = 0;
      Familiar.setFocus(Familiar.focus - 2.6);
      Familiar.setStreak(0);
      if (this.distractSec === 3)  Familiar.setState('dizzy');
      if (this.distractSec === 9) { Familiar.setState('poisoned'); v.classList.add('on'); }
      if (this.distractSec === 18){ Familiar.setState('ghost');    v.classList.add('ghostly'); }
    }
  },
};

/* ── cards ── */
function hideCards(){
  document.getElementById('titleCard').classList.add('off');
  const ec = document.getElementById('endCard');
  ec && ec.classList.add('off');
}
function showEndCard(){
  let ec = document.getElementById('endCard');
  if (!ec) {
    ec = document.createElement('div');
    ec.className = 'card-overlay endcard off';
    ec.id = 'endCard';
    ec.innerHTML = `
      <div class="tc-inner">
        <div class="tc-creature" id="ecCreatureSlot"></div>
        <h1 class="tc-logo" style="font-size:40px">Focus <em>Familiar</em></h1>
        <p class="tc-tag">a creature that lives inside your workflow,<br>protects your focus, and remembers what you forgot.</p>
        <div class="ec-pillars">
          <span class="ec-pill">🐾 desktop pet</span>
          <span class="ec-pill">⚔️ RPG companion</span>
          <span class="ec-pill">🔮 context memory</span>
          <span class="ec-pill">🕯️ ambient coach</span>
        </div>
        <button class="tc-btn" onclick="Demo.play(0)">↻ &nbsp;watch again</button>
        <button class="tc-skip" onclick="Sandbox.start()">play with it in the sandbox</button>
      </div>`;
    document.getElementById('desktop').appendChild(ec);
    cloneCreatureInto('ecCreatureSlot');
    // end-card creature wears the evolved palette
    const slot = document.getElementById('ecCreatureSlot');
    slot.style.setProperty('--fam-hi', '#ffe9b0');
    slot.style.setProperty('--fam-lo', '#f0a832');
    slot.style.setProperty('--wisp', '#ffd76a');
    slot.style.setProperty('--fam-eye', '#4a2e08');
    slot.querySelector('.crown').style.opacity = 1;
  }
  requestAnimationFrame(() => ec.classList.remove('off'));
}

/* ── clock ── */
function tickClock(){
  const d = new Date();
  let h = d.getHours(); const m = String(d.getMinutes()).padStart(2, '0');
  const ap = h >= 12 ? 'PM' : 'AM'; h = h % 12 || 12;
  document.getElementById('mbClock').textContent = `${h}:${m} ${ap}`;
}

/* ── boot ── */
window.addEventListener('DOMContentLoaded', () => {
  mountWindows();
  mountDock(switchApp);
  Familiar.init();
  Demo.buildDots();
  cloneCreatureInto('tcCreatureSlot');
  tickClock(); setInterval(tickClock, 20000);

  document.getElementById('tcStart').onclick = () => Demo.play(0);
  document.getElementById('tcSkip').onclick = () => Sandbox.start();
  document.getElementById('btnPlay').onclick = () => Demo.play(0);
  document.getElementById('btnFree').onclick = () => Sandbox.start();
  document.getElementById('qmClose').onclick = () => QuestMap.hide();
  document.getElementById('familiar').onclick = () => Familiar.restoreContext();

  window.addEventListener('keydown', e => {
    if (e.key === 'Escape') { QuestMap.hide(); Familiar.hush(); }
    if (e.code === 'Space' && e.altKey) { e.preventDefault(); Familiar.restoreContext(); }
    const k = e.key.toLowerCase();
    if (k === 'r' && !e.metaKey) Familiar.restoreContext();
    if (k === 'q' && !e.metaKey) QuestMap.show();
  });
});
