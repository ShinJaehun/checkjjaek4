require "rails_helper"

RSpec.describe "Images in a reading note body", type: :request do
  let(:owner) { User.create!(name: "Reader", email: "note-body-images@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Book with illustrated notes") }
  let!(:entry) { owner.bookshelf_entries.create!(book:) }

  def upload_image(user = owner)
    file = Rack::Test::UploadedFile.new(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png"), "image/png")
    post book_book_note_images_path(book), params: { image: file }
    expect(response).to have_http_status(:created)
    BookNoteImage.where(user:).find(response.parsed_body.fetch("id"))
  end

  def image_path(image, **options)
    book_book_note_image_path(book, image, **options)
  end

  def figure(image, url: image_path(image))
    attributes = { bookNoteImageId: image.id, contentType: "image/webp", url: }
    %(<figure data-trix-attachment="#{ERB::Util.html_escape(attributes.to_json)}"><img src="#{url}"></figure>)
  end

  def editor_draft
    input = Nokogiri::HTML(response.body).at_css("#book-note-editor input[name='book_note[body]']")
    Nokogiri::HTML.fragment(input["value"])
  end

  after do
    BookNoteImage.joins(:user_book).where(user_books: { book_id: book.id }).includes(:blob).find_each do |image|
      image.blob.service.delete(image.blob.key)
    end
  end

  it "saves text and images in order, then reorders, replaces and removes images" do
    sign_in owner
    first = upload_image
    second = upload_image
    post book_book_notes_path(book), params: { book_note: {
      body: %(<div data-action="click->photo-gallery#close">Before#{figure(first)}Between#{figure(second)}After</div>)
    } }
    expect(response).to have_http_status(:see_other)
    note = entry.user_book.book_notes.sole
    expect(note.book_note_images).to contain_exactly(first, second)
    expect(note.body.to_plain_text).to eq("BeforeBetweenAfter")
    expect(note.editable_body.to_html).not_to include(image_path(first), "sgid", "data-trix-attachment")

    get book_book_note_path(book, note)
    document = Nokogiri::HTML(response.body)
    body = document.at_css(".book-note-body .trix-content > div")
    expect(body["data-action"]).to be_nil
    pieces = body.children.filter_map do |node|
      node.at_css("img")&.[]("src") || node.text.strip.presence
    end
    expect(pieces).to eq([ "Before", image_path(first, size: :body), "Between", image_path(second, size: :body), "After" ])
    expect(body.css("figure button").map { |button| button["data-gallery-url"] }).to eq([ image_path(first), image_path(second) ])
    attachments = editor_draft.css("figure[data-trix-attachment]").map { |node| JSON.parse(node["data-trix-attachment"]) }
    expect(attachments.map { |attachment| attachment.fetch("bookNoteImageId").to_i }).to eq([ first.id, second.id ])
    expect(attachments.map { |attachment| attachment.fetch("url") }).to eq([ image_path(first), image_path(second) ])

    get user_library_path(owner, library_tab: "notes")
    preview = Nokogiri::HTML(response.body).at_css(".book-note-preview")
    expect(preview.text).to eq("BeforeBetweenAfter")
    expect(preview.css("img")).to be_empty

    third = upload_image
    patch book_book_note_path(book, note), params: { book_note: { body: "#{figure(third)}New start#{figure(second)}End" } }
    expect(response).to have_http_status(:see_other)
    expect(note.reload.book_note_images).to contain_exactly(second, third)
    expect(first.reload).to be_purging
    get image_path(first)
    expect(response).to have_http_status(:not_found)
    get book_book_note_path(book, note)
    expect(Nokogiri::HTML(response.body).css(".book-note-body .trix-content img").map { |image| image["src"] })
      .to eq([ image_path(third, size: :body), image_path(second, size: :body) ])

    delete bookshelf_entry_path(entry)
    get book_book_note_path(book, note)
    expect(Nokogiri::HTML(response.body).css(".book-note-body .trix-content img, #book-note-editor").map { |node| node["src"] })
      .to eq([ image_path(third, size: :body), image_path(second, size: :body) ])
    get image_path(second)
    expect(response).to have_http_status(:ok)
    patch book_book_note_path(book, note), params: { book_note: { body: "Blocked update" } }
    expect(response).to redirect_to(root_path)

    owner.bookshelf_entries.create!(book:)
    delete book_book_note_path(book, note)
    [ image_path(second), image_path(second, size: :body) ].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
    expect(BookNoteImage.purgeable).to include(first, second, third)
  end

  it "keeps the persisted note and restores the draft when linking fails after the note was saved" do
    sign_in owner
    original = upload_image
    post book_book_notes_path(book), params: { book_note: { title: "Saved title", body: "Old text#{figure(original)}" } }
    expect(response).to have_http_status(:see_other)
    note = entry.user_book.book_notes.sole
    new_image = upload_image
    fail_link = true
    allow_any_instance_of(BookNoteImage).to receive(:attach_to!).and_wrap_original do |attach, *args, **kwargs|
      raise ActiveRecord::RecordNotFound if fail_link && attach.receiver.id == new_image.id

      attach.call(*args, **kwargs)
    end

    draft_params = { book_note: { title: "Draft title", body: "New text#{figure(new_image)}After" } }
    patch book_book_note_path(book, note), params: draft_params
    expect(response).to have_http_status(:unprocessable_content)
    expect(note.reload.title).to eq("Saved title")
    expect(note.body.to_plain_text).to eq("Old text")
    expect(original.reload).to be_attached
    expect(new_image.reload).to be_temporary
    expect(editor_draft.text).to eq("New textAfter")
    expect(editor_draft.at_css("figure")["data-trix-attachment"]).to include(image_path(new_image))
    expect(Nokogiri::HTML(response.body).at_css("input[name='book_note[title]']")["value"]).to eq("Draft title")

    fail_link = false
    patch book_book_note_path(book, note), params: draft_params
    expect(response).to have_http_status(:see_other)
    expect(original.reload).to be_purging
    expect(new_image.reload).to be_attached
  end

  it "rejects foreign, linked, expired and forged references and preserves the text and image limits" do
    other = User.create!(name: "Other", email: "foreign-note-image@example.com", password: "password123!")
    other.bookshelf_entries.create!(book:)
    sign_in other
    foreign = upload_image(other)
    sign_in owner
    expired = upload_image
    expired.update!(expires_at: 1.minute.ago)
    linked = upload_image
    note = entry.user_book.book_notes.create!(body: "Other note")
    linked.attach_to!(note, user: owner)
    available = upload_image

    [ "Text#{figure(foreign)}", "Text#{figure(expired)}", "Text#{figure(linked)}",
      "Text#{figure(available, url: 'https://example.test/external.webp')}",
      "Text<iframe src='https://example.test/iframe'></iframe>",
      "Text<svg></svg>", figure(available), "Text#{figure(available) * 5}", "#{'A' * 10_001}#{figure(available)}" ].each do |body|
      expect do
        post book_book_notes_path(book), params: { book_note: { body: } }
      end.not_to change(BookNote, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(editor_draft.to_html).not_to include("https://example.test/")
    end
    expect(linked.reload.book_note).to eq(note)
    expect([ foreign, expired, available ].map { |image| image.reload.state }).to eq([ "temporary" ] * 3)
  end
end
