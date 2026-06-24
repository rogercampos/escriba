# Escriba

Translations for Rails — without translation keys.

```ruby
E18n.t("Save", meaning: "to store")
E18n.t("Hello %{name}", name: current_user.name)
E18n.t(one: "1 item", other: "%{count} items", count: items.size)
```

You write real copy directly in source code. Escriba derives a stable hash from
that copy (plus an optional `meaning:` to disambiguate short ambiguous strings,
plus the shape of any interpolations) and uses the hash as the I18n key under
the hood. Translations live in a database table, edited through a Rails engine
admin UI mounted in your host app.

Underneath it's still Rails I18n: pluralization rules, interpolation, fallback
chains, and YAML translations all keep working untouched.

> **Status:** alpha (`0.1.0`). The public API may change before `1.0`.

## Why

Translation keys are an indirection nobody asked for. `t("users.show.profile.edit_button")`
forces every developer to invent a name, agree on a hierarchy, and then keep
that hierarchy in sync with what the UI actually says. The English copy is
written somewhere far from the code that displays it — usually in
`config/locales/en.yml` — and the two drift over time.

Escriba flips the relationship. Source code is the source of truth for the
"dev locale" (English by default). Translators don't translate keys; they
translate real strings, with a `meaning:` hint when context isn't obvious from
the string alone.

## Installation

Requirements: Ruby ≥ 3.1, Rails ≥ 7.0.

Add to your `Gemfile`:

```ruby
gem "escriba"
```

Then:

```sh
bundle install
bin/rails generate escriba:install
bin/rails db:migrate
```

Mount the engine in `config/routes.rb`:

```ruby
mount Escriba::Engine => "/escriba"
```

Outside development and test, Rails will refuse to boot until you configure an
authentication hook in `config/initializers/escriba.rb`:

```ruby
Escriba.configure do |config|
  config.authenticate_with = ->(controller) do
    controller.head :forbidden unless controller.current_user&.admin?
  end
end
```

The callable runs as a standard Rails `before_action` in the engine's
controllers and receives the controller instance; halt the request by
rendering or redirecting from it.

## Quick start

Replace `t("save_button")` with `E18n.t("Save")`. That is the whole API for the
singular case. `E18n.t` works anywhere `I18n.t` works — views, controllers,
mailers, jobs, POROs.

```erb
<h1><%= E18n.t("Welcome back, %{name}", name: current_user.name) %></h1>
<%= submit_tag E18n.t("Save", meaning: "to store") %>
<p><%= E18n.t(one: "1 item", other: "%{count} items", count: cart.size) %></p>
```

