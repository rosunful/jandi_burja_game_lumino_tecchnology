/// Everything about the practice table that lives inside the web view.
///
/// The dice, the physics and the page chrome are a self-contained HTML/CSS/JS
/// application served into a [ModelViewer] from a loopback HTTP server. Flutter
/// owns none of it: it paints the page, then sits idle while JavaScript steps
/// the simulation at 240 hertz and writes transforms straight to the DOM. That
/// is the whole reason this screen is not another `CustomPainter` - the frame
/// budget belongs to the throw, not to the widget tree.
///
/// The seam back into Flutter is two [JavascriptChannel]s, declared in
/// [buildDiceLabViewer] and called from [diceLabJs]:
///
/// * `DiceNav` - the back arrow in the page's app bar.
/// * `DiceAudio` - every throw, so the practice table is not the one screen in
///   the app that is silent.
///
/// Neither is optional at the call site: both are guarded in JS, because a
/// missing channel must degrade to "no sound, no shortcut" rather than to a
/// `JS ERROR` banner over the dice.
library;

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

/// Styling for the practice table, injected as [ModelViewer.relatedCss].
///
/// Positioning is fixed rather than flowed on purpose: the dice are moved by
/// writing a `transform` each frame, and a fixed element never triggers layout,
/// so the animation cannot be delayed by the page reflowing around it.
const String diceLabCss = r'''
html, body {
  height: 100%; margin: 0; overflow: hidden; touch-action: none;
  -webkit-tap-highlight-color: transparent; user-select: none;
  background: radial-gradient(circle at 50% 50%, #2e7d32 0%, #1b5e20 55%, #0a2e10 100%) !important;
  font-family: sans-serif;
}
.die {
  position: fixed !important; top: 50%;
  z-index: 2; pointer-events: none;
  background: transparent !important; background-color: transparent !important;
  --poster-color: transparent;
  will-change: transform; transform-origin: 50% 50%;
}
.shadow {
  position: fixed; left: 50%; top: 50%; z-index: 1; border-radius: 50%; pointer-events: none;
  background: radial-gradient(circle at center, rgba(0,0,0,.8) 0%, rgba(0,0,0,0) 70%);
}
#label {
  position: fixed; left: 0; right: 0; top: 66px; z-index: 3; text-align: center;
  color: #fff; font-size: 20px; pointer-events: none; padding: 0 12px;
}
/* ---- app bar ---- */
#bar {
  position: fixed; top: 0; left: 0; right: 0; height: 56px; z-index: 10;
  display: flex; align-items: center; padding: 0 6px 0 6px; box-sizing: border-box;
  background: #14501a; color: #fff; box-shadow: 0 2px 8px rgba(0,0,0,.4);
}
/* Left padding matches the bar's, and the back arrow sits inside it, so the
   title starts after the arrow instead of underneath it. */
#bar .title { font-size: 21px; font-weight: 600; flex: 1; margin-left: 2px; }
#bar button {
  width: 44px; height: 44px; border: 0; border-radius: 22px; background: transparent;
  display: flex; align-items: center; justify-content: center; cursor: pointer;
}
#bar button.cnt { width: auto; padding: 0 12px; gap: 6px; color: #fff; font-size: 19px; font-weight: 700; }
#bar button:active { background: rgba(255,255,255,.18); }
/* ---- panels ---- */
#panel, #cpanel {
  position: fixed; top: 60px; right: 8px; width: min(88vw, 330px); z-index: 11;
  display: none; overflow: hidden;
  background: rgba(8,38,13,.97); color: #fff; border-radius: 16px;
  box-shadow: 0 8px 28px rgba(0,0,0,.55);
}
#panel { max-height: 60vh; flex-direction: column; }
#panel .ph, #cpanel .ph {
  display: flex; align-items: center; justify-content: space-between;
  padding: 12px 16px; font-size: 17px; font-weight: 600; border-bottom: 1px solid rgba(255,255,255,.15);
}
#panel .ph button {
  border: 0; border-radius: 16px; padding: 7px 16px; font-size: 14px; cursor: pointer;
  background: rgba(255,255,255,.16); color: #fff;
}
#plist { overflow-y: auto; padding: 4px 0; touch-action: pan-y; }
#plist .row {
  display: flex; justify-content: space-between; gap: 12px; padding: 11px 16px; font-size: 16px;
  border-bottom: 1px solid rgba(255,255,255,.08);
}
#plist .row .n { opacity: .6; }
#plist .row span:last-child { text-align: right; word-break: break-word; }
#plist .empty { padding: 22px 16px; opacity: .7; text-align: center; font-size: 15px; }
/* ---- dice count picker ---- */
#cgrid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 8px; padding: 14px; }
#cgrid button {
  height: 48px; border: 0; border-radius: 12px; font-size: 20px; font-weight: 700;
  background: rgba(255,255,255,.14); color: #fff; cursor: pointer;
}
#cgrid button.sel { background: #43a047; }
#cgrid button:active { background: #66bb6a; }
''';

