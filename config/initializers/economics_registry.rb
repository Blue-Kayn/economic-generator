# config/initializers/economics_registry.rb
Rails.application.config.to_prepare do
  begin
    Economics::Registry.reload!
    Rails.logger.info "[Economics::Registry] Preloaded successfully with scaled seasonality"
  rescue => e
    Rails.logger.warn "[Economics::Registry] Failed to preload: #{e.class}: #{e.message}"
  end
end