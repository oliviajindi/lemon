# Firebase Migration Plan

Where we left off on **Sunday, May 17, 2026**.

This is the plan for moving Lemon's AI calls from the on-device Gemini API key
(or the Cloudflare Worker proxy) to **Firebase AI Logic**, so the key never
ships with the app.

---

## TL;DR

| What | Why | Action |
| --- | --- | --- |
| Use Firebase AI Logic | iOS SDK calls Gemini through Firebase; no API key on device | Pick this over Cloud Functions / Genkit |
| Blaze billing | `gemini-2.5-flash-image` requires it | Upgrade if you want AI illustrations |
| App Check (App Attest) | Stops anyone-but-your-app from burning your quota | Enable, defer enforcement until tested |
| Skip Sign in with Apple for now | AI Logic doesn't require auth | Add later for Firestore sync |

---

## Why Firebase AI Logic and not Cloud Functions / Genkit

| Approach | Pros | Cons |
| --- | --- | --- |
| **Firebase AI Logic** (recommended) | No server code; Swift SDK talks to Firebase, Firebase talks to Gemini; App Check covers anti-abuse | Requires Blaze for `gemini-2.5-flash-image` |
| Cloud Functions proxy | Total control of routing/logging | You'd write and deploy code — same shape as the existing Cloudflare Worker |
| Genkit on Cloud Run | Useful if we need server-side orchestration | Overkill — Gemini already does everything we need in one call |

Stick with AI Logic. Firestore sync + Sign in with Apple can be a second pass;
this first pass is purely "get the key off the device".

---

## Step-by-step: what to do in Firebase (~10–15 min)

### 1. Create the project + register the iOS app

