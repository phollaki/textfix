# TextFix

TextFix is a Mac menu bar app that rewrites the selected text in any app.
Select text, press a shortcut, and TextFix replaces the selection with the result.
The app talks to a small backend that holds the OpenAI key, counts usage and checks App Store subscriptions.

| Shortcut (default) | Action |
|---|---|
| Control+Option+R | Rephrase |
| Control+Option+G | Fix grammar |
| Control+Option+T | Translate to the language set in the settings |

| Plan | Price | Limit |
|---|---|---|
| Free | $0 | 30 rewrites a month |
| Pro Monthly | $2.99 / month | 2,000 rewrites a month |
| Pro Yearly | $24.99 / year | 2,000 rewrites a month |

Other limits: 4,000 characters per text, 10 requests per minute per install, and a global monthly OpenAI budget (`MONTHLY_BUDGET_USD`).

## Repository

| Folder | Content |
|---|---|
| `app/` | Xcode project for the Mac app (sandboxed, StoreKit 2) |
| `server/` | Backend: Node 24, Fastify, zod, SQLite (`node:sqlite`) |
| `web/` | Landing page, privacy policy and support page |
| `.github/workflows/deploy.yml` | Tests the server and pushes both images to GHCR |

## Run locally

Start the backend with your own OpenAI key:

```sh
cd server
npm install
OPENAI_API_KEY=... APPLE_ENVIRONMENT=Xcode PORT=3999 npm run dev
npm test
```

Open `app/TextFix.xcodeproj` in Xcode and run the TextFix scheme.
The scheme uses `app/Products.storekit`, so test purchases work without App Store Connect.
To point a debug build at the local backend:

```sh
defaults write ~/Library/Containers/com.puteanihollakos.textfix/Data/Library/Preferences/com.puteanihollakos.textfix.plist apiURL http://localhost:3999
```

macOS only applies the Accessibility permission after the app restarts.
Use the "Restart TextFix" button in the settings after you turn it on.
With ad hoc signing, macOS drops the permission after each rebuild.
Sign with your Apple Development certificate to keep it.

The app icon comes from `app/icon.swift`:

```sh
swift app/icon.swift icon.png
```

## Deploy

The server runs at `textfix.puteanihollakos.com`.
Caddy sends `/api/*` to the `api` container and everything else to the `web` container.
The server config lives in `~/server-setup/srv/textfix` and `~/server-setup/srv/proxy/sites/textfix.caddy`.

First deploy: copy `srv/textfix/`, `srv/proxy/compose.yml` and `srv/proxy/sites/textfix.caddy` from `~/server-setup` to the server, then run:

```sh
cp /srv/textfix/.env.example /srv/textfix/.env
chmod 600 /srv/textfix/.env
docker compose -f /srv/proxy/compose.yml up -d
systemctl enable --now app-pull@textfix.timer
```

Fill in `OPENAI_API_KEY` in `/srv/textfix/.env`.
Set `APPLE_APP_ID` (the numeric Apple ID from App Store Connect) before the App Store release.
Without it, the server only accepts Sandbox purchases from TestFlight and App Review.

After that, every push to `main` that changes `server/` or `web/` builds new images, and the pull timer deploys them.

## App Store release

1. Create the app in App Store Connect with bundle ID `com.puteanihollakos.textfix`.
2. Create the subscription group "TextFix Pro" with `com.puteanihollakos.textfix.pro.monthly` ($2.99) and `com.puteanihollakos.textfix.pro.yearly` ($24.99).
3. Set your team in Xcode (Signing & Capabilities), then Product > Archive and upload.
4. Privacy URL: `https://textfix.puteanihollakos.com/privacy.html`. Support URL: `https://textfix.puteanihollakos.com/support.html`.
5. Review notes: TextFix uses Accessibility only to press Copy and Paste for the user after they press a TextFix shortcut.
