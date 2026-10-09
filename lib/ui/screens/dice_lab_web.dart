/// Everything about the 3D dice that lives inside the web view.
///
/// The dice, the physics and the page chrome are a self-contained HTML/CSS/JS
/// application served into a [ModelViewer] from a loopback HTTP server. Flutter
/// owns none of it: it paints the page, then sits idle while JavaScript steps
/// the simulation at 240 hertz and writes transforms straight to the DOM. That
/// is the whole reason this screen is not another `CustomPainter` - the frame
/// budget belongs to the throw, not to the widget tree.
///
/// One page serves two screens, told apart by the `DICE_GAME` flag Dart writes
/// immediately above the script:
///
/// * **Practice** ([buildDiceLabViewer]) - free throws, 1..6 dice chosen on the
///   page, history and a dice-count picker, the player decides when to throw.
///   Its seam back into Flutter is two [JavascriptChannel]s called from
///   [diceLabJs]: `DiceNav` for the back arrow in the page's app bar, and
///   `DiceAudio` on every throw so the practice table is not the one screen in
///   the app that is silent.
/// * **The real-money throw** ([buildGameThrowViewer]) - always the game's six
///   dice, no chrome, no tap to rethrow, and the faces are not the page's to
///   choose: Dart sends them in and waits for the page to report that they have
///   landed. Its seam is the other two channels, `DiceReady` and `DiceSettled`.
///
/// Neither channel is optional at its call site: all four are guarded in JS,
/// because a missing channel must degrade to "no sound, no shortcut" rather
/// than to a `JS ERROR` banner over the dice.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart' show WebViewController;

import '../../core/config.dart';
import '../../models/symbol.dart';

