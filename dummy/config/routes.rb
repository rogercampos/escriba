Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mount Escriba::Engine => "/escriba"

  root to: "demo#home"
  get "demo/spanish", to: "demo#spanish"
  get "demo/plural",  to: "demo#plural"
end
