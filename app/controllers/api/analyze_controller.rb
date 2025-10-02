# frozen_string_literal: true
# app/controllers/api/analyze_controller.rb

module Api
  class AnalyzeController < ApplicationController
    protect_from_forgery with: :null_session
    
    # Minimum sample size changed from 3 to 2
    MIN_LISTINGS_REQUIRED = 2

    def link
      url = params[:url].to_s.strip
      unless url.start_with?("http")
        return render json: { status: "error", error: "url_missing_or_invalid" }, status: 400
      end

      resolved = Resolver::Dispatcher.resolve(url)

      if resolved[:building_name].present?
        normalized_unit = normalize_unit_type(resolved[:unit_type])
        
        # CRITICAL: Check if property has maid's room
        has_maids_room = resolved[:facts][:has_maids_room] || false
        original_bedrooms = resolved[:facts][:bedrooms_without_maid]
        
        Listings::Registry.send(:load_rows!)
        lrows = Listings::Registry.instance_variable_get(:@rows) || []
        
        matched_building = find_best_building_match(lrows, resolved[:building_name])
        
        if matched_building
          chosen = choose_unit_for_building(lrows, matched_building, normalized_unit)

          # FIXED: Only try fallback if property has maid's room
          if chosen[:unit_type].nil?
            if has_maids_room && original_bedrooms
              # Property has maid's room, try N-1 fallback
              fallback_unit = "#{original_bedrooms}BR"
              fallback_unit = "Studio" if original_bedrooms == 0
              
              if chosen[:available_units].find { |u| canonical(u) == canonical(fallback_unit) }
                chosen[:unit_type] = fallback_unit
                chosen[:reason] = "using_fallback_maids_room"
                chosen[:fallback_message] = "⚠️ Maid's Room Detected: This property is listed as #{original_bedrooms}BR + Maid's Room (#{normalized_unit} equivalent). We only have data for standard #{fallback_unit} units. The economics shown are for #{fallback_unit} properties WITHOUT a maid's room. Your property may perform differently."
              else
                # No fallback data available either
                render json: {
                  resolver: {
                    building_name: resolved[:building_name],
                    building_name_matched: matched_building,
                    unit_type: resolved[:unit_type],
                    unit_type_normalized: normalized_unit,
                    confidence: resolved[:confidence],
                    facts: resolved[:facts]
                  },
                  selection: chosen,
                  economics: { 
                    status: "no_data", 
                    reason_code: "UNIT_TYPE_NOT_AVAILABLE", 
                    data: nil, 
                    user_message: "No data available for #{normalized_unit} or #{fallback_unit} in #{matched_building}. This property has a maid's room. Available unit types: #{chosen[:available_units].join(', ')}" 
                  },
                  listings: { status: "no_data", building_name: matched_building, unit_type: normalized_unit, count: 0, items: [] }
                }
                return
              end
            else
              # NO maid's room - don't fallback, just show error
              render json: {
                resolver: {
                  building_name: resolved[:building_name],
                  building_name_matched: matched_building,
                  unit_type: resolved[:unit_type],
                  unit_type_normalized: normalized_unit,
                  confidence: resolved[:confidence],
                  facts: resolved[:facts]
                },
                selection: chosen,
                economics: { 
                  status: "no_data", 
                  reason_code: "UNIT_TYPE_NOT_AVAILABLE", 
                  data: nil, 
                  user_message: "No data available for #{normalized_unit} in #{matched_building}. Available unit types: #{chosen[:available_units].join(', ')}" 
                },
                listings: { status: "no_data", building_name: matched_building, unit_type: normalized_unit, count: 0, items: [] }
              }
              return
            end
          end

          # Get economics data
          econ = Economics::Registry.lookup(
            building_name: matched_building,
            unit_type: chosen[:unit_type]
          )

          # IMPORTANT: If maid's room detected and we're showing data, add warning
          if has_maids_room && econ[:status] == "ok"
            if chosen[:unit_type] == normalized_unit
              # We have exact data (e.g., 3BR data for 2BR+Maid)
              chosen[:fallback_message] ||= "⚠️ Maid's Room Detected: This property is listed as #{original_bedrooms}BR + Maid's Room. Our data shows #{normalized_unit} economics, but these are for standard #{normalized_unit} units which may or may not include maid's rooms. Properties with maid's rooms may perform differently in the market."
            end
          end

          # FIXED: Only try fallback on insufficient sample if property has maid's room
          if econ[:status] == "no_data" && econ[:reason_code] == "INSUFFICIENT_SAMPLE"
            if has_maids_room && original_bedrooms
              fallback_unit = "#{original_bedrooms}BR"
              fallback_unit = "Studio" if original_bedrooms == 0
              
              if chosen[:available_units].find { |u| canonical(u) == canonical(fallback_unit) }
                fallback_econ = Economics::Registry.lookup(
                  building_name: matched_building,
                  unit_type: fallback_unit
                )
                
                if fallback_econ[:status] == "ok"
                  econ = fallback_econ
                  original_unit = chosen[:unit_type]
                  chosen[:unit_type] = fallback_unit
                  chosen[:fallback_message] = "⚠️ Maid's Room Detected: This property is listed as #{original_bedrooms}BR + Maid's Room (#{original_unit} equivalent). Insufficient data for #{original_unit} units. Showing #{fallback_unit} economics instead. Note: Our data covers standard #{fallback_unit} properties WITHOUT a maid's room. Your property may perform differently."
                end
              end
            end
          end

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
              fallback_message: chosen[:fallback_message],
              available_units: chosen[:available_units],
              has_maids_room: has_maids_room
            },
            economics: econ,
            economics_sources: sources,
            listings: lis
          }
        else
          # DON'T send resolver data when building not matched
          render json: {
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
        # DON'T send resolver data when building name not found
        render json: {
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

    def find_best_building_match(rows, query_building)
      return nil if rows.empty?
      
      csv_buildings = rows.map(&:building).uniq
      query_tokens = tokenize(query_building)
      
      best_match = nil
      best_score = 0.0
      
      csv_buildings.each do |csv_building|
        csv_tokens = tokenize(csv_building)
        score = jaccard_similarity(query_tokens, csv_tokens)
        
        if score > best_score && score >= 0.4
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
          reason: "exact_match", 
          available_units: available_units.sort 
        }
      end

      {
        unit_type: nil,
        reason: "requested_unit_not_available",
        requested_unit: requested_unit,
        available_units: available_units.sort
      }
    end

    def canonical(s)
      s.to_s.downcase.strip.gsub(/\s+/, " ")
    end
  end
end