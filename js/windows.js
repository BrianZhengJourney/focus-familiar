/* ── fake app windows + dock ─────────────────────────────── */

const APPS = {
  code: {
    name: 'Code', title: 'motor_controller.c — opensarm', kind: 'deep',
    resource: { icon: '🥩', label: '+protein', key: 'protein' },
    dockBg: 'linear-gradient(135deg,#3b6fd4,#2450a8)', dockGlyph: '⌘',
  },
  term: {
    name: 'Terminal', title: 'brian@arm — make flash', kind: 'deep',
    resource: { icon: '⛓️', label: '+iron', key: 'iron' },
    dockBg: 'linear-gradient(135deg,#23262e,#101217)', dockGlyph: '❯_',
  },
  kicad: {
    name: 'KiCad', title: 'sarm_driver_board.kicad_pcb', kind: 'deep',
    resource: { icon: '⛓️', label: '+iron', key: 'iron' },
    dockBg: 'linear-gradient(135deg,#2e4f43,#173029)', dockGlyph: '⬡',
  },
  paper: {
    name: 'Preview', title: 'diffusion-policy.pdf — page 4 of 22', kind: 'deep',
    resource: { icon: '📖', label: '+spellbook', key: 'spellbook' },
    dockBg: 'linear-gradient(135deg,#e8e2d2,#c9c2ae)', dockGlyph: '¶',
  },
  notion: {
    name: 'Notion', title: 'SARM bring-up checklist', kind: 'deep',
    resource: { icon: '🔮', label: '+memory fragment', key: 'fragment' },
    dockBg: 'linear-gradient(135deg,#f7f6f3,#d8d5cd)', dockGlyph: 'N',
  },
  x: {
    name: 'X', title: 'Home / X', kind: 'distraction',
    dockBg: 'linear-gradient(135deg,#1c1c1c,#000)', dockGlyph: '𝕏',
  },
  shorts: {
    name: 'YouTube', title: 'Shorts', kind: 'distraction',
    dockBg: 'linear-gradient(135deg,#e33,#a00)', dockGlyph: '▶',
  },
};

const CODE_LINES = [
  [['tok-cm','// SPI transaction for the AS5047 encoder']],
  [['tok-kw','static'],['','  '],['tok-ty','uint16_t'],['',' '],['tok-fn','encoder_read_angle'],['','(']] ,
  [['','    '],['tok-ty','spi_dev_t'],['',' *dev) {']],
  [['','    '],['tok-fn','gpio_write'],['','(dev->cs, '],['tok-num','0'],['','];  '],['tok-cm','// assert CS ↓']],
  [['','    '],['tok-ty','uint16_t'],['',' raw = '],['tok-fn','spi_xfer16'],['','(dev, '],['tok-num','0xFFFF'],['',');']],
  [['','    '],['tok-fn','delay_ns'],['','('],['tok-num','350'],['',');       '],['tok-cm','// t_CSn ≥ 350ns  ← the fix']],
  [['','    '],['tok-fn','gpio_write'],['','(dev->cs, '],['tok-num','1'],['',');']],
  [['','    '],['tok-kw','return'],['',' raw & '],['tok-num','0x3FFF'],['',';']],
  [['','}']],
];

const TERM_LINES = [
  ['term-prompt', '❯ make flash'],
  ['term-dim',  'arm-none-eabi-gcc -O2 -mcpu=cortex-m4 motor_controller.c'],
  ['term-dim',  'arm-none-eabi-objcopy -O binary firmware.elf firmware.bin'],
  ['',          'Flashing 41,208 bytes to 0x08000000…'],
  ['term-dim',  '████████████████████████  100%'],
  ['term-ok',   '✓ verified · device reset'],
  ['term-warn', 'encoder self-test: angle=217.4° jitter=0.02° — clean'],
  ['term-prompt','❯ '],
];

