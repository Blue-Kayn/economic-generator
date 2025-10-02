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
      yearly_rent = nil
      facts = {}
      
      # NEW: Track maid's room detection
      has_maids_room = false
      original_bedrooms = nil

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
            
            if p["numberOfBathroomsTotal"]
              bathrooms = p["numberOfBathroomsTotal"].to_i
              facts[:bathrooms] = bathrooms
            end
            
            if p["offers"] && p["offers"]["price"]
              price = p["offers"]["price"].to_s.gsub(/[^\d]/, '').to_i
              if price >= 10_000 && price <= 10_000_000
                yearly_rent = price
                facts[:yearly_rent] = yearly_rent
              end
            end
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
      
      # Find bedrooms
      bedroom_node = doc.css('*').find { |node| node.text.match?(/Bedrooms\s*\d+/i) }
      if bedroom_node && (m = bedroom_node.text.match(/Bedrooms\s*(\d+)/i))
        bedrooms = m[1].to_i
        original_bedrooms = bedrooms  # Store original count
        facts[:bedrooms] = bedrooms
        
        # NEW: Check if there's a maid's room mentioned anywhere on the page
        full_text = doc.text.downcase
        has_maids_room = full_text.include?("+maid") || 
                         full_text.include?("+ maid") || 
                         full_text.include?("maid's room") || 
                         full_text.include?("maids room") ||
                         full_text.match?(/\bmaid\b.*\broom\b/)
        
        # Store maid's room detection in facts
        if has_maids_room
          facts[:has_maids_room] = true
          facts[:bedrooms_without_maid] = original_bedrooms
          
          # Set unit type as N+1 bedrooms
          effective_bedrooms = bedrooms + 1
          unit_type ||= effective_bedrooms == 0 ? "Studio" : "#{effective_bedrooms}BR"
          
          # Update bedrooms count to reflect maid's room
          bedrooms = effective_bedrooms
          facts[:bedrooms] = effective_bedrooms
        else
          # No maid's room
          facts[:has_maids_room] = false
          unit_type ||= bedrooms == 0 ? "Studio" : "#{bedrooms}BR"
        end
      end

      # Find bathrooms - improved multi-strategy approach
      if bathrooms.nil?
        doc.css('[class*="property"], [class*="feature"], [class*="detail"], main, [role="main"]').each do |section|
          section_text = section.text
          matches = section_text.scan(/Bathrooms?\s*:?\s*(\d+)/i)
          if matches.any?
            bathrooms = matches.last[0].to_i
            facts[:bathrooms] = bathrooms
            break
          end
        end
      end

      if bathrooms.nil?
        full_text = doc.text
        bathroom_mentions = full_text.scan(/Bathrooms?\s*:?\s*(\d+)/i).flatten.map(&:to_i)
        if bathroom_mentions.any?
          bathrooms = bathroom_mentions.group_by(&:itself).values.max_by(&:size)&.first || bathroom_mentions.last
          facts[:bathrooms] = bathrooms
        end
      end

      # Find property size (sqft or sqm)
      size_node = doc.css('*').find { |node| node.text.match?(/Property\s*Size\s*[\d,]+\s*(sqft|sqm)/i) }
      if size_node && (m = size_node.text.match(/Property\s*Size\s*([\d,]+)\s*(sqft|sqm)/i))
        size_value = m[1].gsub(',', '').to_i
        size_unit = m[2].downcase
        size = "#{size_value} #{size_unit}"
        facts[:size] = size
        facts[:size_sqft] = size_unit == "sqft" ? size_value : (size_value * 10.764).round(0)
      end

      # Find yearly rent - IMPROVED with multiple strategies
      if yearly_rent.nil?
        full_text = doc.text
        
        rent_patterns = [
          /AED\s*([\d,]+)\s*(?:\/\s*)?(?:per\s+)?year/i,
          /AED\s*([\d,]+)\s*yearly/i,
          /([\d,]+)\s*AED\s*(?:\/\s*)?(?:per\s+)?year/i,
          /([\d,]+)\s*AED\s*yearly/i,
          /Price.*?AED\s*([\d,]+)/i,
          /Rent.*?AED\s*([\d,]+)/i
        ]
        
        rent_patterns.each do |pattern|
          if (m = full_text.match(pattern))
            rent_value = m[1].gsub(',', '').to_i
            if rent_value >= 10_000 && rent_value <= 10_000_000
              yearly_rent = rent_value
              facts[:yearly_rent] = yearly_rent
              break
            end
          end
        end
      end

      if yearly_rent.nil?
        price_meta = doc.at('meta[property="product:price:amount"]')&.[]("content") ||
                     doc.at('meta[property="og:price:amount"]')&.[]("content")
        if price_meta
          rent_value = price_meta.gsub(/[^\d]/, '').to_i
          if rent_value >= 10_000 && rent_value <= 10_000_000
            yearly_rent = rent_value
            facts[:yearly_rent] = yearly_rent
          end
        end
      end

      if yearly_rent.nil?
        doc.css('[class*="price"], [class*="amount"], [data-testid*="price"]').each do |node|
          text = node.text
          if (m = text.match(/AED\s*([\d,]+)/i)) || (m = text.match(/([\d,]+)\s*AED/i))
            rent_value = m[1].gsub(',', '').to_i
            if rent_value >= 10_000 && rent_value <= 10_000_000
              yearly_rent = rent_value
              facts[:yearly_rent] = yearly_rent
              break
            end
          end
        end
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
      building = Resolver::Normalize.normalize_building(building, url)
      building = Resolver::Aliases.canonical_for(building) if building

      # If we got bedrooms from the page, make sure unit_type matches
      if bedrooms && !unit_type
        unit_type = bedrooms == 0 ? "Studio" : "#{bedrooms}BR"
      end

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