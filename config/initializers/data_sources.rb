ENV["MASTER_SHEET_CSV"]  ||= Rails.root.join("data", "reference", "palm_master_clean.csv").to_s
ENV["LISTINGS_CSV_PATH"] ||= ENV["MASTER_SHEET_CSV"]