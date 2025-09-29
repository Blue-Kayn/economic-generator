# config/initializers/listings_registry.rb
# Autoload the building→Airbnb links registry at boot (safe no-op if file missing).
begin
  Listings::Registry.reload!
rescue => e
  Rails.logger.warn("[Listings::Registry] #{e.class}: #{e.message}")
end
