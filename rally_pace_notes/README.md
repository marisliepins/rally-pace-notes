# Rally Pace Notes — phone-sensor MVP

A quick test of the pace-notes idea using only the iPhone's own sensors, before the CAN-bus version.
Flutter code, running for now as a web app in iPhone Safari (no Mac or Apple developer account needed).
The same code can later be built as a native iPhone and Android app.

## What it does

- **Steering angle → corner grade.** The phone sits on the steering wheel. Gravity plus gyroscope give the wheel angle, updated live with no peak hold and no auto-reset. The angle maps to a grade such as `L3-` or `R4+`.
- **Configurable grade table**, stored on the phone. Defaults: 1 = 10°, 2 = 25°, 3 = 45°, 4 = 90°, 5 = 120°, 6 = 180°. A single switch selects 1→6 or 6→1 mode. "+" and "−" mark the zones between grades (±15% of each gap is the plain grade, editable). Left and right use the same values.
- **GPS distances.** The current segment is shown in metres and the total in km.
  - A **short tap** alternates STRAIGHT → CORNER → STRAIGHT…
  - Tap at the corner entry and the straight distance is stored. Tap at the exit and the corner length is stored and labelled plain, **LONG** (≥ 40 m) or **SUPER LONG** (≥ 60 m).
  - **Hold for 1.5 s** to reset everything.
- **Speed**, which can be switched off. Units switch between km/m/km/h and mi/yd/mph. The screen is dark and landscape, and is kept awake.
- **Bluetooth remotes that act as a keyboard** work already:
  - Space, Enter, → or ↓ = next segment.
  - ← ↑ Backspace or Esc = reset all.
  - Remotes that only send "volume up" will need the native app.

## Publish it (one time, about 10 minutes)

1. On GitHub, create a **new public repository**, for example `rally-pace-notes`.
2. Unzip this project. In the repository, choose **Add file → Upload files** and drag in **everything**, including the `.github` folder, then commit.
3. In the repository, go to **Settings → Pages → Build and deployment → Source** and choose **GitHub Actions**.
4. Open the **Actions** tab. If the first run failed (because Pages wasn't switched on yet), open it and choose **Re-run all jobs**. A run takes about 3 minutes.
5. Your app is at `https://<your-github-name>.github.io/rally-pace-notes/`.

Every later change you upload is rebuilt and republished automatically. If a build fails, open the failed run in **Actions** and copy the red error lines back to Claude.

## Use it on the iPhone

1. Open the link in **Safari**. Tap **Share → Add to Home Screen**, then open it from the home-screen icon (this gives full screen).
2. In Control Center, turn on **Portrait Orientation Lock**. The app draws its own landscape layout, so the picture doesn't flip as the wheel turns.
3. Fix the phone on the wheel with the wheel straight. Tap **TAP TO START** and allow **Motion & Orientation** and **Location**.
4. Press **ZERO** with the wheel straight. Turn left: it should show **L**. If it shows R, go to **Settings → Swap left / right**.
5. If the text reads upside down, go to **Settings → Landscape rotation → Rotate left**.
6. If the screen still dims, set **Settings → Display & Brightness → Auto-Lock → Never** on the iPhone while testing.

## Code map

| File | Purpose |
|---|---|
| `lib/grading.dart` | Angle → grade table (unit-tested) |
| `lib/steering.dart` | Gravity + gyro fusion; learns the gyro axis automatically (unit-tested) |
| `lib/trip.dart` | GPS distance with jitter/accuracy filtering, straight/corner segments (unit-tested) |
| `lib/app_controller.dart` | 50 Hz polling loop, taps, keys, settings persistence |
| `lib/ui/drive_screen.dart` | Main landscape screen |
| `lib/ui/settings_screen.dart` | Grade table, mode, thresholds, units, sensor options |
| `web/rally.js` | Browser sensor access (motion permission, GPS, wake lock, keys) |
| `.github/workflows/deploy.yml` | Runs tests, builds, publishes to GitHub Pages |

## Known limits of the web test version

- Expect about ±3–5 m GPS error per segment. Phone GPS updates about once per second.
- Strong cornering forces bias the gravity reading slightly. The gyroscope reduces this.
- Volume-key BLE remotes and a true orientation lock need the native app. That needs an Apple developer account, and either a Mac or a cloud build service.