/// The practice table itself: page chrome, physics and animation.
///
/// Injected as [ModelViewer.relatedJs]. Everything runs inside the web view,
/// which is what keeps a six-die throw off the Flutter UI thread entirely.
///
/// Three things here differ from the standalone app this was written for, and
/// each is marked in place:
///
/// * `sym()` colours hearts and diamonds red - it used to check the wrong pair.
/// * `autoThrow()` posts to `DiceAudio`, so the game can play its dice sounds.
/// * `buildUI()` puts a back arrow in the app bar that posts to `DiceNav`.
const String diceLabJs = r'''
(function () {
  // ================== TWEAK THESE ==================
  var START_COUNT = 2;   // dice at start (1..MAX_DICE)
  var MAX_DICE = 6;     // maximum number of dice
  // canvas / dice size for 1..10 dice (index = number of dice). More dice = smaller dice.
  var SIZES = [0, 1.0, 1.0, 0.9, 0.8, 0.72, 0.66, 0.6, 0.55, 0.5, 0.46];
  var NEAR = 0.84;       // dice size when high up, close to the camera
  //++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // var GROUND = 0.21;     // dice size on the ground (smaller = farther away)
  //++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  var GROUND = 0.30;     // dice size on the ground (smaller = farther away)
  var DICE_HALF = 0.22;  // half width of dice vs screen width at scale 1 (fixes contact size)
  var BAR = 56;          // app bar height (px)
  var WALL = 6;          // invisible wall margin (px)
  var START_Z = 0.8;     // height the dice are thrown from (1 = closest to camera)
  var G = 7;             // gravity (lower = floatier, longer fall)
  var EZ = 0.5;          // ground bounce (0..1)
  var EW = 0.6;          // wall bounce (0..1)
  var EC = 0.75;         // dice-vs-dice bounce (0..1)
  var MU = 0.25;         // dice-vs-dice friction (sideways scrape when they touch)
  var FRICTION = 1500;   // ground friction (px/s^2)
  var DRAG = 0.55;       // air drag
  var SPIN = 0.8;        // rolling: degrees turned per pixel travelled
  var TIMESCALE = 1;     // 0.5 = slow motion
  var MAX_HISTORY = 50;  // how many past rolls to keep

  // [roll, pitch] in degrees that puts each number on TOP (your calibrated values).
  var FACES = { 1:[-90,0], 2:[0,0], 3:[0,90], 4:[0,-90], 5:[0,180], 6:[90,0] };
  // =================================================

   // symbol shown for each number (change here if a pair is swapped)
   var SYMBOLS = { 1:'♥', 2:'👑', 3:'♠', 4:'♣', 5:'🚩', 6:'♦' };
  // var SYMBOLS = { 1:'♣', 2:'👑', 3:'♥', 4:'♦', 5:'🚩', 6:'♠' };
  function sym(v) {
    // Hearts are 1 and diamonds are 6 in the map above, so those are the two
    // that read red. The old test here marked 3 and 4 - spade and club.
    var red = (v === 1 || v === 6);
    return '<span style="font-size:24px;' + (red ? 'color:#ff5252' : '') + '">' + SYMBOLS[v] + '</span>';
  }

  // The two bridges back into Flutter. Both are absent in any page served
  // without javascriptChannels, so every call is guarded: a missing channel
  // costs the sound or the shortcut, never the throw.
  function toFlutter(name, message) {
    try { if (window[name]) window[name].postMessage(message); } catch (e) { }
  }

  var ICON_HIST = '<svg viewBox="0 0 24 24" width="26" height="26" fill="#fff"><path d="M13 3a9 9 0 0 0-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42A8.954 8.954 0 0 0 13 21a9 9 0 0 0 0-18zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z"/></svg>';
  var ICON_DICE = '<svg viewBox="0 0 24 24" width="24" height="24" fill="#fff"><path d="M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zM7.5 18a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm0-9a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm4.5 4.5a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm4.5 4.5a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3zm0-9a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3z"/></svg>';
  var ICON_BACK = '<svg viewBox="0 0 24 24" width="26" height="26" fill="#fff"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>';

  var DT = 1 / 240, NMAX = 240 * 9;
  var ELEM = SIZES[START_COUNT];
  var count = START_COUNT;
  var dice = [], act = [], history = [], rollNo = 0;
  var first, label, bar, panel, cpanel, rolling = false, openId = null, W, H;

  function $(id) { return document.getElementById(id); }
  function mk(tag, id, html) {
    var e = document.createElement(tag); if (id) e.id = id; if (html !== undefined) e.innerHTML = html; return e;
  }
  function rad(z) { return W * DICE_HALF * ELEM * (GROUND + z * (NEAR - GROUND)); }
  function bounds() {
    return { L: WALL - W / 2, R: W - WALL - W / 2, T: BAR + WALL - H / 2, B: H - WALL - H / 2 };
  }
  function rnd(n) { return 1 + Math.floor(Math.random() * n); }
  function corr(v) { return v - Math.round(v / 360) * 360; }
  function say(t) { if (label) label.textContent = t; }

  // ---------------------------------------------------------------- physics
  // Each die has: position (x,y), height z, velocity (vx,vy,vz) and angular speeds
  // wr/wp (tumbling) + wy (spin on the table). On the ground a die ROLLS: its tumble
  // follows its velocity. In the air it keeps its spin. Collisions change both.
  function simulate(bs) {
    var bd = bounds(), L = bd.L, R = bd.R, T = bd.T, B = bd.B;
    var m = bs.length, o = [], k, i, p, q, it;
    for (k = 0; k < m; k++)
      o.push({ X: [], Y: [], Z: [], AR: [], AP: [], AY: [], PL: [], ar: 0, ap: 0, ay: 0, path: 0 });

    for (i = 0; i < NMAX; i++) {
      for (k = 0; k < m; k++) {
        var c = bs[k], a = o[k];
        c.vz -= G * DT; c.z += c.vz * DT;
        if (c.z <= 0) {
          c.z = 0;
          if (Math.abs(c.vz) > 0.35) {
            c.vz = Math.abs(c.vz) * EZ; c.vx *= 0.8; c.vy *= 0.8;
            // landing on a corner/edge kicks the dice into a new spin
            c.wy += (Math.random() - 0.5) * 500;
            c.wr += (Math.random() - 0.5) * 240;
            c.wp += (Math.random() - 0.5) * 240;
          } else { c.vz = 0; }
        }
        var s0 = Math.sqrt(c.vx * c.vx + c.vy * c.vy);
        if (c.z > 0) { var d = Math.pow(DRAG, DT); c.vx *= d; c.vy *= d; }
        else if (s0 > 0) { var f = Math.max(0, s0 - FRICTION * DT) / s0; c.vx *= f; c.vy *= f; }

        c.x += c.vx * DT; c.y += c.vy * DT;

        var r = rad(c.z);
        if (c.x < L + r) { c.x = L + r; if (c.vx < 0) { c.vx = -c.vx * EW; c.wy += c.vy * 0.4; } }
        if (c.x > R - r) { c.x = R - r; if (c.vx > 0) { c.vx = -c.vx * EW; c.wy -= c.vy * 0.4; } }
        if (c.y < T + r) { c.y = T + r; if (c.vy < 0) { c.vy = -c.vy * EW; c.wy += c.vx * 0.4; } }
        if (c.y > B - r) { c.y = B - r; if (c.vy > 0) { c.vy = -c.vy * EW; c.wy -= c.vx * 0.4; } }

        // angular motion
        if (c.z === 0 && c.vz === 0) {
          var kk = Math.min(1, 14 * DT);                 // rolling without slipping
          c.wr += (c.vx * SPIN - c.wr) * kk;
          c.wp += (c.vy * SPIN - c.wp) * kk;
          c.wy *= Math.pow(0.04, DT);                    // table friction slows the spin
        } else {
          c.wy *= Math.pow(0.7, DT);                     // air: spin keeps going
        }
        a.ar += c.wr * DT; a.ap += c.wp * DT; a.ay += c.wy * DT;
      }

      // dice vs dice (2 passes per step so stacks of dice separate cleanly)
      for (it = 0; it < 2; it++) {
        for (p = 0; p < m; p++) for (q = p + 1; q < m; q++) {
          var A = bs[p], Bd = bs[q];
          if (Math.abs(A.z - Bd.z) > 0.3) continue;
          var dx = Bd.x - A.x, dy = Bd.y - A.y, dist = Math.sqrt(dx * dx + dy * dy);
          var minD = rad(A.z) + rad(Bd.z);
          if (dist < minD) {
            if (dist < 0.001) { dx = Math.random() - 0.5; dy = Math.random() - 0.5; dist = Math.sqrt(dx * dx + dy * dy) || 1; }
            var nx = dx / dist, ny = dy / dist, ov = minD - dist;
            A.x -= nx * ov / 2; A.y -= ny * ov / 2; Bd.x += nx * ov / 2; Bd.y += ny * ov / 2;
            var rvx = Bd.vx - A.vx, rvy = Bd.vy - A.vy, rvn = rvx * nx + rvy * ny;

            if (rvn < 0) {
             // NEW: a cube hits with a corner or a flat face, so the push is never perfectly straight
              var ja = (Math.random() - 0.5) * 0.7;               // about ±20°
              var inx = nx * Math.cos(ja) - ny * Math.sin(ja);
              var iny = nx * Math.sin(ja) + ny * Math.cos(ja);

              var j = -(1 + EC) * rvn / 2;                       // bounce (equal mass)
              var tx = -ny, ty = nx, rvt = rvx * tx + rvy * ty;  // sliding speed along the contact
              var jt = Math.max(-MU * j, Math.min(MU * j, -rvt / 2)); // friction, capped (Coulomb)
              var dax = -j * nx - jt * tx, day = -j * ny - jt * ty;
              var dbx = j * nx + jt * tx, dby = j * ny + jt * ty;
              A.vx += dax; A.vy += day; Bd.vx += dbx; Bd.vy += dby;
              // hit = tumble: the impulse also turns the dice, and the scrape makes them spin
              A.wr += dax * SPIN; A.wp += day * SPIN; Bd.wr += dbx * SPIN; Bd.wp += dby * SPIN;
              A.wy -= jt * 6; Bd.wy -= jt * 6;
              A.wy += (Math.random() - 0.5) * 60; Bd.wy += (Math.random() - 0.5) * 60;
            }
          }
        }
      }

      var allRest = true;
      for (k = 0; k < m; k++) {
        var cc = bs[k], oo = o[k], sp2 = Math.sqrt(cc.vx * cc.vx + cc.vy * cc.vy);
        oo.path += sp2 * DT + Math.abs(cc.vz) * DT * 300;
        oo.X.push(cc.x); oo.Y.push(cc.y); oo.Z.push(cc.z);
        oo.AR.push(oo.ar); oo.AP.push(oo.ap); oo.AY.push(oo.ay); oo.PL.push(oo.path);
        if (!(cc.z === 0 && sp2 < 8)) allRest = false;
      }
      if (allRest && i > 30) break;
    }

    for (k = 0; k < m; k++) {
      var zz = o[k], total = zz.PL[zz.PL.length - 1] || 1;
      for (i = 0; i < zz.PL.length; i++) zz.PL[i] /= total;
      zz.cr = corr(zz.ar); zz.cp = corr(zz.ap); zz.cy = corr(zz.ay);
    }
    return o;
  }

  // -------------------------------------------------------------- rendering
  function place(d, x, y, z) {
    d.x = x; d.y = y;
    var s = GROUND + z * (NEAR - GROUND);
    d.el.style.transform = 'translate3d(' + x + 'px,' + y + 'px,0) scale(' + s + ')';
    d.sh.style.transform = 'translate(' + (x + z * 35) + 'px,' + (y + z * 50 + 3) +
      'px) translate(-50%,-50%) scale(' + (s / GROUND) + ')';
    d.sh.style.opacity = (0.1 + 0.5 * (1 - Math.min(z, 1))).toFixed(3);
  }

  function setOri(d, r, p, y) {
    try {
      d.el.orientation = r.toFixed(1) + 'deg ' + p.toFixed(1) + 'deg ' + y.toFixed(1) + 'deg';
    } catch (e) { /* a dice that is not ready must never stop the animation */ }
  }

  // ---------------------------------------------------------------- panels
   function renderHistory() {
    var list = $('plist');
    if (!history.length) {
      list.innerHTML = '<div class="empty">No rolls yet - tap the table to throw the dice!</div>';
      return;
    }
    list.innerHTML = history.map(function (h) {
      var txt = h.vals.map(sym).join(' &nbsp; ');
      return '<div class="row"><span class="n">#' + h.no + '</span><span>' + txt + '</span></div>';
    }).join('');
  }
  function markSel() {
    var bs = $('cgrid').children;
    for (var i = 0; i < bs.length; i++) bs[i].className = (i + 1 === count) ? 'sel' : '';
  }
  function closePanels() {
    panel.style.display = 'none'; cpanel.style.display = 'none'; openId = null;
  }
  function togglePanel(id) {
    if (openId === id) { closePanels(); return; }
    closePanels();
    if (id === 'h') { renderHistory(); panel.style.display = 'flex'; }
    else { markSel(); cpanel.style.display = 'block'; }
    openId = id;
  }

  // ------------------------------------------------------------------ throw
  function throwDice(bs) {
    rolling = true;
    say('Rolling...');
    var k, vals = [], yaws = [];
    for (k = 0; k < act.length; k++) { vals.push(rnd(6)); yaws.push(Math.random() * 360); }
    var sims = simulate(bs), n = sims[0].X.length, t0 = null;

    function frame(now) {
      if (t0 === null) t0 = now;
      var simT = (now - t0) / 1000 * TIMESCALE;
      var i = Math.min(Math.floor(simT / DT), n - 1);
      for (var k = 0; k < act.length; k++) {
        var s = sims[k], p = s.PL[i], f = FACES[vals[k]];
        place(act[k], s.X[i], s.Y[i], s.Z[i]);
        setOri(act[k], f[0] + s.AR[i] - s.cr * p, f[1] + s.AP[i] - s.cp * p, yaws[k] + s.AY[i] - s.cy * p);
      }
      if (i < n - 1) {
        requestAnimationFrame(frame);
       } else {
        var sum = 0;
        for (var j = 0; j < act.length; j++) {
          var ff = FACES[vals[j]];
          setOri(act[j], ff[0], ff[1], yaws[j]);
          sum += vals[j];
        }
        rolling = false;
        rollNo++;
        history.unshift({ no: rollNo, vals: vals.slice(), sum: sum });
        if (history.length > MAX_HISTORY) history.pop();
        if (openId === 'h') renderHistory();
        say(vals.map(function (v) { return SYMBOLS[v]; }).join('  ') + '  |  tap to throw again');
      }
    }
    requestAnimationFrame(frame);
  }

  function autoThrow() {
    // The dice are leaving the cup now, which is when the game plays its
    // rattle. The roll itself lands a beat later, from Flutter's side.
    toFlutter('DiceAudio', 'throw');
    var b = bounds(), r0 = rad(START_Z), span = b.R - b.L - 2 * r0, m = act.length, bs = [];
    for (var k = 0; k < m; k++) {
      var a = (Math.random() * 100 - 50) * Math.PI / 180, sp = 1300 + Math.random() * 1700;
      var vx = sp * Math.sin(a), vy = -sp * Math.cos(a);
      bs.push({
        x: b.L + r0 + span * (k + 0.5) / m + (Math.random() - 0.5) * 20,
        y: b.B - r0 - 20 - Math.random() * 30,
        z: START_Z - 0.05 * (k % 4),                       // different heights = no overlap at start
        vx: vx, vy: vy, vz: 0.9 + Math.random() * 1.3,
        wr: vx * SPIN, wp: vy * SPIN, wy: (Math.random() - 0.5) * 400
      });
    }
    throwDice(bs);
  }

  function onDown(e) {
    var t = e.target;
    if (t && t.closest && t.closest('#bar, #panel, #cpanel')) return; // taps on the UI
    if (openId) { closePanels(); return; }
    if (rolling) return;
    W = window.innerWidth; H = window.innerHeight;
    act = dice.filter(function (d) { return d.ok && d.ready && d.idx < count; });
    if (!act.length) { say('Loading dice...'); return; }
    try { autoThrow(); }
    catch (err) { rolling = false; say('ERROR: ' + err.message); }
  }

  // ---------------------------------------------------------------- set up
  function whenLoaded(e, cb) {
    if (e.loaded) cb(); else e.addEventListener('load', cb, { once: true });
  }

  function restSpot(self) {
    var b = bounds(), r = rad(0), x, y, t = 0;
    do {
      x = b.L + r + Math.random() * (b.R - b.L - 2 * r);
      y = b.T + r + Math.random() * (b.B - b.T - 2 * r);
      t++;
    } while (t < 60 && dice.some(function (q) {
      return q !== self && q.x !== undefined && Math.hypot(q.x - x, q.y - y) < r * 2.2;
    }));
    return { x: x, y: y };
  }

  function statusText() {
    var shown = dice.filter(function (d) { return d.ok && d.idx < count; });
    var loadedCount = shown.filter(function (d) { return d.ready; }).length;
    if (shown.length < count && loadedCount === shown.length && dice.length < count) { say('Loading dice...'); return; }
    say(loadedCount < shown.length ? 'Loading dice ' + loadedCount + '/' + shown.length + '...' : 'Tap to throw the dice');
  }

  function styleDie(d) {
    var e = d.el;
    e.style.setProperty('width', (ELEM * 100) + 'vw', 'important');
    e.style.setProperty('height', (ELEM * 100) + 'vw', 'important');
    e.style.setProperty('left', (-(ELEM - 1) * 50) + 'vw', 'important');
    e.style.setProperty('margin-top', (-ELEM * 50) + 'vw', 'important');
    var sw = W * DICE_HALF * ELEM * 2 * GROUND * 1.15;
    d.sh.style.width = sw + 'px'; d.sh.style.height = sw + 'px';
  }

  function addDie(e) {
    e.classList.add('die');
    e.setAttribute('loading', 'eager');

    var sh = mk('div'); sh.className = 'shadow';
    document.body.appendChild(sh);

    var d = { el: e, sh: sh, ok: true, ready: false, idx: dice.length };
    dice.push(d);
    styleDie(d);
    var spot = restSpot(d);
    place(d, spot.x, spot.y, 0);

    whenLoaded(e, function () {
      var f = FACES[rnd(6)];
      d.ready = true;
      setOri(d, f[0], f[1], Math.random() * 360);
      statusText();
    });
    return d;
  }

  function fail(d) {
    if (!d.ok || d.ready) return;
    d.ok = false;
    d.el.style.display = 'none';
    d.sh.style.display = 'none';
    say('One dice could not load - continuing with the others');
  }

  function spawn() {
    var c = first.cloneNode(true);
    c.id = 'dice' + (dice.length + 1);
    first.parentNode.appendChild(c);
    var d = addDie(c);
    d.el.addEventListener('error', function () { fail(d); });
    setTimeout(function () { fail(d); }, 15000);
    return d;
  }

  // change how many dice are on the table
  function setCount(n) {
    count = Math.max(1, Math.min(MAX_DICE, n));
    ELEM = SIZES[count];
    W = window.innerWidth; H = window.innerHeight;
    while (dice.length < count) spawn();
    dice.forEach(function (d, i) {
      var on = i < count && d.ok;
      d.el.style.display = on ? '' : 'none';
      d.sh.style.display = on ? '' : 'none';
      d.x = undefined;
      if (on) styleDie(d);
    });
    dice.forEach(function (d, i) {
      if (i < count && d.ok) { var s = restSpot(d); place(d, s.x, s.y, 0); }
    });
    $('cnt').textContent = count;
    statusText();
  }

  function buildUI() {
    label = mk('div', 'label', 'Loading dice...');
    document.body.appendChild(label);

    // The back arrow leads; the title follows it. The arrow posts to the
    // DiceNav channel, which pops the route on the Flutter side.
    bar = mk('div', 'bar',
      '<button id="backBtn" title="Back to the table">' + ICON_BACK + '</button>' +
      '<div class="title">Dice Roll</div>' +
      '<button id="cntBtn" class="cnt" title="Number of dice">' + ICON_DICE + '<span id="cnt">' + count + '</span></button>' +
      '<button id="histBtn" title="Roll history">' + ICON_HIST + '</button>');
    document.body.appendChild(bar);

    panel = mk('div', 'panel',
      '<div class="ph"><span>Roll history</span><button id="clrBtn">Clear</button></div><div id="plist"></div>');
    document.body.appendChild(panel);

    cpanel = mk('div', 'cpanel',
      '<div class="ph"><span>Number of dice</span></div><div id="cgrid"></div>');
    document.body.appendChild(cpanel);

    var grid = $('cgrid');
    for (var n = 1; n <= MAX_DICE; n++) {
      var b = mk('button', null, String(n));
      b.setAttribute('data-n', n);
      b.addEventListener('click', function () {
        if (rolling) return;
        setCount(parseInt(this.getAttribute('data-n'), 10));
        closePanels();
      });
      grid.appendChild(b);
    }

    $('backBtn').addEventListener('click', function () { toFlutter('DiceNav', 'back'); });
    $('histBtn').addEventListener('click', function () { togglePanel('h'); });
    $('cntBtn').addEventListener('click', function () { togglePanel('c'); });
    $('clrBtn').addEventListener('click', function () { history = []; rollNo = 0; renderHistory(); });
  }

  function start() {
    first = document.getElementById('dice');
    if (!first) { setTimeout(start, 50); return; }
    W = window.innerWidth; H = window.innerHeight;

    buildUI();
    window.onerror = function (m, u, l) { say('JS ERROR: ' + m + ' (line ' + l + ')'); };

    addDie(first);

    // create the extra dice only AFTER the first one has fully loaded
    whenLoaded(first, function () { setCount(count); });

    window.addEventListener('pointerdown', onDown);
  }
  start();
})();
''';

