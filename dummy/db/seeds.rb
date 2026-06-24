# This file should ensure the existence of records required to run the application in every environment
# (production, development, test). The code here should be idempotent so that it can be executed at any
# point in an environment's lifecycle.

# Escriba demo translations for Spanish (:es), Italian (:it) and French (:fr).
#
# In a real app these (key, locale) rows accumulate at runtime — each string is
# discovered the first time the host app renders it — and a translator fills in
# the value through the admin UI. We seed a deliberately *uneven* dataset so the
# admin UI exercises everything the gem can surface:
#
#   * es — fully translated (100%, green) but with one broken-interpolation entry,
#          to show that completeness != correctness.
#   * it — partially translated (Missing filter populated) + a legitimately
#          identical value + missing-interpolation issues.
#   * fr — least complete + an unknown-interpolation issue, a plural missing its
#          required "other" form, and a legitimately identical plural.
#
# Per-locale value can be:
#   "a string" / { "one" => ... }  -> a normal translation
#   :missing                       -> no row created (shows under the Missing filter)
#   value equal to the source      -> a valid translation (cognate/brand/acronym);
#                                     NOT flagged — identical-to-source is undecidable
#   value with a bad/!@#{} variable -> flagged by the interpolation linter
#
# The :en (dev_locale) row is seeded from the source copy, exactly as runtime
# discovery would — so every string appears in the catalog even though en is
# served from source code (dev_locale_from_code = true).
#
# Idempotent: re-running updates the existing rows in place.

SINGULARS = [
  # --- fully translated everywhere ---------------------------------------
  {
    copy: "Welcome to the escriba dummy app",
    es: "Bienvenido a la app de demostración de escriba",
    it: "Benvenuto nell'app dimostrativa di escriba",
    fr: "Bienvenue dans l'application de démonstration escriba",
  },
  {
    copy: "Back to home",
    es: "Volver al inicio",
    it: "Torna alla home",
    fr: "Retour à l'accueil",
  },
  {
    copy: "Pluralization demo",
    es: "Demostración de pluralización",
    it: "Demo di pluralizzazione",
    fr: "Démo de pluralisation",
  },
  {
    copy: "Profile",
    es: "Perfil",
    it: "Profilo",
    fr: "Profil",
  },

  # --- meaning disambiguation (same copy, two keys) ----------------------
  {
    copy: "Save", meaning: "to store",
    es: "Guardar",
    it: "Salva",
    fr: "Enregistrer",
  },
  {
    copy: "Save", meaning: "to rescue",
    es: "Rescatar",
    it: "Salvare",
    fr: :missing,
  },

  # --- partial coverage (Missing filter) ---------------------------------
  {
    copy: "This page exercises E18n.t across singular, plural, interpolated, and meaning-disambiguated calls.",
    es: "Esta página pone a prueba E18n.t con llamadas en singular, plural, interpoladas y desambiguadas por significado.",
    it: "Questa pagina mette alla prova E18n.t con chiamate al singolare, al plurale, interpolate e disambiguate per significato.",
    fr: :missing,
  },
  {
    copy: "Singular examples",
    es: "Ejemplos en singular",
    it: :missing,
    fr: "Exemples au singulier",
  },
  {
    copy: "Plural examples",
    es: "Ejemplos en plural",
    it: "Esempi al plurale",
    fr: :missing,
  },
  {
    copy: "Manage translations",
    es: "Gestionar traducciones",
    it: "Gestisci le traduzioni",
    fr: "Gérer les traductions",
  },
  {
    copy: "View this page in Spanish",
    es: "Ver esta página en español",
    it: "Visualizza questa pagina in spagnolo",
    fr: :missing,
  },
  {
    # Missing in every editable locale — a freshly discovered, untranslated string.
    copy: "Sign out",
    es: "Cerrar sesión",
    it: :missing,
    fr: :missing,
  },

  # --- legitimately identical to source (a cognate; NOT an issue) --------
  {
    copy: "Links",
    es: "Enlaces",
    it: "Links", # identical to source — valid, not flagged
    fr: "Liens",
  },

  # --- interpolation issues ----------------------------------------------
  {
    # es: unknown %{nombre} (+ missing %{name}); it: missing both; fr: correct.
    copy: "Hello %{name}, you have %{count} new messages",
    es: "Hola %{nombre}, tienes %{count} mensajes nuevos",
    it: "Ciao, hai nuovi messaggi",
    fr: "Bonjour %{name}, vous avez %{count} nouveaux messages",
  },
  {
    # fr: unknown %{titre} (+ missing %{title}).
    copy: "Edit %{title}",
    es: "Editar %{title}",
    it: "Modifica %{title}",
    fr: "Modifier %{titre}",
  },
  {
    # it: missing %{total}.
    copy: "Showing %{from}–%{to} of %{total}",
    es: "Mostrando %{from}–%{to} de %{total}",
    it: "Visualizzazione %{from}–%{to}",
    fr: :missing,
  },
].freeze

