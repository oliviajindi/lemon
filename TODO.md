# Lemon — TODO

Things we want to do later. Loosely ordered: bigger architectural threads first,
then features, then polish, then tech debt. Cross things off when shipped.

---

## 1. Bigger workstreams

### Firebase backend migration  *(paused)*
Replace the Cloudflare Worker proxy + the on-device Gemini key entirely with:
- [ ] Sign in with Apple (Firebase Auth)
- [ ] Cloud Functions that wrap `identifyDishes` / `generateIllustration` /
      `extractRecipe`, with the Gemini key stored only in functions config
- [ ] App Check (App Attest preferred — iOS 14+) so only our app on real
      devices can call those functions
- [ ] Firestore sync of menu, dishes, groups, recipes (offline-first via
      SwiftData, mirrored to Firestore when signed in)
- [ ] Cloud Storage for AI illustrations and the photo log blobs
- [ ] Tier scaffold on the user doc (`tier: "free" | "pro"`) + server-side
      daily-quota enforcement; StoreKit auto-renewable subscription wired up
      later when monetization is wanted

This is the biggest remaining shift. Will probably take ~1500 LOC across iOS
and Functions plus a one-time Firebase Console + Apple Developer setup. We
deferred it to keep velocity on the menu features (groups, recipes, photos).

### Search & filter
- [ ] Search by dish name / description / ingredient
- [ ] Filter by group (multi-select), by has-photo, by has-recipe
- [ ] Was in the original v1 scope, removed when we did the minimal v1.

---

## 2. Features

### AI helpers
- [ ] **AI-suggested recipe (no photo).** A second button in
      `RecipeEditorSheet` next to *Scan from photo* that asks Gemini to draft
      ingredients + steps from `dish.name` + `dish.dishDescription`. Wire
      through `GeminiService.suggestRecipe(name:description:)` returning the
      same `ExtractedRecipe` DTO.
- [ ] **Recipe scan via proxy.** Currently `extractRecipe` throws 501 when
      `useProxy == true`. Add `/api/extract-recipe` to the Cloudflare worker
      (or skip this entirely if Firebase lands first).

### Photo log
- [ ] **Camera capture** in addition to library pick. `PhotosPicker` is
      library-only — add a `UIImagePickerController` (or `.camera` source)
      path behind a small "Camera" / "Library" sheet so users can snap a
      photo of the dish they just cooked without leaving the app.
- [ ] **Share / export a photo.** Long-press a thumbnail → ShareLink to
      Messages / Photos. Also "Save to Photos" so the compressed JPEG can
      be exported back to the camera roll if the user wants it.

### Groups
- [ ] **Drag-to-reorder.** `DishStore.moveGroup(_:to:)` is already in place
      — wire up `.onMove` on the menu's group sections (or a dedicated
      "Manage groups" screen) so users can shuffle the printed-menu order.
- [ ] **SF Symbol picker.** Emoji is the primary logo; iconName is the
      fallback but has no UI to change. A small SF Symbol grid in
      `GroupEditorSheet` would close the loop for users who don't want an
      emoji.
- [ ] **Many-to-many membership.** Right now a dish lives in exactly one
      group. If we ever want "Lemon Risotto" to appear under both *Italian*
      and *Comfort food*, change `Dish.group` to `[DishGroup]` and update
      the menu render to dedupe per section.

### Dishes
- [ ] **Add a recipe inline during creation.** Currently `AddDishView`
      only captures name + photo + illustration; the recipe is opt-in
      afterward from the detail view. Could be a "Add recipe now?" toggle
      below the candidate card.
- [ ] **Bulk-select dishes** on the menu (long-press → multi-select) to
      move a batch into a group or delete them at once.
- [ ] **Servings + prep time + cook time** as small structured fields on
      `Dish`. Render under the recipe heading.

### Menu shell
- [ ] **Default masthead.** Currently defaults to "My Menu". Maybe should
      default to "Lemon" or be empty so the user fills it in on first
      launch. Minor copy decision.

---

## 3. Polish

- [ ] **Onboarding.** First-launch sheet that explains the Gemini key /
      proxy choice and links to the help docs.
- [ ] **Color-coded group accents.** Subtle paper-tint per group section
      so they're scannable at a glance.
- [ ] **Cleanup of stale collapsed-section IDs.** When a group is deleted,
      its UUID remains in `UserDefaults["Lemon.collapsedSectionIDs"]`
      forever. Harmless, but a 3-line cleanup in `deleteGroup` would be
      tidier.
- [ ] **Re-illustrate from detail view.** Add a small "Redraw" button on
      `DishDetailView` so users can regenerate the AI illustration if they
      don't like it.

---

## 4. Tech debt

- [ ] **Remove Cloudflare proxy** once Firebase Functions is doing the
      same job. The `Server/` folder, `proxy*` settings in `AppConfig`,
      and the proxy/direct toggle in `SettingsView` all go away. Keep
      just one path: signed-in → Firebase → Gemini.
- [ ] **Versioned SwiftData schema.** We've been relying on additive
      lightweight migrations as we add fields (`group`, `ingredients`,
      `steps`, `emoji`, `photos`). At some point we should declare a
      proper `VersionedSchema` and `SchemaMigrationPlan` so future
      breaking changes don't risk data loss.
- [ ] **GeminiService prompt unit tests.** Recipes from photos and dish
      identification both depend on JSON schemas — golden-output tests
      against captured Gemini responses would catch silent regressions
      if we change prompts.

---

## Done (for memory)

- Local-first SwiftData store with menu / dishes
- AI dish identification (text + photo, multi-dish from one photo)
- AI hand-drawn illustration (`gemini-2.5-flash-image`)
- Cloudflare Worker proxy (transitional — to be replaced by Firebase)
- Settings: proxy vs direct, illustration style
- Groups (one-to-many), section headers with collapse/expand,
  per-group emoji logo, edit / delete
- Two menu layouts: cards + compact list
- Editable menu title + subtitle
- Recipes: ingredients + steps, add / edit / delete / reorder
- Recipe scan from photo via Gemini vision
- Photo log per dish (multi-photo, captions, viewer + delete)
- Renamed to **Lemon** with hand-drawn lemon app icon
