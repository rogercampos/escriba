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

Strings are discovered at runtime: each one appears in the admin UI the first
time the host app renders it in production. Visit `/escriba` to translate
discovered strings into other locales. Translations become effective on the
next deploy.

## Mental model

There are two locale concepts:

1. **`dev_locale`** (defaults to `:en`) — the locale whose strings live inside
   the source code. In development and test this is short-circuited: Escriba
   returns the source string directly without touching the database. In
   production, the first access to a string seeds a `dev_locale` row in the
   database with the source copy.

2. **All other locales** — read from the database. Missing entries fall through
   Rails' normal I18n fallback chain, which lands on the `dev_locale` — by
   default that's the `dev_locale` row in the DB (seeded on first access from
   the source string), or with `dev_locale_from_code = true` it's the source
   string in code directly. Either way, an untranslated Spanish page in
   production shows English copy that ultimately originated in the source.

### Environment behavior

| Environment | Locale | Behavior |
|---|---|---|
| dev / test | == `dev_locale` | Return source from code. No DB, no cache. |
| dev / test | != `dev_locale` | Cache → DB → fallback chain (lands on source). On miss seeds `dev_locale` row. |
| production (default) | == `dev_locale` | Cache → DB. On miss inserts source as value, returns source. |
| production (default) | != `dev_locale` | Cache → DB. On miss seeds `dev_locale` row, returns nil → fallback chain. |
| production, `dev_locale_from_code = true` | == `dev_locale` | Return source from code. No DB, no cache. |
| production, `dev_locale_from_code = true` | != `dev_locale` | Cache → DB. On miss seeds `dev_locale` row, returns nil → fallback chain (lands on source). |

### Two modes for the dev_locale

Some teams want the `dev_locale` (e.g. `en`) editable in the admin UI like any
other locale — content writers iterate on copy without a deploy. Other teams
want copy changes to flow through pull requests so source code is the single
source of truth.

Set `config.dev_locale_from_code = true` to opt into the second mode. With it
on, the `dev_locale` always reads from source code regardless of environment —
just like dev/test does by default. The admin UI hides the `dev_locale` from
the editable tabs and refuses direct edit attempts. Discovery still works:
when a non-dev locale request misses in the DB, a `dev_locale` row is still
seeded so translators can see what strings exist.

| `dev_locale_from_code` | What changes |
|---|---|
| `false` (default) | `dev_locale` rows are editable in the admin UI; runtime reads them from the DB in production. |
| `true` | `dev_locale` always served from source code; admin UI shows the source as read-only. |

### Caching and refresh

Translations are read once per process and held in a never-evicted in-memory
cache. Edits in the admin UI persist to the database but do not invalidate
caches in running processes — **they become effective on the next deploy**.
The admin UI displays this as a banner.

This is a deliberate trade-off: it removes the need for cache invalidation
plumbing (pub/sub, polling, version stamps) at the cost of translator latency.
For most apps, translations change rarely; deploys are the natural refresh
point.

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
  most recently discovered strings, and the translations staged for the next
  deploy.
- **Translations** — a per-locale workspace: the list of known strings with
  their values for the selected locale, a source-copy search, and `All /
  Missing / Issues` filters (with counts). Each value carries lint badges.
- **Per-key view** — the source copy, meaning, interpolation variables, and the
  value (plus lint badges) in every available locale.
- **Edit form** per `(key, locale)` pair — singular gets a textarea, plural one
  field per CLDR plural form, with source copy/meaning as read-only context.
  `Save & next missing` jumps straight to the next untranslated string in the
  locale for fast burn-down.
- **Issues** — quality problems with existing translations across all locales:
  broken/unknown interpolations, missing required plural forms, and values
  identical to the source (looks untranslated).
- **Import / Export** — placeholder for bulk file workflows (not wired up yet).

Edits do not invalidate running processes; the UI shows a banner explaining
that changes go live on the next deploy.

### Lint checks

Translations are linted against the source string using only stored data
(interpolation shape, plural flag, source copy) — see
`Escriba::TranslationValidator`. It flags unknown interpolation variables
(absent from the source), missing variables (singular only — the `one` plural
form may legitimately drop `%{count}`), a missing required `other` plural form,
and values identical to the source. It deliberately does not compute the full
set of CLDR plural categories a locale requires.

## Not supported (by design, for now)

- **Static extraction.** Strings are discovered at runtime — they appear in the
  admin UI after the host app calls `E18n.t(...)` for that string at least
  once. Static extraction (parsing Ruby + ERB to find all `E18n.t` calls
  upfront) is a planned future addition.
- **Orphan detection.** Strings whose source was deleted or edited stay in the
  database as orphans. This will be visualized in the admin UI once static
  extraction lands.
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
