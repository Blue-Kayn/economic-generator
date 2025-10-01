# frozen_string_literal: true
module Api
  class AnalyzeController < ApplicationController
    protect_from_forgery with: :null_session

    def link
      url = params[:url].to_s.strip
      unless url.start_with?("http")
        return render json: { status: "error", error: "url_missing_or_invalid" }, status: 400
      end

      resolved = Resolver::Dispatcher.resolve(url)

      if resolved[:building_name].present?
        normalized_unit = normalize_unit_type(resolved[:unit_type])
        
        Listings::Registry.send(:load_rows!)
        lrows = Listings::Registry.instance_variable_get(:@rows) || []
        
        # Use fuzzy matching to find best building from CSV
        matched_building = find_best_building_match(lrows, resolved[:building_name])
        
        if matched_building
          chosen = choose_unit_for_building(lrows, matched_building, normalized_unit)

          econ = Economics::Registry.lookup(
            building_name: matched_building,
            unit_type: chosen[:unit_type]
          )

          if econ[:status] == "no_data"
            econ[:user_message] = case econ[:reason_code]
            when "INSUFFICIENT_SAMPLE"
              "Not enough comparable listings (need at least 3 with 270+ days data)"
            when "BUILDING_NOT_FOUND"
              "This building is not in our Palm Jumeirah database yet"
            when "UNIT_TYPE_INVALID"
              "Unit type could not be determined"
            else
              "No economics data available"
            end
          end

          sources = Economics::Registry.sources(
            building_name: matched_building,
            unit_type: chosen[:unit_type]
          )

          lis = Listings::Registry.fetch(
            building_name: matched_building,
            unit_type: chosen[:unit_type],
            limit: 6
          )

          render json: {
            resolver: {
              building_name: resolved[:building_name],
              building_name_matched: matched_building,
              unit_type: resolved[:unit_type],
              unit_type_normalized: normalized_unit,
              confidence: resolved[:confidence],
              facts: resolved[:facts]
            },
            selection: {
              building_name: matched_building,
              unit_type_requested: normalized_unit,
              unit_type_chosen: chosen[:unit_type],
              reason: chosen[:reason],
              available_units: chosen[:available_units]
            },
            economics: econ,
            economics_sources: sources,
            listings: lis
          }
        else
          render json: {
            resolver: resolved,
            economics: { 
              status: "no_data", 
              reason_code: "BUILDING_NOT_FOUND", 
              data: nil, 
              user_message: "Could not match building to our database" 
            },
            listings: { status: "no_data", building_name: nil, unit_type: nil, count: 0, items: [] }
          }
        end
      else
        render json: {
          resolver: resolved,
          economics: { 
            status: "no_data", 
            reason_code: "NOT_SUPPORTED", 
            data: nil, 
            user_message: "Property not found in our Palm Jumeirah database" 
          },
          listings: { status: "no_data", building_name: nil, unit_type: nil, count: 0, items: [] }
        }
      end
    rescue => e
      Rails.logger.error "[AnalyzeController] Error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render json: { 
        status: "error", 
        error: "processing_failed",
        message: "Failed to analyze property. Please try again."
      }, status: 500
    end

    private

    # Fuzzy match to find best building from CSV
    def find_best_building_match(rows, query_building)
      return nil if rows.empty?
      
      csv_buildings = rows.map(&:building).uniq
      query_tokens = tokenize(query_building)
      
      best_match = nil
      best_score = 0.0
      
      csv_buildings.each do |csv_building|
        csv_tokens = tokenize(csv_building)
        score = jaccard_similarity(query_tokens, csv_tokens)
        
        if score > best_score && score >= 0.4  # 40% threshold for controller
          best_score = score
          best_match = csv_building
        end
      end
      
      best_match
    end

    def tokenize(building_name)
      canonical(building_name)
        .split(/\s+/)
        .reject { |w| w.length < 2 }
        .to_set
    end

    def jaccard_similarity(tokens_a, tokens_b)
      return 0.0 if tokens_a.empty? || tokens_b.empty?
      
      intersection = (tokens_a & tokens_b).size.to_f
      union = (tokens_a | tokens_b).size.to_f
      
      intersection / union
    end

    def normalize_unit_type(raw_unit)
      return nil if raw_unit.nil?
      
      s = raw_unit.to_s.downcase.strip
      return "Studio" if s.include?("studio")
      
      if s.match?(/(\d+)\s*(bed|br|bhk)/)
        num = s.match(/(\d+)\s*(bed|br|bhk)/)[1]
        return "#{num}BR"
      end
      
      raw_unit
    end

    def choose_unit_for_building(rows, building_name, requested_unit)
      building_rows = rows.select { |r| canonical(r.building) == canonical(building_name) }
      available_units = building_rows.map { |r| r.unit_type }.uniq

      if requested_unit && available_units.map { |u| canonical(u) }.include?(canonical(requested_unit))
        return { 
          unit_type: requested_unit, 
          reason: "page_detected_and_available", 
          available_units: available_units.sort 
        }
      end

      freq = Hash.new(0)
      building_rows.each { |r| freq[r.unit_type] += 1 }
      best_unit = freq.max_by { |unit, count| [count, unit] }&.first || available_units.first || "1BR"

      { 
        unit_type: best_unit, 
        reason: requested_unit ? "requested_not_available;defaulted_to_most_common" : "no_unit_detected;defaulted_to_most_common", 
        available_units: available_units.sort 
      }
    end

    def canonical(s)
      s.to_s.downcase.strip.gsub(/\s+/, " ")
    end
  end
end