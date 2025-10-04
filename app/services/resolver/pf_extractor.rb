# app/services/resolver/pf_extractor.rb
# frozen_string_literal: true

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
      purchase_price = nil
      listing_type = nil  # 'rent' or 'sale'
      facts = {}
      
      # Track maid's room detection
      has_maids_room = false
      original_bedrooms = nil

      # CRITICAL: Detect listing type from URL first
      if url.match?(/\/(rent|for-rent)\//i)
        listing_type = 'rent'
      elsif url.match?(/\/(buy|for-sale|sale)\//i)
        listing_type = 'sale'
      end

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
            
            # Detect price from LD-JSON
            if p["offers"] && p["offers"]["price"]
              price = p["offers"]["price"].to_s.gsub(/[^\d]/, '').to_i
              if price >= 10_000 && price <= 100_000_000
                if listing_type == 'sale'
                  purchase_price = price
                  facts[:purchase_price] = purchase_price
                elsif listing_type == 'rent'
                  yearly_rent = price
                  facts[:yearly_rent] = yearly_rent
                end
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
        
        # Detect listing type from title if not from URL
        if listing_type.nil? && candidate
          if candidate.match?(/for rent|rent/i)
            listing_type = 'rent'
          elsif candidate.match?(/for sale|sale/i)
            listing_type = 'sale'
          end
        end
      end

      # 3) Extract bedrooms, bathrooms, size from PropertyFinder's property details section
      
      # Find bedrooms
      bedroom_node = doc.css('*').find { |node| node.text.match?(/Bedrooms\s*\d+/i) }
      if bedroom_node && (m = bedroom_node.text.match(/Bedrooms\s*(\d+)/i))
        bedrooms = m[1].to_i
        original_bedrooms = bedrooms
        facts[:bedrooms] = bedrooms
        
        # IMPROVED: Check for maid's room ONLY in property details/description sections
        property_sections = doc.css(
          '[class*="property-description"], ' \
          '[class*="property-detail"], ' \
          '[class*="PropertyDetail"], ' \
          '[data-testid*="description"], ' \
          'main, ' \
          '[role="main"]'
        )
        
        section_text = property_sections.map(&:text).join(" ").downcase
        
        # Exclude "maid service" (amenity) - only detect "maid's room" or "maid room" (bedroom feature)
        cleaned_text = section_text.gsub(/\bmaid'?s?\s+service'?s?\b/, '')
        
        # Only detect if explicitly mentioned with bedroom count OR as a room feature
        has_maids_room = cleaned_text.match?(/#{bedrooms}\s*bed.*\+.*maid/i) ||
                         cleaned_text.match?(/#{bedrooms}\s*br.*\+.*maid/i) ||
                         cleaned_text.match?(/\bmaid'?s?\s+room\b/) ||
                         cleaned_text.match?(/\+\s*maid\s+(room|bed)/i) ||
                         cleaned_text.match?(/with\s+maid'?s?\s+room/i)
        
        if has_maids_room
          facts[:has_maids_room] = true
          facts[:bedrooms_without_maid] = original_bedrooms
          effective_bedrooms = bedrooms + 1
          unit_type ||= effective_bedrooms == 0 ? "Studio" : "#{effective_bedrooms}BR"
          bedrooms = effective_bedrooms
          facts[:bedrooms] = effective_bedrooms
        else
          facts[:has_maids_room] = false
          unit_type ||= bedrooms == 0 ? "Studio" : "#{bedrooms}BR"
        end
      end

      # Find bathrooms
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

      # Find property size
      size_node = doc.css('*').find { |node| node.text.match?(/Property\s*Size\s*[\d,]+\s*(sqft|sqm)/i) }
      if size_node && (m = size_node.text.match(/Property\s*Size\s*([\d,]+)\s*(sqft|sqm)/i))
        size_value = m[1].gsub(',', '').to_i
        size_unit = m[2].downcase
        size = "#{size_value} #{size_unit}"
        facts[:size] = size
        facts[:size_sqft] = size_unit == "sqft" ? size_value : (size_value * 10.764).round(0)
      end

      # Find price - IMPROVED to distinguish rent vs sale
      if listing_type == 'rent' && yearly_rent.nil?
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
      elsif listing_type == 'sale' && purchase_price.nil?
        full_text = doc.text
        
        # Sale price patterns
        price_patterns = [
          /Price.*?AED\s*([\d,]+)/i,
          /AED\s*([\d,]+)/i,
          /([\d,]+)\s*AED/i
        ]
        
        price_patterns.each do |pattern|
          if (m = full_text.match(pattern))
            price_value = m[1].gsub(',', '').to_i
            # Sale prices are typically much higher than rent
            if price_value >= 100_000 && price_value <= 100_000_000
              purchase_price = price_value
              facts[:purchase_price] = purchase_price
              break
            end
          end
        end
      end

      # Try meta tags for price if still not found
      if listing_type == 'rent' && yearly_rent.nil?
        price_meta = doc.at('meta[property="product:price:amount"]')&.[]("content") ||
                     doc.at('meta[property="og:price:amount"]')&.[]("content")
        if price_meta
          rent_value = price_meta.gsub(/[^\d]/, '').to_i
          if rent_value >= 10_000 && rent_value <= 10_000_000
            yearly_rent = rent_value
            facts[:yearly_rent] = yearly_rent
          end
        end
      elsif listing_type == 'sale' && purchase_price.nil?
        price_meta = doc.at('meta[property="product:price:amount"]')&.[]("content") ||
                     doc.at('meta[property="og:price:amount"]')&.[]("content")
        if price_meta
          price_value = price_meta.gsub(/[^\d]/, '').to_i
          if price_value >= 100_000 && price_value <= 100_000_000
            purchase_price = price_value
            facts[:purchase_price] = price_value
          end
        end
      end

      # Try price nodes
      if (listing_type == 'rent' && yearly_rent.nil?) || (listing_type == 'sale' && purchase_price.nil?)
        doc.css('[class*="price"], [class*="amount"], [data-testid*="price"]').each do |node|
          text = node.text
          if (m = text.match(/AED\s*([\d,]+)/i)) || (m = text.match(/([\d,]+)\s*AED/i))
            price_value = m[1].gsub(',', '').to_i
            
            if listing_type == 'rent' && price_value >= 10_000 && price_value <= 10_000_000
              yearly_rent = price_value
              facts[:yearly_rent] = yearly_rent
              break
            elsif listing_type == 'sale' && price_value >= 100_000 && price_value <= 100_000_000
              purchase_price = price_value
              facts[:purchase_price] = purchase_price
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

      # Add listing_type to facts
      facts[:listing_type] = listing_type if listing_type

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