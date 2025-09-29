# frozen_string_literal: true
# app/services/listings/registry.rb
#
# Accepts CSV at either:
#   data/reference/palm_jumeirah_airbnb_links_clean.csv   (repo default)
#   data/references/palm_jumeirah_airbnb_links_clean.csv  (user alt)
#
require "csv"

module Listings
  class Registry
    Row = Struct.new(:airbnb_id, :airbnb_url, :building, :unit_type, keyword_init: true)

    class << self
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

      def sample(building:, unit_type:, limit: 6)
        return [] if building.nil? || unit_type.nil?
        load_rows!

        b = canon_building(building)
        u = canon_unit(unit_type)

        @rows
          .select { |r| canon_building(r.building) == b && canon_unit(r.unit_type) == u }
          .first(limit)
          .map { |r| serialize_row(r) }
      end

      def count(building:, unit_type:)
        return 0 if building.nil? || unit_type.nil?
        load_rows!

        b = canon_building(building)
        u = canon_unit(unit_type)
        @rows.count { |r| canon_building(r.building) == b && canon_unit(r.unit_type) == u }
      end

      # ---------- diagnostics ----------
      def debug_info(query_building:, query_unit:)
        load_rows!

        keys = @rows.group_by { |r| [canon_building(r.building), canon_unit(r.unit_type)] }
                   .transform_values!(&:size)

        qb = query_building ? canon_building(query_building) : nil
        qu = query_unit     ? canon_unit(query_unit)         : nil

        sample = if qb && qu
          @rows.select { |r| canon_building(r.building) == qb && canon_unit(r.unit_type) == qu }
               .first(3).map { |r| serialize_row(r) }
        else
          []
        end

        {
          csv_path: csv_path,
          total_rows_loaded: @rows.size,
          unique_pairs_count: keys.size,
          first_5_pairs: keys.to_a.first(5).map { |(b,u), c| { building: b, unit_type: u, count: c } },
          query: { building: query_building, unit_type: query_unit, canonical: { building: qb, unit: qu } },
          query_sample: sample
        }
      end

      # ---------- internals ----------
      def serialize_row(r)
        { airbnb_id: r.airbnb_id, airbnb_url: r.airbnb_url, airdna_overview_url: airdna_url_for(r.airbnb_id) }
      end

      def airdna_url_for(airbnb_id)
        base = ENV["AIRDNA_BASE"] ||
               "https://app.airdna.co/data/ae/30858/140856/overview?lat=25.117795&lng=55.134474&zoom=14&tab=active-str-listings&listing_id=abnb_"
        "#{base}#{airbnb_id}"
      end

      def canon_building(s)
        x = s.to_s.strip.downcase
        return "Palm Views"           if x.include?("palm views")
        return "Palm Tower"           if x.include?("palm tower")
        return "Seven Palm"           if x.include?("seven palm")
        return "Shoreline"            if x.include?("shoreline")
        return "Tiara Residences"     if x.include?("tiara")
        return "Golden Mile"          if x.include?("golden mile")
        return "Marina Residences"    if x.include?("marina residences")
        return "Fairmont Residences"  if x.include?("fairmont")
        s.to_s.strip
      end

      def canon_unit(u)
        x = u.to_s.strip.downcase
        return "Studio" if x.include?("studio")
        if (m = x.match(/(\d+)\s*(br|bed|beds|bedroom|bedrooms)/))
          return "#{m[1]}BR"
        end
        u.to_s.strip
      end

      def csv_path
        explicit = ENV["LISTINGS_CSV_PATH"].to_s.strip
        return explicit unless explicit.empty?

        plural   = Rails.root.join("data", "references", "palm_jumeirah_airbnb_links_clean.csv")
        singular = Rails.root.join("data", "reference",  "palm_jumeirah_airbnb_links_clean.csv")
        return plural.to_s   if File.exist?(plural)
        return singular.to_s if File.exist?(singular)
        singular.to_s
      end

      def load_rows!
        mtime = File.exist?(csv_path) ? File.mtime(csv_path) : nil
        return if defined?(@loaded_at) && @loaded_at == mtime

        @rows = []
        unless mtime
          Rails.logger.warn("[Listings::Registry] CSV not found at #{csv_path}")
          @loaded_at = nil
          return
        end

        CSV.foreach(csv_path, headers: true) do |row|
          airbnb_id  = (row["airbnb_id"] || row["id"] || row["listing_id"]).to_s.strip
          airbnb_url = (row["link"] || row["airbnb_url"] || row["url"]).to_s.strip
          building   = (row["building"] || row["building_name"] || row["bldg_name"]).to_s.strip
          unit_type  = (row["unit_type"] || row["unit"] || row["bedrooms"] || row["bedroom"] || row["beds_label"]).to_s.strip

          next if airbnb_id.empty? || building.empty? || unit_type.empty?
          airbnb_url = "https://www.airbnb.com/rooms/#{airbnb_id}" if airbnb_url.empty?

          @rows << Row.new(airbnb_id:, airbnb_url:, building:, unit_type:)
        end

        @loaded_at = mtime
        Rails.logger.info("[Listings::Registry] Loaded #{@rows.size} rows from #{csv_path}")
      end
    end
  end
end
