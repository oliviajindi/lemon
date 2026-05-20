# AI Menu — proxy server

A small Cloudflare Worker that holds the Gemini API key and proxies the two
calls the iOS app needs:

| Method | Path             | Purpose                                                       |
|--------|------------------|---------------------------------------------------------------|
| GET    | `/api/health`    | Liveness probe (no auth, used by the iOS Settings → Test)     |
| POST   | `/api/identify`  | `{ text?, imageBase64?, imageMimeType? }` → `{ dishes: […] }` |
| POST   | `/api/illustrate`| `{ name, description?, style?, aspectRatio?, artDirection? }` → image bytes  |

The Gemini key never leaves the Worker. The app authenticates with a
shared-secret header (`x-aimenu-secret`).

---

## One-time setup

1. **Install Node 18+** (e.g. via [nvm](https://github.com/nvm-sh/nvm) or
   `brew install node`).
2. From this `Server/` directory:
   ```bash
   npm install
   ```
3. Log into a (free) Cloudflare account:
   ```bash
   npx wrangler login
   ```
4. Set the two required secrets:
   ```bash
   npx wrangler secret put GEMINI_API_KEY        # paste your Google Gemini key
   npx wrangler secret put PROXY_SHARED_SECRET   # any random string; keep it
   ```
   A good way to generate a shared secret:
   ```bash
   openssl rand -base64 32
   ```

## Deploy

```bash
npx wrangler deploy
```

Wrangler prints a URL like `https://ai-menu-proxy.your-account.workers.dev`.

In the iOS app:

1. **Settings → AI Backend** → choose **Proxy server (recommended)**.
2. Paste the URL into **Proxy URL**.
3. Paste the same shared secret into **Shared secret**.
4. Tap **Test connection** — you should see *"OK — proxy reachable."*
5. Add a dish from the **Add** tab. The phone never touches Gemini directly.

## Local dev

```bash
cp .dev.vars.example .dev.vars     # never commit this file
# edit .dev.vars and fill in the two values
npm run dev
```

`wrangler dev` prints something like `http://localhost:8787`. Use that URL in
the app's Settings during development. (The simulator can reach `localhost`
out of the box; on a real iPhone, use your laptop's LAN IP and run wrangler
with `--ip 0.0.0.0`.)

## Logs

```bash
npx wrangler tail
```

Streams live logs from the deployed Worker. Auth failures, Gemini errors, and
internal exceptions all show up here.

## Updating the Gemini key

```bash
npx wrangler secret put GEMINI_API_KEY
```

No app rebuild required — the next request picks up the new value.

## Rotating the shared secret

```bash
npx wrangler secret put PROXY_SHARED_SECRET
```

Then update the value in **Settings → Shared secret** in every app instance.
Existing devices using the old secret will start getting `401 unauthorized`.

## Switching models

Open `wrangler.jsonc` and edit `GEMINI_TEXT_MODEL` / `GEMINI_IMAGE_MODEL`,
then `npx wrangler deploy`. Or set them as secrets to avoid touching the file.

---

## What this proxy is, and isn't

**It is** a way to keep the Gemini API key off user devices. The shared
secret is a *speed bump* against random scrapers — anyone who can read your
shipped iOS binary can extract the secret from `UserDefaults`. The bound on
abuse is one shared secret per build; rotate to invalidate.

**It is not** per-user authentication, billing, or fine-grained rate limiting.
Before publicly distributing the app, layer at least one of these on top:

- **App Attest** (`DCAppAttestService`) — proves the request comes from a
  legitimate, unmodified copy of *your* app on a real iPhone. Apple-native,
  no user account needed. Verify the assertion in the Worker before forwarding.
- **Sign in with Apple** + JWT — the user signs in, the Worker issues a JWT,
  and `/api/identify` and `/api/illustrate` require it. Lets you do per-user
  quotas and revoke abusers.
- **Cloudflare's [Rate Limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)
  binding** — drop-in per-IP throttle. Add to `wrangler.jsonc` and check
  before calling Gemini.
