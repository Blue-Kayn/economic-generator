# frozen_string_literal: true
# app/services/resolver/normalize.rb

module Resolver
  module Normalize
    module_function

    KNOWN_BUILDINGS = [
      "Shoreline Apartments",
      "Seven Palm Jumeirah",
      "Seven Palm",
      "The Palm Tower",
      "Palm Tower",
      "Five Palm Jumeirah",
      "Five Palm",
      "Fairmont Palm Residences",
      "Palm Views",
      "Marina Residences",
      "Azure Residences",
      "Tiara Residences",
      "Oceana Residences",
      "The Royal Amwaj",
      "Royal Amwaj",
      "Th8",
      "Balqis Residence",
      "Grandeur Residences",
      "Jumeirah Zabeel Saray",
      "Azizi Mina",
      "Sarai Apartments",
      "Rixos Hotel",
      "Club Vista Mare"
    ].freeze

    def slug(s)
      s.to_s.downcase.strip.gsub(/\s+/, " ").gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
    end

    def unit_type_from_text(text)
      t = text.to_s.downcase
      return "Studio" if t.include?("studio")
      
      # Handle "2BR + Maid" or "2 bed + maid" = treat as 3BR
      if t.match?(/(\d+)\s*(bed|br|bhk).*maid/i)
        num = t.match(/(\d+)\s*(bed|br|bhk)/i)[1].to_i
        return "#{num + 1}BR"  # Add 1 to account for maid's room
      end
      
      return "1BR" if t.include?("1br") || t.include?("1 bed")
      return "2BR" if t.include?("2br") || t.include?("2 bed")
      return "3BR" if t.include?("3br") || t.include?("3 bed")
      return "4BR" if t.include?("4br") || t.include?("4 bed")
      nil
    end

    def normalize_building(raw, url = nil)
      return nil if raw.nil? && url.nil?
      
      if raw
        text_lower = raw.to_s.downcase
        KNOWN_BUILDINGS.each do |known_building|
          return known_building if text_lower.include?(known_building.downcase)
        end
      end
      
      if url
        url_lower = url.to_s.downcase
        KNOWN_BUILDINGS.each do |known_building|
          if url_lower.include?(known_building.downcase.gsub(/\s+/, '-')) ||
             url_lower.include?(known_building.downcase.gsub(/\s+/, ''))
            return known_building
          end
        end
      end
      
      return nil unless raw
      
      str = raw.strip
      str = str.sub(/\A(rent in|for rent in|for sale in|buy in|apartment (for )?(rent|sale) in)\s+/i, '')
      str = str.split(/\s*[\|:]\s*/).first || str
      str = str.sub(/\s*\|\s*property\s*finder\s*\z/i, '')
      str = str.sub(/\s*-\s*property\s*finder\s*\z/i, '')
      str = str.sub(/\A(apartment|villa|townhouse|penthouse)\s+(in\s+)?/i, '')
      str = str.strip.gsub(/\s+/, ' ')
      
      return nil if str.length < 3
      return nil if str.downcase.match?(/\A(dubai|palm jumeirah|jumeirah)\z/)
      
      str
    end
  end
end