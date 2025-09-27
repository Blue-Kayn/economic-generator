# frozen_string_literal: true
# app/services/economics/correction.rb
#
# Uses your Palm Jumeirah Studio reference CSVs (revpar/occ/rate series)
# to derive a correction factor so annual revenue reflects market RevPAR.
#
# Formula:
#   base_rev = ADR * Occ * 365
#   factor   = clamp( mean(RevPAR_series) / (ADR * Occ), MIN..MAX )
#   corrected_rev = base_rev * factor
#
# Enable/disable with ENV:
#   ECON_CORRECTION_PALM_STUDIOS=1 (default 1)
# Bounds (defaults):
#   ECON_CORR_MIN=0.70  ECON_CORR_MAX=1.30
#
# Expected files (already provided by you) in data/reference/ :
#   - revpar_last_12_month.csv  (must contain a numeric 'value' column; one row per day/month)
#
require "csv"

module Economics
  module Correction
    module PalmStudios
      module_function

      def enabled?
        (ENV["ECON_CORRECTION_PALM_STUDIOS"] || "1") != "0"
      end

      def applies_to?(building_name:, unit_type:)
        return false unless enabled?
        return false unless unit_type.to_s.strip.casecmp("Studio").zero?
        # Treat any building that contains "palm" as Palm Jumeirah for studios; expand later if needed.
        building_name.to_s.downcase.include?("palm")
      end

      def factor_for(adr:, occ:)
        return 1.0 if adr.nil? || occ.nil? || adr <= 0 || occ <= 0
        revpar_mean = mean_revpar
        return 1.0 if revpar_mean.nil? || revpar_mean <= 0

        base_revpar = adr * occ
        raw_factor  = revpar_mean / base_revpar
        clamp(raw_factor, min_factor, max_factor)
      rescue
        1.0
      end

      def correct_revenue(adr:, occ:, annual_rev:)
        return annual_rev if annual_rev.nil?
        (annual_rev * factor_for(adr: adr, occ: occ)).round(0)
      end

      # -------- internals --------
      def mean_revpar
        return @mean_revpar if defined?(@mean_revpar)

        path = revpar_path
        unless File.exist?(path)
          @mean_revpar = nil
          return nil
        end

        vals = []
        CSV.foreach(path, headers: true) do |r|
          v = to_f(r["value"]) || to_f(r["revpar"]) || to_f(r["RevPAR"])
          vals << v if v && v > 0
        end
        @mean_revpar = vals.empty? ? nil : (vals.sum / vals.size.to_f)
      rescue
        @mean_revpar = nil
      end

      def revpar_path
        ENV["ECON_CORR_PALM_STUDIOS_REVPAR"].presence ||
          Rails.root.join("data", "reference", "revpar_last_12_month.csv").to_s
      end

      def min_factor
        (ENV["ECON_CORR_MIN"] || "0.70").to_f
      end

      def max_factor
        (ENV["ECON_CORR_MAX"] || "1.30").to_f
      end

      def clamp(x, lo, hi)
        [[x, lo].max, hi].min
      end

      def to_f(x)
        Float(x) rescue nil
      end
    end
  end
end
