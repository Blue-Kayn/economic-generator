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
      bedrooms = nil
      bathrooms = nil
      size = nil
      facts = {}

      # 1) Try LD-JSON first
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

      # 2) Try og:title / <title>
      if building.nil?
        meta_title = doc.at('meta[property="og:title"]')&.[]("content")
        page_title = doc.at("title")&.text
        candidate  = meta_title || page_title
        building ||= candidate
        unit_type ||= Resolver::Normalize.unit_type_from_text(candidate)
      end

      # 3) Extract bedrooms, bathrooms, size from PropertyFinder's property details section
      # PropertyFinder displays these as: "Bedrooms1", "Bathrooms2", "Property Size715 sqft"
      
      # Find bedrooms
      bedroom_node = doc.css('*').find { |node| node.text.match?(/Bedrooms\s*\d+/i) }
      if bedroom_node && (m = bedroom_node.text.match(/Bedrooms\s*(\d+)/i))
        bedrooms = m[1].to_i
        unit_type ||= bedrooms == 0 ? "Studio" : "#{bedrooms}BR"
        facts[:bedrooms] = bedrooms
      end

      # Find bathrooms
      bathroom_node = doc.css('*').find { |node| node.text.match?(/Bathrooms\s*\d+/i) }
      if bathroom_node && (m = bathroom_node.text.match(/Bathrooms\s*(\d+)/i))
        bathrooms = m[1].to_i
        facts[:bathrooms] = bathrooms
      end

      # Find property size (sqft or sqm)
      size_node = doc.css('*').find { |node| node.text.match?(/Property\s*Size\s*[\d,]+\s*(sqft|sqm)/i) }
      if size_node && (m = size_node.text.match(/Property\s*Size\s*([\d,]+)\s*(sqft|sqm)/i))
        size_value = m[1].gsub(',', '')
        size_unit = m[2].downcase
        size = "#{size_value} #{size_unit}"
        facts[:size] = size
      end

      # 4) Meta description fallback
      if unit_type.nil?
        meta_desc = doc.at('meta[name="description"]')&.[]("content")
        unit_type ||= Resolver::Normalize.unit_type_from_text(meta_desc)
      end

      # 5) URL path fallback
      if unit_type.nil?
        unit_type ||= Resolver::Normalize.unit_type_from_text(url)
      end

      # Normalize & alias
      building = Resolver::Normalize.normalize_building(building)
      building = Resolver::Aliases.canonical_for(building) if building

      # If we got bedrooms from the page, make sure unit_type matches
      if bedrooms && !unit_type
        unit_type = bedrooms == 0 ? "Studio" : "#{bedrooms}BR"
      end

      # Add bedrooms to facts if we determined unit_type but didn't find it explicitly
      if unit_type && !facts[:bedrooms]
        if unit_type == "Studio"
          facts[:bedrooms] = 0
        elsif unit_type.match?(/(\d+)BR/)
          facts[:bedrooms] = unit_type.match(/(\d+)BR/)[1].to_i
        end
      end

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