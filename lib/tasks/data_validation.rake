# frozen_string_literal: true
# lib/tasks/data_validation.rake
#
# Rake tasks to validate CSV data integrity

namespace :data do
  desc "Validate palm_master_clean.csv data integrity"
  task validate: :environment do
    csv_path = ENV["MASTER_SHEET_CSV"].presence ||
               Rails.root.join("data", "reference", "palm_master_clean.csv").to_s

    unless File.exist?(csv_path)
      puts "❌ CSV file not found: #{csv_path}"
      exit 1
    end

    puts "🔍 Validating CSV: #{csv_path}"
    puts ""

    errors = []
    warnings = []
    stats = {
      total_rows: 0,
      buildings: Set.new,
      unit_types: Set.new,
      missing_revenue: 0,
      missing_occupancy: 0,
      missing_adr: 0,
      invalid_days: 0,
      duplicate_ids: []
    }

    airbnb_ids = Hash.new(0)

    CSV.foreach(csv_path, headers: true).with_index(2) do |row, line_num|
      stats[:total_rows] += 1

      # Check required fields
      airbnb_id = row["airbnb_id"]
      building = row["building"]
      bedrooms = row["bedrooms"]
      revenue = row["revenue"]
      occupancy = row["occupancy"]
      days_available = row["days_available"]
      adr = row["adr"]

      # Validate airbnb_id
      if airbnb_id.blank?
        errors << "Line #{line_num}: Missing airbnb_id"
      else
        airbnb_ids[airbnb_id] += 1
        stats[:buildings] << building if building.present?
      end

      # Validate building
      errors << "Line #{line_num}: Missing building name" if building.blank?

      # Validate bedrooms
      if bedrooms.blank?
        warnings << "Line #{line_num}: Missing bedrooms"
      else
        stats[:unit_types] << normalize_unit_type(bedrooms)
      end

      # Validate revenue
      if revenue.blank? || revenue.to_f <= 0
        stats[:missing_revenue] += 1
        warnings << "Line #{line_num}: Invalid revenue (#{revenue})"
      end

      # Validate occupancy
      if occupancy.blank?
        stats[:missing_occupancy] += 1
      elsif occupancy.to_f < 0 || occupancy.to_f > 1.1
        warnings << "Line #{line_num}: Suspicious occupancy (#{occupancy})"
      end

      # Validate days_available
      days = days_available.to_i
      if days < 1 || days > 365
        stats[:invalid_days] += 1
        errors << "Line #{line_num}: Invalid days_available (#{days_available})"
      end

      # Validate ADR
      if adr.blank? || adr.to_f <= 0
        stats[:missing_adr] += 1
        warnings << "Line #{line_num}: Invalid ADR (#{adr})"
      end
    end

    # Check for duplicate IDs
    airbnb_ids.each do |id, count|
      stats[:duplicate_ids] << id if count > 1
    end

    # Print results
    puts "📊 Statistics:"
    puts "  Total rows: #{stats[:total_rows]}"
    puts "  Unique buildings: #{stats[:buildings].size}"
    puts "  Unit types: #{stats[:unit_types].to_a.sort.join(', ')}"
    puts "  Missing revenue: #{stats[:missing_revenue]}"
    puts "  Missing occupancy: #{stats[:missing_occupancy]}"
    puts "  Missing ADR: #{stats[:missing_adr]}"
    puts "  Invalid days_available: #{stats[:invalid_days]}"
    puts "  Duplicate Airbnb IDs: #{stats[:duplicate_ids].size}"
    puts ""

    if errors.any?
      puts "❌ Errors found (#{errors.size}):"
      errors.first(10).each { |e| puts "  - #{e}" }
      puts "  ... and #{errors.size - 10} more" if errors.size > 10
      puts ""
    end

    if warnings.any?
      puts "⚠️  Warnings (#{warnings.size}):"
      warnings.first(10).each { |w| puts "  - #{w}" }
      puts "  ... and #{warnings.size - 10} more" if warnings.size > 10
      puts ""
    end

    if errors.empty? && warnings.empty?
      puts "✅ All validations passed!"
    else
      puts "❌ Validation completed with issues"
      exit 1 if errors.any?
    end
  end

  desc "Generate data quality report"
  task report: :environment do
    Economics::Registry.reload!
    
    puts "📈 Economics Registry Report"
    puts "=" * 50
    
    # Sample different building/unit combinations
    test_cases = [
      ["Seven Palm Jumeirah", "Studio"],
      ["Seven Palm Jumeirah", "1BR"],
      ["Seven Palm Jumeirah", "2BR"],
      ["The Palm Tower", "1BR"],
      ["Five Palm Jumeirah", "1BR"],
      ["Palm Views", "Studio"]
    ]
    
    test_cases.each do |building, unit_type|
      result = Economics::Registry.lookup(
        building_name: building,
        unit_type: unit_type
      )
      
      status_icon = result[:status] == "ok" ? "✅" : "❌"
      
      puts "\n#{status_icon} #{building} - #{unit_type}"
      
      if result[:status] == "ok"
        data = result[:data]
        puts "  Sample size: #{data[:sample_n]}"
        puts "  Revenue p50: AED #{data[:rev_p50].to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
        puts "  Occupancy p50: #{data[:occ_p50]}%"
        puts "  ADR p50: AED #{data[:adr_p50]}"
        puts "  Truth count: #{data[:truth_count]}"
        puts "  Scaled count: #{data[:scaled_count]}"
      else
        puts "  Reason: #{result[:reason_code]}"
      end
    end
    
    puts "\n" + "=" * 50
  end

  private

  def normalize_unit_type(bedrooms)
    b = bedrooms.to_s.strip
    return "Studio" if b == "0" || b.downcase.include?("studio")
    return "#{b}BR" if b.match?(/^\d+$/)
    b
  end
end