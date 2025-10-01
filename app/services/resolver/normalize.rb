# frozen_string_literal: true
# app/services/resolver/normalize.rb
#
# Normalization helpers:
# - collapse noisy PF/Bayut titles into clean building names
# - infer unit type from URL/text

module Resolver
  module Normalize
    module_function

    # Turn text into safe slug
    def slug(s)
      s.to_s.downcase.strip.gsub(/\s+/, " ").gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
    end

    # Try to extract a unit type from free text or URL
    # => "Studio", "1BR", "2BR", ...
    def unit_type_from_text(text)
      t = text.to_s.downcase
      return "Studio" if t.include?("studio")
      return "1BR" if t.include?("1br") || t.include?("1 bed")
      return "2BR" if t.include?("2br") || t.include?("2 bed")
      return "3BR" if t.include?("3br") || t.include?("3 bed")
      return "4BR" if t.include?("4br") || t.include?("4 bed")
      nil
    end

    # Given a long building/title string, collapse to a clean building name
    # Strips common PropertyFinder/Bayut prefixes and suffixes
    def normalize_building(raw)
      return nil if raw.nil?
      str = raw.strip
      
      # Strip common prefixes (case insensitive)
      str = str.sub(/\A(rent in|for rent in|for sale in|buy in|apartment (for )?(rent|sale) in)\s+/i, '')
      
      # Strip everything after | or : (usually property features/descriptions)
      str = str.split(/\s*[\|:]\s*/).first || str
      
      # Strip trailing " | Property Finder" or similar
      str = str.sub(/\s*\|\s*property\s*finder\s*\z/i, '')
      str = str.sub(/\s*-\s*property\s*finder\s*\z/i, '')
      
      # Strip "Apartment" or "Villa" at the start if followed by "in"
      str = str.sub(/\A(apartment|villa|townhouse|penthouse)\s+(in\s+)?/i, '')
      
      # Clean up whitespace
      str = str.strip.gsub(/\s+/, ' ')
      
      # If we ended up with something too short or generic, return nil
      return nil if str.length < 3
      return nil if str.downcase.match?(/\A(dubai|palm jumeirah|jumeirah)\z/)
      
      str
    end
  end
end