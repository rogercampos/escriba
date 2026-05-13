Escriba::Engine.routes.draw do
  root to: "translations#index"

  get   "translations",                       to: "translations#index",  as: :translations
  get   "translations/:key",                  to: "translations#show",   as: :translation,    constraints: { key: /[a-f0-9]{16}/ }
  get   "translations/:key/:locale/edit",     to: "translations#edit",   as: :edit_translation, constraints: { key: /[a-f0-9]{16}/ }
  patch "translations/:key/:locale",          to: "translations#update", as: :update_translation, constraints: { key: /[a-f0-9]{16}/ }
end
