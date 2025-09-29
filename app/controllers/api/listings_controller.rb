# app/controllers/api/listings_controller.rb
class Api::ListingsController < ApplicationController
  protect_from_forgery with: :null_session

  # POST /api/listings/lookup
  # { "building_name": "Palm Views", "unit_type": "Studio" }
  def lookup
    b = params[:building_name].to_s
    u = params[:unit_type].to_s
    return render json: { error: "building_name and unit_type are required" }, status: 400 if b.blank? || u.blank?

    begin
      render json: Listings::Registry.fetch(building_name: b, unit_type: u), status: 200
    rescue => e
      render json: { error: "lookup_failed", detail: e.message }, status: 422
    end
  end
end
