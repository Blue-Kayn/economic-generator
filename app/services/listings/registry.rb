# frozen_string_literal: true
# app/services/listings/registry.rb
#
# Loads Airbnb listings mapped to (building, unit_type) and exposes helpers to return
# actual Airbnb links + Airdna overview URLs.
#
# CSV expected at:
#   data/references/palm_jumeirah_airbnb_links_clean.csv
# Columns (min):
#   airbnb_id, link, building, unit_type
#
require "csv"

module Listings
  class Registry
    Row = Struct.new(:airbnb_id, :airbnb_url, :building, :unit_type, keyword_init: true)

    class << self
      # Controller-friendly wrapper (so existing code calling `.fetch` keeps working).
      # Returns a hash ready to render as JSON.
      def fetch(building_name:, unit_type:, limit: 6)
        items = sample(building: building_name, unit_type: unit_type, limit: limit)
        {
          status: (items.any? ? "ok" : "no_data"),
          building_name: building_name,
          unit_type: unit_type,
          count: count(building: building_name, unit_type: unit_type),
          items: items
        }
      end

      # Return up to `limit` listings for a building/unit pair (case-insensitive).
      # Each item includes airbnb_id, airbnb_url, and airdna_overview_url.
      def sample(building:, unit_type:, limit: 6)
        return [] if building.nil? || unit_type.nil?
        load_rows!

        b = canonical(building)
        u = canonical(unit_type)

        @rows
          .select { |r| canonical(r.building) == b && canonical(r.unit_type) == u }
          .first(limit)
          .map { |r| serialize_row(r) }
      end

      # Count how many listings we have for a building/unit pair.
      def count(building:, unit_type:)
        return 0 if building.nil? || unit_type.nil?
        load_rows!

        b = canonical(building)
        u = canonical(unit_type)

        @rows.count { |r| canonical(r.building) == b && canonical(r.unit_type) == u }
      end

      # ----- internals -----

      def serialize_row(r)
        {
          airbnb_id: r.airbnb_id,
          airbnb_url: r.airbnb_url,
          airdna_overview_url: airdna_url_for(r.airbnb_id)
        }
      end

      def airdna_url_for(airbnb_id)
        base = ENV["AIRDNA_BASE"] ||
               "https://app.airdna.co/data/ae/30858/140856/overview?lat=25.117795&lng=55.134474&zoom=14&tab=active-str-listings&listing_id=abnb_"
        "#{base}#{airbnb_id}"
      end

      def canonical(s) = s.to_s.strip.downcase

      def csv_path
        explicit = ENV["LISTINGS_CSV_PATH"].to_s.strip
        return explicit unless explicit.empty?
        Rails.root.join("data", "references", "palm_jumeirah_airbnb_links_clean.csv").to_s
      end

      def load_rows!
        mtime = File.exist?(csv_path) ? File.mtime(csv_path) : nil
        return if defined?(@loaded_at) && @loaded_at == mtime

        @rows = []
        if mtime
          CSV.foreach(csv_path, headers: true) do |row|
            airbnb_id  = (row["airbnb_id"] || row["id"] || row["listing_id"]).to_s.strip
            airbnb_url = (row["link"] || row["airbnb_url"] || row["url"]).to_s.strip
            building   = (row["building"] || row["building_name"] || row["bldg_name"]).to_s.strip
            unit_type  = (row["unit_type"] || row["unit"] || row["bedrooms"] || row["beds_label"]).to_s.strip

            next if airbnb_id.empty? || building.empty? || unit_type.empty?
            airbnb_url = "https://www.airbnb.com/rooms/#{airbnb_id}" if airbnb_url.empty?

            @rows << Row.new(
              airbnb_id: airbnb_id,
              airbnb_url: airbnb_url,
              building: building,
              unit_type: normalize_unit(unit_type)
            )
          end
        end

        @loaded_at = mtime
      end

      def normalize_unit(u)
        x = u.to_s.strip.downcase
        return "Studio" if x.include?("studio")
        if (m = x.match(/(\d+)\s*(br|bed|beds|bedroom|bedrooms)/))
          return "#{m[1]}BR"
        end
        u.to_s.strip
      end
    end
  end
end
