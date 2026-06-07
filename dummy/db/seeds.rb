# This file should ensure the existence of records required to run the application in every environment
# (production, development, test). The code here should be idempotent so that it can be executed at any
# point in an environment's lifecycle.

# Escriba demo translations for Spanish (:es), Italian (:it) and French (:fr).
#
# In a real app these (key, locale) rows accumulate at runtime — each string is
# discovered the first time the host app renders it — and a translator fills in
# the value through the admin UI. We seed them here so the dummy app ships with
# complete es/it/fr translations for every E18n.t string in the demo views.
#
# The :en (dev_locale) copy is served straight from source code
# (dev_locale_from_code = true), so it is intentionally not seeded.
#
# Idempotent: re-running updates the existing rows in place.

SINGULARS = [
  {
    copy: "Welcome to the escriba dummy app",
    es: "Bienvenido a la app de demostración de escriba",
    fr: "Bienvenue dans l'application de démonstration escriba",
    it: "Benvenuto nell'app dimostrativa di escriba",
  },
  {
    copy: "This page exercises E18n.t across singular, plural, interpolated, and meaning-disambiguated calls.",
    es: "Esta página pone a prueba E18n.t con llamadas en singular, plural, interpoladas y desambiguadas por significado.",
    fr: "Cette page met en œuvre E18n.t pour des appels au singulier, au pluriel, interpolés et désambiguïsés par leur sens.",
    it: "Questa pagina mette alla prova E18n.t con chiamate al singolare, al plurale, interpolate e disambiguate per significato.",
  },
  {
    copy: "Singular examples",
    es: "Ejemplos en singular",
    fr: "Exemples au singulier",
    it: "Esempi al singolare",
  },
  {
    copy: "Save", meaning: "to store",
    es: "Guardar",
    fr: "Enregistrer",
    it: "Salva",
  },
  {
    copy: "Save", meaning: "to rescue",
    es: "Rescatar",
    fr: "Sauver",
    it: "Salvare",
  },
  {
    copy: "Hello %{name}, you have %{count} new messages",
    es: "Hola %{name}, tienes %{count} mensajes nuevos",
    fr: "Bonjour %{name}, vous avez %{count} nouveaux messages",
    it: "Ciao %{name}, hai %{count} nuovi messaggi",
  },
  {
    copy: "Plural examples",
    es: "Ejemplos en plural",
    fr: "Exemples au pluriel",
    it: "Esempi al plurale",
  },
  {
    copy: "Links",
    es: "Enlaces",
    fr: "Liens",
    it: "Collegamenti",
  },
  {
    copy: "View this page in Spanish",
    es: "Ver esta página en español",
    fr: "Voir cette page en espagnol",
    it: "Visualizza questa pagina in spagnolo",
  },
  {
    copy: "Pluralization demo",
    es: "Demostración de pluralización",
    fr: "Démo de pluralisation",
    it: "Demo di pluralizzazione",
  },
  {
    copy: "Manage translations",
    es: "Gestionar traducciones",
    fr: "Gérer les traductions",
    it: "Gestisci le traduzioni",
  },
  {
    copy: "Back to home",
    es: "Volver al inicio",
    fr: "Retour à l'accueil",
    it: "Torna alla home",
  },
].freeze

PLURALS = [
  {
    forms: { one: "1 item in your inbox", other: "%{count} items in your inbox" },
    es: { one: "1 elemento en tu bandeja de entrada", other: "%{count} elementos en tu bandeja de entrada" },
    fr: { one: "1 message dans votre boîte de réception", other: "%{count} messages dans votre boîte de réception" },
    it: { one: "1 elemento nella tua casella di posta", other: "%{count} elementi nella tua casella di posta" },
  },
].freeze

LOCALES = %i[es it fr].freeze

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

  LOCALES.each do |locale|
    seed_escriba_row(
      key: key,
      locale: locale,
      value: entry.fetch(locale),
      source_copy: entry[:copy],
      meaning: meaning,
      plural: false,
      interpolation_names: interpolation_names,
    )
  end
end

PLURALS.each do |entry|
  meaning = entry[:meaning]
  key = Escriba::KeyDeriver.for_plural(meaning: meaning, **entry[:forms])
  source_forms = entry[:forms].transform_keys(&:to_s)
  interpolation_names = entry[:forms].values.flat_map { |v| Escriba::KeyDeriver.interpolation_names(v) }.uniq

  LOCALES.each do |locale|
    seed_escriba_row(
      key: key,
      locale: locale,
      value: entry.fetch(locale).transform_keys(&:to_s),
      source_copy: source_forms,
      meaning: meaning,
      plural: true,
      interpolation_names: interpolation_names,
    )
  end
end

puts "Seeded #{Escriba::Translation.where(locale: LOCALES.map(&:to_s)).count} Escriba translation rows (#{LOCALES.join(', ')})."