const X_POSTS = [
  { name:'techbro.eth', handle:'@shipfast', av:'#7b5cff',
    text:'unpopular opinion: nobody actually reads the papers they retweet 🧵 (1/23)', img:null },
  { name:'DramaAlert', handle:'@drama', av:'#e0447a',
    text:'You will NOT believe what happened at the robotics conference today 😱😱', img:'linear-gradient(120deg,#e0447a,#7b2cbf)' },
  { name:'hot takes only', handle:'@takes', av:'#f2a33c',
    text:'C is dead. Rust is dead. Everything is dead. We should all write firmware in JavaScript.', img:null },
  { name:'CatsDoingThings', handle:'@cats', av:'#3cb9f2',
    text:'cat discovers oscilloscope (sound on) 🔊', img:'linear-gradient(120deg,#3cb9f2,#2a6fdb)' },
  { name:'ReplyGuy9000', handle:'@wellactually', av:'#66d17e',
    text:'well actually if you read the datasheet section 7.3.2 footnote 4…', img:null },
  { name:'techbro.eth', handle:'@shipfast', av:'#7b5cff',
    text:'day 47 of building in public: today I renamed a variable', img:null },
  { name:'AI Hype Daily', handle:'@agi_tmrw', av:'#c93cf2',
    text:'BREAKING: model can now count the Rs in strawberry (this changes everything)', img:'linear-gradient(120deg,#c93cf2,#5c2ce0)' },
  { name:'DoomScroll', handle:'@onemore', av:'#8892a0',
    text:'you’ve been scrolling for 11 minutes. this post is not a sign. keep going.', img:null },
];

const SHORTS = [
  { label:'POV: your solder bridge', sub:'@fixitfelix · 2.1M', bg:'linear-gradient(160deg,#ff6b6b,#7b2cbf)' },
  { label:'ranking capacitors by vibes', sub:'@voltvibes · 890K', bg:'linear-gradient(160deg,#3cb9f2,#0e4da0)' },
  { label:'day in my life as a robot', sub:'@sarm_official · 4.4M', bg:'linear-gradient(160deg,#66d17e,#0e6e4a)' },
  { label:'this one trick voids warranties', sub:'@donttrythis · 1.7M', bg:'linear-gradient(160deg,#f2a33c,#c0392b)' },
];

/* ── builders ── */

function el(tag, cls, html){
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (html != null) n.innerHTML = html;
  return n;
}

function winShell(id, app, geo){
  const w = el('div', `window win-${id}`);
  w.id = `win-${id}`;
  Object.assign(w.style, geo);
  w.innerHTML = `
    <div class="titlebar">
      <div class="lights"><span class="light r"></span><span class="light y"></span><span class="light g"></span></div>
      <div class="win-title">${app.title}</div>
    </div>
    <div class="win-body"></div>`;
  return w;
}

function buildCode(w){
  const b = w.querySelector('.win-body');
  b.innerHTML = `
    <div class="code-side"><i></i><i></i><i></i><i></i></div>
    <div class="code-tree">
      <div>▾ opensarm</div>
      <div>&nbsp;&nbsp;▸ drivers</div>
      <div class="sel">&nbsp;&nbsp;&nbsp;&nbsp;motor_controller.c</div>
      <div>&nbsp;&nbsp;&nbsp;&nbsp;encoder.h</div>
      <div>&nbsp;&nbsp;▸ scripts</div>
      <div>&nbsp;&nbsp;Makefile</div>
    </div>
    <div class="code-main" id="codeMain"></div>`;
}

function typeCode(reset = true){
  const m = document.getElementById('codeMain');
  if (!m) return;
  if (reset) m.innerHTML = '';
  CODE_LINES.forEach((line, i) => {
    const d = el('div', 'ln');
    d.style.animationDelay = `${i * 0.42}s`;
    d.innerHTML = line.map(([c, t]) => `<span class="${c}">${t}</span>`).join('');
    m.appendChild(d);
  });
  const cur = el('span', 'code-cursor');
  const last = m.lastChild;
  last && last.appendChild(cur);
}

