# config/initializers/resolver_aliases.rb
Rails.application.config.to_prepare do
  begin
    Resolver::Aliases.load!
  rescue => e
    Rails.logger.warn("[resolver] aliases preload skipped: #{e.class}: #{e.message}")
  end
end
