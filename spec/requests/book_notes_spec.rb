require "rails_helper"

RSpec.describe "Personal reading notes", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:owner) { User.create!(name: "Reader", email: "note-owner@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Book for personal notes") }
  let(:entry) { owner.bookshelf_entries.create!(book:) }
  let(:note) { entry.user_book.book_notes.create!(title: "My private note", body: "<strong>Private observation</strong>") }
  let(:note_attributes) { { title: "New thought", body: "<strong>Important detail</strong>" } }

  it "lets the owner create, read, update and delete a note independently of Jjaek and BookActivity" do
    book.update!(authors_text: "Note Author")
    entry
    sign_in owner
    activity_count = BookActivity.count
    jjaek_count = Jjaek.count

    get book_path(book)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("button[aria-controls='book-note-editor']").text).to eq(t("book_notes.new"))
    new_note_dialog = document.at_css("#book-note-editor")
    new_note_header = new_note_dialog.at_css("header")
    expect(new_note_header.at_css("h2").text).to eq(t("book_notes.heading"))
    expect(new_note_dialog.at_css("input[name='book_note[title]']")["required"]).to be_nil
    expect(new_note_header.text).to include(book.title, book.authors_text, t("books.thumbnail.no_thumbnail"))
    expect(new_note_header.css("a, img")).to be_empty
    expect(new_note_header.at_css("time")["datetime"]).to eq(Date.current.iso8601)
    expect(new_note_header.at_css("time").text).to eq(I18n.l(Date.current, format: :book_note))

    post book_book_notes_path(book), params: { book_note: note_attributes }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:see_other)
    follow_redirect!
    expect(response.body).to include("New thought")
    saved_note = entry.user_book.book_notes.sole
    created_at = saved_note.created_at

    get book_book_note_path(book, saved_note)
    expect(Nokogiri::HTML(response.body).at_css(".trix-content strong").text).to eq("Important detail")

    travel_to(1.minute.from_now) do
      patch book_book_note_path(book, saved_note), params: { book_note: { body: "<em>Revised thought</em>" } }
    end
    expect(response).to have_http_status(:see_other)
    expect(saved_note.reload.body.to_plain_text).to eq("Revised thought")
    expect(saved_note.created_at).to eq(created_at)
    expect(saved_note.updated_at).to be > created_at

    expect {
      delete book_book_note_path(book, saved_note)
    }.to change(BookNote, :count).by(-1)
    expect(response).to have_http_status(:see_other)
    expect(BookActivity.count).to eq(activity_count)
    expect(Jjaek.count).to eq(jjaek_count)
  end

  it "does not create a note or UserBook for an unregistered book" do
    sign_in owner

    expect {
      post book_book_notes_path(book), params: { book_note: note_attributes }
    }.not_to change(BookNote, :count)
    expect(response).to have_http_status(:not_found)
    expect(owner.user_books.exists?(book:)).to be(false)
  end

  it "preserves a failed draft in the editor and rejects a forged attachment" do
    entry
    sign_in owner

    expect {
      post book_book_notes_path(book),
           params: { book_note: { title: "Draft", body: '<p>Keep these words</p><img src="https://example.test/forged">' } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.not_to change(ActionText::RichText, :count)

    expect(response).to have_http_status(:unprocessable_content)
    document = Nokogiri::HTML(response.body)
    editor = document.at_css("#book-note-editor")
    expect(editor.css("header p").map(&:text)).to eq([ book.title ])
    expect(editor.at_css("input[name='book_note[title]']")["value"]).to eq("Draft")
    expect(editor.at_css("input[name='book_note[body]']")["value"]).to include("Keep these words")
    expect(editor.at_css("[role='alert']:not([hidden])").text).to include(t("book_notes.attachments_not_allowed"))
    expect(response.body).not_to include("https://example.test/forged")
  end

  it "returns 404 for another reader's note even when the viewer is an admin with the same book" do
    admin = User.create!(name: "Admin", email: "note-admin@example.com", password: "password123!", global_admin: true)
    admin.bookshelf_entries.create!(book:)
    path = book_book_note_path(book, note)
    sign_in admin

    get path
    expect(response).to have_http_status(:not_found)

    sign_in admin
    patch path, params: { book_note: note_attributes }
    expect(response).to have_http_status(:not_found)
    sign_in admin
    delete path
    expect(response).to have_http_status(:not_found)
    expect(note.reload.title).to eq("My private note")
  end

  it "keeps notes private on a public shelf and hides the note UI in another user's book context" do
    expect(entry.bookshelf).to be_visibility_public
    note
    friend = User.create!(name: "Friend", email: "note-friend@example.com", password: "password123!")
    BookFriendship.create!(requester: owner, addressee: friend, status: :accepted)
    sign_in friend

    [ user_path(owner), user_library_path(owner), user_library_path(owner, library_tab: "notes"), book_path(book) ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(note.title, "Private observation", 'id="book-notes"')
      expect(Nokogiri::HTML(response.body).at_css("[data-library-notes-link]")).to be_nil
    end

    friend.bookshelf_entries.create!(book:)
    get book_path(book, return_to: user_library_path(owner))
    expect(response.body).not_to include('id="book-notes"')
  end

  it "retains notes in the library when removed and restores editing when the book is placed again" do
    saved_note = note
    sign_in owner
    delete bookshelf_entry_path(entry)
    expect(response).to have_http_status(:see_other)

    get user_library_path(owner, library_tab: "notes")
    cards = Nokogiri::HTML(response.body).at_css("#book-notes")
    expect(cards.text).to include(book.title, saved_note.title, t("books.thumbnail.no_thumbnail"), "Private observation")
    get book_path(book)
    expect(response.body).to include(saved_note.title)
    expect(response.body).not_to include(t("book_notes.new"))
    expect(Nokogiri::HTML(response.body).at_css("#book-notes a[href='#{book_book_note_path(book, saved_note)}']")).to be_present
    get book_book_note_path(book, saved_note)
    expect(response.body).to include("Private observation")
    expect(response.body).not_to include(t("book_notes.edit"), t("book_notes.delete"))
    expect(Nokogiri::HTML(response.body).at_css("article footer")).to be_nil

    post book_book_notes_path(book), params: { book_note: note_attributes }
    expect(response).to redirect_to(root_path)
    patch book_book_note_path(book, saved_note), params: { book_note: note_attributes }
    expect(response).to redirect_to(root_path)
    delete book_book_note_path(book, saved_note)
    expect(response).to redirect_to(root_path)

    post bookshelf_entries_path, params: { book_id: book.id }
    expect(owner.bookshelf_entries.find_by!(book:).user_book_id).to eq(saved_note.user_book_id)
    get book_path(book, tab: "reading")
    document = Nokogiri::HTML(response.body)
    reading = document.at_css("#book-my-reading:not([hidden])")
    expect(reading.at_css("#book-notes").text).to include(saved_note.title)
    expect(document.at_css("[data-tab-panel='book-my-reading']:not([hidden]) button[aria-controls='book-note-editor']")).to be_present
    patch book_book_note_path(book, saved_note), params: { book_note: note_attributes }
    expect(response).to have_http_status(:see_other)
    expect(saved_note.reload.title).to eq("New thought")
  end

  it "renders the same paginated card in the library and book detail and returns to either list" do
    book.update!(authors_text: "Note Author", publisher: "Note Publisher", thumbnail: "https://example.test/note-cover.jpg",
                 isbn: "9780000000002", description: "Publisher description")
    travel_to(2.days.ago) { note }
    oldest_note = note
    oldest_note.update!(body: "<strong>Private observation</strong> <em>#{'긴' * 140}</em> END_OF_NOTE")
    user_book = entry.user_book
    30.times { user_book.book_notes.create!(body: "Later entry") }
    sign_in owner

    library_options = { bookshelf_id: entry.bookshelf_id, sort: "title", library_tab: "notes" }
    get user_library_path(owner, library_options)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("#book-notes").text).not_to include(oldest_note.title)
    expect(document.at_css("#book-notes h3").text).to eq(t("book_notes.untitled"))
    next_page = document.at_css("#book-notes nav a")
    expect(next_page["href"]).to include("bookshelf_id=#{entry.bookshelf_id}", "sort=title", "library_tab=notes", "notes_page=2")

    get next_page["href"]
    document = Nokogiri::HTML(response.body)
    library_notes_tab = document.at_css('[data-library-notes-link][aria-current="page"]')
    expect(library_notes_tab.text.strip).to eq(t("book_notes.heading"))
    expect(library_notes_tab.at_css('svg[aria-hidden="true"]')).to be_present
    expect(document.css("#book-notes h2:not(.sr-only)")).to be_empty
    library_card = document.at_css("#book-notes ul a")
    expect(library_card["class"].split).to include("book-note-paper")
    expect(library_card.text).to include(book.title, book.authors_text, oldest_note.title)
    expect(library_card.text).not_to include(t("book_notes.heading"))
    expect(library_card.css("svg")).to be_empty
    expect(library_card.at_css("img")["src"]).to eq(book.thumbnail)
    expect(library_card.css("time").map { |time| time["datetime"] }).to eq([ oldest_note.created_at.iso8601 ])
    expect(library_card.at_css("time").text).to eq(I18n.l(oldest_note.created_at, format: :short))
    library_book_info = library_card.element_children.last
    expect(library_card.css("h3, time, p").map(&:name)).to eq(%w[h3 time p p p])
    expect(library_book_info.css("p").map(&:text)).to eq([ book.title, "#{book.authors_text} · #{book.publisher}" ])
    expect(library_card.css("a")).to be_empty
    expect(URI.parse(library_card["href"]).path).to eq(book_book_note_path(book, oldest_note))

    get library_card["href"]
    document = Nokogiri::HTML(response.body)
    book_link = document.at_css(%(a[href="#{book_path(book, tab: "reading")}"]))
    detail_card = book_link.ancestors("article").first
    note_header = detail_card.at_css("header")
    note_body = detail_card.at_css(".book-note-body")
    footer = detail_card.at_css("footer")
    expect(detail_card["class"].split).to include("book-note-paper")
    expect(detail_card.ancestors("a")).to be_empty
    expect(note_header.at_css("a")).to eq(book_link)
    expect(note_header.at_css("h1").text).to eq(oldest_note.title)
    expect(note_header.next_element).to eq(note_body)
    expect(note_body.next_element).to eq(footer)
    note_date = oldest_note.created_at.to_date
    expect(note_header.css("time").map(&:text)).to eq([ I18n.l(note_date, format: :book_note) ])
    expect(note_header.css("time").map { |time| time["datetime"] }).to eq([ oldest_note.created_at.iso8601 ])
    expect(book_link.at_css("img")["src"]).to eq(book.thumbnail)
    expect(book_link.css("p").map(&:text)).to eq([ book.title, "#{book.authors_text} · #{book.publisher}" ])
    expect(book_link.css("a, button, form")).to be_empty
    expect(detail_card.text.scan(book.title).size).to eq(2)
    expect(detail_card.text).not_to include(book.description, book.isbn)
    expect(note_body.at_css(".trix-content strong").text).to eq("Private observation")
    expect(note_body.at_css(".trix-content").text).to include("END_OF_NOTE")
    expect(footer.at_css("button[aria-controls='book-note-editor']").text).to eq(t("book_notes.edit"))
    edit_dialog = footer.at_css("#book-note-editor")
    edit_header = edit_dialog.at_css(".book-note-paper header")
    expect(edit_header.at_css("h2").text).to eq(t("book_notes.heading"))
    expect(edit_header.text).to include(book.title, book.authors_text)
    expect(edit_header.at_css("img")["src"]).to eq(book.thumbnail)
    expect(edit_header.css("a")).to be_empty
    expect(edit_header.at_css("time")["datetime"]).to eq(note_date.iso8601)
    expect(edit_header.at_css("time").text).to eq(I18n.l(note_date, format: :book_note))
    expect(edit_dialog.at_css("trix-editor")).to be_present
    delete_form = footer.at_css("form[data-turbo-confirm]")
    expect(delete_form["data-turbo-confirm"]).to eq(t("book_notes.confirm_delete"))
    expect(delete_form.at_css('input[name="_method"]')["value"]).to eq("delete")
    back_link = document.at_css("a[data-back-link]")
    expect(back_link["href"]).to eq(user_library_path(owner, **library_options, notes_page: 2, anchor: "book-notes"))
    get back_link["href"]
    expect(Nokogiri::HTML(response.body).at_css('[data-library-notes-link][aria-current="page"]')).to be_present

    get book_path(book, tab: "reading")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("#book-notes").text).not_to include(oldest_note.title)
    next_page = document.at_css("#book-notes nav a")
    expect(next_page["href"]).to include("tab=reading", "notes_page=2", "#book-notes")
    get next_page["href"]
    document = Nokogiri::HTML(response.body)
    notes_section = document.at_css("#book-my-reading:not([hidden]) #book-notes")
    timeline = document.at_css("#book-timeline")
    expect(notes_section["class"]).to eq(timeline["class"])
    expect(notes_section.at_css("h2")["class"]).to eq(timeline.at_css("h2")["class"])
    expect(notes_section.css("h2").map { |heading| heading.text.strip }).to eq([ t("book_notes.heading") ])
    expect(notes_section.at_css('h2 svg[aria-hidden="true"]')).to be_present
    expect(notes_section.text).to include(oldest_note.title)
    book_card = notes_section.at_css("ul a")
    expect(book_card["class"]).to eq(library_card["class"])
    expect(book_card.inner_html).to eq(library_card.inner_html)
    expect(book_card.at_css("p").text).to start_with("Private observation").and end_with("...")
    expect(book_card.at_css("p").text.length).to eq(120)
    expect(book_card.text).not_to include("END_OF_NOTE")
    expect(book_card.css("strong, em, action-text-attachment, [data-trix-attachment]")).to be_empty
    get book_card["href"]
    expect(Nokogiri::HTML(response.body).at_css("a[data-back-link]")["href"]).to eq(book_path(book, tab: "reading", notes_page: 2, anchor: "book-notes"))
  end

  def t(key)
    I18n.t(key)
  end
end
