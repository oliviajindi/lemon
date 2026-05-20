# Lemon

> A personal AI-illustrated menu — log every dish you cook or eat at home.

The Xcode project, target, and scheme are named **Lemon**. The app shows as **Lemon** on the Home Screen (`CFBundleDisplayName`). SwiftData still uses the on-disk store name `AIMenu` so existing installs keep their dishes after this rename.

A personal menu of every dish you cook or eat — *not* a feed.

**v1 is intentionally tiny:**

1. Type the dish name (or a quick description).
2. Gemini cleans up the name and draws a hand-drawn illustration of it.
3. You can tweak the name before saving.
4. It appears on your menu.

That's the whole flow. Photo/video input, recipes, ratings, sync, search — all parked for later versions.

---

## Stack

| Layer            | Choice                                                                |
|------------------|-----------------------------------------------------------------------|
| UI               | SwiftUI (iOS 17+), `Bradley Hand` + `Georgia` typefaces               |
| Local storage    | SwiftData                                                             |
| AI               | Google Gemini — `gemini-2.5-flash` (text) + `gemini-2.5-flash-image` (image) |
| AI transport     | Either direct from the device (with a key in Settings) or via a tiny Cloudflare Worker proxy in `Server/` that holds the key |

No external Swift packages. The iOS project opens, builds, and runs on a fresh Xcode install with nothing to resolve. The Worker is a separate `npm install` if you want to use it.

---

## Quick start

### 1. Open in Xcode

```bash
open ~/Documents/AIMenu/Lemon.xcodeproj
```

Pick an iOS 17+ simulator and hit ▶.

### 2. Pick how the app talks to Gemini

There are two ways. Pick one in **Settings → AI Backend**.

**A. Direct (key on device)** — fastest setup, fine for solo dev:
1. [Google AI Studio](https://aistudio.google.com) → **Get API key → Create API key**.
2. **Settings → AI Backend → Direct** → paste the key. Done.

The key lives only in this device's `UserDefaults`. Convenient for one user, **not safe to ship** — anyone with the binary can extract it.

**B. Proxy (key on a server you own)** — required if you'll share the app:
1. From `Server/` run `npm install`, then `npx wrangler login`.
2. Set the secrets:
   ```bash
   npx wrangler secret put GEMINI_API_KEY
   npx wrangler secret put PROXY_SHARED_SECRET   # any random string
   ```
3. `npx wrangler deploy` — copy the printed URL.
4. **Settings → AI Backend → Proxy** → paste the URL + the same shared secret.
5. Tap **Test connection**.

Now the Gemini key never touches the phone — the app only ever sees your proxy URL and the shared secret. See `Server/README.md` for full details and the path to per-user auth.

### 3. Add your first dish

- Tap the **Add** tab.
- Type something like `miso butter pasta with corn`.
- Tap **Draw it**. After a few seconds you'll see the illustration and a cleaned-up name like *Miso-Butter Corn Pasta*.
- Edit the name if you want. Tap **Add to menu**.
- Switch to **Menu** — it's there.

---

## Project layout

```
Lemon/                               # iOS app sources (Xcode project: Lemon.xcodeproj)
├── LemonApp.swift
├── Theme/Theme.swift                 # Paper + ink palette, sketch borders
├── Models/Models.swift               # Dish (SwiftData @Model) + AI DTO
├── Services/
│   ├── AppConfig.swift               # UserDefaults-backed settings (key, proxy, style)
│   ├── GeminiService.swift           # Routes calls direct-to-Gemini OR via proxy
│   └── DishStore.swift               # SwiftData facade + AI orchestration
└── Views/
    ├── RootView.swift                # TabView (Menu / Add / Settings)
    ├── MenuView.swift                # Printed-menu list of your dishes
    ├── DishCardView.swift            # Dish row with dotted leader + illustration
    ├── AddDishView.swift             # text + photo input, multi-dish preview
    ├── DishDetailView.swift          # Large illustration + name + delete
    └── SettingsView.swift            # Backend toggle, key/proxy fields, style

Server/                               # Cloudflare Worker (optional but recommended)
├── src/worker.ts                     # /api/identify, /api/illustrate, /api/health
├── wrangler.jsonc                    # Worker config
├── package.json                      # `npm install` then `npx wrangler deploy`
└── README.md                         # Full deploy guide
```

---

## Design notes

- **Menu, not feed.** Dishes lay out like a printed menu (name + dotted leader + illustration), sorted by recency but with no timestamps or social affordances on the home screen.
- **One AI round-trip per add.** First `gemini-2.5-flash` cleans the user's text into a 4-word name and a 12-word description. Then `gemini-2.5-flash-image` draws the dish using the description plus a style prompt you can edit in Settings. Both calls share the same `:generateContent` endpoint, so a single Gemini API key is enough.
- **Local-first.** Everything lives in SwiftData on-device. No accounts, no sync, no server.

---

## Next steps (not implemented yet)

- Photo and video input (add to `AddDishView` and `GeminiService`).
- Dedupe suggestions when adding a dish you've already logged.
- Per-occurrence logging (date / rating / notes / restaurant) so you can re-log the same dish multiple times.
- Tags, categories, and a way to organize the menu by section.
- Cloud sync (Supabase or CloudKit).
- Share a dish card as an image.
- Move API key from UserDefaults to Keychain before TestFlight.
