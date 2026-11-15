# Tranym Android app

Tranym packages Photon for an Lemmy instance inside the ZKPassport React Native app. Photon builds its login query offline, without opening the Obsidion bridge of the original ZKP workflow, and exchanges the request and proof directly through the local Android WebView bridge. Photon contacts its configured backend to obtain a nonce before the verification and submit the proof for login after verification.

## Android test run

1. Install the dependencies for `photon` and `mobile-app`.
2. Connect you android device (or do nothing to automatically start an emulator).
3. From the repository root, run:

   ```powershell
   .\tranym-app\run-android.ps1
   ```

   For a physical Android device, pass backend and instance URLs reachable from that device. The backend must publish port `1236` on the host and allow the WebView's local file origin to call the two existing passport authentication endpoints.

4. The wrapper opens Photon automatically. Add a passport from the **Passport app** screen if needed, then open the login page and start the verification. Photon sends the request to the native mobile app, which opens the approval flow directly. Photon receives the proof and sends the existing login request to the backend.

## Notes and Config

The script reads `tranym-app/.env`. Set `PHOTON_MODE=dev` to start Photon with Vite hot reload and load it from the URL in `PHOTON_DEV_URL`; for the Android emulator, use `http://10.0.2.2:5173`. The server binds to `PHOTON_DEV_HOST` (default `0.0.0.0`) and `PHOTON_DEV_PORT` (default `5173`). The configured URL must point to the same server and be reachable from the Android device. Backend and instance URLs are passed to the Photon dev server from the script parameters.

Set `PHOTON_MODE=static` to build Photon with SvelteKit's static adapter and copy its output into Android app assets. The mode defaults to `static`. Both modes launch the Android app after preparing Photon. The `mobile-app/app.config.js` file supplies Tranym's Android package identity while leaving the upstream `app.json` values intact.

The existing standalone mobile app QR/Obsidion flow remains available through the original app entry point.
