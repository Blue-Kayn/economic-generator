Rails.application.routes.draw do
  namespace :api do
    post "economics/lookup", to: "economics#lookup"
    post "analyze_link",     to: "analyze#link"
  end
end