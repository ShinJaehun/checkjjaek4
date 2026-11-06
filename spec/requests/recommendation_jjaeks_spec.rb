require "rails_helper"

# The former recommendation window is replaced by the common inline composer.
# Keep its persistence, authorization and external-selection contracts here.
RSpec.describe "Unified Jjaek composition", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(name: "Reader", email: "unified-writer@example.com", password: "password123!") }
  let(:friend) { User.create!(name: "Friend", email: "unified-friend@example.com", password: "password123!") }
  let(:outsider) { User.create!(name: "Other", email: "unified-other@example.com", password: "password123!") }
  let!(:book) { Book.create!(title: "First attached book") }
  let!(:other_book) { Book.create!(title: "Second attached book") }
  let(:group) { Group.create!(group_admin: user, name: "Readers", group_type: :private_group, lifecycle_status: :active) }

  before do
    sign_in user
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
  end

  def legacy_recommendation
    record = user.jjaeks.new(content: "Original #before", recommendation: true)
    [ book, other_book ].each_with_index { |item, position| record.jjaek_recommendations.build(book: item, position:) }
    record.save!
    record
  end

  def external_key
    allow(BookSearches::SearchService).to receive(:call).and_return(
      results: [ { title: "External book", isbn: "9780140328721", url: "https://example.com/external" } ], meta: { is_end: true })
    get book_search_path, params: { attachment: 1, query: "External" }
    token = Nokogiri::HTML(response.body).at_css("input[name='search_result_token']")["value"]
    post recommendation_books_path, params: { search_result_token: token, selected_books: [""] }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    Nokogiri::HTML(response.body).css("input[name='selected_books[]']").map { |input| input["value"] }.find { |key| key.start_with?("external:") }
  end

  it "renders inline forms for home, profile, group and book with a selection-only floating window" do
    BookFriendship.create!(requester: user, addressee: friend, status: :accepted)
    [[root_path, "내 소식에 남길..."], [user_path(friend), "#{friend.name}님에게 남길..."],
     [group_path(group), "#{group.name}에 남길..."], [book_path(book), "이 책에 남길..."]].each do |path, placeholder|
      get path
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(page.css("form textarea[name='jjaek[content]']")).not_to be_empty
      expect(page.at_css("#jjaek-publish-form textarea")["placeholder"]).to eq(placeholder)
      expect(page.css("[data-book-selection-open]")).not_to be_empty
      expect(page.at_css("#recommendation-window")["aria-modal"]).to eq("false")
      expect(page.at_css("#recommendation-window button[data-action='recommendation-composer#cancel']")).to be_present
      expect(page.css("#recommendation-window textarea")).to be_empty
      expect(page.css("dialog textarea")).to be_empty
    end
  end

  it "posts with omitted books and explicit zero books without JavaScript" do
    [ nil, [ "" ] ].each do |selection|
      parameters = { jjaek: { content: "No books", visibility: :private_jjaek } }
      parameters[:selected_books] = selection unless selection.nil?
      expect { post jjaeks_path, params: parameters }.to change(Jjaek, :count).by(1)
      expect(response).to have_http_status(:see_other)
      expect(Jjaek.last.attached_books).to be_empty
    end
  end

  it "stores ordered books without a shelf or a new post type, through HTML and Turbo" do
    books = [other_book, book, *3.times.map { |i| Book.create!(title: "Attached #{i}") }]
    books.each_with_index { |item, i| item.update!(authors_text: "Author #{i}", thumbnail: "https://example.com/cover-#{i}.jpg") }
    [ "text/html", "text/vnd.turbo-stream.html" ].each do |accept|
      expect {
        post jjaeks_path, params: { selected_books: books.map(&:id), jjaek: { content: "Read together #books" } }, headers: { "Accept" => accept }
      }.to change(Jjaek, :count).by(1).and change(JjaekRecommendation, :count).by(5)
      expect(response).to have_http_status(:see_other)
      record = Jjaek.last
      expect(record.attached_books).to eq(books)
      expect(record).not_to be_recommendation
      expect(record.tags.pluck(:name)).to eq([ "books" ])
      get jjaek_path(record)
      attachments = Nokogiri::HTML(response.body).at_css("#jjaek_#{record.id} [data-attached-books]")
      expect(attachments.css("img").map { |image| image["src"] }).to eq(books.map(&:thumbnail))
      expect(attachments.css("[data-attached-book-cover-row]").map { |row| row.css("img").size }).to eq([3, 2])
      expect(attachments.css("li a").map(&:text)).to eq(books.map(&:title))
      expect(attachments.css("li a").map { |link| URI.parse(link["href"]).path }).to eq(books.map { |item| book_path(item) })
      post jjaek_like_path(record)
      post jjaek_comments_path(record), params: { comment: { content: "Thanks" } }
      expect(record.likes.exists?(user:)).to be(true)
      expect(record.comments.exists?(user:, content: "Thanks")).to be(true)
    end
    expect(user.bookshelf_entries).to be_empty
    expect(BookActivity.count).to eq(0)
  end

  it "rejects malformed, missing, duplicate and oversized selections without partial data" do
    extra = 4.times.map { |i| Book.create!(title: "Extra #{i}").id }
    [ [ { id: book.id } ], { id: book.id }, [ " " ], [ book.id, book.id ], [ book.id, "999999999" ], [ book.id, other_book.id, *extra ] ].each do |selection|
      expect {
        post jjaeks_path, params: { selected_books: selection, jjaek: { content: "Invalid" } }
      }.not_to change { [ Book.count, Jjaek.count, JjaekRecommendation.count ] }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Invalid")
    end
  end

  it "preserves content, visibility, verified choices and errors on failed HTML and Turbo posts" do
    [ "text/html", "text/vnd.turbo-stream.html" ].each do |accept|
      expect {
        post jjaeks_path, params: { selected_books: [ book.id, other_book.id ], jjaek: { content: "한" * 201, visibility: :private_jjaek } }, headers: { "Accept" => accept }
      }.not_to change { [ Book.count, Jjaek.count, JjaekRecommendation.count ] }
      expect(response).to have_http_status(:unprocessable_content)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("textarea[name='jjaek[content]']").text.strip).to eq("한" * 201)
      expect(page.at_css("input[type='radio'][name='jjaek[visibility]'][checked]")["value"]).to eq("private_jjaek")
      expect(page.css("input[name='selected_books[]']").map { |input| input["value"] }).to eq([ "", book.id.to_s, other_book.id.to_s ])
      expect(page.css("[role='alert']").text).not_to be_empty
    end
  end

  it "changes attachments on the same legacy record while preserving reactions and timestamps" do
    record = legacy_recommendation
    comment = record.comments.create!(user:, content: "Preserved")
    like = record.likes.create!(user:)
    quote = friend.jjaeks.create!(quoted_jjaek: record, content: "Opinion")
    notification = Notification.create!(recipient: user, actor: friend, notifiable: record, action: :requote_created)
    created_at = record.created_at
    patch jjaek_path(record), params: { selected_books: [ other_book.id ], jjaek: { content: "Edited", visibility: :private_jjaek } }
    expect(response).to have_http_status(:see_other)
    expect(record.reload.attached_books).to eq([ other_book ])
    expect(record.created_at).to eq(created_at)
    expect(record.comments).to include(comment)
    expect(record.likes).to include(like)
    expect(quote.reload.quoted_jjaek_id).to eq(record.id)
    expect(notification.reload.notifiable).to eq(record)
  end

  it "preserves omitted attachments and clears explicit empty selections without a legacy fallback" do
    record = user.jjaeks.create!(book:, content: "Single book")
    patch jjaek_path(record), params: { jjaek: { content: "Keep books" } }
    expect(record.reload.attached_books).to eq([ book ])
    patch jjaek_path(record), params: { selected_books: [ "" ], jjaek: { content: "Clear books" } }
    expect(record.reload.attached_books).to be_empty
    expect(record.book_id).to be_nil
    get edit_jjaek_path(record)
    expect(response.body).not_to include(book.title)
  end

  it "keeps invalid edits out of the DB and preserves submitted text and visibility on both responses" do
    record = legacy_recommendation
    extra = 4.times.map { |i| Book.create!(title: "Edit extra #{i}").id }
    invalid = [ [ book.id, "missing" ], [ { id: book.id } ], [ book.id, book.id ], [ book.id, other_book.id, *extra ] ]
    [ "text/html", "text/vnd.turbo-stream.html" ].each do |accept|
      invalid.each do |keys|
        original_links = record.jjaek_recommendations.reload.map(&:attributes)
        expect {
          patch jjaek_path(record), params: { selected_books: keys, jjaek: { content: "Attempt #changed", visibility: :private_jjaek } }, headers: { "Accept" => accept }
        }.not_to change { [ Book.count, Jjaek.count, JjaekRecommendation.count ] }
        expect(response).to have_http_status(:unprocessable_content)
        page = Nokogiri::HTML(response.body)
        expect(page.at_css("textarea").text.strip).to eq("Attempt #changed")
        expect(page.at_css("input[type='radio'][name='jjaek[visibility]'][checked]")["value"]).to eq("private_jjaek")
        expect(page.css("[role='alert']").text.strip).not_to be_empty
        expect(record.reload).to have_attributes(content: "Original #before", visibility: "public_jjaek")
        expect(record.jjaek_recommendations.reload.map(&:attributes)).to eq(original_links)
        expect(record.tags.pluck(:name)).to eq([ "before" ])
      end
    end
  end

  it "keeps external selection temporary and imports only during successful publication" do
    original_count = Book.count
    key = external_key
    expect(Book.count).to eq(original_count)
    expect(key.length).to eq(41)
    post jjaeks_path, params: { selected_books: [ key ], jjaek: { content: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Book.count).to eq(original_count)
    post jjaeks_path, params: { selected_books: [ key, book.id ], jjaek: { content: "External #read" } }
    expect(response).to have_http_status(:see_other)
    expect(Book.count).to eq(original_count + 1)
    expect(Jjaek.last.attached_books.map(&:title)).to eq([ "External book", book.title ])
    expect(user.bookshelf_entries).to be_empty
    expect(Rails.cache.read([ "recommendation_selection", user.id, key ])).to be_nil
  end

  it "rejects forged, cross-user and expired references on create and update without partial writes" do
    record = legacy_recommendation
    key = external_key
    [ [ "external:#{'0' * 32}", user ], [ key, outsider ] ].each do |selection, actor|
      sign_in actor
      expect { post jjaeks_path, params: { selected_books: [ selection ], jjaek: { content: "Invalid" } } }.not_to change { [ Book.count, Jjaek.count ] }
      expect(response).to have_http_status(:unprocessable_content)
    end
    sign_in user
    travel 31.minutes do
      expect { post jjaeks_path, params: { selected_books: [ key ], jjaek: { content: "Expired" } } }.not_to change { [ Book.count, Jjaek.count ] }
      expect(response).to have_http_status(:unprocessable_content)
      patch jjaek_path(record), params: { selected_books: [ key ], jjaek: { content: "Expired edit" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(record.reload.attached_books).to eq([ book, other_book ])
    end
  end

  it "rolls back a new external Book and all edits when content validation fails" do
    record = legacy_recommendation
    key = external_key
    links = record.jjaek_recommendations.reload.map(&:attributes)
    expect {
      patch jjaek_path(record), params: { selected_books: [ key ], jjaek: { content: "x" * 201, visibility: :private_jjaek } }
    }.not_to change { [ Book.count, JjaekRecommendation.count ] }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("x" * 201)
    expect(record.reload).to have_attributes(content: "Original #before", visibility: "public_jjaek")
    expect(record.jjaek_recommendations.reload.map(&:attributes)).to eq(links)
    expect(record.tags.pluck(:name)).to eq([ "before" ])
  end

  it "reuses a book registered after an external selection and rejects duplicate identities" do
    key = external_key
    token = Rails.cache.read(["recommendation_selection", user.id, key])
    imported = Book.create!(title: "Canonical", isbn: "9780140328721")
    post jjaeks_path, params: { selected_books: [ key, imported.id ], jjaek: { content: "Duplicate" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Jjaek.count).to eq(0)
    expect {
      post jjaeks_path, params: { book_context_token: token, selected_books: [ key ], jjaek: { content: "Reused" } }
    }.not_to change(Book, :count)
    expect(Jjaek.last.attached_books).to eq([ imported ])
    expect(response).to redirect_to(book_path(imported))
    expect(imported.reload.title).to eq("Canonical")
  end

  it "preserves two-person access for profile attachments after friendship ends" do
    friendship = BookFriendship.create!(requester: user, addressee: friend, status: :accepted)
    post jjaeks_path, params: { selected_books: [ book.id ], jjaek: { target_user_id: friend.id, content: "Private conversation", visibility: :public_jjaek } }
    record = Jjaek.last
    expect(record.target_user).to eq(friend)
    get edit_jjaek_path(record)
    expect(response.body).not_to include("name=\"jjaek[visibility]\"")
    friendship.destroy!
    [ user, friend ].each do |actor|
      sign_in actor
      get jjaek_path(record)
      expect(response.body).to include(book.title)
    end
    sign_in outsider
    get jjaek_path(record)
    expect(response.body).not_to include(book.title, "Private conversation")
    get jjaek_books_path, params: { editing_jjaek_id: record.id }
    expect(response).not_to have_http_status(:ok)
    sign_in user
    expect {
      post jjaeks_path, params: { selected_books: [ book.id ], jjaek: { target_user_id: friend.id, content: "No longer allowed" } }
    }.not_to change(Jjaek, :count)
  end

  it "rechecks Group writing permission and never accepts private visibility or mixed targets" do
    post group_jjaeks_path(group), params: { selected_books: [ book.id ], jjaek: { content: "Club", visibility: :private_jjaek } }
    record = Jjaek.last
    expect(record).to have_attributes(group_id: group.id, visibility: "public_jjaek")
    get edit_jjaek_path(record)
    expect(response.body).not_to include("name=\"jjaek[visibility]\"")
    expect {
      post group_jjaeks_path(group), params: { selected_books: [ book.id ], jjaek: { target_user_id: friend.id, content: "Mixed" } }
    }.not_to change(Jjaek, :count)
    sign_in outsider
    expect { post group_jjaeks_path(group), params: { selected_books: [ book.id ], jjaek: { content: "Forbidden" } } }.not_to change(Jjaek, :count)
    sign_in user
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed")
    patch jjaek_path(record), params: { selected_books: [ other_book.id ], jjaek: { content: "Forbidden edit" } }
    expect(record.reload.attached_books).to eq([ book ])
    expect(record.content).to eq("Club")
  end

  it "blocks attachment selection, changes and PATCH by a reader who is not the author" do
    record = legacy_recommendation
    original = record.attributes
    links = record.jjaek_recommendations.map(&:attributes)
    sign_in outsider
    get jjaek_path(record)
    expect(response).to have_http_status(:ok)

    expect {
      get jjaek_books_path, params: { editing_jjaek_id: record.id }
      expect(response).to redirect_to(root_path)
      post recommendation_books_path, params: { editing_jjaek_id: record.id, book_id: book.id, selected_books: [other_book.id] }
      expect(response).to redirect_to(root_path)
      delete recommendation_book_path(book.id), params: { editing_jjaek_id: record.id, selected_books: [book.id, other_book.id] }
      expect(response).to redirect_to(root_path)
      patch jjaek_path(record), params: { selected_books: [other_book.id], jjaek: { content: "Forbidden #changed", visibility: :private_jjaek } }
      expect(response).to redirect_to(root_path)
    }.not_to change { [Book.count, Jjaek.count, JjaekRecommendation.count] }

    expect(record.reload.attributes).to eq(original)
    expect(record.jjaek_recommendations.reload.map(&:attributes)).to eq(links)
    expect(record.tags.pluck(:name)).to eq(["before"])
  end

  it "revokes an author's attachment selection and editing access after Group membership ends" do
    club = Group.create!(group_admin: friend, name: "Membership readers", group_type: :private_group, lifecycle_status: :active)
    membership = club.group_memberships.create!(user:, status: :active)
    record = user.jjaeks.new(group: club, content: "Group #before")
    record.jjaek_recommendations.build(book:, position: 0)
    record.save!
    original = record.attributes
    links = record.jjaek_recommendations.map(&:attributes)
    get jjaek_books_path, params: { editing_jjaek_id: record.id }
    expect(response).to have_http_status(:ok)
    membership.destroy!

    expect {
      get jjaek_books_path, params: { editing_jjaek_id: record.id }
      expect(response).to redirect_to(root_path)
      post recommendation_books_path, params: { editing_jjaek_id: record.id, book_id: other_book.id, selected_books: [book.id] }
      expect(response).to redirect_to(root_path)
      delete recommendation_book_path(book.id), params: { editing_jjaek_id: record.id, selected_books: [book.id] }
      expect(response).to redirect_to(root_path)
      patch jjaek_path(record), params: { selected_books: [other_book.id], jjaek: { content: "Forbidden #changed" } }
      expect(response).to have_http_status(:not_found)
    }.not_to change { [Book.count, Jjaek.count, JjaekRecommendation.count] }

    expect(record.reload.attributes).to eq(original)
    expect(record.jjaek_recommendations.reload.map(&:attributes)).to eq(links)
    expect(record.tags.pluck(:name)).to eq(["before"])
  end

  it "ignores protected context fields while allowing an authorized content edit" do
    record = user.jjaeks.create!(content: "Context")
    { book_id: book.id, group_id: group.id, target_user_id: friend.id, quoted_jjaek_id: other_book.id }.each do |key, value|
      content = "Edited with #{key}"
      patch jjaek_path(record), params: { jjaek: { key => value, content: } }
      expect(response).to have_http_status(:see_other)
      expect(record.reload.content).to eq(content)
      expect(record).to have_attributes(book_id: nil, group_id: nil, target_user_id: nil, quoted_jjaek_id: nil)
      expect(record.attached_books).to be_empty
    end
  end

  it "only quotes the source and rejects newly attached books on creation and editing" do
    source = user.jjaeks.create!(book:, content: "Source")
    expect {
      post jjaeks_path, params: { selected_books: [ other_book.id ], jjaek: { quoted_jjaek_id: source.id, content: "Invalid quote" } }
    }.not_to change(Jjaek, :count)
    post jjaeks_path, params: { jjaek: { quoted_jjaek_id: source.id, content: "Opinion" } }
    quote = Jjaek.last
    expect(quote.attached_books).to be_empty
    patch jjaek_path(quote), params: { selected_books: [ other_book.id ], jjaek: { content: "Invalid edit" } }
    expect(quote.reload.content).to eq("Opinion")
    expect(quote.attached_books).to be_empty
    get edit_jjaek_path(quote)
    expect(Nokogiri::HTML(response.body).css("#jjaek-composer [data-book-selection-open]")).to be_empty
  end

  it "keeps legacy recommendation URLs and edits on the common form" do
    record = legacy_recommendation
    get edit_jjaek_path(record)
    expect(response.body).to include(book.title, other_book.title, "Original #before")
    expect(Nokogiri::HTML(response.body).css("#recommendation-window textarea")).to be_empty
    get book_search_path, params: { recommendation: 1, editing_jjaek_id: record.id }
    expect(response).to redirect_to(edit_jjaek_path(record))
    post recommendation_books_path, params: { editing_jjaek_id: record.id, book_id: book.id, selected_books: [book.id, other_book.id] }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(record.reload.attached_books).to eq([ book, other_book ])
  end

  it "does not treat normal composer or search parameters as unpermitted" do
    allow(ActionController::Parameters).to receive(:action_on_unpermitted_parameters).and_return(:raise)
    get jjaek_books_path, params: { query: book.title, page: 1 }
    expect(response).to have_http_status(:ok)
    post jjaeks_path, params: { selected_books: [ book.id ], commit: "짹", jjaek: { content: "Permitted", visibility: :public_jjaek } }
    expect(response).to have_http_status(:see_other)
  end

  it "keeps search results in the page and the floating window limited to selection" do
    get jjaek_books_path, params: { selected_books: [book.id], search_origin: root_path }
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("turbo-frame#recommendation_composer")).to be_present
    expect(page.at_css("button[data-action='recommendation-composer#finish']")).to be_present
    expect(page.css("textarea, form[action='#{jjaeks_path}']")).to be_empty
    expect(page.css("#recommendation-selected-books").text).to include(book.title)
    expect(page.at_css("form[method='get']")["action"]).to eq(book_search_path)

    get book_search_path, params: { attachment: 1, query: book.title, selected_books: [book.id], search_origin: root_path }
    page = Nokogiri::HTML(response.body)
    expect(page.css("#recommendation-search-results article").text).to include(book.title)
    expect(page.css("#recommendation-window article")).to be_empty
    expect(page.at_css("[hidden] #jjaek-composer[data-turbo-permanent]")).to be_present
  end

  it "enforces five unique selections and supports removal without creating Books or Jjaeks" do
    books = [book, other_book, *3.times.map { |i| Book.create!(title: "Selected #{i}") }]
    sixth = Book.create!(title: "Sixth selection")
    headers = { "Accept" => "text/vnd.turbo-stream.html", "X-Recommendation-Revision" => SecureRandom.uuid }
    expect {
      post recommendation_books_path, params: { selected_books: books.map(&:id), book_id: sixth.id }, headers: headers
    }.not_to change { [Book.count, Jjaek.count, JjaekRecommendation.count] }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.headers["X-Recommendation-Revision"]).to eq(headers["X-Recommendation-Revision"])
    expect(response.body).to include(I18n.t("jjaek_books.limit", count: 5))
    post recommendation_books_path, params: { selected_books: books.map(&:id), book_id: book.id }, headers: headers
    expect(response).to have_http_status(:ok)
    fields = Nokogiri::HTML(response.body).at_css("turbo-stream[target='recommendation-selection-fields'] template")
    expect(fields.css("input[name='selected_books[]']").map { |input| input["value"] }.reject(&:empty?)).to eq(books.map { |item| item.id.to_s })
    delete recommendation_book_path(book.id), params: { selected_books: books.map(&:id) }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(Jjaek.count).to eq(0)
  end

  it "registers an attachment via the existing shelf modal without changing any Jjaek data" do
    record = legacy_recommendation
    shelf = user.bookshelves.create!(name: "Chosen shelf")
    original = record.attributes
    links = record.jjaek_recommendations.map(&:attributes)
    get edit_jjaek_path(record)
    page = Nokogiri::HTML(response.body)
    registration = page.at_css("#jjaek-attached-books dialog form")
    expect(registration["action"]).to eq(bookshelf_entries_path)
    expect(registration.ancestors("form")).to be_empty
    expect(registration.at_css("input[name='bookshelf_entry_source']")["value"]).to eq("jjaek_attachment")
    expect {
      post bookshelf_entries_path, params: { book_id: book.id, bookshelf_entry_source: "jjaek_attachment", bookshelf_entry: { bookshelf_id: shelf.id } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(BookshelfEntry, :count).by(1).and change(BookActivity, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("attachment_shelf_book_search_result_stored_#{book.id}")
    expect(response.body).not_to include('target="jjaek-composer"', 'target="jjaek-attached-books"')
    expect(user.bookshelf_entries.find_by!(book:).bookshelf).to eq(shelf)
    expect(record.reload.attributes).to eq(original)
    expect(record.jjaek_recommendations.reload.map(&:attributes)).to eq(links)
    expect {
      post bookshelf_entries_path, params: { search_result_token: "invalid", bookshelf_entry_source: "jjaek_attachment" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.not_to change { [Book.count, BookshelfEntry.count, BookActivity.count] }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(record.reload.attributes).to eq(original)
  end

  it "keeps legacy recommendation search classification and its visibility boundary until the search stage" do
    record = legacy_recommendation
    expect(record.reload).to be_recommendation
    expect(Jjaek.recommendation_posts.where(id: record.id)).to exist
    expect(JjaekPolicy::SearchScope.new(user, Jjaek.all).resolve.where(id: record.id)).to exist

    get search_path, params: { q: "Original", type: "recommendation_jjaeks" }
    expect(response).to have_http_status(:ok)
    section = Nokogiri::HTML(response.body)
      .at_css("section[aria-labelledby='search-recommendation_jjaeks-title']")
    expect(section).not_to be_nil
    expect(section.css("article").size).to eq(1)
    expect(section.text).to include(record.content)
    expect(section.text).to include(book.title)
    record.update!(visibility: :private_jjaek)
    sign_in outsider
    get search_path, params: { q: "Original", type: "recommendation_jjaeks" }
    expect(response.body).not_to include(record.content, book.title)
  end
end
