Escriba::Engine.routes.draw do
  root to: "dashboard#index"

  get "dashboard",     to: "dashboard#index",      as: :dashboard
  get "issues",        to: "issues#index",         as: :issues

  get  "import-export",         to: "import_export#index",   as: :import_export
  get  "import-export/export",  to: "import_export#export",  as: :import_export_export
  post "import-export/preview", to: "import_export#preview", as: :import_export_preview
  post "import-export/apply",   to: "import_export#apply",   as: :import_export_apply

  get   "translations",                       to: "translations#index",  as: :translations
  get   "translations/:key",                  to: "translations#show",   as: :translation,    constraints: { key: /[a-f0-9]{16}/ }
  get   "translations/:key/:locale/edit",     to: "translations#edit",   as: :edit_translation, constraints: { key: /[a-f0-9]{16}/ }
  patch "translations/:key/:locale",          to: "translations#update", as: :update_translation, constraints: { key: /[a-f0-9]{16}/ }
end
