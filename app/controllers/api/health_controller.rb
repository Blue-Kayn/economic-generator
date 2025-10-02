# frozen_string_literal: true
# app/controllers/api/health_controller.rb
#
# Health check endpoint for monitoring and load balancers

module Api
  class HealthController < ApplicationController
    protect_from_forgery with: :null_session

    # GET /api/health
    def show
      checks = {
        database: check_database,
        csv_file: check_csv_file,
        economics_registry: check_economics_registry,
        listings_registry: check_listings_registry
      }

      all_healthy = checks.values.all? { |c| c[:status] == "ok" }
      status_code = all_healthy ? 200 : 503

      render json: {
        status: all_healthy ? "healthy" : "unhealthy",
        timestamp: Time.current.iso8601,
        version: Rails.application.class.module_parent_name,
        rails_version: Rails.version,
        ruby_version: RUBY_VERSION,
        checks: checks
      }, status: status_code
    end

    private

    def check_database
      ActiveRecord::Base.connection.execute("SELECT 1")
      { status: "ok" }
    rescue => e
      { status: "error", message: e.message }
    end

    def check_csv_file
      csv_path = ENV["MASTER_SHEET_CSV"].presence ||
                 Rails.root.join("data", "reference", "palm_master_clean.csv").to_s

      if File.exist?(csv_path)
        row_count = CSV.read(csv_path, headers: true).size
        { status: "ok", rows: row_count, path: csv_path }
      else
        { status: "error", message: "CSV file not found" }
      end
    rescue => e
      { status: "error", message: e.message }
    end

    def check_economics_registry
      result = Economics::Registry.lookup(
        building_name: "Seven Palm Jumeirah",
        unit_type: "1BR"
      )
      
      if result[:status] == "ok" || result[:reason_code] == "INSUFFICIENT_SAMPLE"
        { status: "ok", loaded: true }
      else
        { status: "error", message: "Registry not properly loaded" }
      end
    rescue => e
      { status: "error", message: e.message }
    end

    def check_listings_registry
      result = Listings::Registry.fetch(
        building_name: "Seven Palm Jumeirah",
        unit_type: "1BR",
        limit: 1
      )
      
      { status: "ok", loaded: true }
    rescue => e
      { status: "error", message: e.message }
    end
  end
end