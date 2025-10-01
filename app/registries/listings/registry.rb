# frozen_string_literal: true
# app/.../listings/registry.rb
#
# Single-source listings registry. Fuzzy building matching + aliases so
# "Seven Palm" also matches "Seven Palm Jumeirah".
#
# CSV path:
#   ENV["LISTINGS_CSV_PATH"] || Rails.root/"data/reference/palm_master_clean.csv"
#
# Required headers (case-insensitive):
#   airbnb_id, link, building, bedrooms, revenue, occupancy, days_available, adr
#
require "csv"
require "set"

module Listings
  class Registry
    Row = Struct.new(:airbnb_id, :airbnb_url, :building, :unit_type, keyword_init: true)

    BUILDING_ALIASES = {
      "seven palm" => ["seven palm jumeirah"],
      "palm tower" => ["the palm tower"],
      "the palm tower" => ["palm tower"],
      "five palm" => ["five palm jumeirah", "viceroy palm"],
      "five palm jumeirah" => ["five palm", "viceroy palm"]
    }.freeze

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
      alias lookup fetch

      def sample(building:, unit_type:, limit: 6)
        return [] if building.nil? || unit_type.nil?
        load_rows!

        b = canonical(building)
        u = canonical(unit_type)

        rows = rows_for_building_and_unit(b, u)
        rows.first(limit).map { |r| serialize_row(r) }
      end

      def count(building:, unit_type:)
        return 0 if building.nil? || unit_type.nil?
        load_rows!

        b = canonical(building)
        u = canonical(unit_type)
        rows_for_building_and_unit(b, u).size
      end

      # ---------------- Internals ----------------

      def rows_for_building_and_unit(b, u)
        # 1) Exact match
        exact = @rows.select { |r| canonical(r.building) == b && canonical(r.unit_type) == u }
        return exact unless exact.empty?

        # 2) Simple containment (either side)
        contain = @rows.select do |r|
          rb = canonical(r.building)
          (rb.include?(b) || b.include?(rb)) && canonical(r.unit_type) == u
        end
        return contain unless contain.empty?

        # 3) Alias-based
        alias_rows = []
        BUILDING_ALIASES.fetch(b, []).each do |aka|
          aka_b = canonical(aka)
          alias_rows.concat @rows.select { |r| canonical(r.building) == aka_b && canonical(r.unit_type) == u }
        end
        return alias_rows unless alias_rows.empty?

        # 4) Token-overlap fallback (≥60% overlap)
        btok = tokens(b)
        token_rows = @rows.select do |r|
          rb = canonical(r.building)
          rtok = tokens(rb)
          overlap = (btok & rtok).size
          required = [(btok.size * 0.6).ceil, 1].max
          overlap >= required && canonical(r.unit_type) == u
        end
        return token_rows unless token_rows.empty?

        []
      end

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

      def canonical(s) = s.to_s.strip.downcase.gsub(/\s+/, " ")
      def tokens(s) = canonical(s).split(/\s+/).to_set

      def csv_path
        explicit = ENV["LISTINGS_CSV_PATH"].to_s.strip
        return explicit unless explicit.empty?
        Rails.root.join("data", "reference", "palm_master_clean.csv").to_s
      end

      def load_rows!
        mtime = File.exist?(csv_path) ? File.mtime(csv_path) : nil
        return if defined?(@loaded_at) && @loaded_at == mtime

        @rows = []
        if mtime
          CSV.foreach(csv_path, headers: true) do |row|
            airbnb_id = pick(row, %w[airbnb_id id listing_id])
            airbnb_url = pick(row, %w[link airbnb_url url])
            building = pick(row, %w[building building_name bldg_name])
            unit_field = pick(row, %w[unit_type unit bedrooms beds_label])

            next if blank?(airbnb_id) || blank?(building) || blank?(unit_field)

            airbnb_url = "https://www.airbnb.com/rooms/#{airbnb_id}" if blank?(airbnb_url)

            @rows << Row.new(
              airbnb_id: airbnb_id.to_s.strip,
              airbnb_url: airbnb_url.to_s.strip,
              building: building.to_s.strip,
              unit_type: normalize_unit(unit_field)
            )
          end
        end

        @loaded_at = mtime
      end

      def normalize_unit(u)
        x = u.to_s.strip.downcase
        return "Studio" if x == "0" || x == "0br" || x.include?("studio")
        return "#{x}BR"  if x.match?(/^\d+$/)
        if (m = x.match(/(\d+)\s*(br|bed|beds|bedroom|bedrooms)?/))
          return "#{m[1]}BR"
        end
        u.to_s.strip
      end

      def pick(row, keys)
        keys.each do |k|
          v = row[k] || row[k.capitalize] || row[k.upcase]
          return v unless v.nil?
        end
        nil
      end

      def blank?(v)
        v.nil? || v.to_s.strip.empty? || v.to_s.strip.downcase == "nil"
      end
    end
  end
end
