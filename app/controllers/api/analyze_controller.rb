# frozen_string_literal: true
module Api
  class AnalyzeController < ApplicationController
    protect_from_forgery with: :null_session

    def link
      url = params[:url].to_s.strip
      unless url.start_with?("http")
        return render json: { status: "error", error: "url_missing_or_invalid" }, status: 400
      end

      Listings::Registry.send(:load_rows!)
      lrows = Listings::Registry.instance_variable_get(:@rows) || []

      resolved = resolve_from_url(url, lrows)

      if resolved[:building_name].present?
        chosen = choose_unit_for_building(lrows, resolved[:building_name], resolved[:unit_type])

        econ = Economics::Registry.lookup(
          building_name: resolved[:building_name],
          unit_type: chosen[:unit_type]
        )

        if econ[:status] == "no_data" && econ[:reason_code] == "INSUFFICIENT_SAMPLE"
          econ[:user_message] = "No solid data available for such unit"
        end

        # NEW: include exact comps and their URLs (used + candidates)
        sources = Economics::Registry.sources(
          building_name: resolved[:building_name],
          unit_type: chosen[:unit_type]
        )

        lis = Listings::Registry.fetch(
          building_name: resolved[:building_name],
          unit_type: chosen[:unit_type],
          limit: 6
        )

        render json: {
          resolver: resolved,
          selection: {
            building_name: resolved[:building_name],
            unit_type_requested: resolved[:unit_type],
            unit_type_chosen: chosen[:unit_type],
            reason: chosen[:reason],
            available_units: chosen[:available_units]
          },
          economics: econ,
          economics_sources: sources,
          listings: lis
        }
      else
        render json: {
          resolver: resolved,
          economics: { status: "no_data", reason_code: "NOT_SUPPORTED", data: nil },
          listings:  { status: "no_data", building_name: nil, unit_type: nil, count: 0, items: [] }
        }
      end
    end

    private

    BUILDING_SYNONYMS = {
      "fairmont palm residences" => [
        "the fairmont palm residences",
        "the fairmont palm residence south",
        "the fairmont palm residence north",
        "fairmont residences", "fairmont south", "fairmont north"
      ],
      "palm views"             => ["palm views east", "palm views west"],
      "the palm tower"         => ["palm tower"],
      "five palm jumeirah"     => ["five palm", "viceroy palm"],
      "seven palm jumeirah"    => ["seven palm"],
      "shoreline apartments"   => ["shoreline", "shoreline apartments palm"],
      "oceana residences"      => ["oceana", "oceana palm"],
      "marina residences"      => ["marina residences palm", "marina residences 1", "marina residences 6"]
    }.freeze

    def resolve_from_url(url, rows)
      slug_tokens = tokens_from_url(url)
      unit_guess = guess_unit_from_tokens(slug_tokens)

      csv_buildings = rows.map(&:building).uniq
      candidates = csv_buildings.dup
      BUILDING_SYNONYMS.each do |canon, syns|
        if csv_buildings.any? { |b| canonical(b) == canonical(canon) }
          candidates.concat(syns)
        end
      end

      best_name, best_score = nil, 0.0
      candidates.each do |nm|
        score = jaccard(slug_tokens, canonical_tokens(nm))
        if score > best_score
          best_name  = nm
          best_score = score
        end
      end

      resolved_csv =
        if best_name && csv_buildings.map { |b| canonical(b) }.include?(canonical(best_name))
          best_name
        else
          csv_buildings.find do |b|
            syns = BUILDING_SYNONYMS[b.to_s.downcase] || []
            syns.map { |s| canonical(s) }.include?(canonical(best_name))
          end
        end

      if resolved_csv
        {
          building_name: resolved_csv,
          unit_type: unit_guess,
          confidence: best_score.round(2),
          facts: { source: "url_guess", matched: best_name }
        }
      else
        { building_name: nil, unit_type: unit_guess, confidence: 0.0, facts: { source: "url_guess", matched: nil } }
      end
    end

    def choose_unit_for_building(rows, building_name, requested_unit)
      building_rows = rows.select { |r| canonical(r.building) == canonical(building_name) }
      available_units = building_rows.map { |r| r.unit_type }.uniq

      if requested_unit && available_units.map { |u| canonical(u) }.include?(canonical(requested_unit))
        return { unit_type: requested_unit, reason: "url_detected_and_available", available_units: available_units.sort }
      end

      freq = Hash.new(0)
      building_rows.each { |r| freq[r.unit_type] += 1 }
      best_unit = freq.max_by { |unit, count| [count, unit] }&.first || available_units.first || "1BR"

      { unit_type: best_unit, reason: requested_unit ? "requested_not_available;defaulted_to_most_common" : "no_unit_in_url;defaulted_to_most_common", available_units: available_units.sort }
    end

    def tokens_from_url(url)
      s = url.downcase
      s = s.sub(/\Ahttps?:\/\//, "")
      s = s.gsub(/[^\p{Alnum}\-\/_]+/, " ")
      s.split(/[\/\-\_\s]+/).reject(&:blank?)
    end

    def canonical(s) = s.to_s.downcase.strip.gsub(/\s+/, " ")
    def canonical_tokens(s) = canonical(s).split(/\s+/)

    require "set"
    def jaccard(a_tokens, b_tokens)
      a = a_tokens.to_set
      b = b_tokens.to_set
      inter = (a & b).size
      uni   = (a | b).size
      uni.zero? ? 0.0 : inter.to_f / uni
    end

    def guess_unit_from_tokens(tokens)
      joined = tokens.join(" ")
      return "Studio" if joined.match?(/\bstudio\b/)
      if (m = joined.match(/\b(\d)\s*(b\s*\/\s*r|br|bhk|bed|beds|bedroom|bedrooms)\b/))
        return "#{m[1]}BR"
      end
      if (m = joined.match(/\b(\d)\s*(?:\w+\s*)?(bed|beds|bedroom|bedrooms)\b/))
        return "#{m[1]}BR"
      end
      %w[one two three four].each_with_index do |w, idx|
        n = idx + 1
        if joined.match?(/\b#{Regexp.escape(w)}\s*-\s*(bed|beds|bedroom|bedrooms)\b/) ||
           joined.match?(/\b#{Regexp.escape(w)}\s*(bed|beds|bedroom|bedrooms)\b/)
          return "#{n}BR"
        end
      end
      nil
    end
  end
end
