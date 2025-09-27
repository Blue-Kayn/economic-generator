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

    # Given a long building/title string, collapse to a known alias/canonical.
    def normalize_building(raw)
      return nil if raw.nil?
      str = raw.strip.downcase

      # Known patterns
      return "Palm Views"  if str.include?("palm views")
      return "Palm Tower"  if str.include?("palm tower")
      return "Seven Palm"  if str.include?("seven palm")
      return "Shoreline"   if str.include?("shoreline")

      # Fallback: truncate to first 5 words
      raw.split(/\s+/)[0..4].join(" ")
    end
  end
end
