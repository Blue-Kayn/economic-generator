# app/controllers/api/listings_controller.rb
class Api::ListingsController < ApplicationController
  protect_from_forgery with: :null_session

  # POST /api/listings/lookup
  # Body: { "building_name": "Palm Views", "unit_type": "Studio" }
  def lookup
    b = params[:building_name].to_s
    u = params[:unit_type].to_s
    return render json: { error: "building_name and unit_type are required" }, status: 400 if b.blank? || u.blank?

    items = Listings::Registry.sample(building: b, unit_type: u, limit: 6)
    cnt   = Listings::Registry.count(building: b, unit_type: u)

    payload = {
      status: (items.any? ? "ok" : "no_data"),
      building_name: b,
      unit_type: u,
      count: cnt,
      items: items
    }

    if truthy?(params[:debug])
      payload[:_debug] = Listings::Registry.debug_info(query_building: b, query_unit: u)
    end

    render json: payload
  end

  # POST /api/listings/debug
  # Optional body: { "building_name": "Palm Views", "unit_type": "Studio" }
  def debug
    b = params[:building_name].to_s.presence
    u = params[:unit_type].to_s.presence
    render json: Listings::Registry.debug_info(query_building: b, query_unit: u)
  end

  private

  def truthy?(v)
    %w[1 true yes on y].include?(v.to_s.strip.downcase)
  end
end