1. Open the [Firebase Console](https://console.firebase.google.com) → **Create project** (or reuse one). Name it whatever, e.g. `lemon-app`.
2. Inside the project, click the **iOS+** icon → **Add app**.
   - **Bundle ID:** `com.lemonowo.app` — this must match the Xcode project's `PRODUCT_BUNDLE_IDENTIFIER` character-for-character (see `Scripts/generate_xcodeproj.rb`).
   - **App nickname:** `Lemon` (anything).
   - **App Store ID:** leave blank.
3. Click **Register app**. **Download `GoogleService-Info.plist`.** Do **not** tap through the "Add Firebase SDK / Initialization code / Run your app" pages — the assistant handles those from the code side. Just **Continue to console**.

### 2. Enable AI Logic + Gemini

1. Sidebar → **Build → AI Logic** (may still be labeled "Vertex AI in Firebase" until the rename rolls through).
2. Click **Get started**.
3. Provider: choose **Gemini Developer API** (the other option is Vertex AI Gemini — strictly enterprise, not needed).
4. Click **Enable APIs**. Firebase will turn on the Generative Language API automatically.

### 3. Switch to Blaze billing (only if you want AI illustrations)

- `gemini-2.5-flash-image` (the hand-drawn illustration model) requires **Blaze pay-as-you-go**. Text identification and recipe OCR work on the free Spark plan; only the illustration step needs Blaze.
- Project settings → **Usage and billing → Modify plan → Blaze**.
- Set a budget alert at e.g. `$5/month` — image gen is roughly `$0.039` per image (~25 illustrations per dollar at current pricing), so a small budget goes a long way.

If you skip Blaze for now, the app will fall back to the SF Symbol placeholder
for illustrations until you upgrade.

### 4. Turn on App Check

1. Sidebar → **Build → App Check** → click the Lemon iOS app.
2. **Provider:** App Attest (Apple's hardware attestation; the right choice for iOS).
3. **Token TTL:** leave at 1 hour.
4. **Enforcement:** leave **OFF** for AI Logic for now. Flip it to **Enforce** *after* you've verified the app works end-to-end (otherwise a misconfigured client will silently fail).
5. In Xcode: **Signing & Capabilities → + Capability → App Attest**. The assistant will wire the SDK side, but this capability has to live on the bundle in your provisioning profile.

### 5. (Optional now) Sign in with Apple

Only needed when you want per-user Firestore sync. **Skip for this pass.** AI Logic does not require auth as long as App Check is on. Pick this up next time alongside Firestore.

---

## What to hand off to the assistant tomorrow

Drop these in chat (the assistant will find files on disk):

1. **`GoogleService-Info.plist`** from step 1.3, saved at:
   ```
   /Users/oliviajin/Documents/AIMenu/Lemon/GoogleService-Info.plist
   ```
   Don't paste the contents — just save the file and mention it.
2. **Firebase Project ID** (you'll find it as `PROJECT_ID` near the top of the plist, also in the console URL). The assistant will sanity-check it matches the file.
3. **Billing status**, one of:
   - "I enabled Blaze" → assistant keeps `gemini-2.5-flash-image` for illustrations.
   - "Still on Spark / no billing yet" → assistant disables image gen and uses the placeholder until upgraded.
4. **App Attest capability status**, one of:
   - "Added in Xcode" → assistant initializes App Check at launch.
   - "Not added yet" → assistant still writes the code, you'll see warnings until the capability is enabled.

---

## What the assistant will do once you've sent those

(Listed so you know what's coming — no action needed from you.)

1. Add Firebase SPM packages: `firebase-ios-sdk` → products `FirebaseCore`, `FirebaseAI`, `FirebaseAppCheck`.
2. Drop `GoogleService-Info.plist` into the project and register it in `Scripts/generate_xcodeproj.rb` so future regenerations include it.
3. In `LemonApp.swift`, configure Firebase at launch and install the App Attest App Check provider.
4. Replace the body of `Services/GeminiService.swift` with `FirebaseAI.firebaseAI(backend: .googleAI())`:
   - `identifyDishes` → text + optional image part via `generateContent(...)`.
   - `extractRecipe` → vision call with image part.
   - `generateIllustration` → image-capable model.
   - Public actor surface (`identifyDishes`, `generateIllustration`, `extractRecipe`) stays the same → no other file changes.
5. Retire `AppConfig.useProxy / proxyURL / proxySecret / geminiAPIKey` from `SettingsView` (key field becomes a read-only "Backed by Firebase" indicator).
6. Update README + add a `TODO.md` entry: next step is Sign in with Apple + Firestore sync.

---

## Caveats / gotchas

- **Bundle ID is forever.** If `com.lemonowo.app` isn't what you want long-term (e.g. you'd prefer `dev.olivia.lemon`), change `BUNDLE_ID` in `Scripts/generate_xcodeproj.rb` and regenerate the project **before** registering with Firebase. Otherwise the `GoogleService-Info.plist` is locked to the wrong ID and Firebase rejects calls from the app.
- **Existing dishes stay local.** This change only moves the AI key off the device. Your SwiftData (dishes, photos, today entries, calendar) stays on the phone. Cross-device sync = next step (Auth + Firestore), opt-in.
- **Don't paste the Gemini API key anywhere.** If you previously had one in `AppConfig`, the assistant will remove the field; you don't need to share it.
- **`.gitignore`.** `GoogleService-Info.plist` contains the Firebase project's *client* API key. Not secret in the classic sense (App Check is what protects your quota), but if your repo is public you may want to gitignore it and document how teammates regenerate. The assistant will add a note in the README.

---

## Quick checklist (print/screenshot if useful)

- [ ] Firebase project created (or reused)
- [ ] iOS app registered with bundle ID `com.lemonowo.app`
- [ ] `GoogleService-Info.plist` downloaded and saved into `Lemon/` (project root: `…/AIMenu/Lemon/`)
- [ ] AI Logic enabled with **Gemini Developer API** provider
- [ ] Blaze enabled (or accepted: no image gen until upgrade)
- [ ] App Check provider set to **App Attest** (enforcement OFF for now)
- [ ] App Attest capability added in Xcode (or accepted: warnings until added)
- [ ] Ready to message the assistant with project ID + billing/App Attest status
