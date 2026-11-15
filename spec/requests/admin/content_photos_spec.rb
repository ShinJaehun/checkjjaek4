require "rails_helper"

RSpec.describe "Admin content photo summaries", type: :request do
  let(:admin) { User.create!(name: "Admin", email: "photo-inventory-admin@example.com", password: "password123!", global_admin: true) }
  let(:reader) { User.create!(name: "Reader", email: "photo-inventory-reader@example.com", password: "password123!") }
  let(:group) { Group.create!(name: "Inventory club", group_admin: reader, lifecycle_status: :active) }

  def attach_photo(record, bytes)
    # Inventory reads only stored DB facts; there is deliberately no object file.
    blob = ActiveStorage::Blob.create!(filename: "photo.webp", content_type: "image/webp",
      byte_size: bytes, checksum: "1B2M2Y8AsgTpgAmY7PhCfg==", service_name: "test",
      metadata: { jjaek_photo: true, analyzed: true, identified: true })
    ActiveStorage::Attachment.create!(record:, name: "photos", blob:)
  end

  %i[user group].each do |context|
    it "shows current photo counts and original bytes only in the #{context} content inventory" do
      posting_group = context == :group ? group : nil
      book = Book.create!(title: "Inventory book")
      source = create_jjaek_with_books(user: reader, group: posting_group, books: [ book ], content: "Original")
      first = attach_photo(source, 512)
      attach_photo(source, 1536)
      large = reader.jjaeks.create!(group: posting_group, content: "Large")
      attach_photo(large, 2.megabytes)
      plain = reader.jjaeks.create!(group: posting_group, content: "Plain")
      removed = reader.jjaeks.create!(group: posting_group, content: "Removed")
      attach_photo(removed, 4.megabytes).destroy!
      quote = reader.jjaeks.create!(group: posting_group, content: "Quote", quoted_jjaek: source)
      legacy_quote = reader.jjaeks.create!(group: posting_group, content: "Historical quote", quoted_jjaek: large)
      # Existing attachments are DB facts even though new requote photos are forbidden.
      attach_photo(legacy_quote, 512)
      comment = source.comments.create!(user: reader, content: "Comment")

      variant = ActiveStorage::VariantRecord.create!(blob: first.blob, variation_digest: "inventory-variant")
      variant_blob = ActiveStorage::Blob.create!(filename: "variant.webp", content_type: "image/webp",
        byte_size: 3.megabytes, checksum: "1B2M2Y8AsgTpgAmY7PhCfg==", service_name: "test",
        metadata: { analyzed: true, identified: true })
      ActiveStorage::Attachment.create!(record: variant, name: "image", blob: variant_blob)

      sign_in admin
      expect_any_instance_of(ActiveStorage::Blob).not_to receive(:download)
      expect_any_instance_of(ActiveStorage::Blob).not_to receive(:open)
      expect_any_instance_of(ActiveStorage::Blob).not_to receive(:variant)
      summary_queries = []
      subscriber = lambda do |_name, _start, _finish, _id, payload|
        summary_queries << payload[:sql] if payload[:sql].include?("SUM(active_storage_blobs.byte_size)")
      end
      path = context == :user ? content_admin_user_path(reader) : content_admin_group_path(group)
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        get path, params: { per_page: 100 }
      end
      expect(response).to have_http_status(:ok)
      expect(summary_queries.size).to eq(1)
      document = Nokogiri::HTML(response.body)
      prefix = context == :user ? "timeline" : "group_timeline"
      source_row = document.at_css("##{prefix}_jjaek_#{source.id}")
      expect(source_row.at_css("[data-field='metadata']").text).to include(book.title, "사진 2장 · 합계 2KB")
      expect(document.at_css("##{prefix}_jjaek_#{large.id} [data-field='metadata']").text).to include("사진 1장 · 합계 2MB")
      expect(document.at_css("##{prefix}_jjaek_#{legacy_quote.id} [data-field='metadata']").text).to include("사진 1장 · 합계 0.5KB")
      [ plain, removed, quote ].each do |record|
        expect(document.at_css("##{prefix}_jjaek_#{record.id}").text).not_to include("사진 ")
      end
      expect(document.at_css("##{prefix}_comment_#{comment.id}").text).not_to include("사진 ")
      expect(document.css("a[href*='/photos/']")).to be_empty
    end
  end

  it "keeps both inventories restricted to global admins" do
    source = reader.jjaeks.create!(group:, content: "Protected")
    attach_photo(source, 1024)
    paths = [ content_admin_user_path(reader), content_admin_group_path(group) ]
    paths.each do |path|
      get path
      expect(response).to redirect_to(new_user_session_path)
    end
    sign_in reader
    paths.each do |path|
      get path
      expect(response).to redirect_to(root_path)
      expect(response.body).not_to include("사진 1장")
    end
  end
end
