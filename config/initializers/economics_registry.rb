Rails.application.config.to_prepare do
  begin
    Economics::Registry.reload!
  rescue => e
    Rails.logger.warn("[economics] preload skipped: #{e.class}: #{e.message}")
  end
end
