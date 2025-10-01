module Api
  class EconomicsController < ApplicationController
    protect_from_forgery with: :null_session

    def lookup
      result = Economics::Registry.lookup(
        building_name: params[:building_name],
        unit_type: params[:unit_type]
      )
      render json: result
    end
  end
end
