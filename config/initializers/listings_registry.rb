# config/initializers/listings_registry.rb
# Preload Listings::Registry to warm its CSV cache on boot (safe no-op if missing).
begin
  Listings::Registry.fetch(building_name: "dummy", unit_type: "dummy", limit: 0)
rescue => e
  Rails.logger.warn("[Listings::Registry preload] #{e.class}: #{e.message}")
end
