require "image_processing/vips"

Vips.concurrency_set(1)
Vips.cache_set_max(0)
Vips.cache_set_max_mem(16.megabytes)

Rails.application.config.active_storage.variant_processor = :vips
Rails.application.config.active_storage.track_variants = true
