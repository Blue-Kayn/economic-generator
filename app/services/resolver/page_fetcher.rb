# frozen_string_literal: true
# app/services/resolver/page_fetcher.rb
require "httparty"
require "nokogiri"

module Resolver
  class PageFetcher
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "\
                 "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36".freeze

    def self.get(url)
      resp = HTTParty.get(
        url,
        headers: { "User-Agent" => USER_AGENT, "Accept" => "text/html" },
        follow_redirects: true,
        timeout: 15
      )
      # Even on 404/403 we try to parse the body to allow URL-token fallback.
      unless resp.success?
        Rails.logger.warn("[resolver] non-200 for #{url} -> #{resp.code}")
      end
      Nokogiri::HTML(resp.body.to_s)
    end
  end
end
