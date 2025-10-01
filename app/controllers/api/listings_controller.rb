module Api
  class ListingsController < ApplicationController
    protect_from_forgery with: :null_session

    def lookup
      result = Listings::Registry.fetch(
        building_name: params[:building_name],
        unit_type: params[:unit_type],
        limit: (params[:limit] || 6).to_i
      )
      render json: result
    end
  end
end
