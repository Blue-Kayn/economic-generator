# config/routes.rb - NO CHANGES NEEDED, already correct
Rails.application.routes.draw do
  get "/demo", to: "demo#index"
  root to: "demo#index"
  get "/analyze", to: "analyze#index"  # ✅ This points to our view

  namespace :api, defaults: { format: :json } do
    get '/health', to: 'health#show'
    match "listings/lookup",   to: "listings#lookup",   via: [:get, :post]
    match "economics/lookup",  to: "economics#lookup",  via: [:get, :post]
    match "analyze/link",      to: "analyze#link",      via: [:get, :post]
    match "enrich",            to: "enrich#batch",      via: [:get, :post]
  end
end