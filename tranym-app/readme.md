# Tranym Android app

Tranym packages Photon inside the ZKPassport React Native app. Photon builds its login query offline, without opening the normal Obsidion bridge, and exchanges the request and proof directly through the local Android WebView bridge. That exchange does not use QR codes, Obsidion, a WebSocket, or a local network service. Photon still contacts its configured backend to obtain a nonce and submit the proof for login.

## Android test run

1. Install the dependencies for `photon` and `mobile-app`.
2. Start an Android emulator. The script uses `10.0.2.2` by default, which maps to the development computer's loopback interface from the Android emulator.
3. From the repository root, run:

   ```powershell
   .\tranym-app\run-android.ps1
   ```

   For a physical Android device, pass backend and instance URLs reachable from that device. The backend must publish port `1236` on the host and allow the WebView's local file origin to call the two existing passport authentication endpoints.
4. The wrapper opens Photon automatically. Add a passport from the **Passport app** screen if needed, then open the login page. Photon sends the request to the native mobile app, which opens the existing approval flow directly. Photon receives the proof and sends the existing login request to the backend.

The script builds Photon with SvelteKit's static adapter, copies its output into Android app assets, installs the mobile app dependencies, and launches the Android app. The `mobile-app/app.config.js` file supplies Tranym's Android package identity while leaving the upstream `app.json` values intact.

The existing standalone mobile app QR/Obsidion flow remains available through the original app entry point.
