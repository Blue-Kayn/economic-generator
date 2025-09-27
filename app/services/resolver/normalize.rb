# frozen_string_literal: true
# app/services/resolver/normalize.rb
module Resolver
  module Normalize
    module_function

    def slug(s)
      s.to_s.downcase.strip.gsub(/\s+/, " ").gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
    end

    # Map "1 bedroom" → "1BR", "Studio" → "Studio", etc.
    def unit_type_from_text(text)
      t = text.to_s.downcase
      return "Studio" if t.include?("studio")

      if (m = t.match(/(\d+)\s*bed(room)?s?/))
        return "#{m[1]}BR"
      end
      nil
    end

    def clean_building_name(name)
      return nil if name.nil?
      name = name.strip
      # collapse multiple spaces / remove trailing commas
      name = name.gsub(/\s+/, " ").gsub(/\s*,\s*$/, "")
      name
    end
  end
end