function buildTerm(w){ w.querySelector('.win-body').id = 'termBody'; }

function runTerm(){
  const b = document.getElementById('termBody');
  if (!b) return;
  b.innerHTML = '';
  TERM_LINES.forEach(([cls, txt], i) => {
    const d = el('div', `term-line ${cls}`);
    d.textContent = txt;
    d.style.animationDelay = `${i * 0.5}s`;
    b.appendChild(d);
  });
}

function buildKicad(w){
  w.querySelector('.win-body').innerHTML = `
    <div class="kicad-toolbar"><i></i><i></i><i></i><i></i><i></i></div>
    <svg class="kicad-canvas" viewBox="0 0 640 360" preserveAspectRatio="xMidYMid slice">
      <rect x="0" y="0" width="640" height="360" fill="#0e1512"/>
      <g opacity=".18" stroke="#3a5a4a" stroke-width="1">
        ${Array.from({length:16},(_,i)=>`<line x1="${i*40}" y1="0" x2="${i*40}" y2="360"/>`).join('')}
        ${Array.from({length:9},(_,i)=>`<line x1="0" y1="${i*40}" x2="640" y2="${i*40}"/>`).join('')}
      </g>
      <rect x="120" y="80" width="180" height="120" rx="4" fill="none" class="silk" stroke-width="1.4"/>
      <text x="130" y="72" fill="#e8e6da" font-size="10" font-family="monospace" opacity=".7">U3 — STM32G431</text>
      <path class="trace" d="M300 100 H 380 Q 392 100 392 112 V 180 Q 392 192 404 192 H 500"/>
      <path class="trace t2" d="M300 140 H 350 Q 362 140 362 152 V 250 H 240 Q 228 250 228 238 V 200"/>
      <path class="trace blue" d="M120 120 H 70 Q 58 120 58 132 V 280 Q 58 292 70 292 H 420 Q 432 292 432 280 V 230"/>
      ${[[300,100],[300,140],[120,120],[500,192],[228,200],[432,230]].map(([x,y])=>`<circle class="pad" cx="${x}" cy="${y}" r="5"/>`).join('')}
      ${[[392,150],[58,210],[362,220]].map(([x,y])=>`<circle class="via" cx="${x}" cy="${y}" r="3.4"/>`).join('')}
      <text x="470" y="330" fill="#5a7a68" font-size="9" font-family="monospace">sarm_driver_board · rev C</text>
    </svg>`;
}

function buildPaper(w){
  const lines = n => Array.from({length:n},(_,i)=>{
    const wcls = ['','w90','w80','','w60'][i % 5];
    return `<div class="pline ${wcls}"></div>`;
  }).join('');
  w.querySelector('.win-body').innerHTML = `
    <div class="paper-title">Diffusion Policy: Visuomotor Learning via Action Diffusion</div>
    <div class="paper-authors">C. Chi, S. Feng, Y. Du, Z. Xu, E. Cousineau, B. Burchfiel, S. Song</div>
    <div class="paper-cols">
      <div class="paper-col">${lines(6)}<div class="pline hl w80"></div><div class="pline hl w60"></div>${lines(5)}</div>
      <div class="paper-col">${lines(3)}<div class="paper-fig">Fig. 3 — action denoising</div>${lines(6)}</div>
    </div>`;
}

function buildNotion(w){
  w.querySelector('.win-body').innerHTML = `
    <div class="notion-icon">🦾</div>
    <div class="notion-h1">SARM bring-up checklist</div>
    <div class="notion-todo done"><div class="notion-check done"></div><span>Order rev C boards</span></div>
    <div class="notion-todo done"><div class="notion-check done"></div><span>Fix encoder CS timing (350ns hold)</span></div>
    <div class="notion-todo"><div class="notion-check"></div><span>Flash + verify on joint 3</span></div>
    <div class="notion-todo"><div class="notion-check"></div><span>Log jitter over 10-min soak test</span></div>
    <div class="notion-todo"><div class="notion-check"></div><span>Write up bring-up notes for the lab</span></div>`;
}

