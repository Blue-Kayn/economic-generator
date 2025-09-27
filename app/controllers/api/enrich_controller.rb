# app/controllers/api/enrich_controller.rb
class Api::EnrichController < ApplicationController
  protect_from_forgery with: :null_session

  # POST /api/enrich
  # Body JSON:
  # {
  #   "items": [
  #     { "building_name": "Palm Views", "unit_type": "Studio" },
  #     { "building_name": "Palm Tower", "unit_type": "1BR" }
  #   ]
  # }
  def create
    payload = params[:items]
    return render json: { error: "items must be an array" }, status: 400 unless payload.is_a?(Array)

    max = (ENV["ENRICH_MAX_ITEMS"] || "500").to_i
    return render json: { error: "too_many_items", max: max }, status: 413 if payload.size > max

    results = payload.each_with_index.map do |item, idx|
      b = (item["building_name"] || item[:building_name]).to_s
      u = (item["unit_type"]     || item[:unit_type]).to_s

      if b.empty? || u.empty?
        { index: idx, status: "no_data", reason_code: "INVALID_INPUT" }.merge(item || {})
      else
        econ = Economics::Registry.fetch(building_name: b, unit_type: u)
        if econ.status == "ok"
          { index: idx, status: "ok", building_name: b, unit_type: u, metrics: econ.metrics }
        else
          { index: idx, status: "no_data", building_name: b, unit_type: u, reason_code: econ.reason_code }
        end
      end
    end

    render json: { count: results.size, items: results }, status: 200
  end
end
