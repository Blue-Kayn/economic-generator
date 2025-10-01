module Economics
  class Registry
    class << self
      # Main entrypoint: look up building/unit and return economics + listings
      def lookup(building_name:, unit_type:)
        rows = load_csv

        # filter dataset for building + unit_type
        candidates = rows.select do |row|
          row[:building] == building_name && row[:unit_type] == unit_type
        end

        # compute sample stats
        expanded = candidates.map do |row|
          days_avail = row[:days_available].to_i
          {
            airbnb_id: row[:airbnb_id],
            airbnb_url: row[:airbnb_url].presence,
            adr_365: row[:adr].to_f,
            occ_365: row[:occ].to_f,
            rev_potential: row[:rev_potential].to_f,
            days_available: days_avail,
            mode: (days_avail >= 360 ? "truth" : "season-adjusted") # internal use only
          }
        end

        # summary metrics
        metrics = summarize(expanded, building_name, unit_type)

        # build listings payload with guaranteed Airbnb links (mode removed from response)
        listings = expanded.map do |x|
          {
            airbnb_id: x[:airbnb_id],
            airbnb_url: x[:airbnb_url] || "https://www.airbnb.com/rooms/#{x[:airbnb_id]}",
            adr: x[:adr_365],
            occ: x[:occ_365],
            rev_potential: x[:rev_potential]
          }
        end

        {
          status: "ok",
          data: metrics,
          listings: listings
        }
      end

      private

      def load_csv
        path = Rails.root.join("data", "reference", "palm_jumeirah_airbnb_links_clean.csv")
        rows = []
        CSV.foreach(path, headers: true, header_converters: :symbol) do |row|
          rows << row.to_h
        end
        rows
      end

      def summarize(expanded, building_name, unit_type)
        return {} if expanded.empty?

        adr_values = expanded.map { |x| x[:adr_365].to_f }
        occ_values = expanded.map { |x| x[:occ_365].to_f }
        rev_values = expanded.map { |x| x[:rev_potential].to_f }

        {
          adr_p50: median(adr_values),
          adr_p75: percentile(adr_values, 0.75),
          occ_p50: median(occ_values),
          occ_p75: percentile(occ_values, 0.75),
          rev_p50: median(rev_values),
          rev_p75: percentile(rev_values, 0.75),
          building: building_name,
          unit_type: unit_type,
          sample_n: expanded.size,
          sample_total_candidates: expanded.size,
          min_avail_days_applied: 270,
          scope: "building",
          method_version: "4.2-truth-vs-adjusted"
        }
      end

      def median(arr)
        return 0 if arr.empty?
        sorted = arr.sort
        mid = sorted.length / 2
        sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
      end

      def percentile(arr, pct)
        return 0 if arr.empty?
        sorted = arr.sort
        k = (pct * (sorted.length - 1)).floor
        sorted[k]
      end
    end
  end
end
