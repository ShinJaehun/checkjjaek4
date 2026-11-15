class JjaekPhotoUpload < ApplicationRecord
  # Successful upload history survives photo deletion; deleting cannot reset a day.
  belongs_to :user, optional: true
  belongs_to :blob, class_name: "ActiveStorage::Blob", optional: true

  def self.daily_limit
    Integer(ENV.fetch("JJAEK_PHOTO_DAILY_LIMIT", "4"))
  end

  def self.retained_limit
    Integer(ENV.fetch("JJAEK_PHOTO_RETAINED_LIMIT", "50"))
  end

  def self.storage_limit
    Integer(ENV.fetch("JJAEK_PHOTO_STORAGE_LIMIT_BYTES", 1.gigabyte.to_s))
  end

  def self.enabled?
    ENV.fetch("JJAEK_PHOTO_UPLOADS_ENABLED", "true") == "true"
  end

  def self.original_blobs
    ActiveStorage::Blob.where("metadata::jsonb @> ?::jsonb", { jjaek_photo: true }.to_json)
  end
end
