# frozen_string_literal: true
# app/services/resolver/pf_extractor.rb
require "json"
require_relative "normalize"
require_relative "aliases"
require_relative "page_fetcher"

module Resolver
  class PfExtractor
    def self.extract(url)
      doc = PageFetcher.get(url)

      building = nil
      unit_type = nil
      facts = {}

      # 1) LD-JSON
      doc.css('script[type="application/ld+json"]').each do |node|
        begin
          payload = JSON.parse(node.text)
          payload = [payload] unless payload.is_a?(Array)
          payload.each do |p|
            next unless p.is_a?(Hash)
            name = p["name"] || p.dig("@graph", 0, "name")
            desc = p["description"] || p.dig("@graph", 0, "description")
            building ||= name
            unit_type ||= Resolver::Normalize.unit_type_from_text("#{name} #{desc}")
            facts[:address] ||= p["address"] if p["address"]
          end
        rescue
          next
        end
      end

      # 2) og:title / <title>
      if building.nil?
        meta_title = doc.at('meta[property="og:title"]')&.[]("content")
        page_title = doc.at("title")&.text
        candidate  = meta_title || page_title
        building ||= candidate
        unit_type ||= Resolver::Normalize.unit_type_from_text(candidate)
      end

      # 3) Meta description
      if unit_type.nil?
        meta_desc = doc.at('meta[name="description"]')&.[]("content")
        unit_type ||= Resolver::Normalize.unit_type_from_text(meta_desc)
      end

      # 4) URL path fallback
      if unit_type.nil?
        unit_type ||= Resolver::Normalize.unit_type_from_text(url)
      end

      # Normalize & alias
      building = Resolver::Normalize.normalize_building(building)
      building = Resolver::Aliases.canonical_for(building) if building
      unit_type ||= Resolver::Normalize.unit_type_from_text(building)

      conf = 0.5
      conf += 0.2 if building
      conf += 0.3 if unit_type

      {
        building_name: building,
        unit_type: unit_type,
        confidence: conf.clamp(0.0, 1.0),
        facts: facts.compact
      }
    end
  end
end
