# Dummy app

Minimal Rails app used for developing and testing the escriba gem. `/` renders
a demo page in English (the copy in the source); `/es`, `/it` and `/fr` render
it from `config/locales/escriba.<locale>.yml`, which are deliberately left
partly untranslated so the fallback to English shows.

After changing copy in `app/views`, run `bin/rails escriba:dump_yml` and
translate the new blank entries.
