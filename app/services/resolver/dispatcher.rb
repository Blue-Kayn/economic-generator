# frozen_string_literal: true
# app/services/resolver/dispatcher.rb
module Resolver
  class Dispatcher
    def self.resolve(url)
      resolved = nil

      begin
        case url
        when /propertyfinder\./i
          resolved = PfExtractor.extract(url)
        when /bayut\./i
          resolved = BayutExtractor.extract(url)
        else
          raise ArgumentError, "Unsupported domain"
        end
      rescue => e
        Rails.logger.warn("[resolver] primary extract failed: #{e.class}: #{e.message}")
      end

      # If primary resolution failed or is incomplete, try URL guesser
      if resolved.nil? || resolved[:building_name].to_s.strip.empty? || resolved[:unit_type].to_s.strip.empty?
        guess = UrlGuesser.guess(url)
        resolved ||= guess
        # Fill missing fields from guess
        resolved = {
          building_name: resolved[:building_name] || guess[:building_name],
          unit_type:     resolved[:unit_type]     || guess[:unit_type],
          confidence:    [resolved[:confidence].to_f, guess[:confidence].to_f].max,
          facts:         (resolved[:facts] || {}).merge(guess[:facts] || {})
        }
      end

      resolved
    end
  end
end
