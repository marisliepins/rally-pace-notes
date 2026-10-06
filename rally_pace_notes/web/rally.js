// Browser side of Rally Pace Notes: owns the sensor APIs and hands raw data
// to the Flutter app through a few window.rally* functions.
(function () {
  'use strict';

  var KEY = 'rally.settings.v1';
  var S = {
    gx: 0, gy: 0,
    gyro: [0, 0, 0],      // accumulated rotation in degrees (alpha, beta, gamma)
    hasGyro: false,
    n: 0, lastT: 0,
    fixes: [], keys: [],
    motion: 'not started', geo: 'not started', wake: 'off',
    started: false, watchId: null
  };

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

  function startGeo() {
    if (!('geolocation' in navigator)) { S.geo = 'unsupported'; return; }
    S.geo = 'searching';
    S.watchId = navigator.geolocation.watchPosition(function (p) {
      var c = p.coords;
      var speed = (typeof c.speed === 'number' && !isNaN(c.speed)) ? c.speed : -1;
      S.fixes.push(c.latitude, c.longitude, c.accuracy, speed, p.timestamp);
      if (S.fixes.length > 5000) S.fixes.splice(0, S.fixes.length - 5000);
      S.geo = 'ok';
    }, function (err) {
      S.geo = 'error: ' + err.message;
    }, { enableHighAccuracy: true, maximumAge: 0, timeout: 30000 });
  }

  function requestWake() {
    if (!('wakeLock' in navigator)) { S.wake = 'unsupported - set Auto-Lock to Never'; return; }
    navigator.wakeLock.request('screen').then(function (lock) {
      S.wake = 'on';
      lock.addEventListener('release', function () { S.wake = 'off'; });
    }).catch(function () { S.wake = 'failed - set Auto-Lock to Never'; });
  }

  document.addEventListener('visibilitychange', function () {
    if (S.started && document.visibilityState === 'visible') requestWake();
  });

  // Keyboard-type Bluetooth remotes arrive as key presses.
  window.addEventListener('keydown', function (e) {
    if (e.repeat) return;
    S.keys.push(e.key || e.code || '');
    if (S.keys.length > 50) S.keys.shift();
  }, true);

  function start() {
    var overlay = document.getElementById('rally-start');
    function finish() {
      window.addEventListener('devicemotion', onMotion);
      startGeo();
      S.started = true;
      if (overlay) overlay.style.display = 'none';
    }
    // iPhone: the motion permission must be requested directly in the tap.
    var needsPermission = typeof DeviceMotionEvent !== 'undefined' &&
      typeof DeviceMotionEvent.requestPermission === 'function';
    var p = needsPermission ? DeviceMotionEvent.requestPermission() : null;
    requestWake();
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
  });

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
