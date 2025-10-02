# frozen_string_literal: true
# app/jobs/refresh_csv_cache_job.rb
#
# Background job to reload CSV data and clear caches

class RefreshCsvCacheJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[RefreshCsvCacheJob] Starting CSV refresh..."

    # Reload Economics Registry
    Economics::Registry.reload!
    Rails.logger.info "[RefreshCsvCacheJob] Economics::Registry reloaded"

    # Reload Listings Registry
    Listings::Registry.send(:load_rows!)
    Rails.logger.info "[RefreshCsvCacheJob] Listings::Registry reloaded"

    # Clear all cached data
    clear_all_caches

    Rails.logger.info "[RefreshCsvCacheJob] Completed successfully"
  rescue => e
    Rails.logger.error "[RefreshCsvCacheJob] Failed: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end

  private

  def clear_all_caches
    # Clear Rails cache
    Rails.cache.clear
    
    # If using Cacheable concern methods:
    # Rails.cache.delete_matched("economics:*")
    # Rails.cache.delete_matched("listings:*")
    # Rails.cache.delete_matched("resolver:*")
    
    Rails.logger.info "[RefreshCsvCacheJob] All caches cleared"
  end
end