# frozen_string_literal: true
module Api
  class EnrichController < ApplicationController
    protect_from_forgery with: :null_session

    # GET/POST /api/enrich
    # Body (JSON):
    # { "items": [ { "building_name": "Palm Views", "unit_type": "Studio" }, ... ] }
    def batch
      items = extract_items
      return render json: { status: "error", error: "items_missing" }, status: 400 if items.empty?

      results = items.map do |it|
        b = it["building_name"].to_s
        u = it["unit_type"].to_s

        econ = Economics::Registry.lookup(building_name: b, unit_type: u)
        lis  = Listings::Registry.fetch(building_name: b, unit_type: u, limit: 6)

        {
          input: { building_name: b, unit_type: u },
          economics: econ,
          listings: lis
        }
      end

      render json: { status: "ok", results: results }
    end

    private

    def extract_items
      if request.get?
        # allow items via query param ?items=[{...}]
        raw = params[:items]
        raw.present? ? JSON.parse(raw) rescue [] : []
      else
        begin
          body = request.body.read
          json = body.present? ? JSON.parse(body) : {}
          json["items"].is_a?(Array) ? json["items"] : []
        rescue JSON::ParserError
          []
        end
      end
    end
  end
end