function buildX(w){
  const posts = [...X_POSTS, ...X_POSTS].map(p => `
    <div class="x-post">
      <div class="x-av" style="background:${p.av}"></div>
      <div class="x-body">
        <span class="x-name">${p.name}</span><span class="x-handle">${p.handle}</span>
        <div class="x-text">${p.text}</div>
        ${p.img ? `<div class="x-img" style="background:${p.img}"></div>` : ''}
        <div class="x-meta"><span>💬 ${(Math.abs(p.text.length*7)%900)+12}</span><span>↻ ${(p.text.length*3)%400}</span><span>♥ ${(p.text.length*29)%8000}</span></div>
      </div>
    </div>`).join('');
  w.querySelector('.win-body').innerHTML =
    `<div class="x-feed"><div class="x-scroll" id="xScroll">${posts}</div></div>`;
}

let xScrollTimer = null;
function doomscroll(on){
  clearInterval(xScrollTimer);
  const s = document.getElementById('xScroll');
  if (!s) return;
  if (on) {
    let y = 0;
    s.style.transition = 'transform .55s cubic-bezier(.3,.7,.4,1)';
    xScrollTimer = setInterval(() => {
      y += 150 + Math.floor(y % 90);
      s.style.transform = `translateY(-${y % 1900}px)`;
    }, 620);
  } else {
    s.style.transform = 'translateY(0)';
  }
}

function buildShorts(w){
  w.querySelector('.win-body').innerHTML =
    `<div class="short-card" id="shortCard">
       <div class="sc-play">▶</div>
       <div class="sc-label"></div><div class="sc-sub"></div>
     </div>`;
}

let shortsTimer = null;
function playShorts(on){
  clearInterval(shortsTimer);
  const c = document.getElementById('shortCard');
  if (!c) return;
  let i = 0;
  const show = () => {
    const s = SHORTS[i % SHORTS.length];
    c.style.background = s.bg;
    c.querySelector('.sc-label').textContent = s.label;
    c.querySelector('.sc-sub').textContent = s.sub;
    i++;
  };
  show();
  if (on) shortsTimer = setInterval(show, 1400);
}

/* ── mount everything ── */

const WIN_GEO = {
  code:   { left:'6%',  top:'5%',  width:'58%', height:'78%' },
  term:   { left:'30%', top:'16%', width:'44%', height:'52%' },
  kicad:  { left:'8%',  top:'7%',  width:'60%', height:'74%' },
  paper:  { left:'14%', top:'4%',  width:'46%', height:'84%' },
  notion: { left:'12%', top:'6%',  width:'50%', height:'78%' },
  x:      { left:'22%', top:'3%',  width:'40%', height:'88%' },
  shorts: { left:'26%', top:'4%',  width:'32%', height:'86%' },
};

const WIN_BUILDERS = { code:buildCode, term:buildTerm, kicad:buildKicad,
  paper:buildPaper, notion:buildNotion, x:buildX, shorts:buildShorts };

function mountWindows(){
  const layer = document.getElementById('windows');
  for (const id of Object.keys(APPS)) {
    const w = winShell(id, APPS[id], WIN_GEO[id]);
    layer.appendChild(w);
    WIN_BUILDERS[id](w);
  }
}

function mountDock(onLaunch){
  const dock = document.getElementById('dock');
  const order = ['code','term','kicad','paper','notion','sep','x','shorts'];
  for (const id of order) {
    if (id === 'sep') { dock.appendChild(el('div','dock-sep')); continue; }
    const a = APPS[id];
    const d = el('button', 'dock-app', `<span style="font-family:var(--font-mono);font-weight:600;font-size:15px;color:#fff;text-shadow:0 1px 3px #0008">${a.dockGlyph}</span>`);
    d.id = `dock-${id}`;
    d.style.background = a.dockBg;
    d.title = a.name;
    d.onclick = () => onLaunch(id, { user: true });
    dock.appendChild(d);
  }
}
