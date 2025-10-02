# frozen_string_literal: true
# config/initializers/compression.rb
#
# Enable gzip compression for API responses

Rails.application.config.middleware.use Rack::Deflater

# Add this concern to API controllers for better compression handling
module Compressible
  extend ActiveSupport::Concern

  included do
    after_action :set_compression_headers
  end

  private

  def set_compression_headers
    # Indicate that response can be compressed
    response.headers["Vary"] = "Accept-Encoding"
    
    # Set content type explicitly for JSON
    response.headers["Content-Type"] = "application/json; charset=utf-8" if response.media_type == "application/json"
  end
end