Strings are discovered by static extraction: `escriba:dump_yml` scans the
source for `E18n.t` calls and `escriba:import_yml` loads them into the catalog
at deploy time (see [Shipping copies in a PR](#shipping-copies-in-a-pr-yaml-dumps)).
The lookup path itself is read-only — rendering a page never writes. Visit
`/escriba` to translate the catalog into other locales. Translations become
effective on the next deploy.

## Mental model

There are two locale concepts:

1. **`dev_locale`** (defaults to `:en`) — the locale whose strings live inside
   the source code. In development and test this is short-circuited: Escriba
   returns the source string directly without touching the database. In
   production it reads the `dev_locale` row from the database (seeded at deploy
   by `escriba:import_yml`), and if none exists yet serves the source copy from
   code as a fallback — the lookup never writes.

2. **All other locales** — read from the database first; on a DB miss the
   dumped `config/locales/escriba.<locale>.yml` files are consulted (see
   [Shipping copies in a PR](#shipping-copies-in-a-pr-yaml-dumps)), so copies
   shipped with a deploy are live before anyone touches the admin UI. Entries
   missing in both fall through Rails' normal I18n fallback chain, which lands
   on the `dev_locale` — the `dev_locale` row in the DB, or the source string
   in code when there's no row (or always, with `dev_locale_from_code = true`).
   Either way, an untranslated Spanish page in production shows English copy
   that ultimately originated in the source.

### Environment behavior

| Environment | Locale | Behavior |
|---|---|---|
| dev / test | == `dev_locale` | Return source from code. No DB, no cache. |
| dev / test | != `dev_locale` | Cache → DB → fallback chain (lands on source). No write. |
| production (default) | == `dev_locale` | Cache → DB. On miss returns source from code. No write. |
| production (default) | != `dev_locale` | Cache → DB. On miss returns nil → fallback chain (lands on source). No write. |
| production, `dev_locale_from_code = true` | == `dev_locale` | Return source from code. No DB, no cache. |
| production, `dev_locale_from_code = true` | != `dev_locale` | Cache → DB. On miss returns nil → fallback chain (lands on source). No write. |

### Two modes for the dev_locale

Some teams want the `dev_locale` (e.g. `en`) editable in the admin UI like any
other locale — content writers iterate on copy without a deploy. Other teams
want copy changes to flow through pull requests so source code is the single
source of truth.

Set `config.dev_locale_from_code = true` to opt into the second mode. With it
on, the `dev_locale` always reads from source code regardless of environment —
just like dev/test does by default. The admin UI hides the `dev_locale` from
the editable tabs and refuses direct edit attempts. The catalog translators
work from is populated the same way in either mode: by static extraction at
deploy time, independent of this setting.

| `dev_locale_from_code` | What changes |
|---|---|
| `false` (default) | `dev_locale` rows are editable in the admin UI; production reads them from the DB. |
| `true` | `dev_locale` always served from source code; admin UI shows the source as read-only. |

### Caching and refresh

Translations are read once per process and held in a never-evicted in-memory
cache. Edits in the admin UI persist to the database but do not invalidate
caches in running processes — **they become effective on the next deploy**.

This is a deliberate trade-off: it removes the need for cache invalidation
plumbing (pub/sub, polling, version stamps) at the cost of translator latency.
For most apps, translations change rarely; deploys are the natural refresh
point.

The admin UI makes this state visible: values edited after the last publish
carry a **pending deploy** badge, the dashboard counts them, and the footer
reports when the last publish happened. "Last publish" is the process' boot
time — the moment its cache started filling, which under Kamal (and most
deploy tools) coincides with the last deploy.

To ship a feature with its translations already in place — instead of
deploying, translating in production, and waiting for the *next* deploy — see
[Shipping copies in a PR](#shipping-copies-in-a-pr-yaml-dumps) below.

## Shipping copies in a PR (YAML dumps)

There are two ways translations reach production, and they complement each
other:

- **Translate in production** (the default flow): deploy the feature, see
  dev-locale copy everywhere, translate in the admin UI, and the values become
  visible on the *next* deploy. Zero developer ceremony, but the first deploy
  ships untranslated.
- **Translate in the PR** (this flow): the PR carries the code, the new copies
  in views, *and* their translations for every language — everything is live
  right after the deploy that ships the feature.

### The developer workflow

Say you're building a feature with new copy in views:

```erb
<h1><%= E18n.t("Your order is on its way") %></h1>
<p><%= E18n.t(one: "1 item", other: "%{count} items", count: @items.size) %></p>
```

1. **Write the feature** as usual — new `E18n.t` calls in views, helpers,
   mailers, anywhere. You don't need to run any of it.

2. **Run the dump**:

   ```sh
   bin/rails escriba:dump_yml
   ```

   This regenerates `config/locales/escriba.<locale>.yml` — one file per
   supported locale (only `escriba.*.yml` files are touched; other locale
   files are left alone). The catalog comes from the database **plus static
   extraction**: the source tree (`app/`, `lib/`, including `.erb` views) is
   parsed with Prism for `E18n.t` calls, so your brand-new strings appear in
   every locale file even though they have never executed. New entries are
   blank, annotated with the source copy as a comment:

   ```yaml
   es:
     escriba:
       # Your order is on its way
       7c9e1b2a8f3d4e5f: ''
       # one: 1 item · other: %{count} items
       3f2a9c8b1d7e6a4b:
         one: ''
         other: ''
   ```

   Regenerating is lossless: every entry keeps its value from your local
   database or, when your local DB doesn't have it (it usually doesn't have
   what teammates translated), from the committed files themselves. You can
   re-run the task as often as you like.

3. **Fill in the blanks** for your new strings in each locale file — by hand,
   or paste the file into your favorite LLM (the source-copy comments give it
   everything it needs).

4. **Commit code and locale files together.** Reviewers see the new copy and
   its translations side by side in the diff.

5. **Merge and deploy.** The copies are live in all languages immediately:
   at runtime the backend reads the database first and falls back to these
   files for values the database doesn't have yet. With the deploy-time
   import below, they also land in the database so the admin UI reflects
   them.

Notes:

- Blank entries count as missing — they are never served; the normal locale
  fallback chain applies (users see the dev-locale copy until someone fills
  the value, in the file or in the admin UI).
- The database always wins over the files, so anything translators changed in
  the admin UI is unaffected by whatever the files say.
- Calls whose copy isn't a literal string can't be extracted statically; the
  task lists them so you can exercise those code paths once instead.
- When `dev_locale_from_code` is enabled no file is generated for the dev
  locale — that locale is always served from source code.

### Importing on deploy

The files work as a live fallback with zero setup, but importing them into
the database at deploy time keeps the admin UI consistent (completeness,
Missing filter, lint issues all reflect what production serves):

```sh
bin/rails escriba:import_yml
```

The import seeds the dev-locale catalog from static extraction (so brand-new
strings exist in the admin UI right at deploy), then fills in values the
database has blank. It never overwrites — an edit made in the admin UI always
wins over the files — skips blank entries, rejects values with error-level
lint issues, and is idempotent, so it is safe to run on every boot.

With Kamal, run it from a `pre-app-boot` hook. Kamal executes hooks from your
repo's `.kamal/hooks/` directory on the machine running the deploy, so a gem
cannot register one automatically — add it yourself:

```sh
#!/bin/sh
# .kamal/hooks/pre-app-boot (chmod +x)
kamal app exec --version "$KAMAL_VERSION" "bin/rails escriba:import_yml"
```

The hook runs after the new image is pulled and before the new containers
boot, once per boot group (re-running is fine — the task is idempotent).
Alternatively, call `bin/rails escriba:import_yml` from `bin/docker-entrypoint`
next to `db:prepare`, which needs no hook at all.

## API

### Singular

```ruby
E18n.t(copy, meaning: nil, **interpolation_values)
```

- `copy` — the source string. Required.
- `meaning:` — optional disambiguation hint. Two calls with the same `copy` but
  different `meaning:` produce different keys (e.g. `"Save"` as in "store" vs.
  "Save" as in "rescue").
- Any other keyword arguments are forwarded to I18n as interpolation values.

### Plural

```ruby
E18n.t(zero: "...", one: "...", two: "...", few: "...", many: "...", other: "...",
       count: n, meaning: nil, **interpolation_values)
```

- At least `other:` and `count:` are required.
- Other CLDR plural forms (`zero`, `one`, `two`, `few`, `many`) are optional.
  English source typically supplies `one` and `other`; translators fill in
  whatever extra forms their target locale needs (Russian needs `one/few/many/other`,
  Arabic uses all six).
- No positional argument — passing one alongside plural forms is a programmer
  error.

### Errors

`Escriba::ArgumentError` is raised for malformed calls: missing copy in the
singular case, missing `count:` or `other:` in the plural case, or a positional
argument mixed with plural forms.

## Key derivation

The I18n key is a SHA-256 hash, truncated to 16 hex characters, of a canonical
form of the call. Before hashing:

1. **Whitespace is normalized** — leading/trailing whitespace stripped; internal
   runs (including newlines and tabs) collapsed to a single space.
2. **Interpolation variable names are ordinalized** — `%{name}` is replaced by
   `%{1}`, `%{count}` by `%{2}`, and so on, in left-to-right order of first
   appearance. Renaming `%{name}` to `%{user_name}` does *not* change the key,
   but adding or removing an interpolation does.
3. **For plurals**, the canonical form is the sorted hash of plural forms;
   key order at the call site doesn't matter.
4. **`meaning:` is part of the hash** and is also stored on the row for the
   translator UI.

Editing the source copy (typo fix, rewording) produces a new key and orphans
the old translations. This is deliberate — see "Not supported" below.

## Configuration

```ruby
Escriba.configure do |config|
  config.dev_locale = :en               # locale represented by source code
  config.dev_locale_from_code = false   # true = dev_locale always from code, not DB
  config.authenticate_with = ->(c) { } # required outside dev/test
  config.available_locales = %i[en es]  # defaults to I18n.available_locales
end
```

Hardcoded (not configurable): the hash is always SHA-256 truncated to 16 hex
characters; the table is always `escriba_translations`.

## Styling (Tailwind CSS)

The admin UI is styled with [Tailwind CSS v4](https://tailwindcss.com). Escriba
does **not** ship compiled CSS — it plugs into your app's existing Tailwind
build. This keeps the gem's footprint tiny and lets the UI inherit your own
Tailwind version. The assumption is that the host app uses
[`tailwindcss-rails`](https://github.com/rails/tailwindcss-rails) `~> 4.0` (what
you get from `rails new --css tailwind`). It is an implicit requirement of the
admin UI, not of the `E18n.t` runtime — translations work with or without it.

The gem ships a Tailwind entry point at
`app/assets/tailwind/escriba/engine.css` that registers its own view templates
as Tailwind [`@source`s](https://tailwindcss.com/docs/detecting-classes-in-source-files).
`tailwindcss-rails`' (experimental) engine support detects it and auto-generates
`app/assets/builds/tailwind/escriba.css` on the next build/watch. You opt in
with a single line in your `app/assets/tailwind/application.css`:

```css
@import "tailwindcss";
@import "../builds/tailwind/escriba";   /* <- add this */
```

That's the entire integration. The gem "subscribes" its own templates to your
Tailwind build — so the utility classes the admin UI uses survive the
production purge — and you never reference the gem's internal paths. The
standalone admin layout pulls in the compiled stylesheet via
`stylesheet_link_tag :app`, the Rails 8 default bundle.

If your app doesn't use Tailwind (or uses a non-`tailwindcss-rails` toolchain),
the admin UI still renders and functions — just unstyled. To style it, point a
Tailwind `@source` at the installed escriba gem's `app/views` directory.

## Admin UI

Mounted at whatever path you chose (the install generator suggests `/escriba`).
Styled with Tailwind (see above). The pages:

- **Dashboard** — per-locale completeness (translated / total, missing), the
  most recently added strings, a lint-issue summary by type, and the
  count of edits pending the next deploy.
- **Translations** — a per-locale workspace: the paginated list of known
  strings with their values for the selected locale, a source-copy search, and
  `All / Missing / Issues` filters (with counts). Each value carries lint
  badges and a "pending deploy" badge when edited after the last publish.
- **Per-key view** — the source copy, meaning, interpolation variables, and the
  value (plus lint badges) in every available locale.
- **Edit form** per `(key, locale)` pair — singular gets a textarea, plural one
  field per CLDR plural form, with source copy/meaning as read-only context.
  `Save & next missing` jumps straight to the next untranslated string in the
  locale for fast burn-down.
- **Issues** — quality problems with existing translations across all locales:
  broken/unknown interpolations and missing required plural forms. Strings that
  haven't been translated yet are not listed here — that's a provenance fact (no
  value supplied), surfaced per-locale by the **Missing** filter.
- **Import / Export** — CSV export (one locale or all), CSV import with a
  dry-run preview, and an LLM-assisted bulk-translation flow (generate a
  prompt with the missing strings, paste the JSON answer back, review, apply).

Edits do not invalidate running processes; the footer reports the last publish
and rows edited since carry a "pending deploy" badge.

### Lint checks

Translations are linted against the source string using only stored data
(interpolation shape, plural flag, source copy) — see
`Escriba::TranslationValidator`. It flags unknown interpolation variables
(absent from the source), missing variables (singular only — the `one` plural
form may legitimately drop `%{count}`), and a missing required `other` plural
form. It deliberately does not compute the full set of CLDR plural categories a
locale requires.

It does **not** flag a value that is byte-identical to its source copy. That is
undecidable from the string alone — a legitimate cognate, brand or acronym
(`DNS`, `SEO`, `Avatar`, `Plan`) looks exactly like a value nobody translated —
so equality produced only false positives. Whether a translation is still
pending is a provenance question (was a value ever supplied?), tracked
accurately as "missing" (no row, or `value IS NULL`) and surfaced by the
per-locale **Missing** filter, not guessed from string content.

After upgrading from a version that cached the old `untranslated` lint, run
`rake escriba:relint` once to drop those stale entries from the `issues` column
(it rewrites only the cache, leaving `updated_at` untouched).

Lint results are computed when a row is saved and cached in its `issues`
column (every validation input lives on the row, so only value changes
matter). The Issues page, the dashboard summary and the `Issues` filter are
plain indexed SQL over that column — no re-validation per request.

## Not supported (by design, for now)

- **Static extraction of dynamic copy.** Static extraction powers
  `escriba:dump_yml` / `escriba:import_yml` (see
  [Shipping copies in a PR](#shipping-copies-in-a-pr-yaml-dumps)) and is the
  only way strings enter the catalog, but it can only resolve literal strings.
  Calls whose copy or `meaning:` is built at runtime never enter the catalog —
  they still render via the source fallback, but won't appear in the admin UI.
  The tasks list them so you know what extraction couldn't see.
- **Orphan detection.** Strings whose source was deleted or edited stay in the
  database as orphans. The extractor provides the raw material to flag them,
  but the admin UI doesn't visualize it yet.
- **Mid-process cache invalidation.** Refresh happens on deploy. This is a
  deliberate simplification.
- **HTML safety / `_html` suffix conventions.** HTML safety is the host
  template layer's responsibility.

## Repository layout

```
escriba/
├── gem/      The Rails engine gem.
└── dummy/    A Rails 8 app used for integration testing.
```

- `gem/lib/escriba/` — the gem's core (key derivation, cache, backend, API).
- `gem/app/` — the engine's controllers, views, helpers.
- `gem/config/routes.rb` — the engine's routes.
- `gem/lib/generators/escriba/install/` — the install generator.
- `gem/test/` — Minitest unit tests.
- `dummy/` — a Rails 8 host app with demo controllers exercising every code
  path of the gem.

## Development

```sh
cd gem
bundle install
bundle exec rake test
```

To run the dummy app:

```sh
cd dummy
bundle install
bin/rails db:prepare   # migrate + seed (seeds es/it/fr demo translations)
bin/dev                # runs the Rails server + Tailwind watch (Procfile.dev)
```

`bin/dev` defaults to port 3001. Visit `http://localhost:3001` for the demo
pages, or `http://localhost:3001/escriba` for the admin UI. (`bin/rails server`
also works but won't rebuild Tailwind on change.)

## License

MIT.