PLURALS = [
  {
    # fr: missing the required "other" form.
    forms: { one: "1 item in your inbox", other: "%{count} items in your inbox" },
    es: { one: "1 elemento en tu bandeja de entrada", other: "%{count} elementos en tu bandeja de entrada" },
    it: { one: "1 elemento nella tua casella di posta", other: "%{count} elementi nella tua casella di posta" },
    fr: { one: "1 message dans votre boîte de réception" },
  },
  {
    # it: missing entirely.
    forms: { one: "%{count} file", other: "%{count} files" },
    es: { one: "%{count} archivo", other: "%{count} archivos" },
    it: :missing,
    fr: { one: "%{count} fichier", other: "%{count} fichiers" },
  },
  {
    # fr: legitimately identical to source (not flagged).
    forms: { one: "%{count} day left", other: "%{count} days left" },
    es: { one: "%{count} día restante", other: "%{count} días restantes" },
    it: { one: "%{count} giorno rimasto", other: "%{count} giorni rimasti" },
    fr: { one: "%{count} day left", other: "%{count} days left" },
  },
].freeze

LOCALES = %i[es it fr].freeze
DEV_LOCALE = Escriba.config.dev_locale

def seed_escriba_row(key:, locale:, value:, source_copy:, meaning:, plural:, interpolation_names:)
  row = Escriba::Translation.find_or_initialize_by(key: key, locale: locale.to_s)
  row.value = value
  row.source_copy = source_copy
  row.meaning = meaning
  row.plural = plural
  row.interpolation_names = interpolation_names
  row.save!
end

SINGULARS.each do |entry|
  meaning = entry[:meaning]
  key = Escriba::KeyDeriver.for_singular(entry[:copy], meaning: meaning)
  interpolation_names = Escriba::KeyDeriver.interpolation_names(entry[:copy])

  # Dev-locale row mirrors runtime discovery: value == source.
  seed_escriba_row(key: key, locale: DEV_LOCALE, value: entry[:copy], source_copy: entry[:copy],
    meaning: meaning, plural: false, interpolation_names: interpolation_names)

  LOCALES.each do |locale|
    value = entry.fetch(locale, :missing)
    next if value == :missing

    seed_escriba_row(key: key, locale: locale, value: value, source_copy: entry[:copy],
      meaning: meaning, plural: false, interpolation_names: interpolation_names)
  end
end

PLURALS.each do |entry|
  meaning = entry[:meaning]
  key = Escriba::KeyDeriver.for_plural(meaning: meaning, **entry[:forms])
  source_forms = entry[:forms].transform_keys(&:to_s)
  interpolation_names = entry[:forms].values.flat_map { |v| Escriba::KeyDeriver.interpolation_names(v) }.uniq

  seed_escriba_row(key: key, locale: DEV_LOCALE, value: source_forms, source_copy: source_forms,
    meaning: meaning, plural: true, interpolation_names: interpolation_names)

  LOCALES.each do |locale|
    value = entry.fetch(locale, :missing)
    next if value == :missing

    seed_escriba_row(key: key, locale: locale, value: value.transform_keys(&:to_s), source_copy: source_forms,
      meaning: meaning, plural: true, interpolation_names: interpolation_names)
  end
end

all_locales = [DEV_LOCALE, *LOCALES].map(&:to_s)
puts "Seeded #{Escriba::Translation.where(locale: all_locales).count} Escriba translation rows " \
  "across #{Escriba::Translation.distinct.count(:key)} strings (#{all_locales.join(', ')})."
