/* docs.js: the render functions of the components, exported as R6. Every name and figure is sample data. The block at the end is documentation chrome, not the sheet: it marks a table, specimen or nav strip that is wider than its column, so it scrolls in its own box with a visible edge. */
window.R6 = (() => {
const EIGHTHS = ['', '▏', '▎', '▍', '▌', '▋', '▊', '▉'];
const NOW = new Date(2026, 9, 15, 14, 20);
const WIN = {
  weekly: {title:'Weekly (all models)', start:new Date(2026, 9, 11, 18, 0), reset:new Date(2026, 9, 18, 18, 0), resetText:'Resets Sun 18:00', days:true},
  five:   {title:'5h window', start:new Date(2026, 9, 15, 12, 45), reset:new Date(2026, 9, 15, 17, 45), resetText:'Resets 17:45', days:false}
};
const STATES = { ahead:{win:'five', used:24}, on:{win:'weekly', used:57}, over:{win:'weekly', used:61} };
const DAYS = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
const pad = n => String(n).padStart(2, '0');
const hhmm = d => pad(d.getHours()) + ':' + pad(d.getMinutes());
const esc = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;');
const L = (s, cls) => '<div class="l' + (cls ? ' ' + cls : '') + '">' + s + '</div>';
const BL = L('');
const sp = (s, cls) => '<span class="' + cls + '">' + s + '</span>';
const col = (s, w) => s.length > w ? s.slice(0, w - 1) + '…' : s.padEnd(w);
const rcol = (s, w) => s.padStart(w);
const POP = 47;   /* content cells in the 380 px popover at SF Mono 12 */
const POPBAR = 36;

/* the block glyph's ink box inside the 16 px line, measured from the font the engine resolved, so the bar box fits the glyph */
function probe(root) {
  const term = root;
  const p = document.createElement('span'); p.textContent = '0'.repeat(50); p.style.whiteSpace = 'pre'; p.style.font = '12px/16px ' + getComputedStyle(term).getPropertyValue('--mono'); term.appendChild(p);
  const cw = p.getBoundingClientRect().width / 50; p.remove();
  const x = document.createElement('canvas').getContext('2d');
  for (const fam of [getComputedStyle(term).getPropertyValue('--mono'), 'ui-monospace', 'Menlo']) {
    x.font = '12px ' + fam;
    if (Math.abs(x.measureText('0').width - cw) > .05) continue;
    const m = x.measureText('█');
    const baseline = (16 - (m.fontBoundingBoxAscent + m.fontBoundingBoxDescent)) / 2 + m.fontBoundingBoxAscent;
    root.style.setProperty('--bt', (baseline - m.actualBoundingBoxAscent).toFixed(2) + 'px');
    root.style.setProperty('--bh', (m.actualBoundingBoxAscent + m.actualBoundingBoxDescent).toFixed(2) + 'px');
    break;
  }
}

/* the pace model */
function pace(winKey, used) {
  const w = WIN[winKey];
  const elapsedH = (NOW - w.start) / 36e5, lenH = (w.reset - w.start) / 36e5, remainH = (w.reset - NOW) / 36e5;
  const E = elapsedH / lenH * 100;
  const status = used > E + 5 ? 'Over pace' : used < E - 5 ? 'Ahead' : 'On pace';
  const rate = used / elapsedH;
  const toLimitH = (100 - used) / rate;
  let proj;
  if (toLimitH < remainH) {
    const t = new Date(NOW.getTime() + toLimitH * 36e5);
    t.setMinutes(Math.round(t.getMinutes() / 5) * 5, 0, 0);
    proj = 'limit ' + (w.days ? DAYS[t.getDay()] + ' ' : '') + hhmm(t) + ' at this rate';
  } else {
    proj = Math.round(used + rate * remainH) + '% by reset at this rate';
  }
  const perHour = (100 - used) / remainH;
  const allow = (perHour < 1 ? perHour.toFixed(1) : String(Math.round(perHour))) + '% an hour left';
  const d = Math.floor(remainH / 24), h = Math.floor(remainH % 24), m = Math.floor((remainH * 60) % 60);
  const countdown = 'in ' + (d ? d + 'd ' + h + 'h' : h + 'h ' + m + 'm');
  return {title:w.title, used, E, status, over:status === 'Over pace', proj, allow, reset:w.resetText, countdown, elapsedH, lenH, remainH, rate, toLimitH, perHour};
}

/* block bar from glyphs: full cells plus one eighth block, the tick at the elapsed share */
function bar(N, U, E, o = {}) {
  const f = U / 100 * N, full = Math.floor(f), e8 = Math.round((f - full) * 8);
  const t = (E == null) ? null : Math.min(N - 1, Math.round(E / 100 * N));
  const cells = [];
  for (let i = 0; i < N; i++) cells.push(i < full ? '█' : i === full ? (e8 === 8 ? '█' : EIGHTHS[e8]) : ' ');
  const fillCol = o.col || (o.stale ? '#505370' : '#b1b9f9'), pastCol = o.over ? '#d77757' : fillCol;
  /* full cells run with the colour behind them too, so SF Mono's hairline between blocks closes */
  let html = '', cur = null, buf = '';
  const flush = () => { if (!buf) return; const solid = cur.solid ? ';background:' + cur.c : ''; html += '<span style="color:' + cur.c + solid + '">' + buf + '</span>'; buf = ''; };
  for (let i = 0; i < N; i++) {
    const c = {c:(t != null && i >= t) ? pastCol : fillCol, solid:cells[i] === '█'};
    if (!cur || c.c !== cur.c || c.solid !== cur.solid) { flush(); cur = c; }
    buf += cells[i];
  }
  flush();
  const tick = t == null ? '' : '<span class="tk" style="left:' + t + 'ch">▏</span>';
  const cls = 'bar' + (o.stale ? ' stale' : '') + (o.plain ? ' plain' : '') + (o.anim ? ' anim' : '');
  return '<span class="' + cls + '" style="width:' + N + 'ch"><span class="fl">' + html + '</span>' + tick + '</span>';
}
const pct = (m, dim) => sp(' ' + m.used + '% used', dim ? 'd' : '');

/* window section, popover width */
function windowSection(m, o = {}) {
  const stale = !!o.stale;
  let s = L(' ' + sp(m.title, 'b'));
  s += L(' ' + bar(POPBAR, m.used, m.E, {over:m.over && !stale, stale, anim:o.anim}) + pct(m, stale));
  if (stale) {
    s += L(' ' + sp(m.reset, 'd'));
    s += L(' ' + sp('as of ' + (o.asOf || '13:05'), 'd'));
  } else {
    s += L(' ' + sp(m.reset + '  ' + m.countdown, 'd'));
    s += L(' ' + sp(m.status, 'b') + sp('  ' + m.proj, 'd'));
    s += L(' ' + sp(m.allow, 'd'));
  }
  return s;
}
function paceLines(m, stale) {
  if (stale) return L(sp(m.reset, 'd')) + L(sp('as of 13:05', 'd')) + L('');
  return L(sp(m.reset + '  ' + m.countdown, 'd')) + L(sp(m.status, 'b') + sp('  ' + m.proj, 'd')) + L(sp(m.allow, 'd'));
}

/* header and tab strip */
/* line one: "Usage live" while a session feeds the snapshot, with "Mac live" at the right; between sessions the snapshot time and its source take the line (the tier is not in the feed, so there is no plan badge) */
function header(sel, warn, asOf) {
  const tabs = ['Claude', 'Mac', 'Settings'].map((t, i) => {
    const label = ' ' + t + (t === 'Mac' && warn ? ' ' + sp('●', 'w') : '') + ' ';
    return '<span class="tab" role="tab" aria-selected="' + (i === sel) + '">' + label + '</span>';
  }).join('  ');
  const line = asOf ? 'Usage as of ' + asOf + ', last Claude Code session' : 'Usage live' + rcol('', POP - 11 - 8) + 'Mac live';
  return L(' ' + sp(line, 'd'))
    + L(sp('▔'.repeat(POP + 1), 'rule'))
    + L(' ' + tabs);
}

/* table rows: name, block bar, figure, readout on hover */
function row(name, hue, share, figure, tip, o = {}) {
  const lead = o.selected ? sp('<span class="g">❯</span>', 'a') : ' ';
  const nm = o.selected ? sp(col(name, 14), 'b') : col(name, 14);
  const fig = '<span class="fig" tabindex="0">' + rcol(figure, 5) + '<span class="tip">' + esc(tip) + '</span></span>';
  return L(lead + nm + ' ' + bar(24, share, null, {col:hue, plain:true, anim:o.anim}) + '  ' + fig, 'row' + (o.hover ? ' is-hover' : ''));
}
const MODELS = [['Fable 5.1', '#bd7bcd', 49, '1.02B'], ['Opus 5.5', '#c4ac62', 34, '0.71B'], ['Sonnet 5.5', '#7ccbcd', 11, '0.24B'], ['Haiku 4.5', '#6caa71', 6, '0.13B']];
const PROJECTS = [['workspace', '#6d96b4', 70, '1.46B'], ['website', '#6d96b4', 20, '0.42B'], ['tooling', '#6d96b4', 7, '0.14B'], ['other', '#6d96b4', 4, '0.08B']];
const SESSIONS = [['3f1a9c2e', '#67b5ed', 43, '31.2M'], ['7b2d4e6f', '#67b5ed', 25, '18.0M'], ['c91e0a44', '#67b5ed', 17, '12.6M']];
const PROCS = [['Safari', '#dee5eb', 68, '6.1%', '6.1% CPU  6.2 GB memory'], ['Xcode', '#dee5eb', 26, '2.3%', '2.3% CPU  1.4 GB memory'], ['WindowServer', '#dee5eb', 16, '1.4%', '1.4% CPU'], ['Terminal', '#dee5eb', 9, '0.8%', '0.8% CPU'], ['Music', '#dee5eb', 7, '0.6%', '0.6% CPU  2.1 GB memory']];
const rows = (list, unit, o = {}) => list.map((r, i) => row(r[0], r[1], r[2], r[3], r[4] || (r[3] + ' tokens  ' + r[2] + '% of ' + unit), {selected:o.selected === i, hover:o.hover === i, anim:o.anim})).join('');

/* section switch in the sub tab grammar */
function subTabs(sel, hover) {
  return ['Models', 'Projects', 'Sessions'].map((t, i) => '<button type="button" class="tab sub' + (hover === i ? ' is-hover' : '') + '" data-sub="' + i + '" aria-pressed="' + (i === sel) + '"' + (hover === i ? ' style="color:#ffffff"' : '') + '> ' + t + ' </button>').join('  ');
}

/* weeks */
function week(date, used, o = {}) {
  const mark = o.hit ? sp('⚠', 'w g') : ' ';
  const b = bar(20, used, o.E == null ? null : o.E, {over:o.over, plain:false, anim:o.anim});
  return L(' ' + col(date, 6) + '  ' + b + mark + ' ' + rcol(used + '%', 4) + (o.note ? sp('  ' + o.note, 'd') : ''));
}

/* the Mac memory grid in the context grammar */
function memGrid() {
  const total = 200, used = Math.round(25.5 / 36 * total), swap = Math.round(0.9 / 36 * total);
  let s = '';
  for (let r = 0; r < 10; r++) {
    let line = ' ';
    for (let c = 0; c < 20; c++) {
      const i = r * 20 + c;
      line += i < used ? sp('⛁', 'gc a') : i >= total - swap ? sp('⛝', 'gc w') : sp('⛶', 'gc dd');
    }
    s += L(line);
  }
  s += L(' ' + sp('⛁', 'gc a') + 'Used ' + sp('25.5 of 36 GB (71%)', 'd'));
  s += L(' ' + sp('⛶', 'gc dd') + 'Free ' + sp('10.5 GB', 'd'));
  s += L(' ' + sp('⛝', 'gc w') + 'Swap ' + sp('0.9 GB', 'd') + '   ' + sp('Pressure normal', 'd'));
  return s;
}

/* checkbox rows */
function cbRow(label, on, sub, o = {}) {
  let s = L(' <button type="button" class="cb" role="checkbox" aria-checked="' + on + '">[' + (on ? 'x' : ' ') + ']</button> ' + label, 'srow' + (o.hover ? ' is-hover' : ''));
  if (sub) s += L('     ' + sp(sub, 'd'));
  return s;
}

/* menu bar item: SF digits, 5 cell block bar at 9 px with the tick, monochrome */
function item(used, E, o = {}) {
  const N = 5, f = used / 100 * N, full = Math.floor(f), e8 = Math.round((f - full) * 8);
  const t = Math.min(N - 1, Math.round(E / 100 * N));
  let solid = '', rest = '';
  for (let i = 0; i < N; i++) {
    const g = i < full ? '█' : i === full ? (e8 === 8 ? '█' : EIGHTHS[e8]) : ' ';
    const gg = (o.over && i >= t && g === '█') ? '▓' : g;
    if (gg === '█' && !rest) solid += gg; else rest += gg;
  }
  const cls = 'mbi' + (o.over ? ' over' : '') + (o.stale ? ' stale' : '');
  return '<span class="' + cls + '">' + used + '%<span class="mini" style="width:' + N + 'ch"><span class="mt">' + '█'.repeat(N) + '</span><span class="mf"><span class="solid">' + solid + '</span>' + rest + '</span><span class="mk" style="left:' + t + 'ch">▏</span></span>'
    + (o.warn ? '<span class="g">⚠</span>' : '') + (o.mac ? '<span> CPU 9%</span>' : '') + '</span>';
}
const strip = (html, light) => '<span class="strip' + (light ? ' light' : '') + '">' + html + '</span>';

/* open sessions (added 2026-10-13): one feed per running session; title line is project, model and the context figure, then the context bar in the window grammar without a tick */
const OPEN = [['workspace', 'Fable 5.1', 405.6, 41, 'USD 38.20 list price equivalent  112 added  9 removed'], ['tooling', 'Opus 5.5', 88.4, 9, 'USD 6.10 list price equivalent  0 added  0 removed']];
function openSession(name, model, k, used, tip, o = {}) {
  const figure = k + 'k of 1M';
  const left = ' ' + sp(col(name, 14), 'b') + '  ' + sp(model, 'd');
  const fig = '<span class="fig" tabindex="0">' + sp(figure, 'd') + '<span class="tip">' + esc(tip) + '</span></span>';
  return L(left + rcol('', POP - 1 - 14 - 2 - model.length - figure.length) + fig)
    + L(' ' + bar(POPBAR, used, null, {anim:o.anim}) + ' ' + used + '% used');
}
function openSessions(o = {}) {
  let s = L(' ' + sp('Open sessions', 'b'));
  OPEN.forEach((r, i) => { s += openSession(r[0], r[1], r[2], r[3], r[4], o); });
  return s;
}

/* the Claude tab, the Mac tab and Settings as the assembled popover draws them */
function claudeTab(st, sub, price, anim) {
  const mW = pace('weekly', st.weekly), mF = pace('five', st.five);
  const o = {stale:st.stale, asOf:st.asOf, anim};
  let s = windowSection(mW, o) + BL + windowSection(mF, o) + BL;
  if (st.stale) s += L(' ' + sp('limits are shared with the Claude app and other', 'd')) + L(' ' + sp('Macs, so the real figure may be higher', 'd')) + BL;
  else s += openSessions({anim}) + BL;
  const title = ['Tokens by model  7 days', 'Tokens by project  7 days', 'Tokens by session  today'][sub];
  s += L(' ' + sp(title, 'b'));
  s += L(' ' + subTabs(sub));
  s += rows([MODELS, PROJECTS, SESSIONS][sub], sub === 2 ? 'today' : '7 days', {anim});
  if (price) s += L(' ' + sp('[list price equivalent  USD 1,140]', 'd'));
  s += L(' ' + sp('[44% by subagents]', 'd'));
  s += BL + L(' ' + sp('Week over week', 'b'));
  s += week('21 Sep', 88, {anim}) + week('28 Sep', 100, {hit:true, note:'Thu 16:10', anim}) + week('5 Oct', 96, {anim}) + week('12 Oct', mW.used, {E:mW.E, over:mW.over && !st.stale, note:'so far', anim});
  return s;
}
function macTab(anim) {
  let s = L(' ' + sp('CPU', 'b'));
  s += L(' ' + bar(POPBAR, 9, null, {anim}) + ' 9%');
  s += L(' ' + sp('user 5%  system 4%  10 cores', 'd'));
  s += BL + L(' ' + sp('GPU', 'b'));
  s += L(' ' + bar(POPBAR, 11, null, {anim}) + ' 11%');
  s += L(' ' + sp('device utilisation', 'd'));
  s += BL + L(' ' + sp('Memory', 'b')) + memGrid();
  s += BL + L(' ' + sp('Battery', 'b'));
  s += L(' ' + bar(POPBAR, 75, null, {anim}) + ' 75%');
  s += L(' ' + sp('charging  47.6 W in  94 W adapter', 'd'));
  s += L(' ' + sp('full in 51 min  health 89%  316 cycles', 'd'));
  s += BL + L(' ' + sp('Processes by CPU', 'b'));
  s += rows(PROCS, '', {anim});
  return s;
}
function settingsTab(st) {
  return cbRow('Mac figures in the bar', st.mac)
    + cbRow('Nudge at 80% and before the 5h end', st.nudge)
    + cbRow('List price equivalent', st.price, 'tokens at list prices, not the plan price')
    + BL
    + hookRow(st.hook !== false)
    + BL
    + L(' ' + sp('This app makes no network calls. Usage comes', 'd'))
    + L(' ' + sp("from Claude Code's own status feed on this Mac.", 'd'))
    + BL
    + L(' Quit' + rcol('⌘Q', POP - 5));
}
/* the status line entry row: install or remove, one click each */
function hookRow(installed) {
  return L(' <button type="button" class="tab hk">' + (installed ? 'Remove the status line entry' : 'Install the status line entry') + '</button>', 'srow')
    + L('     ' + sp(installed ? 'puts back what statusLine held before' : 'one statusLine entry in ~/.claude/settings.json', 'd'));
}
/* the key hints: m p s work on the Claude tab only, so only that tab names them */
const foot = (tab) => BL + L(' ' + sp(tab === 0 ? 'Esc closes  Tab switches  m p s sections' : 'Esc closes  Tab switches', 'q'));
function popover(tab, st, o = {}) {
  let body = header(tab, !!o.warn, st.stale ? st.asOf : null) + BL;
  body += tab === 0 ? claudeTab(st, o.sub || 0, o.price !== false, o.anim) : tab === 1 ? macTab(o.anim) : settingsTab({mac:!!o.mac, nudge:o.nudge !== false, price:o.price !== false});
  body += foot(tab);
  return '<div class="popover" role="dialog" aria-label="Usage"><div class="arrow"></div>' + body + '</div>';
}

return {EIGHTHS, NOW, WIN, STATES, L, BL, sp, col, rcol, esc, POP, POPBAR, probe, pace, bar, pct, windowSection, paceLines, header, row, rows, MODELS, PROJECTS, SESSIONS, PROCS, OPEN, openSession, openSessions, subTabs, week, memGrid, cbRow, item, strip, claudeTab, macTab, settingsTab, hookRow, foot, popover};
})();

/* documentation chrome: a box wider than its column scrolls inside itself and shows its edge (.xs in docs.css) */
(() => {
const SEL = '.dk .main table,.dk .main .spec,.dk .main .stage,.dk .main .state,.dk .nav .toc';
const fit = () => document.querySelectorAll(SEL).forEach(e => {
  e.classList.remove('xs');
  const p = e.parentElement, cs = getComputedStyle(p);
  const room = p.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
  if (e.scrollWidth > e.clientWidth + 1 || e.getBoundingClientRect().width > room + 1) e.classList.add('xs');
});
let raf = 0;
const later = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(fit); };
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fit); else fit();
addEventListener('load', fit);
addEventListener('resize', later);
if (document.fonts) document.fonts.ready.then(fit);
document.addEventListener('click', later);
})();
