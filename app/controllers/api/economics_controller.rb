# app/controllers/api/economics_controller.rb
class Api::EconomicsController < ApplicationController
  protect_from_forgery with: :null_session

  # POST /api/economics/lookup
  # Body JSON: { "building_name": "Palm Views", "unit_type": "Studio" }
  def lookup
    building = params[:building_name]
    unit     = params[:unit_type]

    if building.blank? || unit.blank?
      render json: { error: "building_name and unit_type are required" }, status: 400 and return
    end

    result = Economics::Registry.fetch(building_name: building, unit_type: unit)

    if result.status == "ok"
      render json: { status: "ok", metrics: result.metrics }, status: 200
    else
      render json: { status: "no_data", reason_code: result.reason_code }, status: 200
    end
  end
end