// Browser side of Rally Pace Notes: owns the sensor APIs and hands raw data
// to the Flutter app through a few window.rally* functions.
(function () {
  'use strict';

  var VERSION = '0.3';
  var KEY = 'rally.settings.v1';
  var S = {
    gx: 0, gy: 0,
    gyro: [0, 0, 0],      // accumulated rotation in degrees (alpha, beta, gamma)
    hasGyro: false,
    n: 0, lastT: 0,
    fixes: [], keys: [],
    motion: 'not started', geo: 'not started', wake: 'off',
    started: false, watchId: null,
    geoDenied: false, lastFixAt: 0, geoStartedAt: 0, geoRetry: null
  };

  // ------------------------------------------------------------ motion
  function onMotion(e) {
    var a = e.accelerationIncludingGravity;
    if (!a || typeof a.x !== 'number' || typeof a.y !== 'number') return;
    S.gx = a.x;
    S.gy = a.y;
    var now = e.timeStamp || performance.now();
    var r = e.rotationRate;
    if (r && typeof r.alpha === 'number') {
      if (S.lastT > 0) {
        var dt = (now - S.lastT) / 1000;
        if (dt > 0 && dt < 0.5) {
          S.gyro[0] += (r.alpha || 0) * dt;
          S.gyro[1] += (r.beta || 0) * dt;
          S.gyro[2] += (r.gamma || 0) * dt;
        }
      }
      S.hasGyro = true;
    }
    S.lastT = now;
    S.n++;
    S.motion = 'ok';
  }

  // --------------------------------------------------------------- GPS
  function onFix(p) {
    var c = p.coords;
    var speed = (typeof c.speed === 'number' && !isNaN(c.speed) && c.speed >= 0) ? c.speed : -1;
    S.fixes.push(c.latitude, c.longitude, c.accuracy, speed, p.timestamp || Date.now());
    if (S.fixes.length > 5000) S.fixes.splice(0, S.fixes.length - 5000);
    S.lastFixAt = Date.now();
    S.geoDenied = false;
    S.geo = 'ok (±' + Math.round(c.accuracy) + ' m)';
    hideGeoHelp();
  }

  function onGeoError(err) {
    if (err && err.code === 1) {            // PERMISSION_DENIED
      S.geoDenied = true;
      S.geo = 'error: location permission denied';
      showGeoHelp();
      return;
    }
    // POSITION_UNAVAILABLE / TIMEOUT: keep trying
    S.geo = 'searching (' + (err && err.message ? err.message : 'no fix yet') + ')';
    scheduleGeoRetry(3000);
  }

  function startGeo() {
    if (!('geolocation' in navigator)) { S.geo = 'error: not supported'; return; }
    if (S.watchId !== null) {
      try { navigator.geolocation.clearWatch(S.watchId); } catch (e) { /* ignore */ }
      S.watchId = null;
    }
    if (S.geo.indexOf('ok') !== 0) S.geo = 'searching';
    S.geoStartedAt = Date.now();
    // No timeout option: Safari then keeps waiting for a fix instead of failing.
    S.watchId = navigator.geolocation.watchPosition(onFix, onGeoError,
      { enableHighAccuracy: true, maximumAge: 0 });
  }

  function scheduleGeoRetry(ms) {
    if (S.geoRetry) return;
    S.geoRetry = setTimeout(function () { S.geoRetry = null; startGeo(); }, ms);
  }

  // Watchdog: if fixes stop (app was in background, tunnel, iOS paused it), restart.
  setInterval(function () {
    if (!S.started || S.geoDenied) return;
    var now = Date.now();
    var last = Math.max(S.lastFixAt, S.geoStartedAt);
    if (now - last > 30000) startGeo();
  }, 5000);

  function showGeoHelp() {
    if (document.getElementById('rally-geo-help')) return;
    var d = document.createElement('div');
    d.id = 'rally-geo-help';
    d.style.cssText = 'position:fixed;left:12px;right:12px;bottom:12px;z-index:9998;' +
      'background:#ff4d4d;color:#000;font:600 16px -apple-system,system-ui,sans-serif;' +
      'padding:14px 16px;border-radius:12px;line-height:1.35';
    d.innerHTML = '<b>Location is blocked.</b> On the iPhone: Settings → Privacy &amp; Security → ' +
      'Location Services → ON, then <b>Safari Websites</b> → <b>While Using the App</b> and ' +
      '<b>Precise Location</b> ON. Then close this app completely and open it again. (Tap to hide)';
    d.addEventListener('click', hideGeoHelp);
    document.body.appendChild(d);
  }

  function hideGeoHelp() {
    var d = document.getElementById('rally-geo-help');
    if (d && d.parentNode) d.parentNode.removeChild(d);
  }

  // --------------------------------------------------------- wake lock
  function requestWake() {
    if (!('wakeLock' in navigator)) { S.wake = 'unsupported - set Auto-Lock to Never'; return; }
    navigator.wakeLock.request('screen').then(function (lock) {
      S.wake = 'on';
      lock.addEventListener('release', function () { S.wake = 'off'; });
    }).catch(function () { S.wake = 'failed - set Auto-Lock to Never'; });
  }

  document.addEventListener('visibilitychange', function () {
    if (S.started && document.visibilityState === 'visible') {
      requestWake();
      if (!S.geoDenied) startGeo();   // iOS often stops GPS while in background
    }
  });

  // Keyboard-type Bluetooth remotes arrive as key presses.
  window.addEventListener('keydown', function (e) {
    if (e.repeat) return;
    S.keys.push(e.key || e.code || '');
    if (S.keys.length > 50) S.keys.shift();
  }, true);

  // ------------------------------------------------------------- start
  function start() {
    var overlay = document.getElementById('rally-start');
    // iPhone: the motion permission must be requested directly in the tap.
    var needsPermission = typeof DeviceMotionEvent !== 'undefined' &&
      typeof DeviceMotionEvent.requestPermission === 'function';
    var p = needsPermission ? DeviceMotionEvent.requestPermission() : null;
    // Start GPS inside the same tap so iOS shows the location prompt.
    startGeo();
    requestWake();
    S.started = true;

    function finish() {
      window.addEventListener('devicemotion', onMotion);
      if (overlay) overlay.style.display = 'none';
    }
    if (p) {
      p.then(function (r) {
        S.motion = r === 'granted' ? 'waiting for data' : 'denied';
        finish();
      }).catch(function (e) {
        S.motion = 'error: ' + (e && e.message ? e.message : e);
        finish();
      });
    } else {
      S.motion = 'waiting for data';
      finish();
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    var btn = document.getElementById('rally-start-btn');
    if (btn) btn.addEventListener('click', start);
    var overlay = document.getElementById('rally-start');
    if (overlay) {
      var v = document.createElement('p');
      v.textContent = 'version ' + VERSION;
      v.style.cssText = 'font-size:12px;opacity:0.6;margin-top:16px';
      overlay.appendChild(v);
    }
  });

  // ------------------------------------------------- Flutter interface
  window.rallyGetMotion = function () {
    return [S.gx, S.gy, S.gyro[0], S.gyro[1], S.gyro[2], S.hasGyro ? 1 : 0, S.n];
  };
  window.rallyDrainFixes = function () { var f = S.fixes; S.fixes = []; return f; };
  window.rallyDrainKeys = function () { var k = S.keys; S.keys = []; return k; };
  window.rallyStatus = function () {
    return JSON.stringify({ motion: S.motion, geo: S.geo, wake: S.wake, started: S.started });
  };
  window.rallyLoad = function () {
    try { return localStorage.getItem(KEY) || ''; } catch (e) { return ''; }
  };
  window.rallySave = function (s) {
    try { localStorage.setItem(KEY, s); } catch (e) { /* ignore */ }
  };
})();
