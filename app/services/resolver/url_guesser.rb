# frozen_string_literal: true
# app/services/resolver/url_guesser.rb
require_relative "normalize"

module Resolver
  class UrlGuesser
    TOKENS_TO_BUILDING = {
      /palm[-_]?views/     => "Palm Views",
      /palm[-_]?tower/     => "Palm Tower",
      /seven[-_]?palm/     => "Seven Palm",
      /shoreline.*\b(\d{1,2})\b/ => "Shoreline Bldg \\1"
    }.freeze

    UNIT_REGEXES = [
      [/studio/,       "Studio"],
      [/(\d+)\s*[-_ ]*\s*bed(room)?s?/i, ->(m){ "#{m[1]}BR" }]
    ].freeze

    def self.guess(url)
      path = URI(url).path.to_s.downcase

      building_name = nil
      TOKENS_TO_BUILDING.each do |rx, repl|
        if (m = path.match(rx))
          building_name = repl.is_a?(String) ? repl.gsub("\\1", (m[1] || "")) : repl.call(m)
          break
        end
      end

      unit_type = nil
      UNIT_REGEXES.each do |rx, val|
        if (m = path.match(rx))
          unit_type = val.is_a?(Proc) ? val.call(m) : val
          break
        end
      end

      # Normalize through alias map if we got anything
      if building_name
        building_name = Resolver::Aliases.canonical_for(building_name)
      end

      conf = 0.4
      conf += 0.3 if building_name
      conf += 0.3 if unit_type

      {
        building_name: building_name,
        unit_type: unit_type,
        confidence: conf.clamp(0.0, 1.0),
        facts: { source: "url_guess" }
      }
    rescue
      { building_name: nil, unit_type: nil, confidence: 0.0, facts: { source: "url_guess_error" } }
    end
  end
end
