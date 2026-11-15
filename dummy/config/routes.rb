Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get "(:locale)", to: "demo#show", as: :demo, constraints: { locale: /en|es|it|fr/ }
end
