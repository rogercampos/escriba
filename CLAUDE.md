# Escriba

## About this library

- Escriba is a translations gem for Rails, without translation keys: copy is written in source (`E18n.t("Save", meaning: "to store")`), its key is a hash derived from the copy, and translations live in a database table edited through the engine's admin UI. Underneath it is still Rails I18n. `README.md` describes it.
- It is used from git `main`, so what is pushed to `main` is what users get at their next `bundle update escriba`: a breaking change to the public API is called out in the commit.
- Layout: `gem/` is the gem (`escriba.gemspec`, `app/` for the admin UI engine, `lib/escriba/`, `test/`); `dummy/` is a Rails app that mounts it, for integration tests; `config/ci.rb` and `bin/` are repo tooling at the root. Each of `gem/` and `dummy/` has its own `Gemfile` and committed `Gemfile.lock`; the Ruby is the root `.ruby-version`.

## Running it

- Full verification: `bin/ci` (steps in `config/ci.rb`, run from `gem/`): gem tests, then the dummy app's tests.
- Gem tests: `cd gem && bundle exec rake test`. Dummy app tests: `cd gem && bundle exec rake test_dummy`.
- Coverage: `bin/coverage` runs both suites, merged into one report (`gem/test/simplecov_setup.rb`), and leaves it in `coverage/.resultset.json` (and `gem/coverage/`).
- A second checkout for an isolated run: `bin/setup-worktree DIR --id ID [--provision]`.
