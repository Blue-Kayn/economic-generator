# frozen_string_literal: true
# app/services/economics/registry.rb
require "csv"
require "date"

module Economics
  Result = Struct.new(:status, :reason_code, :metrics, keyword_init: true)

  class Registry
    class << self
      def fetch(building_name:, unit_type:)
        ensure_loaded!
        key = [slug(building_name), slug(unit_type)]
        row = @store[key]
        return Result.new(status: "no_data", reason_code: "NOT_FOUND", metrics: nil) unless row

        return Result.new(status: "no_data", reason_code: "INSUFFICIENT_SAMPLE", metrics: nil) if row[:sample_n].to_i < min_sample
        return Result.new(status: "no_data", reason_code: "STALE_DATA", metrics: nil) if stale?(row[:asof])

        Result.new(
          status: "ok",
          metrics: {
            adr_p50: row[:adr_p50],
            adr_p75: row[:adr_p75],
            occ_p50: row[:occ_p50],
            occ_p75: row[:occ_p75],
            rev_p50: row[:rev_p50],
            rev_p75: row[:rev_p75],
            sample_n: row[:sample_n],
            asof: row[:asof],
            method_version: "1.0"
          }
        )
      end

      def reload!
        path = csv_path
        raise ArgumentError, "Economics CSV not found: #{path}" unless File.exist?(path)
        @store = {}

        CSV.foreach(path, headers: true) do |r|
          b = r["building_name"]&.strip
          u = r["unit_type"]&.strip
          next if b.to_s.empty? || u.to_s.empty?

          @store[[slug(b), slug(u)]] = {
            adr_p50: f(r["adr_p50"]), adr_p75: f(r["adr_p75"]),
            occ_p50: f(r["occ_p50"]), occ_p75: f(r["occ_p75"]),
            rev_p50: f(r["rev_p50"]), rev_p75: f(r["rev_p75"]),
            sample_n: i(r["sample_n"]), asof: r["asof"]&.strip
          }
        end
        @loaded_at = Time.now
      end

      private

      def ensure_loaded!; (@store && @loaded_at) ? true : reload!; end
      def csv_path; ENV["ECON_CSV_PATH"].presence || Rails.root.join("data","reference","economics_apartments.csv").to_s; end
      def min_sample; (ENV["ECON_MIN_SAMPLE"] || "8").to_i; end
      def max_age_days; (ENV["ECON_MAX_AGE_DAYS"] || "21").to_i; end
      def stale?(asof_str); asof = (Date.parse(asof_str) rescue nil); asof.nil? || (Date.today - asof).to_i > max_age_days; end
      def slug(s); s.to_s.downcase.strip.gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, ""); end
      def f(v); v.nil? ? nil : Float(v) rescue nil; end
      def i(v); v.nil? ? nil : Integer(v) rescue nil; end
    end
  end
end
