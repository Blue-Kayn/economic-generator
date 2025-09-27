Rails.application.routes.draw do
  namespace :api do
    post "economics/lookup", to: "economics#lookup"
  end
end