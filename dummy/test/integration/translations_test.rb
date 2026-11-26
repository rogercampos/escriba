require "test_helper"

class TranslationsTest < ActionDispatch::IntegrationTest
  test "English is the copy in the source" do
    get demo_path

    assert_response :success
    assert_text "Welcome to the escriba dummy app"
    assert_texts_in "Singular examples", "Save"
    assert_texts_in "Plural examples", "1 item in your inbox", "3 days left"
  end

  test "another locale renders its escriba YAML file" do
    get demo_path(locale: :es)

    assert_text "Bienvenido a la app de demostración de escriba"
    assert_texts_in "Ejemplos en singular", "Guardar", "Rescatar", "Hola Roger, tienes 7 mensajes nuevos"
    assert_texts_in "Ejemplos en plural",
      "1 elemento en tu bandeja de entrada", "5 elementos en tu bandeja de entrada", "Quedan 3 días"
  end

  test "an untranslated entry falls back to the source copy" do
    get demo_path(locale: :fr)

    assert_text "Bienvenue dans l'application de démonstration escriba"
    # "Singular examples" and the "to rescue" meaning of "Save" have no French yet
    assert_texts_in "Singular examples", "Enregistrer", "Save"
    assert_texts_in "Plural examples", "5 items in your inbox", "3 jours restants"
  end

  private
    def assert_text(text)
      assert_select "*", text: text
    end

    def assert_texts_in(section, *texts)
      assert_select "[aria-label=?]", section do
        texts.each { |text| assert_text text }
      end
    end
end
