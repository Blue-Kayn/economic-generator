Rails.application.routes.draw do
  get  "demo", to: "demo#index"

  namespace :api do
    post "economics/lookup", to: "economics#lookup"
    post "analyze_link",     to: "analyze#link"
    post "enrich",           to: "enrich#create"
  end
end
