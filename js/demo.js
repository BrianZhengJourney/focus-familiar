/* ── the scripted concept demo: 7 scenes, ~2 minutes ────── */

function setCaption(html, holdMs = 0){
  const c = document.getElementById('caption');
  const t = document.getElementById('captionText');
  c.classList.remove('on');
  setTimeout(() => { t.innerHTML = html; c.classList.add('on'); }, 320);
  if (holdMs) setTimeout(() => c.classList.remove('on'), holdMs);
}
function clearCaption(){ document.getElementById('caption').classList.remove('on'); }

const Demo = {
  timers: [],
  playing: false,
  sceneIdx: -1,

  at(ms, fn){ this.timers.push(setTimeout(fn, ms)); },
  stopAll(){
    this.timers.forEach(clearTimeout); this.timers = [];
    this.playing = false;
    doomscroll(false); playShorts(false);
    document.getElementById('vignette').className = 'vignette';
    Familiar.hush();
    clearCaption();
    QuestMap.hide();
  },

  scenes: [

    /* 1 ── the quiet companion */
    { name: 'companion', dur: 14000, run(){
      switchApp('code');
      Familiar.setState('idle'); Familiar.hud(true);
      Familiar.setFocus(58); Familiar.setStreak(4);
      Demo.at(600,  () => setCaption('it just… floats there while you work. <em>watching. purring, probably.</em>'));
      Demo.at(4200, () => Familiar.setState('focused'));
      Demo.at(4600, () => { Familiar.setFocus(66); Familiar.setStreak(9); });
      Demo.at(5000, () => setCaption('when you sink into real work, it starts to <em>feed</em>.'));
      Demo.at(5600, () => Familiar.gain('protein','🥩','+protein', document.getElementById('win-code')));
      Demo.at(8600, () => Familiar.gain('protein','🥩','+protein', document.getElementById('win-code')));
      Demo.at(9400, () => { Familiar.setFocus(74); Familiar.setStreak(14); });
      Demo.at(10000,() => setCaption('shipping code → <em>protein</em>. your familiar is a carnivore for focus.'));
    }},

    /* 2 ── shapeshifting with the work */
    { name: 'shapeshift', dur: 21000, run(){
      Demo.at(0,    () => setCaption('it knows <em>what kind</em> of work you’re doing —'));
      Demo.at(1400, () => { switchApp('term'); });
      Demo.at(3200, () => Familiar.gain('iron','⛓️','+iron', document.getElementById('win-term')));
      Demo.at(4600, () => setCaption('terminal grind smelts <em>iron</em>…'));
      Demo.at(7000, () => { switchApp('paper'); Familiar.setState('scholar'); });
      Demo.at(8400, () => Familiar.gain('spellbook','📖','+spellbook', document.getElementById('win-paper')));
      Demo.at(8800, () => setCaption('…reading papers earns <em>spellbooks</em>…'));
      Demo.at(12400,() => { switchApp('kicad'); Familiar.setState('focused'); });
      Demo.at(14000,() => Familiar.gain('iron','⛓️','+iron', document.getElementById('win-kicad')));
      Demo.at(14400,() => setCaption('…and routing a PCB is honest blacksmith work.'));
      Demo.at(15000,() => { Familiar.setFocus(82); Familiar.setStreak(26); });
      Demo.at(17800,() => { switchApp('notion'); });
      Demo.at(18800,() => Familiar.gain('fragment','🔮','+memory fragment', document.getElementById('win-notion')));
      Demo.at(19000,() => setCaption('every task you touch becomes a <em>memory fragment</em> it keeps for you.'));
    }},

    /* 3 ── the corruption */
    { name: 'corruption', dur: 23000, run(){
      Demo.at(0,    () => setCaption('then you open X. <em>“just for a second.”</em>'));
      Demo.at(1200, () => { switchApp('x'); doomscroll(true); });
      Demo.at(3600, () => { Familiar.setState('dizzy'); Familiar.setFocus(58); Familiar.setStreak(0); });
      Demo.at(5600, () => setCaption('the scroll makes it <em>dizzy</em>…'));
      Demo.at(8600, () => { Familiar.setFocus(38); });
      Demo.at(9600, () => {
        Familiar.setState('poisoned');
        document.getElementById('vignette').classList.add('on');
        setCaption('nine minutes later: <em>poisoned</em>. it’s not mad, it’s just nauseous.');
      });
      Demo.at(13400,() => { switchApp('shorts'); playShorts(true); doomscroll(false); });
      Demo.at(14200,() => Familiar.setFocus(22));
      Demo.at(15400,() => setCaption('shorts. reddit. shorts again. tab, tab, tab —'));
      Demo.at(16200,() => { switchApp('x'); doomscroll(true); });
      Demo.at(17000,() => switchApp('shorts'));
      Demo.at(17800,() => switchApp('x'));
      Demo.at(18400,() => {
        document.getElementById('desktop').classList.add('glitching');
        document.getElementById('vignette').classList.add('ghostly');
        Familiar.setState('ghost'); Familiar.setFocus(8);
      });
      Demo.at(19600,() => {
        document.getElementById('desktop').classList.remove('glitching');
        setCaption('too much switching and it goes <em>ghost</em> — barely there. like your attention.');
      });
    }},

    /* 4 ── the deep-work streak & evolution */
    { name: 'streak', dur: 21000, run(){
      Demo.at(0,    () => { doomscroll(false); playShorts(false); });
      Demo.at(400,  () => setCaption('but you close the feed. you go back in.'));
      Demo.at(1600, () => { switchApp('code'); document.getElementById('vignette').className = 'vignette'; });
      Demo.at(3200, () => { Familiar.setState('idle'); Familiar.setFocus(30); });
      Demo.at(5200, () => { Familiar.setState('focused'); Familiar.setFocus(48); Familiar.setStreak(12); });
      Demo.at(6000, () => setCaption('the flame comes back. minute by minute.'));
      Demo.at(7600, () => { Familiar.setFocus(62); Familiar.setStreak(31); Familiar.sparkle(3); });
      Demo.at(9200, () => { switchApp('term'); });
      Demo.at(10400,() => Familiar.gain('iron','⛓️','+iron', document.getElementById('win-term')));
      Demo.at(11600,() => { Familiar.setFocus(78); Familiar.setStreak(55); });
      Demo.at(12400,() => setCaption('55 minutes. no tab-outs. it’s getting <em>stronger</em>.'));
      Demo.at(14400,() => { Familiar.setFocus(92); Familiar.setStreak(88); Familiar.sparkle(5); });
      Demo.at(16400,() => { Familiar.setStreak(92); Familiar.levelUp(); });
      Demo.at(17400,() => setCaption('a 92-minute streak, and your familiar <em>evolves</em>.'));
    }},

    /* 5 ── restore my context */
    { name: 'restore', dur: 19500, run(){
      Demo.at(0,    () => setCaption('— three hours, one lunch and two meetings later —', 3400));
      Demo.at(3800, () => { switchApp('code'); Familiar.setState('idle'); Familiar.setStreak(0); Familiar.setFocus(44); });
      Demo.at(5200, () => setCaption('you sit down and think: <em>“…what was I even doing?”</em>'));
      Demo.at(8200, () => { setCaption('so you ask the one who never forgot. <span style="opacity:.6">⌥ space</span>'); });
      Demo.at(9400, () => Familiar.restoreContext());
      Demo.at(15600,() => setCaption('it kept the thread: the file, the fix, the <em>next step</em>.'));
    }},

    /* 6 ── the daily quest map */
    { name: 'questmap', dur: 15000, run(){
      Demo.at(0,   () => { Familiar.hush(); setCaption('and at day’s end, it tells your day back to you — <em>as a quest</em>.'); });
      Demo.at(2200,() => QuestMap.show());
      Demo.at(8600,() => setCaption('main quest, side quests, admin tax… and the pit you fell in.'));
    }},

    /* 7 ── end card */
    { name: 'end', dur: 1e9, run(){
      QuestMap.hide(); clearCaption(); Familiar.hush();
      Demo.at(700, () => showEndCard());
      Demo.playing = false;
    }},
  ],

  play(i = 0){
    this.stopAll();
    this.playing = true;
    Sandbox.stop();
    hideCards();
    this.runScene(i);
    document.getElementById('demoChrome').classList.add('on');
  },

  runScene(i){
    if (i >= this.scenes.length) return;
    this.sceneIdx = i;
    this.updateDots();
    const s = this.scenes[i];
    s.run();
    if (s.dur < 1e8) this.at(s.dur, () => this.runScene(i + 1));
  },

  updateDots(){
    document.querySelectorAll('.dc-dot').forEach((d, j) =>
      d.classList.toggle('cur', j === this.sceneIdx));
  },

  buildDots(){
    const box = document.getElementById('dcDots');
    this.scenes.forEach((s, i) => {
      const d = document.createElement('div');
      d.className = 'dc-dot'; d.title = s.name;
      d.onclick = () => this.play(i);
      box.appendChild(d);
    });
  },
};
