/* ── the familiar: states, faces, resources, pickups, bubble ── */

const Familiar = {
  el: null, zone: null,
  state: 'idle',
  level: 1,
  focus: 55,           // 0–100 focus flame
  streakMin: 0,
  resources: { protein: 0, iron: 0, spellbook: 0, fragment: 0 },

  FACE_FOR: {
    idle: 'open', focused: 'happy', scholar: 'open', dizzy: 'spiral',
    poisoned: 'dead', ghost: 'low', evolved: 'happy', sleep: 'low',
  },

  init(){
    this.el = document.getElementById('familiar');
    this.zone = document.getElementById('familiarZone');
    this.setState('idle');
    this.renderRes();
    setInterval(() => this.blink(), 4200);
  },

  setState(s){
    this.state = s;
    this.el.dataset.state = s;
    this.el.dataset.famFace = this.FACE_FOR[s] || 'open';
    const glyph = document.getElementById('mbGlyph');
    glyph.textContent = { idle:'◐', focused:'●', scholar:'◉', dizzy:'◒', poisoned:'◍', ghost:'○', evolved:'✦' }[s] || '◐';
  },

  blink(){
    if (this.el.dataset.famFace !== 'open') return;
    this.el.dataset.famFace = 'low';
    setTimeout(() => { if (this.state && this.FACE_FOR[this.state] === 'open') this.el.dataset.famFace = 'open'; }, 140);
  },

  setFocus(v){
    this.focus = Math.max(0, Math.min(100, v));
    const f = document.getElementById('flameFill');
    f.style.width = this.focus + '%';
    f.classList.toggle('low', this.focus < 30);
  },

  setStreak(min){
    this.streakMin = min;
    document.getElementById('streakMin').textContent = min + 'm';
  },

  hud(on){ document.getElementById('hud').classList.toggle('on', on); },

  renderRes(){
    const icons = { protein:'🥩', iron:'⛓️', spellbook:'📖', fragment:'🔮' };
    const box = document.getElementById('hudRes');
    box.innerHTML = Object.entries(this.resources)
      .filter(([,v]) => v > 0)
      .map(([k,v]) => `<span class="res-chip" data-res="${k}">${icons[k]} <b>${v}</b></span>`)
      .join('');
  },

  gain(key, icon, label, fromEl){
    // spawn pickup at the active window, fly it to the familiar
    const layer = document.getElementById('pickups');
    const p = document.createElement('div');
    p.className = 'pickup';
    p.innerHTML = `${icon}<span class="pk-label">${label}</span>`;
    const src = fromEl?.getBoundingClientRect();
    const x0 = src ? src.left + src.width * (0.3 + Math.random() * 0.4) : innerWidth * 0.4;
    const y0 = src ? src.top + src.height * (0.3 + Math.random() * 0.3) : innerHeight * 0.4;
    p.style.transform = `translate(${x0}px, ${y0}px) scale(1)`;
    layer.appendChild(p);
    const dst = this.el.getBoundingClientRect();
    requestAnimationFrame(() => requestAnimationFrame(() => {
      p.style.transform = `translate(${dst.left + 46}px, ${dst.top + 40}px) scale(.45)`;
      p.style.opacity = '0';
    }));
    setTimeout(() => {
      p.remove();
      this.resources[key]++;
      this.renderRes();
      const chip = document.querySelector(`.res-chip[data-res="${key}"]`);
      chip && chip.classList.add('pop');
      chip && setTimeout(() => chip.classList.remove('pop'), 500);
      this.sparkle(2);
    }, 1080);
  },

  sparkle(n = 3){
    const r = this.el.getBoundingClientRect();
    for (let i = 0; i < n; i++) {
      const s = document.createElement('div');
      s.className = 'spark';
      s.style.left = r.left + 18 + Math.random() * (r.width - 36) + 'px';
      s.style.top = r.top + 12 + Math.random() * 40 + 'px';
      s.style.animationDelay = (Math.random() * 0.35) + 's';
      document.body.appendChild(s);
      setTimeout(() => s.remove(), 1900);
    }
  },

  levelUp(){
    this.level++;
    this.el.dataset.level = this.level;
    const ring = document.getElementById('evolveRing');
    ring.classList.remove('burst'); void ring.offsetWidth; ring.classList.add('burst');
    this.setState('evolved');
    this.sparkle(9);
    toast(`✦ your familiar evolved — <b>Emberling, lv.${this.level}</b> ✦`, 'fed on 92 minutes of unbroken focus', 3600);
  },

  /* ── speech bubble ── */
  say(html, { sticky = false, ms = 5200 } = {}){
    const b = document.getElementById('bubble');
    document.getElementById('bubbleInner').innerHTML = html;
    b.classList.add('on');
    clearTimeout(this._sayT);
    if (!sticky) this._sayT = setTimeout(() => b.classList.remove('on'), ms);
  },
  hush(){ document.getElementById('bubble').classList.remove('on'); clearTimeout(this._sayT); },

  /* the signature move: restore lost context */
  restoreContext(){
    this.say(`<div class="bb-head">✦ remembering…</div><div class="bb-typing"><i></i><i></i><i></i></div>`, { sticky: true });
    setTimeout(() => {
      this.say(`
        <div class="bb-head">✦ here's your thread</div>
        <div class="bb-thread">
          <div class="tt">Encoder CS-timing bug — opensarm</div>
          <div class="ts">Before the meeting, you fixed the 350ns CS hold in
            <span class="bb-mono">motor_controller.c</span> and were about to flash joint&nbsp;3.</div>
        </div>
        <div>Next thing you said you'd do: run <span class="bb-mono">make flash</span>,
          then the 10-min jitter soak. The AS5047 datasheet is still open at §7.3.</div>
        <div class="bb-actions">
          <button class="bb-btn primary">⚡ resume thread</button>
          <button class="bb-btn">show my last 20 min</button>
        </div>`, { sticky: true });
    }, 1600);
  },
};

/* ── toast helper ── */
let _toastT = null;
function toast(html, sub = '', ms = 3000){
  const t = document.getElementById('toast');
  t.innerHTML = html + (sub ? `<small>${sub}</small>` : '');
  t.classList.add('on');
  clearTimeout(_toastT);
  _toastT = setTimeout(() => t.classList.remove('on'), ms);
}

/* clone creature svg into the title card.
   defs ids must be unique per clone, or url(#…) fills resolve to the
   live familiar's gradient and the clone inherits its current state */
function cloneCreatureInto(slotId){
  const slot = document.getElementById(slotId);
  if (!slot) return;
  let html = document.getElementById('creatureSvg').outerHTML;
  html = html.replace('id="creatureSvg"', '')
    .replaceAll('bodyGrad', `bodyGrad-${slotId}`)
    .replaceAll('id="soft"', `id="soft-${slotId}"`)
    .replaceAll('url(#soft)', `url(#soft-${slotId})`);
  slot.dataset.famFace = 'open';   // face visibility is driven by this attribute
  slot.innerHTML = html;
}
