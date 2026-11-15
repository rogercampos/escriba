require "test_helper"

class TranslationsTest < ActionDispatch::IntegrationTest
  test "English is the copy in the source" do
    get demo_path

    assert_response :success
    assert_select "h1", "Welcome to the escriba dummy app"
    assert_select "li", "Save"
    assert_select "li", "1 item in your inbox"
    assert_select "li", "3 days left"
  end

  test "another locale renders its escriba YAML file" do
    get demo_path(locale: :es)

    assert_select "h1", "Bienvenido a la app de demostración de escriba"
    assert_select "li", "Guardar"
    assert_select "li", "Rescatar"
    assert_select "li", "Hola Roger, tienes 7 mensajes nuevos"
    assert_select "li", "1 elemento en tu bandeja de entrada"
    assert_select "li", "5 elementos en tu bandeja de entrada"
    assert_select "li", "Quedan 3 días"
  end

  test "an untranslated entry falls back to the source copy" do
    get demo_path(locale: :fr)

    assert_select "h1", "Bienvenue dans l'application de démonstration escriba"
    assert_select "li", "Enregistrer"
    assert_select "li", "Save" # the "to rescue" meaning has no French yet
    assert_select "h2", "Singular examples"
    assert_select "li", "5 items in your inbox"
    assert_select "li", "3 jours restants"
  end
end
