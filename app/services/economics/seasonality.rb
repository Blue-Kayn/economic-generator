# frozen_string_literal: true
# app/services/economics/seasonality.rb
#
# Stores AirDNA monthly seasonality patterns for Palm Jumeirah by unit type.
# Data from Sept 2024 - Aug 2025 cycle (your 12-month insights).
#
# Usage:
#   Economics::Seasonality.monthly_revenue_share("Studio", 12) # => 0.115 (Dec is 11.5% of annual)
#   Economics::Seasonality.monthly_adr("2BR", 1) # => 1401 (Jan ADR for 2BR)

module Economics
  module Seasonality
    # Your AirDNA data converted to month number (1=Jan, 12=Dec)
    # We'll use 2024-09 through 2025-08 as the reference year
    
    MONTHLY_DATA = {
      "Studio" => {
        # Month number => { revenue, occupancy (%), adr, revpar }
        9  => { revenue: 7530,   occ: 77.43, adr: 383,  revpar: 296.46 },  # Sep
        10 => { revenue: 13765,  occ: 88.65, adr: 576,  revpar: 510.93 },  # Oct
        11 => { revenue: 15980,  occ: 86.35, adr: 669,  revpar: 577.60 },  # Nov
        12 => { revenue: 14131,  occ: 73.92, adr: 712,  revpar: 526.44 },  # Dec
        1  => { revenue: 15632,  occ: 84.26, adr: 664,  revpar: 559.85 },  # Jan
        2  => { revenue: 15455,  occ: 93.02, adr: 629,  revpar: 585.54 },  # Feb
        3  => { revenue: 11288,  occ: 73.03, adr: 544,  revpar: 397.53 },  # Mar
        4  => { revenue: 13655,  occ: 92.17, adr: 558,  revpar: 514.27 },  # Apr
        5  => { revenue: 9591,   occ: 74.67, adr: 456,  revpar: 340.60 },  # May
        6  => { revenue: 6188,   occ: 57.14, adr: 384,  revpar: 219.50 },  # Jun
        7  => { revenue: 4955,   occ: 63.06, adr: 278,  revpar: 175.07 },  # Jul
        8  => { revenue: 4986,   occ: 67.06, adr: 287,  revpar: 192.57 }   # Aug
      },
      "1BR" => {
        9  => { revenue: 9789,   occ: 77.05, adr: 509,  revpar: 392.22 },
        10 => { revenue: 16377,  occ: 86.22, adr: 691,  revpar: 595.93 },
        11 => { revenue: 18505,  occ: 86.39, adr: 783,  revpar: 676.61 },
        12 => { revenue: 17998,  occ: 74.51, adr: 861,  revpar: 641.58 },
        1  => { revenue: 18489,  occ: 81.00, adr: 785,  revpar: 636.20 },
        2  => { revenue: 17218,  occ: 88.95, adr: 746,  revpar: 663.24 },
        3  => { revenue: 14543,  occ: 76.09, adr: 663,  revpar: 504.78 },
        4  => { revenue: 17757,  occ: 93.11, adr: 685,  revpar: 637.51 },
        5  => { revenue: 12217,  occ: 77.37, adr: 543,  revpar: 420.26 },
        6  => { revenue: 8139,   occ: 60.17, adr: 469,  revpar: 282.10 },
        7  => { revenue: 6550,   occ: 60.72, adr: 374,  revpar: 226.87 },
        8  => { revenue: 7258,   occ: 69.14, adr: 387,  revpar: 267.78 }
      },
      "2BR" => {
        9  => { revenue: 13587,  occ: 62.51, adr: 846,   revpar: 528.72 },
        10 => { revenue: 29289,  occ: 83.05, adr: 1277,  revpar: 1060.47 },
        11 => { revenue: 31589,  occ: 80.76, adr: 1425,  revpar: 1150.60 },
        12 => { revenue: 31531,  occ: 70.78, adr: 1556,  revpar: 1101.45 },
        1  => { revenue: 30203,  occ: 77.26, adr: 1401,  revpar: 1082.59 },
        2  => { revenue: 28208,  occ: 82.61, adr: 1316,  revpar: 1087.49 },
        3  => { revenue: 21738,  occ: 68.72, adr: 1117,  revpar: 767.99 },
        4  => { revenue: 30282,  occ: 90.21, adr: 1240,  revpar: 1118.58 },
        5  => { revenue: 18777,  occ: 70.49, adr: 959,   revpar: 676.28 },
        6  => { revenue: 14165,  occ: 60.88, adr: 815,   revpar: 496.09 },
        7  => { revenue: 12460,  occ: 65.32, adr: 687,   revpar: 448.57 },
        8  => { revenue: 13057,  occ: 67.35, adr: 714,   revpar: 480.67 }
      },
      "3BR" => {
        9  => { revenue: 25627,  occ: 64.74, adr: 1586,  revpar: 1026.72 },
        10 => { revenue: 46109,  occ: 81.99, adr: 1999,  revpar: 1638.67 },
        11 => { revenue: 44545,  occ: 71.71, adr: 2273,  revpar: 1629.69 },
        12 => { revenue: 49189,  occ: 70.08, adr: 2451,  revpar: 1717.88 },
        1  => { revenue: 45500,  occ: 73.71, adr: 2163,  revpar: 1594.64 },
        2  => { revenue: 40794,  occ: 80.42, adr: 2000,  revpar: 1608.19 },
        3  => { revenue: 33094,  occ: 69.74, adr: 1663,  revpar: 1159.84 },
        4  => { revenue: 50162,  occ: 89.04, adr: 1973,  revpar: 1757.10 },
        5  => { revenue: 34424,  occ: 74.18, adr: 1574,  revpar: 1167.57 },
        6  => { revenue: 22366,  occ: 66.38, adr: 1240,  revpar: 823.29 },
        7  => { revenue: 20246,  occ: 71.84, adr: 1123,  revpar: 806.51 },
        8  => { revenue: 21189,  occ: 75.23, adr: 1206,  revpar: 907.17 }
      },
      "4BR" => {
        9  => { revenue: 33332,  occ: 68.08, adr: 1695,  revpar: 1153.81 },
        10 => { revenue: 47116,  occ: 78.42, adr: 2161,  revpar: 1694.81 },
        11 => { revenue: 55795,  occ: 72.82, adr: 2728,  revpar: 1986.24 },
        12 => { revenue: 56258,  occ: 72.20, adr: 2738,  revpar: 1977.13 },
        1  => { revenue: 61017,  occ: 85.22, adr: 2477,  revpar: 2110.64 },
        2  => { revenue: 54589,  occ: 78.83, adr: 2481,  revpar: 1955.95 },
        3  => { revenue: 43681,  occ: 72.21, adr: 2010,  revpar: 1451.63 },
        4  => { revenue: 58456,  occ: 87.23, adr: 2296,  revpar: 2003.17 },
        5  => { revenue: 38006,  occ: 75.00, adr: 1720,  revpar: 1290.32 },
        6  => { revenue: 35166,  occ: 71.56, adr: 1689,  revpar: 1208.83 },
        7  => { revenue: 31873,  occ: 79.54, adr: 1323,  revpar: 1051.92 },
        8  => { revenue: 26488,  occ: 75.45, adr: 1394,  revpar: 1051.88 }
      }
    }.freeze

    class << self
      # Get total annual revenue for a unit type (sum of all months)
      def annual_revenue(unit_type)
        data = MONTHLY_DATA[normalize_unit_type(unit_type)]
        return 0 unless data
        data.values.sum { |m| m[:revenue] }
      end

      # Get what % of annual revenue comes from a specific month
      def monthly_revenue_share(unit_type, month_num)
        data = MONTHLY_DATA[normalize_unit_type(unit_type)]
        return 0.0833 unless data # fallback to 1/12
        
        total = annual_revenue(unit_type)
        return 0.0833 if total.zero?
        
        month_data = data[month_num]
        return 0.0833 unless month_data
        
        month_data[:revenue].to_f / total
      end

      # Get ADR for a specific month
      def monthly_adr(unit_type, month_num)
        data = MONTHLY_DATA[normalize_unit_type(unit_type)]
        return 0 unless data
        data.dig(month_num, :adr) || 0
      end

      # Get occupancy for a specific month
      def monthly_occ(unit_type, month_num)
        data = MONTHLY_DATA[normalize_unit_type(unit_type)]
        return 0 unless data
        data.dig(month_num, :occ) || 0
      end

      # FIXED: Calculate which days are missing per month (handles partial months)
      # Returns hash: { month_num => days_missing_in_that_month }
      def missing_days_per_month(days_available, data_end_date = Date.new(2025, 9, 22))
        return {} if days_available >= 365
        
        data_start_date = data_end_date - days_available.days + 1.day
        full_year_start = data_end_date - 364.days
        
        # For each month in the full year, calculate how many days are missing
        missing_days = {}
        
        (1..12).each do |month|
          # Find all dates in this month within the full year window
          month_dates = []
          current = full_year_start
          while current <= data_end_date
            month_dates << current if current.month == month
            current += 1.day
          end
          
          # Count how many of those dates are NOT in the available data window
          missing_count = month_dates.count { |date| date < data_start_date || date > data_end_date }
          
          missing_days[month] = missing_count if missing_count > 0
        end
        
        missing_days
      end

      # FIXED: Calculate seasonal multiplier based on actual missing days
      # Returns ratio of "missing revenue" / "covered revenue"
      def missing_months_multiplier(unit_type, days_available)
        missing_days = missing_days_per_month(days_available)
        return 0.0 if missing_days.empty?
        
        data = MONTHLY_DATA[normalize_unit_type(unit_type)]
        return 0.0 unless data
        
        # Calculate what % of revenue is missing
        total_missing_revenue = 0.0
        total_annual_revenue = annual_revenue(unit_type).to_f
        
        missing_days.each do |month, days_missing|
          month_data = data[month]
          next unless month_data
          
          days_in_month = Date.new(2025, month, -1).day # get last day of month
          month_revenue = month_data[:revenue].to_f
          
          # Pro-rate the month's revenue by missing days
          missing_revenue = (month_revenue / days_in_month) * days_missing
          total_missing_revenue += missing_revenue
        end
        
        covered_revenue = total_annual_revenue - total_missing_revenue
        return 0.0 if covered_revenue.zero?
        
        total_missing_revenue / covered_revenue
      end

      # For backward compatibility - returns full missing months only
      def missing_months(days_available, data_end_date = Date.new(2025, 9, 22))
        missing_days = missing_days_per_month(days_available, data_end_date)
        
        # Only return months where the entire month (or most of it) is missing
        missing_days.select { |month, days| days >= 25 }.keys
      end

      private

      def normalize_unit_type(unit_type)
        s = unit_type.to_s.strip
        return "Studio" if s.match?(/studio/i) || s == "0BR" || s == "0"
        return "1BR" if s.match?(/^1/i)
        return "2BR" if s.match?(/^2/i)
        return "3BR" if s.match?(/^3/i)
        return "4BR" if s.match?(/^4/i)
        s
      end
    end
  end
end