/// Styling for the 3D dice page, injected as [ModelViewer.relatedCss].
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
  --progress-bar-height: 0px;
  --progress-bar-color: transparent;
  will-change: transform; transform-origin: 50% 50%;
}
.die::part(default-progress-bar) { display: none; }

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
  // DICE_GAME and DICE_COUNT come from Dart, written immediately above this
  // script so they are set before the IIFE reads them. The practice table is
  // free and self-governed; the real-money throw is fixed at the game's six
  // dice and has no bar of its own to spend height on.
  var START_COUNT = DICE_GAME ? DICE_COUNT : 2;   // dice at start (1..MAX_DICE)
  var MAX_DICE = 6;     // maximum number of dice
  // canvas / dice size for 1..10 dice (index = number of dice). More dice = smaller dice.
  var SIZES = [0, 1.0, 1.0, 0.9, 0.8, 0.72, 0.66, 0.6, 0.55, 0.5, 0.46];
  var NEAR = 0.84;       // dice size when high up, close to the camera
  //++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // var GROUND = 0.21;     // dice size on the ground (smaller = farther away)
  //++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  var GROUND = 0.30;     // dice size on the ground (smaller = farther away)
  var DICE_HALF = 0.22;  // half width of dice vs screen width at scale 1 (fixes contact size)
  var BAR = DICE_GAME ? 0 : 56;   // app bar height (px); none in game mode
  var WALL = 6;          // invisible wall margin (px)
  var START_Z = 0.8;     // height the dice are thrown from (1 = closest to camera)
  var G = 7;             // gravity (lower = floatier, longer fall)
  var EZ = 0.42;         // ground bounce (0..1): less lively, more weight
  var EW = 0.5;          // wall bounce (0..1)
  var EC = 0.62;         // dice-vs-dice bounce (0..1)
  var MU = 0.32;         // contact friction (the sideways scrape on a hit)
  var WSPIN = 0.9;       // table spin a scrape along a wall imparts (deg per px/s)
  var FRICTION = 1150;   // ground friction (px/s^2)
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
  // Smallest angle between two headings, in degrees, whatever number of full
  // turns separate the raw accumulations.
  function angGap(a, b) {
    var d = Math.abs(a - b) % 360;
    return d > 180 ? 360 - d : d;
  }
  function say(t) { if (label) label.textContent = t; }

  // One die against a static wall whose inward normal is (nx, ny). Resolves the
  // normal bounce, Coulomb friction along the wall, and the table spin that
  // scrape imparts - so a die skids and spins off a rail like a real cube
  // instead of reflecting with a hand-tuned twist.
  function wallResponse(c, nx, ny) {
    var vn = c.vx * nx + c.vy * ny;
    if (vn >= 0) return;                 // not moving into the wall
    var tx = -ny, ty = nx;               // along the wall
    var vt = c.vx * tx + c.vy * ty;
    var dvn = -(1 + EW) * vn;            // push back out of the wall
    var maxF = MU * dvn;                 // Coulomb limit for the scrape
    var dvt = Math.max(-maxF, Math.min(maxF, -vt));
    c.vx += dvn * nx + dvt * tx;
    c.vy += dvn * ny + dvt * ty;
    c.wy -= dvt * WSPIN;
  }

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
          var impact = -c.vz;                 // how hard the corner hit the felt
          c.z = 0;
          if (impact > 0.35) {
            c.vz = impact * EZ;
            c.vx *= 0.82; c.vy *= 0.82;
            // a corner catches and kicks the die into a new tumble; the harder
            // the landing, the bigger the kick
            var kick = Math.min(1, impact);
            c.wy += (Math.random() - 0.5) * 520 * kick;
            c.wr += (Math.random() - 0.5) * 260 * kick;
            c.wp += (Math.random() - 0.5) * 260 * kick;
          } else { c.vz = 0; }
        }
        var s0 = Math.sqrt(c.vx * c.vx + c.vy * c.vy);
        if (c.z > 0) { var d = Math.pow(DRAG, DT); c.vx *= d; c.vy *= d; }
        else if (s0 > 0) { var f = Math.max(0, s0 - FRICTION * DT) / s0; c.vx *= f; c.vy *= f; }

        c.x += c.vx * DT; c.y += c.vy * DT;

        var r = rad(c.z);
        if (c.x < L + r) { c.x = L + r; wallResponse(c, 1, 0); }
        if (c.x > R - r) { c.x = R - r; wallResponse(c, -1, 0); }
        if (c.y < T + r) { c.y = T + r; wallResponse(c, 0, 1); }
        if (c.y > B - r) { c.y = B - r; wallResponse(c, 0, -1); }

        // angular motion
        if (c.z === 0 && c.vz === 0) {
          var kk = Math.min(1, 14 * DT);                 // rolling without slipping
          c.wr += (c.vx * SPIN - c.wr) * kk;
          c.wp += (c.vy * SPIN - c.wp) * kk;
          c.wy *= Math.pow(0.04, DT);                    // table friction slows the spin
        } else {
          c.wy *= Math.pow(0.7, DT);                     // air: spin keeps going
          var ad = Math.pow(0.9, DT);                    // a touch of air tumble drag
          c.wr *= ad; c.wp *= ad;
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
            // Leave a hair of overlap and correct most of the rest, so touching
            // dice stop micro-jittering against each other while still parting.
            var push = Math.max(ov - 0.02 * minD, 0) * 0.5;
            A.x -= nx * push; A.y -= ny * push; Bd.x += nx * push; Bd.y += ny * push;
            var rvx = Bd.vx - A.vx, rvy = Bd.vy - A.vy;
            // A cube meets a cube with a corner or a flat face, so the contact
            // normal is a little off the centre line - jitter it about ±20°.
            var ja = (Math.random() - 0.5) * 0.7;
            var inx = nx * Math.cos(ja) - ny * Math.sin(ja);
            var iny = nx * Math.sin(ja) + ny * Math.cos(ja);
            var itx = -iny, ity = inx;                             // along the contact
            var rvn = rvx * inx + rvy * iny;

            if (rvn < 0) {
              var j = -(1 + EC) * rvn / 2;                         // bounce (equal mass)
              var rvt = rvx * itx + rvy * ity;                     // sliding speed along the contact
              var jt = Math.max(-MU * j, Math.min(MU * j, -rvt / 2)); // friction, capped (Coulomb)
              var dax = -j * inx - jt * itx, day = -j * iny - jt * ity;
              var dbx = j * inx + jt * itx, dby = j * iny + jt * ity;
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
        // Demand that the spin has actually died before the roll ends. With the
        // fast table decay the die reaches these thresholds naturally, so the
        // roll just runs the extra ~half second instead of freezing mid-spin.
        if (!(cc.z === 0 && sp2 < 8 && Math.abs(cc.wy) < 8 &&
              Math.abs(cc.wr) < 15 && Math.abs(cc.wp) < 15)) allRest = false;
      }
      if (allRest && i > 30) break;
    }

    for (k = 0; k < m; k++) {
      var zz = o[k], total = zz.PL[zz.PL.length - 1] || 1;
      for (i = 0; i < zz.PL.length; i++) zz.PL[i] /= total;
      zz.cr = corr(zz.ar); zz.cp = corr(zz.ap); zz.cy = corr(zz.ay);

      // The path keeps a sample per step until the LAST die rests, so a die that
      // stopped early is padded with identical values. Find the first of those
      // trailing samples and let the render loop skip the die from there on:
      // every skipped frame is a model-viewer scene that does not re-render.
      var last = zz.X.length - 1;
      var fx = zz.X[last], fy = zz.Y[last], fz = zz.Z[last], fp = zz.PL[last];
      var fa = zz.AR[last], fb = zz.AP[last], fc = zz.AY[last];
      zz.settle = last;
      while (zz.settle > 0) {
        var j = zz.settle - 1;
        if (Math.abs(zz.X[j] - fx) < 0.05 && Math.abs(zz.Y[j] - fy) < 0.05 &&
            Math.abs(zz.Z[j] - fz) < 0.001 && Math.abs(zz.PL[j] - fp) < 0.0005 &&
            Math.abs(zz.AR[j] - fa) < 0.05 && Math.abs(zz.AP[j] - fb) < 0.05 &&
            Math.abs(zz.AY[j] - fc) < 0.05) {
          zz.settle = j;
        } else { break; }
      }
    }
    return o;
  }

  // -------------------------------------------------------------- rendering
  function place(d, x, y, z) {
    d.x = x; d.y = y;
    var s = GROUND + z * (NEAR - GROUND);
    d.el.style.transform = 'translate3d(' + x + 'px,' + y + 'px,0) scale(' + s + ')';
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
  // `forced` is the real-money path: Dart has already drawn the faces from
  // DiceRoller, and the page only has to land on them. Without it the page
  // decides for itself, which is what the practice table wants.
  function throwDice(bs, forced) {
    rolling = true;
    say('Rolling...');
    var k, vals = [], yaws = [];
    for (k = 0; k < act.length; k++) { vals.push(forced ? forced[k] : rnd(6)); yaws.push(Math.random() * 360); }
    var sims = simulate(bs), n = sims[0].X.length, t0 = null;
    var frozen = [], last = [];
    for (k = 0; k < act.length; k++) { frozen.push(false); last.push(null); }

    // Every die has stopped, so paint the exact faces, record the roll and let
    // Flutter settle. Split out so the loop can reach it the moment the last
    // die freezes rather than ticking through the precomputed tail.
    function finish() {
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
      // The real-money throw waits on this and nothing else, so it fires from
      // the settle frame rather than from the release: Dart must not settle
      // the wagers while the dice are still moving.
      toFlutter('DiceSettled', vals.join(','));
    }

    function frame(now) {
      if (t0 === null) t0 = now;
      var simT = (now - t0) / 1000 * TIMESCALE;
      var i = Math.min(Math.floor(simT / DT), n - 1);
      var allFrozen = true;
      for (var k = 0; k < act.length; k++) {
        var s = sims[k];
        if (frozen[k]) continue;   // settled already: leave its scene untouched
        allFrozen = false;
        var p = s.PL[i], f = FACES[vals[k]];
        // Pull the tumble onto the dealt face with a smoothstep of how far the
        // die has travelled: barely at first, firmly as it slows. The ramp is
        // mapped to finish at 90% of the path and then held, so the correction
        // has stopped moving before the die freezes - otherwise it was still
        // turning the die a little on the very last painted frame, which read
        // as the spin cutting off.
        var t = Math.min(1, p / 0.9);
        var ease = t * t * (3 - 2 * t);
        var x = s.X[i], y = s.Y[i], z = s.Z[i];
        var r = f[0] + s.AR[i] - s.cr * ease;
        var pi = f[1] + s.AP[i] - s.cp * ease;
        var yy = yaws[k] + s.AY[i] - s.cy * ease;
        // Only write when the change is big enough to see. A die on its slow
        // tail would otherwise re-render its whole scene for a fraction of a
        // pixel, and those frames are most of a roll.
        var q = last[k];
        if (!q || Math.abs(x - q.x) >= 0.5 || Math.abs(y - q.y) >= 0.5 ||
            Math.abs(z - q.z) >= 0.004 || angGap(r, q.r) >= 0.25 ||
            angGap(pi, q.pi) >= 0.25 || angGap(yy, q.yy) >= 0.25) {
          place(act[k], x, y, z);
          setOri(act[k], r, pi, yy);
          last[k] = { x: x, y: y, z: z, r: r, pi: pi, yy: yy };
        }
        if (i >= s.settle) { frozen[k] = true; last[k] = null; }
      }
      if (allFrozen || i >= n - 1) { finish(); return; }
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  }

  // Releases the dice from the cup. `forced`, when given, are the faces Dart
  // has already dealt; null lets the page choose for itself.
  function launch(forced) {
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
    throwDice(bs, forced);
  }

  function autoThrow() {
    // The dice are leaving the cup now, which is when the game plays its
    // rattle. The roll itself lands a beat later, from Flutter's side.
    // The real-money throw stays silent here: there, Dart plays the rattle the
    // moment it starts the throw and the landing sound from DiceSettled, so a
    // second rattle would double up under one release.
    if (!DICE_GAME) toFlutter('DiceAudio', 'throw');
    launch(null);
  }

  // The one way the real-money screen throws. Dart calls it with the faces it
  // has already dealt, so the page never decides anything that reaches the
  // wallet. It refuses rather than guessing when it cannot honour the request,
  // and reports the refusal on DiceSettled so Dart is never left waiting on a
  // throw that did not happen.
  window.diceThrow = function (vals) {
    if (rolling) { toFlutter('DiceSettled', 'refused'); return false; }
    W = window.innerWidth; H = window.innerHeight;
    act = dice.filter(function (d) { return d.ok && d.ready && d.idx < count; });
    if (act.length !== vals.length) { toFlutter('DiceSettled', 'refused'); return false; }
    launch(vals);
    return true;
  };

  function onDown(e) {
    if (DICE_GAME) return;   // the real-money throw is Dart's to start, once
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

  // The real-money throw's gate. Dart will not deal a round until every die on
  // the table has loaded, so a page that half-starts falls back to the 2D dice
  // instead of throwing six dice and showing four. Practice never sends this -
  // it has its own "Loading dice..." text and a tap to discover the rest.
  var readySent = false;
  function maybeReady() {
    if (!DICE_GAME || readySent) return;
    var shown = dice.filter(function (d) { return d.ok && d.idx < count; });
    if (shown.length < count) return;
    for (var i = 0; i < shown.length; i++) if (!shown[i].ready) return;
    readySent = true;
    toFlutter('DiceReady', 'ready');
  }

  function styleDie(d) {
    var e = d.el;
    e.style.setProperty('width', (ELEM * 100) + 'vw', 'important');
    e.style.setProperty('height', (ELEM * 100) + 'vw', 'important');
    e.style.setProperty('left', (-(ELEM - 1) * 50) + 'vw', 'important');
    e.style.setProperty('margin-top', (-ELEM * 50) + 'vw', 'important');
  }

  function addDie(e) {
    e.classList.add('die');
    e.setAttribute('loading', 'eager');

    var d = { el: e, ok: true, ready: false, idx: dice.length };
    dice.push(d);
    styleDie(d);
    var spot = restSpot(d);
    place(d, spot.x, spot.y, 0);

    whenLoaded(e, function () {
      var f = FACES[rnd(6)];
      d.ready = true;
      setOri(d, f[0], f[1], Math.random() * 360);
      statusText();
      maybeReady();
    });
    return d;
  }

  function fail(d) {
    if (!d.ok || d.ready) return;
    d.ok = false;
    d.el.style.display = 'none';
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
      d.x = undefined;
      if (on) styleDie(d);
    });
    dice.forEach(function (d, i) {
      if (i < count && d.ok) { var s = restSpot(d); place(d, s.x, s.y, 0); }
    });
    // The counter lives in the page's bar, which game mode never builds.
    if ($('cnt')) $('cnt').textContent = count;
    statusText();
    maybeReady();
  }

  function buildUI() {
    // The real-money throw has no page chrome at all: Flutter draws the button,
    // the result and the way out, and a bar painted inside the view would sit
    // in the middle of the screen rather than at the top of it. Everything
    // below this line is therefore practice-only.
    if (DICE_GAME) return;

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

/// How long the real-money throw waits for the page to finish loading before
/// it falls back to the 2D dice.
///
/// The model ships in the bundle and the server is on loopback, so this is
/// generous rather than long: it only costs anything when the page is genuinely
/// never going to arrive, and then it costs a spinner instead of a locked board.
const Duration pageLoadTimeout = Duration(seconds: 5);

/// How long the real-money throw waits for the dice to come to rest.
///
/// The physics is capped at `NMAX = 240 * 9` frames and plays back in real
/// time, so nine seconds is the longest a healthy page can take. This is the
/// guard against an unhealthy one: `GameController.roll` is awaiting this
/// future, and a page that stops answering must not leave the board stuck in
/// `RollPhase.rolling` with the back button disabled.
const Duration landingTimeout = Duration(seconds: 10);

/// Overrides applied only to the real-money throw, appended to [diceLabCss].
///
/// Appended rather than prepended on purpose: both are written into one style
/// block at equal specificity, so the later rule wins. The page normally paints
/// its own green felt, but on the throw screen the dice sit inside the app's
/// own column and the felt behind the view has to show through.
const String _gameCss = r'''
html, body { background: transparent !important; background-image: none !important; }
''';

/// The page for one mode: the flags first, then the script that reads them.
///
/// Both modes share one copy of the physics; only these two variables tell them
/// apart, and they have to be set before the IIFE runs.
String _pageJs({required bool game}) =>
    'var DICE_GAME = ${game ? 'true' : 'false'};\n'
    'var DICE_COUNT = ${AppConfig.diceCount};\n'
    '$diceLabJs';

/// One [ModelViewer] over the shared page, differing only in how it is dressed
/// and which channels it carries.
///
/// Served from a loopback HTTP server started by the widget, which is why the
/// Android manifest permits cleartext traffic to localhost.
Widget _diceViewer({
  required String css,
  required String js,
  required Set<JavascriptChannel> channels,
  void Function(WebViewController controller)? onWebViewCreated,
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
    onWebViewCreated: onWebViewCreated,
    javascriptChannels: channels,
    relatedCss: css,
    relatedJs: js,
  );
}

/// Builds the web view that is the body of the practice table.
///
/// [onBack] fires when the arrow in the page's app bar is tapped and [onThrow]
/// on every throw; both are called from the web view, so a caller must expect
/// them at any time and must not assume they arrive from a user gesture on the
/// Flutter side.
Widget buildDiceLabViewer({
  required VoidCallback onBack,
  required VoidCallback onThrow,
}) {
  return _diceViewer(
    css: diceLabCss,
    js: _pageJs(game: false),
    channels: <JavascriptChannel>{
      JavascriptChannel('DiceNav', onMessageReceived: (_) => onBack()),
      JavascriptChannel('DiceAudio', onMessageReceived: (_) => onThrow()),
    },
  );
}

/// Builds the web view that carries a real, coin-affecting throw.
///
/// [onController] hands over the page's own web view so a [WebDiceThrowBridge]
/// can call into it, [onReady] fires once every die has loaded and [onSettled]
/// once they have come to rest. All three are called from the web view, so a
/// caller must expect them at any time.
Widget buildGameThrowViewer({
  required void Function(WebViewController controller) onController,
  required VoidCallback onReady,
  required VoidCallback onSettled,
}) {
  return _diceViewer(
    css: '$diceLabCss$_gameCss',
    js: _pageJs(game: true),
    channels: <JavascriptChannel>{
      JavascriptChannel('DiceReady', onMessageReceived: (_) => onReady()),
      JavascriptChannel('DiceSettled', onMessageReceived: (_) => onSettled()),
    },
    onWebViewCreated: onController,
  );
}

/// The Dart half of one 3D throw: show the page, start it on faces Dart chose,
/// and report when the dice have landed.
///
/// Two implementations. [WebDiceThrowBridge] is the real one, holding the web
/// view behind [buildGameThrowViewer]. Tests install a fake through
/// `RollScreen.bridgeOverride`, because neither the loopback server nor the
/// platform web view exists under `flutter test`.
abstract interface class DiceThrowBridge {
  /// The page itself. Built once by the screen that needs it, so the web view
  /// and its server are not restarted on every rebuild.
  Widget buildViewer();

  /// Resolves true once every die has loaded, or false if [timeout] passes
  /// first - which is the signal to show the 2D dice instead.
  Future<bool> waitForReady({Duration timeout = pageLoadTimeout});

  /// Throws [faces] and resolves once the dice have come to rest.
  ///
  /// Bounded by [timeout] on purpose: the caller is `GameController.roll`, and
  /// a page that never reports a landing must not hold the board hostage.
  Future<void> land(List<Symbol> faces, {Duration timeout = landingTimeout});
}

/// The real bridge, over `model_viewer_plus` and `webview_flutter`.
class WebDiceThrowBridge implements DiceThrowBridge {
  WebViewController? _controller;

  /// The page posting `DiceReady`. One-shot, and guarded because a page can
  /// only be loaded once per viewer.
  final Completer<void> _ready = Completer<void>();

  /// The page posting `DiceSettled`. Created per throw in [land], since the
  /// refusal path can report before the call that triggered it returns.
  Completer<void>? _settled;

  @override
  Widget buildViewer() => buildGameThrowViewer(
    onController: (WebViewController controller) => _controller = controller,
    onReady: () {
      if (!_ready.isCompleted) _ready.complete();
    },
    onSettled: () {
      final Completer<void>? settled = _settled;
      if (settled != null && !settled.isCompleted) settled.complete();
    },
  );

  @override
  Future<bool> waitForReady({Duration timeout = pageLoadTimeout}) async {
    try {
      await _ready.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Future<void> land(
    List<Symbol> faces, {
    Duration timeout = landingTimeout,
  }) async {
    final WebViewController? controller = _controller;
    // The viewer was never attached to a web view. Returning settles the round
    // immediately rather than waiting for a message no channel can deliver.
    if (controller == null) return;

    final Completer<void> landed = Completer<void>();
    _settled = landed;
    final String values = faces.map((Symbol face) => face.dieNumber).join(',');

    try {
      await controller.runJavaScript(
        'window.diceThrow && window.diceThrow([$values]);',
      );
      await landed.future.timeout(timeout);
    } on TimeoutException {
      // The page stopped answering after the throw started. The faces being
      // scored are Dart's either way, so the round settles on them instead of
      // leaving the board locked behind `RollPhase.rolling`.
    } catch (_) {
      // The web view went away underneath the throw, most often because the
      // route was torn down. Same answer: settle rather than deadlock.
    } finally {
      if (identical(_settled, landed)) _settled = null;
    }
  }
}
