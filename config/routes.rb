Rails.application.routes.draw do
  # Demo page (browser)
  get "/demo", to: "demo#index"
  root to: "demo#index"
  get "/analyze", to: "analyze#index"


  # API namespace (browser + programmatic)
  namespace :api do
    # Listings & Economics (GET for browser, POST for programmatic)
    match "listings/lookup",   to: "listings#lookup",   via: [:get, :post]
    match "economics/lookup",  to: "economics#lookup",  via: [:get, :post]

    # Analyze a PF/Bayut URL (returns resolver + economics + a few listings)
    match "analyze/link",      to: "analyze#link",      via: [:get, :post]

    # Batch enrich [{building_name, unit_type}]
    match "enrich",            to: "enrich#batch",      via: [:get, :post]
  end
end
