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
the hood. Translations live in one YAML file per locale,
`config/locales/escriba.<locale>.yml`, generated from the source code and
committed with it.

Underneath it's still Rails I18n: pluralization rules, interpolation, fallback
chains, and your other YAML translations all keep working untouched.

> **Status:** alpha (`0.2.0`). The public API may change before `1.0`.

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

Requirements: Ruby ≥ 4.0, Rails ≥ 8.1.

Add to your `Gemfile`:

```ruby
gem "escriba"
```

Then:

```sh
bundle install
bin/rails generate escriba:install   # config/initializers/escriba.rb
```

and add `bin/rails escriba:check` to your CI (see [Checking the catalog](#checking-the-catalog)).

## Quick start

Replace `t("save_button")` with `E18n.t("Save")`. That is the whole API for the
singular case. `E18n.t` works anywhere `I18n.t` works — views, controllers,
mailers, jobs, POROs.

```erb
<h1><%= E18n.t("Welcome back, %{name}", name: current_user.name) %></h1>
<%= submit_tag E18n.t("Save", meaning: "to store") %>
<p><%= E18n.t(one: "1 item", other: "%{count} items", count: cart.size) %></p>
```

Then write the files for the other locales, translate the blank entries, and
commit them with the code:

```sh
bin/rails escriba:dump_yml
```

## How it works

There are two kinds of locale:

1. **The `dev_locale`** (defaults to `:en`) — the locale of the copy written in
   the code. `E18n.t("Save")` in English returns `"Save"`, straight from the
   call site, in every environment. It has no file.

2. **Every other locale** — read from `config/locales/escriba.<locale>.yml`.
   Rails loads those files like any other locale file, so translations are in
   memory from boot and a lookup is a hash access. An entry that is blank (not
   translated yet) falls through Rails' I18n fallback chain, which lands on the
   `dev_locale`: an untranslated string on a Spanish page shows its English
   copy.

The files are the only source of translations: what is committed is what is
served, in development, in tests and in production alike. There is no
database table, no boot-time import and no admin UI. A translation changes the
way code does: in a commit, reviewed in a diff, live with the deploy that ships
it. Rolling back a deploy rolls back its translations too.

## The workflow

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

   This rewrites `config/locales/escriba.<locale>.yml`, one file per locale in
   `available_locales` except the dev locale (other locale files are left
   alone). The catalog comes from **static extraction**: the source tree
   (`app/`, `lib/`, including `.erb` views) is parsed with Prism for `E18n.t`
   calls, so brand-new strings appear even though they have never executed.
   New entries are blank, annotated with the source copy as a comment:

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

   Every existing entry keeps its value, and entries for strings no longer in
   the source are dropped. Run it as often as you like.

3. **Fill in the blanks** in each locale file — by hand, or hand the file to an
   LLM (the source-copy comments give it everything it needs).

4. **Commit code and locale files together.** Reviewers see the new copy and
   its translations side by side in the diff. `escriba:check` in CI verifies
   the files match the code.

5. **Merge and deploy.** The copies are live in every language.

To **change a translation**, edit its value in the file and commit. That's all:
nothing else holds a copy of it.

Editing the **English** copy changes the key (it is a hash of the copy), so the
next dump drops the old entry, translations included, and adds a blank one for
the new copy. For a typo fix, copy the old values onto the new entry before
committing.

## Checking the catalog

```sh
bin/rails escriba:check
```

Fails, listing every problem, when:

- an `E18n.t` call can't be extracted (its copy or `meaning:` isn't a string
  literal), or a source file can't be parsed: those strings never reach the
  files, so they can't be translated;
- two call sites share a key but name their interpolations differently. Keys
  ordinalize the names, so `E18n.t("Edit %{name}")` and `E18n.t("Edit %{title}")`
  are one entry, and any translation of it breaks one of the two call sites —
  in every locale but English. Give each a different `meaning:`, or use the same
  names;
- a file is out of step with the source (`escriba:dump_yml` fixes it): missing,
  a new string without an entry, an entry for a string gone from the source, a
  file for a locale that isn't translated, or invalid YAML. How a value is
  formatted doesn't matter: edit the files by hand freely;
- a value can't be served: not a string (an unquoted `yes` or `123`), unknown
  plural forms, or a lint error — an interpolation the source doesn't have, one
  it has that the translation dropped (singular strings), or a plural without
  its `other` form or without a form its locale uses (see Plural below).

Blank entries are not problems: untranslated strings show the source copy.
`bin/rails escriba:stats` reports how much of each locale is translated.

Lint checks are deliberately limited to what the strings themselves can tell.
They do not flag a value identical to its source (a cognate, brand or acronym —
`DNS`, `Plan` — looks exactly like an untranslated value).

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
  English source typically supplies `one` and `other`, while other locales need
  more (Polish needs `one/few/many/other`, Arabic uses all six). The forms a
  locale uses are read from its I18n data, `i18n.plural.keys`, which
  [rails-i18n](https://github.com/svenfuchs/rails-i18n) declares for every
  locale along with its plural rule: `escriba:dump_yml` gives each plural a
  slot for every one of them, and `escriba:check` fails on a translated plural
  that leaves one blank, since I18n serves `other` for a count whose form is
  missing ("3 stron" where Polish says "3 strony"). A locale that declares no
  forms gets the source's forms, and only `other` is required.
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
4. **`meaning:` is part of the hash**, and is written next to the entry in the
   files for the translator.

## Configuration

```ruby
Escriba.configure do |config|
  config.dev_locale = :en                 # the locale of the copy in the code
  config.available_locales = %i[en es]    # defaults to I18n.available_locales
end
```

## Rake tasks

| Task | What it does |
|---|---|
| `escriba:dump_yml` | Writes `config/locales/escriba.<locale>.yml` from the source, keeping existing values. |
| `escriba:check` | Fails on anything that would make the files wrong; for CI. |
| `escriba:stats` | Counts of strings, call sites, meanings, plurals, and how much of each locale is translated. `TOP=n` sizes the ranked lists. |

## Not supported (by design)

- **Dynamic copy.** Calls whose copy or `meaning:` is built at runtime can't be
  extracted, so they never enter the files; they render the copy they are
  given, in every locale. `escriba:check` lists them.
- **Editing translations without a deploy.** Translations ship with the code.
- **HTML safety / `_html` suffix conventions.** HTML safety is the host
  template layer's responsibility.

## Upgrading from the database-backed version

Earlier versions kept translations in an `escriba_translations` table, edited
in a mounted admin UI and imported from the files at deploy. To upgrade:

1. **Rescue anything only the database has** before anything else. An admin
   edit that never went through `escriba:dump_yml` exists only in production's
   table. Compare its non-blank values with the files, and copy into them every
   difference whose key is still in the source — including keys the files have
   no entry for at all (a string added after the last dump and translated in
   the admin UI). Rows for keys no longer in the source can be ignored.
2. Remove `mount Escriba::Engine` from `config/routes.rb`, the
   `authenticate_with` and `dev_locale_from_code` settings from the initializer
   (the dev locale is now always served from the code), the
   `@import "../builds/tailwind/escriba"` line from your Tailwind entry point,
   and `escriba:import_yml` from your deploy (`bin/docker-entrypoint` or a
   Kamal hook).
3. Run `bin/rails escriba:dump_yml`: it drops entries for strings no longer in
   the source. Commit the result, and add `bin/rails escriba:check` to CI.
4. After that has been deployed, drop the table in a migration of its own
   (`drop_table :escriba_translations`). Deploying it separately keeps
   processes still running the old version, which read the table, from failing
   during the rollout.

## Repository layout

```
escriba/
├── gem/      The gem.
└── dummy/    A Rails 8 app used for integration testing.
```

- `gem/lib/escriba/` — the gem's core (key derivation, I18n backend, extractor,
  dumper, check).
- `gem/lib/tasks/` — the rake tasks.
- `gem/lib/generators/escriba/install/` — the install generator.
- `gem/test/` — Minitest unit tests.
- `dummy/` — a Rails app rendering a demo page from its own escriba files.

## Development

```sh
bin/ci        # both suites: the gem's tests and the dummy app's
```

To run the dummy app: `cd dummy && bin/rails server`, then visit
`http://localhost:3001` (and `/es`, `/it`, `/fr`).

## License

MIT.