/// Builds the web view that is the body of the practice table.
///
/// [onBack] fires when the arrow in the page's app bar is tapped and [onThrow]
/// on every throw; both are called from the web view, so a caller must expect
/// them at any time and must not assume they arrive from a user gesture on the
/// Flutter side.
///
/// The page is served from a loopback HTTP server started by the widget, which
/// is why the Android manifest permits cleartext traffic to localhost.
Widget buildDiceLabViewer({
  required VoidCallback onBack,
  required VoidCallback onThrow,
}) {
  return ModelViewer(
    id: 'dice',
    src: 'assets/dice.glb',
    backgroundColor: Colors.transparent,
    ar: false,
    autoRotate: false,
    cameraControls: false,
    disableZoom: true,
    disablePan: true,
    disableTap: true,
    interactionPrompt: InteractionPrompt.none,
    // fixed aerial (top-down) camera
    cameraOrbit: '0deg 6deg auto',
    minCameraOrbit: 'auto 0deg auto',
    maxCameraOrbit: 'auto 180deg auto',
    debugLogging: false,
    javascriptChannels: <JavascriptChannel>{
      JavascriptChannel(
        'DiceNav',
        onMessageReceived: (_) => onBack(),
      ),
      JavascriptChannel(
        'DiceAudio',
        onMessageReceived: (_) => onThrow(),
      ),
    },
    relatedCss: diceLabCss,
    relatedJs: diceLabJs,
  );
}
