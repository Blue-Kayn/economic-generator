# frozen_string_literal: true
# app/services/economics/registry.rb
#
# UPDATED: Minimum sample size changed from 3 to 2 listings
#
require_relative "seasonality"

module Economics
  class Registry
    MIN_DAYS_FOR_SAMPLE = 270
    MIN_LISTINGS_REQUIRED = 2  # Changed from 3 to 2
    FUZZY_MATCH_THRESHOLD = 0.6  # 60% similarity for building matching
    
    class << self
      def reload!
        @rows = nil
        @loaded_at = nil
        load_rows!
      end

      def lookup(building_name:, unit_type:)
        load_rows!
        
        building = building_name.to_s.strip
        unit = normalize_unit_type(unit_type)
        
        return no_data_response(building, unit, "BUILDING_NOT_FOUND") if building.empty?
        return no_data_response(building, unit, "UNIT_TYPE_INVALID") if unit.empty?
        
        # Find best matching building from CSV using fuzzy matching
        matched_building = find_best_building_match(building)
        return no_data_response(building, unit, "BUILDING_NOT_FOUND") unless matched_building
        
        # Filter for matched building + unit type with minimum days
        candidates = @rows.select do |r|
          canonical(r[:building]) == canonical(matched_building) &&
          normalize_unit_type(r[:unit_type]) == unit &&
          r[:days_available].to_i >= MIN_DAYS_FOR_SAMPLE
        end
        
        # Changed from 3 to 2 minimum listings
        return no_data_response(building, unit, "INSUFFICIENT_SAMPLE") if candidates.size < MIN_LISTINGS_REQUIRED
        
        expanded = candidates.map { |r| expand_listing(r, unit) }
        metrics = calculate_metrics(expanded, building, unit)
        listings = expanded.map { |x| listing_summary(x) }
        
        {
          status: "ok",
          data: metrics,
          listings: listings
        }
      end

      def sources(building_name:, unit_type:)
        load_rows!
        
        building = building_name.to_s.strip
        unit = normalize_unit_type(unit_type)
        
        matched_building = find_best_building_match(building)
        return { count: 0, min_days: MIN_DAYS_FOR_SAMPLE, comps: [] } unless matched_building
        
        candidates = @rows.select do |r|
          canonical(r[:building]) == canonical(matched_building) &&
          normalize_unit_type(r[:unit_type]) == unit &&
          r[:days_available].to_i >= MIN_DAYS_FOR_SAMPLE
        end
        
        {
          count: candidates.size,
          min_days: MIN_DAYS_FOR_SAMPLE,
          comps: candidates.map do |r|
            {
              airbnb_id: r[:airbnb_id],
              airbnb_url: r[:airbnb_url],
              airdna_url: airdna_url(r[:airbnb_id]),
              days_available: r[:days_available],
              raw_revenue: normalize_revenue(r[:revenue]),
              raw_adr: r[:adr],
              raw_occ: r[:occupancy]
            }
          end
        }
      end

      private

      # Normalize ONLY revenue values - convert millions to full numbers
      # Only applies to revenue, not ADR, occupancy, or any other metric
      def normalize_revenue(revenue_value)
        rev = revenue_value.to_f
        # If revenue is less than 100, it's in millions (e.g., 1.1 = 1.1M)
        if rev > 0 && rev < 100
          (rev * 1_000_000).round(0)
        else
          rev.round(0)
        end
      end

      # Fuzzy match building name against all buildings in CSV
      # Returns the best matching building name from CSV, or nil if no good match
      def find_best_building_match(query_building)
        return nil if @rows.empty?
        
        csv_buildings = @rows.map { |r| r[:building] }.uniq
        query_tokens = tokenize(query_building)
        
        best_match = nil
        best_score = 0.0
        
        csv_buildings.each do |csv_building|
          csv_tokens = tokenize(csv_building)
          score = jaccard_similarity(query_tokens, csv_tokens)
          
          if score > best_score && score >= FUZZY_MATCH_THRESHOLD
            best_score = score
            best_match = csv_building
          end
        end
        
        best_match
      end

      # Tokenize building name into words (normalized)
      def tokenize(building_name)
        canonical(building_name)
          .split(/\s+/)
          .reject { |w| w.length < 2 }  # ignore 1-letter words
          .to_set
      end

      # Calculate Jaccard similarity between two sets of tokens
      def jaccard_similarity(tokens_a, tokens_b)
        return 0.0 if tokens_a.empty? || tokens_b.empty?
        
        intersection = (tokens_a & tokens_b).size.to_f
        union = (tokens_a | tokens_b).size.to_f
        
        intersection / union
      end

      def expand_listing(row, unit_type)
        days = row[:days_available].to_i
        raw_adr = row[:adr].to_f
        raw_occ = row[:occupancy].to_f
        raw_occ = raw_occ * 100 if raw_occ <= 1.0
        raw_revenue = normalize_revenue(row[:revenue])  # ONLY normalize revenue
        
        if days >= 365
          return {
            airbnb_id: row[:airbnb_id],
            airbnb_url: row[:airbnb_url],
            days_available: days,
            raw_revenue: raw_revenue,
            raw_adr: raw_adr,
            raw_occ: raw_occ,
            adr_365: raw_adr,
            occ_365: raw_occ,
            rev_365: raw_revenue,
            mode: "truth",
            adjustment_factor: 1.0,
            missing_months: []
          }
        end
        
        missing_months = Seasonality.missing_months(days)
        missing_multiplier = Seasonality.missing_months_multiplier(unit_type, days)
        
        projected_revenue_365 = raw_revenue * (1.0 + missing_multiplier)
        projected_adr = raw_adr
        projected_occ = (projected_revenue_365 / (projected_adr * 365.0)) * 100
        projected_occ = [[projected_occ, 0].max, 100].min
        
        {
          airbnb_id: row[:airbnb_id],
          airbnb_url: row[:airbnb_url],
          days_available: days,
          raw_revenue: raw_revenue,
          raw_adr: raw_adr,
          raw_occ: raw_occ,
          adr_365: projected_adr,
          occ_365: projected_occ,
          rev_365: projected_revenue_365.round(0),
          mode: "seasonality_scaled",
          adjustment_factor: (1.0 + missing_multiplier).round(2),
          missing_months: missing_months,
          missing_months_multiplier: missing_multiplier.round(3)
        }
      end

      def calculate_metrics(expanded, building, unit_type)
        return {} if expanded.empty?
        
        adr_values = expanded.map { |x| x[:adr_365] }
        occ_values = expanded.map { |x| x[:occ_365] }
        rev_values = expanded.map { |x| x[:rev_365] }
        
        weights = expanded.map { |x| x[:mode] == "truth" ? 365 : x[:days_available] }
        
        {
          adr_p50: weighted_percentile(adr_values, weights, 0.50).round(0),
          adr_p75: weighted_percentile(adr_values, weights, 0.75).round(0),
          occ_p50: weighted_percentile(occ_values, weights, 0.50).round(1),
          occ_p75: weighted_percentile(occ_values, weights, 0.75).round(1),
          rev_p50: weighted_percentile(rev_values, weights, 0.50).round(0),
          rev_p75: weighted_percentile(rev_values, weights, 0.75).round(0),
          building: building,
          unit_type: unit_type,
          sample_n: expanded.size,
          truth_count: expanded.count { |x| x[:mode] == "truth" },
          scaled_count: expanded.count { |x| x[:mode] == "seasonality_scaled" },
          min_days_filter: MIN_DAYS_FOR_SAMPLE,
          min_listings_required: MIN_LISTINGS_REQUIRED,
          method_version: "6.3-min-2-listings",
          data_snapshot_date: "2025-09-22"
        }
      end

      def listing_summary(expanded_listing)
        {
          airbnb_id: expanded_listing[:airbnb_id],
          airbnb_url: expanded_listing[:airbnb_url],
          days_available: expanded_listing[:days_available],
          raw_revenue: expanded_listing[:raw_revenue],
          raw_adr: expanded_listing[:raw_adr],
          raw_occ: expanded_listing[:raw_occ],
          projected_adr_365: expanded_listing[:adr_365],
          projected_occ_365: expanded_listing[:occ_365],
          projected_rev_365: expanded_listing[:rev_365],
          projection_mode: expanded_listing[:mode],
          adjustment_factor: expanded_listing[:adjustment_factor],
          missing_months: expanded_listing[:missing_months]
        }
      end

      def weighted_percentile(values, weights, percentile)
        return 0 if values.empty?
        sorted = values.zip(weights).sort_by { |v, w| v }
        total_weight = weights.sum.to_f
        target = total_weight * percentile
        cumulative = 0.0
        sorted.each do |val, weight|
          cumulative += weight
          return val if cumulative >= target
        end
        sorted.last.first
      end

      def no_data_response(building, unit, reason_code)
        {
          status: "no_data",
          reason_code: reason_code,
          data: nil,
          building_name: building,
          unit_type: unit,
          user_message: reason_messages[reason_code]
        }
      end

      def reason_messages
        {
          "INSUFFICIENT_SAMPLE" => "Not enough data for this building/unit combination (need at least #{MIN_LISTINGS_REQUIRED} comps with #{MIN_DAYS_FOR_SAMPLE}+ days)",
          "BUILDING_NOT_FOUND" => "Building not found in dataset",
          "UNIT_TYPE_INVALID" => "Unit type not recognized"
        }
      end

      def normalize_unit_type(unit_type)
        s = unit_type.to_s.strip.downcase
        return "Studio" if s == "0" || s == "0br" || s.include?("studio")
        return "1BR" if s.match?(/^1/)
        return "2BR" if s.match?(/^2/)
        return "3BR" if s.match?(/^3/)
        return "4BR" if s.match?(/^4/)
        s
      end

      def canonical(str)
        str.to_s.strip.downcase.gsub(/\s+/, " ")
      end

      def airdna_url(airbnb_id)
        base = "https://app.airdna.co/data/ae/30858/140856/overview?lat=25.117795&lng=55.134474&zoom=14&tab=active-str-listings&listing_id=abnb_"
        "#{base}#{airbnb_id}"
      end

      def load_rows!
        path = csv_path
        mtime = File.exist?(path) ? File.mtime(path) : nil
        return if defined?(@loaded_at) && @loaded_at == mtime
        
        @rows = []
        return unless mtime
        
        require "csv"
        CSV.foreach(path, headers: true) do |row|
          airbnb_id = pick(row, %w[airbnb_id id listing_id])
          airbnb_url = pick(row, %w[link airbnb_url url])
          building = pick(row, %w[building building_name])
          bedrooms = pick(row, %w[bedrooms beds unit_type])
          revenue = pick(row, %w[revenue annual_revenue])
          occupancy = pick(row, %w[occupancy occ])
          days_available = pick(row, %w[days_available days])
          adr = pick(row, %w[adr average_daily_rate])
          
          next if blank?(airbnb_id) || blank?(building)
          
          airbnb_url = "https://www.airbnb.com/rooms/#{airbnb_id}" if blank?(airbnb_url)
          
          @rows << {
            airbnb_id: airbnb_id.to_s.strip,
            airbnb_url: airbnb_url.to_s.strip,
            building: building.to_s.strip,
            unit_type: normalize_unit_from_bedrooms(bedrooms),
            revenue: to_f(revenue),  # Keep raw value, normalize_revenue handles conversion
            occupancy: to_f(occupancy),  # Never converted
            days_available: to_i(days_available),  # Never converted
            adr: to_f(adr)  # Never converted
          }
        end
        
        @loaded_at = mtime
      end

      def csv_path
        ENV["MASTER_SHEET_CSV"].presence ||
          Rails.root.join("data", "reference", "palm_master_clean.csv").to_s
      end

      def normalize_unit_from_bedrooms(bedrooms)
        b = bedrooms.to_s.strip.downcase
        return "Studio" if b == "0" || b.include?("studio")
        return "#{b}BR" if b.match?(/^\d+$/)
        b
      end

      def pick(row, keys)
        keys.each do |k|
          v = row[k] || row[k.capitalize] || row[k.upcase]
          return v unless v.nil?
        end
        nil
      end

      def blank?(v)
        v.nil? || v.to_s.strip.empty?
      end

      def to_f(v)
        Float(v) rescue 0.0
      end

      def to_i(v)
        Integer(v) rescue 0
      end
    end
  end
end