# app/controllers/api/analyze_controller.rb
class Api::AnalyzeController < ApplicationController
  protect_from_forgery with: :null_session

  # POST /api/analyze_link  { "url": "https://..." }
  def link
    url = params[:url].to_s
    return render json: { error: "url is required" }, status: 400 if url.blank?

    begin
      resolved = Resolver::Dispatcher.resolve(url)
    rescue => e
      return render json: { error: "resolve_failed", detail: e.message }, status: 422
    end

    building = resolved[:building_name]
    unit     = resolved[:unit_type]

    # If we can't confidently identify needed fields, say so transparently.
    if building.blank? || unit.blank?
      return render json: {
        resolver: resolved,
        economics: { status: "no_data", reason_code: "NOT_SUPPORTED" }
      }, status: 200
    end

    econ = Economics::Registry.fetch(building_name: building, unit_type: unit)

    render json: {
      resolver: resolved,
      economics: econ.status == "ok" ? { status: "ok", metrics: econ.metrics } :
                                       { status: "no_data", reason_code: econ.reason_code }
    }, status: 200
  end
end
