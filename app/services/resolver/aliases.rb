# frozen_string_literal: true
# app/services/resolver/aliases.rb
require "yaml"

module Resolver
  class Aliases
    @aliases = {}
    class << self
      def load!(path: Rails.root.join("data","reference","building_aliases.yml").to_s)
        @aliases = File.exist?(path) ? YAML.load_file(path) : {}
        @aliases.default = []
      end

      def canonical_for(name)
        return nil if name.to_s.strip.empty?
        key = name.to_s.downcase.strip
        # exact canonical match
        return name if @aliases.key?(key) && @aliases[key].include?("__canonical__")

        # find any canonical that lists this alias
        @aliases.each do |canonical_key, variants|
          next unless variants.is_a?(Array)
          return canonical_from_key(canonical_key) if variants.map(&:downcase).include?(key)
        end

        # fallback: return cleaned original
        name
      end

      private

      def canonical_from_key(key)
        # stored in downcase; titleize-ish for display
        key.split("_").map { |w| w == "bldg" ? "Bldg" : w.capitalize }.join(" ")
      end
    end
  end
end
