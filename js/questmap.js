/* ── daily quest map overlay ─────────────────────────────── */

const QuestMap = {
  built: false,

  NODES: [
    { x: 70,  y: 200, icon: '🏰', label: 'dawn',            sub: '9:04 wake',            delay: .2 },
    { x: 185, y: 120, icon: '⚔️', label: 'MAIN QUEST',      sub: 'encoder driver · 2h 10m', main: true, delay: .5 },
    { x: 305, y: 205, icon: '🗡️', label: 'side quest',      sub: 'paper reading · 40m',  delay: .9 },
    { x: 420, y: 118, icon: '🧾', label: 'admin tax',        sub: 'email & forms · 25m',  tax: true, delay: 1.3 },
    { x: 520, y: 215, icon: '🕳️', label: 'distraction pit', sub: 'X + shorts · −31m',    bad: true, delay: 1.7 },
    { x: 640, y: 130, icon: '⚔️', label: 'main quest II',   sub: 'flash + soak test · 1h 30m', main: true, delay: 2.1 },
    { x: 750, y: 195, icon: '✦',  label: 'evolution',        sub: 'lv.2 — Emberling',     gold: true, delay: 2.5 },
  ],

  build(){
    if (this.built) return;
    this.built = true;
    const nodes = this.NODES.map(n => `
      <g class="qm-node" style="animation-delay:${n.delay}s" transform="translate(${n.x},${n.y})">
        <circle r="21" fill="${n.bad ? '#3c2b3a' : n.gold ? '#3d3420' : n.main ? '#2b2450' : '#241f42'}"
                stroke="${n.bad ? '#e88fae55' : n.gold ? '#ffd76a88' : n.main ? '#b9a5ff66' : '#ffffff22'}" stroke-width="1.5"/>
        <text class="qm-node-ico" text-anchor="middle" dy="6">${n.icon}</text>
        <text class="qm-node-label" text-anchor="middle" y="38"
              ${n.main ? 'font-weight="600" fill="#cabcf5"' : ''} ${n.bad ? 'fill="#e88fae"' : ''} ${n.gold ? 'fill="#ffd76a"' : ''}>${n.label}</text>
        <text class="qm-node-sub" text-anchor="middle" y="51">${n.sub}</text>
      </g>`).join('');

    const path = 'M70 200 C 120 200 140 122 185 120 C 240 118 255 205 305 205 C 365 205 365 118 420 118 C 475 118 468 215 520 215 C 575 215 588 130 640 130 C 692 130 706 195 750 195';

    document.getElementById('qmBody').innerHTML = `
      <svg viewBox="0 0 820 280">
        <path class="qm-path" d="${path}"/>
        <path class="qm-path walked" d="${path}"/>
        ${nodes}
        <g class="qm-node" style="animation-delay:2.8s" transform="translate(750,158)">
          <text text-anchor="middle" font-size="13">👑</text>
        </g>
      </svg>`;

    document.getElementById('qmFoot').innerHTML = `
      <div class="qm-stat good"><div class="v">4h 20m</div><div class="k">deep work — familiar well fed</div></div>
      <div class="qm-stat"><div class="v">25m</div><div class="k">admin tax — tolerated, grudgingly</div></div>
      <div class="qm-stat bad"><div class="v">−31m</div><div class="k">distraction damage — 1 poisoning</div></div>
      <div class="qm-stat gold"><div class="v">lv.2</div><div class="k">evolution — 🥩12 ⛓️8 📖5 🔮9</div></div>`;
  },

  show(){
    this.build();
    // restart node/path animations each open
    const body = document.getElementById('qmBody');
    body.innerHTML = body.innerHTML;
    document.getElementById('questmap').classList.add('on');
  },
  hide(){ document.getElementById('questmap').classList.remove('on'); },
};
