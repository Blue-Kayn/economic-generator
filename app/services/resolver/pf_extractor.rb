# frozen_string_literal: true
# app/services/resolver/pf_extractor.rb
require "json"
require_relative "normalize"

module Resolver
  class PfExtractor
    include Resolver::Normalize

    # Returns { building_name:, unit_type:, confidence:, facts: {} }
    def self.extract(url)
      doc = PageFetcher.get(url)

      # 1) LD-JSON first (often contains name/address)
      building = nil
      unit_type = nil
      facts = {}

      doc.css('script[type="application/ld+json"]').each do |node|
        begin
          payload = JSON.parse(node.text)
          payload = [payload] unless payload.is_a?(Array)
          payload.each do |p|
            next unless p.is_a?(Hash)
            name = p["name"] || p.dig("@graph", 0, "name")
            building ||= name
            addr = p["address"]
            facts[:address] ||= addr if addr
            desc = p["description"]
            unit_type ||= Resolver::Normalize.unit_type_from_text("#{name} #{desc}")
          end
        rescue
          next
        end
      end

      # 2) Fallback to meta/title
      if building.nil?
        meta_title = doc.at('meta[property="og:title"]')&.[]("content")
        building ||= meta_title
        unit_type ||= Resolver::Normalize.unit_type_from_text(meta_title)
      end

      # 3) Try page h1/h2 text blocks for building & beds
      if building.nil?
        header = doc.at("h1")&.text || doc.at("h2")&.text
        building ||= header
        unit_type ||= Resolver::Normalize.unit_type_from_text(header)
      end

      building = Resolver::Normalize.clean_building_name(building)
      canonical = Resolver::Aliases.canonical_for(building) if building

      # Confidence heuristic
      conf = 0.5
      conf += 0.2 if canonical && canonical != building # alias normalized
      conf += 0.2 if facts[:address]
      conf += 0.1 if unit_type

      {
        building_name: canonical || building,
        unit_type: unit_type,
        confidence: conf.clamp(0.0, 1.0),
        facts: facts.compact
      }
    end
  end
end
