require "rails_helper"

RSpec.describe "Book context in the common composer", type: :request do
  let(:user) { User.create!(name: "Reader", email: "book-posting@example.com", password: "password123!") }
  let(:admin) { User.create!(name: "Admin", email: "book-admin@example.com", password: "password123!") }
  let!(:book) { Book.create!(title: "Context book") }
  let(:group) { Group.create!(name: "Readers", group_admin: admin, group_type: :private_group, lifecycle_status: :active) }
  let!(:membership) { group.group_memberships.create!(user:, status: :active) }

  before do
    sign_in user
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  it "preselects the book and fixes the original personal or Group posting context" do
    [[book_path(book), jjaeks_path, true], [book_path(book, group_id: group.id), group_jjaeks_path(group), false]].each do |path, destination, visibility|
      get path
      expect(response).to have_http_status(:ok)
      form = Nokogiri::HTML(response.body).at_css("#book-jjaek-form form")
      expect(form["action"]).to eq(destination)
      expect(Nokogiri::HTML(response.body).at_css("input[name='selected_books[]'][value='#{book.id}'][form='jjaek-publish-form']")).to be_present
      expect(form.at_css("input[type='radio'][name='jjaek[visibility]']").present?).to eq(visibility)
      expect(form.ancestors("dialog")).to be_empty
    end
  end

  it "returns book-page posts to a fresh composer with only the current book preselected" do
    book.update!(authors_text: "Context author", thumbnail: "https://example.com/context-cover.jpg")
    other_book = Book.create!(title: "Additional book", authors_text: "Other author")
    [[jjaeks_path, nil], [group_jjaeks_path(group), group.id]].each do |destination, group_id|
      origin = book_path(book, group_id:)
      get origin
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("meta[name='turbo-cache-control']")["content"]).to eq("no-cache")
      expect(page.at_css("#jjaek-publish-form input[name='book_context_id']")["value"]).to eq(book.id.to_s)
      expect(page.at_css("#jjaek-publish-form textarea").text.strip).to be_empty
      expect(page.at_css("#jjaek-attached-books").text).to include(book.title, book.authors_text)
      expect(page.at_css("#jjaek-attached-books img")["src"]).to eq(book.thumbnail)

      post destination, params: { book_context_id: book.id, selected_books: [book.id, other_book.id], jjaek: { content: "Published from book" } }
      expect(Jjaek.last).to have_attributes(group_id:, content: "Published from book")
      expect(Jjaek.last.attached_books).to eq([book, other_book])
      expect(response).to redirect_to(origin)
      follow_redirect!
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#jjaek-publish-form textarea").text.strip).to be_empty
      expect(page.css("#jjaek-attached-books input[name='selected_books[]']").map { |input| input["value"] }).to eq(["", book.id.to_s])

      post destination, params: { book_context_id: book.id, selected_books: [""], jjaek: { content: "No attached books" } }
      expect(response).to redirect_to(root_path)
      expect(Jjaek.last.attached_books).to be_empty
      expect(Jjaek.last.group_id).to eq(group_id)

      post destination, params: { book_context_id: book.id, selected_books: [other_book.id], jjaek: { content: "Only another book" } }
      expect(response).to redirect_to(root_path)
      expect(Jjaek.last.attached_books).to eq([other_book])
      expect(Jjaek.last.group_id).to eq(group_id)

      post destination, params: { book_context_id: book.id, selected_books: [other_book.id], jjaek: { content: "x" * 201, visibility: :private_jjaek } }
      expect(response).to have_http_status(:unprocessable_content)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#jjaek-publish-form textarea").text.strip).to eq("x" * 201)
      expect(page.css("#jjaek-attached-books input[name='selected_books[]']").map { |input| input["value"] }).to eq(["", other_book.id.to_s])
      expect(page.at_css("#jjaek-attached-books").text).to include(other_book.authors_text)
      if group_id.nil?
        expect(page.at_css("input[name='jjaek[visibility]'][checked]")["value"]).to eq("private_jjaek")
      end
    end
  end

  it "uses the saved attachment and validated book context rather than an arbitrary return URL" do
    ["text/html", "text/vnd.turbo-stream.html"].each do |accept|
      post jjaeks_path, params: { book_context_id: book.id, return_to: "https://example.com/redirect",
        selected_books: [book.id], jjaek: { content: "Validated context" } }, headers: { "Accept" => accept }
      expect(response).to redirect_to(book_path(book))

      post jjaeks_path, params: { book_context_id: "#{book.id}invalid", return_to: book_path(book),
        selected_books: [book.id], jjaek: { content: "Ordinary post" } }, headers: { "Accept" => accept }
      expect(response).to redirect_to(jjaek_path(Jjaek.last, return_to: book_path(book)))

      post jjaeks_path, params: { book_context_id: book.id, return_to: book_path(book),
        selected_books: [""], jjaek: { content: "Removed context book" } }, headers: { "Accept" => accept }
      expect(response).to redirect_to(root_path)
    end
  end

  it "previews an external book and publishes ordered attachments without adding reading data" do
    ["text/html", "text/vnd.turbo-stream.html"].each_with_index do |accept, index|
      [[jjaeks_path, nil], [group_jjaeks_path(group), group.id]].each do |destination, group_id|
        url = "https://example.com/new-book-#{index}-#{group_id || 'personal'}"
        token = external_book_token(url:)
        expect {
          get lookup_books_path, params: { search_result_token: token, group_id: }
        }.not_to change { [Book.count, BookshelfEntry.count, BookActivity.count] }
        expect(response).to have_http_status(:ok)
        page = Nokogiri::HTML(response.body)
        form = page.at_css("#jjaek-publish-form")
        expect(form["action"]).to eq(destination)
        key = page.css("#jjaek-attached-books input[name='selected_books[]']").last["value"]
        expect(key).to start_with("external:")
        expect(form.at_css("input[name='book_context_token']")["value"]).to eq(token)

        expect {
          post destination, params: { book_context_token: token, selected_books: [book.id, key], jjaek: { content: "External context #{index}" } },
            headers: { "Accept" => accept }
        }.to change(Jjaek, :count).by(1).and change(Book, :count).by(1).and change(BookshelfEntry, :count).by(0).and change(BookActivity, :count).by(0)
        stored_book = Book.find_by!(external_url: url)
        record = Jjaek.last
        expect(record.group_id).to eq(group_id)
        expect(record.attached_books).to eq([book, stored_book])
        expect(response).to redirect_to(book_path(stored_book, group_id:))
        follow_redirect!
        page = Nokogiri::HTML(response.body)
        expect(page.at_css("#feed-items #jjaek_#{record.id}")).to be_present
        expect(page.at_css("#jjaek-publish-form textarea").text.strip).to be_empty
        expect(page.css("#jjaek-attached-books input[name='selected_books[]']").map { |input| input["value"] }).to eq(["", stored_book.id.to_s])
      end
    end
  end

  it "keeps an external book temporary when removed, or when HTML and Turbo publication fails" do
    user.jjaeks.create!(content: "Unrelated bookless post")
    token = external_book_token
    get lookup_books_path, params: { search_result_token: token }
    key = Nokogiri::HTML(response.body).css("#jjaek-attached-books input[name='selected_books[]']").last["value"]
    expect(key).to start_with("external:")

    ["text/html", "text/vnd.turbo-stream.html"].each do |accept|
      [[key, book.id], [book.id], [""]].each do |selection|
        expect {
          post jjaeks_path, params: { book_context_token: token, selected_books: selection,
            jjaek: { content: "x" * 201, visibility: :private_jjaek } }, headers: { "Accept" => accept }
        }.not_to change { [Book.count, Jjaek.count, JjaekRecommendation.count, BookshelfEntry.count, BookActivity.count] }
        expect(response).to have_http_status(:unprocessable_content)
        page = Nokogiri::HTML(response.body)
        expect(page.at_css("#book-jjaek-form textarea").text.strip).to eq("x" * 201)
        expect(page.at_css("input[name='jjaek[visibility]'][checked]")["value"]).to eq("private_jjaek")
        expect(page.at_css("#jjaek-publish-form input[name='book_context_token']")["value"]).to eq(token)
        expect(page.css("#jjaek-attached-books input[name='selected_books[]']").map { |input| input["value"] }).to eq(["", *selection.map(&:to_s).reject(&:empty?)])
        expect(page.css("#feed-items article")).to be_empty
      end

      [[book.id], [""]].each do |selection|
        expect {
          post jjaeks_path, params: { book_context_token: token, selected_books: selection,
            jjaek: { content: "Removed external book" } }, headers: { "Accept" => accept }
        }.to change(Jjaek, :count).by(1).and change(Book, :count).by(0)
        expect(response).to redirect_to(root_path)
      end
    end
  end

  it "stores shelved and unshelved attachments without changing existing reading data" do
    shelved_book = Book.create!(title: "Shelved context book")
    shelf = user.bookshelves.create!(name: "Existing reading shelf")
    entry = user.bookshelf_entries.create!(book: shelved_book, bookshelf: shelf, status: :reading)
    sticker = StickerDefinition.create!(key: "book_posting_preserved", name: "Preserved sticker")
    entry.sticker_definitions << sticker
    reading_state = [entry.status, entry.bookshelf_id, entry.sticker_definition_ids.sort]

    expect {
      post group_jjaeks_path(group), params: { selected_books: [book.id, shelved_book.id], jjaek: { content: "Group note", visibility: :private_jjaek } }
    }.to change(Jjaek, :count).by(1).and change(BookshelfEntry, :count).by(0).and change(BookActivity, :count).by(0)
    expect(Jjaek.last).to have_attributes(group_id: group.id, visibility: "public_jjaek", book_id: nil)
    expect(Jjaek.last.attached_books).to eq([book, shelved_book])
    entry.reload
    expect([entry.status, entry.bookshelf_id, entry.sticker_definition_ids.sort]).to eq(reading_state)
    expect(user.bookshelf_entries.exists?(book:)).to be(false)
  end

  it "keeps the route Group authoritative and rejects mixed profile targets" do
    other = Group.create!(name: "Other", group_admin: user, lifecycle_status: :active)
    expect {
      post group_jjaeks_path(group), params: { selected_books: [book.id], jjaek: {group_id: other.id, content: "Scoped"} }
    }.to change(group.jjaeks, :count).by(1).and change(other.jjaeks, :count).by(0)
    expect(group.jjaeks.last.attached_books).to eq([book])

    expect {
      post group_jjaeks_path(group), params: { selected_books: [book.id], jjaek: {target_user_id: admin.id, content: "Mixed"} }
    }.not_to change(Jjaek, :count)
  end

  it "rejects publication after membership revocation, activity suspension or Group shutdown" do
    get book_path(book, group_id: group.id)
    membership.update!(moderation_status: :activity_suspended)
    expect { post group_jjaeks_path(group), params: { selected_books: [book.id], jjaek: {content: "Suspended"} } }.not_to change(Jjaek, :count)
    membership.update!(moderation_status: :normal)
    membership.destroy!
    expect { post group_jjaeks_path(group), params: { selected_books: [book.id], jjaek: {content: "Revoked"} } }.not_to change(Jjaek, :count)
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed")
    expect { post group_jjaeks_path(group), params: { selected_books: [book.id], jjaek: {content: "Closed"} } }.not_to change(Jjaek, :count)
  end

  it "rejects conflicting or ambiguous legacy book IDs and requote attachments" do
    other = Book.create!(title: "Other")
    [ {book_id: [book.id, other.id]}, {book_id: "#{book.id}bad"} ].each do |attributes|
      expect { post jjaeks_path, params: {jjaek: attributes.merge(content: "Invalid")} }.not_to change(Jjaek, :count)
    end
    expect {
      post jjaeks_path, params: {book_id: book.id, jjaek: {book_id: other.id, content: "Mismatch"}}
    }.not_to change(Jjaek, :count)
    source = admin.jjaeks.create!(book:, content: "Source")
    expect {
      post jjaeks_path, params: {jjaek: {book_id: book.id, quoted_jjaek_id: source.id, content: "Quote with book"}}
    }.not_to change(Jjaek, :count)
  end

  def external_book_token(url: "https://example.com/new-book")
    BookSearches::ResultToken.issue({ title: "External context book", authors_text: "External author", url: }, user:)
  end
end
