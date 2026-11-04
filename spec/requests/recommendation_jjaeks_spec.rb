require "rails_helper"

RSpec.describe "Book recommendation jjaeks", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(name: "Recommender", email: "recommendation-request@example.com", password: "password123!") }
  let(:outsider) { User.create!(name: "Other reader", email: "recommendation-outsider@example.com", password: "password123!") }
  let!(:book) { Book.create!(title: "추천할 첫 책") }
  let!(:other_book) { Book.create!(title: "추천할 둘째 책") }
  let(:group) { Group.create!(group_admin: user, name: "Recommendation club", group_type: :private_group, lifecycle_status: :active) }

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    sign_in user
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: false })
  end

  [ 1, 5 ].each do |count|
    it "shows ordered covers, title links, and authors for #{count} recommended books" do
      books = Array.new(count) do |index|
        Book.create!(title: "긴 추천 책 제목 #{index} " * 8, authors_text: "추천 저자 #{index}",
          thumbnail: "https://example.com/recommended-#{index}.jpg")
      end
      recommendation = user.jjaeks.new(content: "추천 카드의 책 정보", recommendation: true)
      books.each_with_index do |selected_book, position|
        recommendation.jjaek_recommendations.build(book: selected_book, position:)
      end
      recommendation.save!

      [ root_path, jjaek_path(recommendation) ].each do |path|
        get path

        card = Nokogiri::HTML(response.body).at_css("#jjaek_#{recommendation.id}")
        rows = card.css("ul[aria-label='#{I18n.t('recommendations.selected_books')}'] > li")
        expect(rows.size).to eq(count)
        rows.zip(books).each do |row, selected_book|
          expect(row.text).to include(selected_book.title, selected_book.authors_text)
          expect(row.at_css("img")["src"]).to eq(selected_book.thumbnail)
          title_link = row.css("a").find { |link| link.text.strip == selected_book.title.strip }
          expect(URI.parse(title_link["href"]).path).to eq(book_path(selected_book))
        end
      end
    end
  end

  it "opens a nonmodal permanent window and keeps its context on recommendation search pages" do
    [ [ root_path, nil ], [ group_path(group), group ] ].each do |origin, destination_group|
      get origin
      page = Nokogiri::HTML(response.body)
      window = page.at_css("#recommendation-window[data-turbo-permanent]")
      expect(window["hidden"]).to be_present
      opener = page.at_css("main a[data-recommendation-open]")
      expect(opener.text).to eq("추천짹")
      expect(opener["data-turbo-frame"]).to eq("recommendation_composer")
      expect(page.at_css("main button[aria-controls$='book-search-dialog']")).to be_present

      get opener["href"], headers: { "Turbo-Frame" => "recommendation_composer" }
      panel = Nokogiri::HTML(response.body).at_css("turbo-frame#recommendation_composer")
      expect(panel.at_css("[data-recommendation-composer-target='panel']")["data-step"]).to eq("selection")
      expect(panel.css("article")).to be_empty
      expect(panel.at_css("form[method='get']")["data-turbo-frame"]).to eq("_top")

      get book_search_path, params: { recommendation: 1, group_id: destination_group&.id,
                                     query: "추천할", selected_books: [ book.id ] }
      page = Nokogiri::HTML(response.body)
      window = page.at_css("#recommendation-window[data-turbo-permanent]")
      expect(window["hidden"]).to be_nil
      expect(window["role"]).to eq("dialog")
      expect(window["aria-modal"]).to eq("false")
      expect(window.at_css("#recommendation-window-title").text).to eq(I18n.t("recommendations.select_title"))
      expect(window.css("article, dialog")).to be_empty
      expect(page.css("main article").text).to include(book.title, other_book.title)
      expect(window.at_css("[data-recommendation-composer-target='panel']")["data-group-id"]).to eq(destination_group&.id.to_s)
      expect(window.css("input[name='selected_books[]'][form='recommendation-jjaek-form']").map { |input| input["value"] }).to eq([ book.id.to_s ])
      posting = window.at_css("#recommendation-jjaek-form")
      expect(posting["action"]).to eq(destination_group ? group_jjaeks_path(destination_group) : jjaeks_path)
      expect(posting.css("select[name='jjaek[visibility]']").any?).to eq(destination_group.nil?)

      next_link = page.css("main a[data-recommendation-navigation='true']").find do |link|
        link.text == I18n.t("book_search.pagination.next")
      end

      get next_link["href"]
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#recommendation-window[data-turbo-permanent]")["hidden"]).to be_nil
      expect(page.at_css("#recommendation-selection-fields input[name='page']")["value"]).to eq("2")
      expect(page.css("#recommendation-selection-fields").size).to eq(1)
      expect(page.css("#recommendation-selection-fields input[name='selected_books[]'][form='recommendation-jjaek-form']").map { |input| input["value"] }).to eq([ book.id.to_s ])
    end
    expect(Jjaek.count).to eq(0)
  end

  it "keeps both writing stages in the same window without a save action between them" do
    get new_jjaek_path, params: { recommendation: 1, selected_books: [ book.id ] }
    page = Nokogiri::HTML(response.body)
    window = page.at_css("#recommendation-window")
    expect(window.at_css("button[data-action='recommendation-composer#write']").text).to eq(I18n.t("recommendations.entry"))
    writing = window.at_css("[data-recommendation-composer-target='writing']")
    expect(writing).to have_attribute("hidden")
    form = writing.at_css("#recommendation-jjaek-form")
    expect(form.css("form")).to be_empty
    expect(form.at_css("textarea[name='jjaek[content]']")).to be_present
    expect(form.at_css("select[name='jjaek[visibility]']")).to be_present
    expect(form.at_css("input[type='submit']")["value"]).to eq(I18n.t("jjaeks.actions.publish_short"))
    expect(writing.at_css("button[data-action='recommendation-composer#select']").text).to eq(I18n.t("recommendations.back_to_selection"))
    search = window.at_css("form[data-recommendation-selection-form='search']")
    expect(search.ancestors.any? { |ancestor| ancestor["data-recommendation-composer-target"] == "selection" }).to be(false)
    expect(Jjaek.count).to eq(0)
  end

  it "marks top navigation as an explicit exit while a new composer starts empty" do
    get new_jjaek_path, params: { recommendation: 1, selected_books: [ book.id ] }
    page = Nokogiri::HTML(response.body)
    window = page.at_css("#recommendation-window")
    expect(window["data-action"]).not_to include("keydown.esc", "focusout", "blur", "scroll")
    header = page.at_css("header[data-recommendation-navigation-end]")
    expect(header.at_css("a[href='#{search_path}']")).to be_present
    expect(header.at_css("button[aria-controls='global-book-search-dialog']")["data-action"]).to include("book-modal#open")

    get search_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#recommendation-window")["hidden"]).to be_present
    get new_jjaek_path, params: { recommendation: 1 }
    page = Nokogiri::HTML(response.body)
    expect(page.css("input[name='selected_books[]'][form='recommendation-jjaek-form']")).to be_empty
    expect(page.at_css("#recommendation-jjaek-form textarea").text.strip).to eq("")
    expect(page.at_css("#recommendation-jjaek-form option[selected]")["value"]).to eq("public_jjaek")
  end

  it "renders search-only frame responses without replacing the composer or writing form" do
    get book_search_path, params: { recommendation: 1, query: "추천할", page: 1,
                                   selected_books: [ book.id ], search_origin: root_path },
                          headers: { "Turbo-Frame" => "recommendation-search-results" }
    page = Nokogiri::HTML(response.body)
    results = page.at_css("turbo-frame#recommendation-search-results")
    expect(results["data-turbo-action"]).to eq("advance")
    expect(results.at_css("[data-recommendation-results-state]")["data-query"]).to eq("추천할")
    expect(results.css("article").text).to include(book.title, other_book.title)
    expect(page.css("#recommendation-window, #recommendation-jjaek-form, textarea")).to be_empty
  end

  it "limits selections to five unique books and allows another book after removal" do
    books = [ book, other_book, *3.times.map { |index| Book.create!(title: "Selected #{index}") } ]
    selected = books.map(&:id)
    headers = { "Accept" => "text/vnd.turbo-stream.html" }
    post recommendation_books_path, params: { book_id: book.id, selected_books: selected }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css("input[name='selected_books[]'][form='recommendation-jjaek-form']").size).to eq(5)
    expect(response.body).to include(I18n.t("recommendations.selected_count", count: 5, max: 5))

    token = BookSearches::ResultToken.issue({ title: "Sixth", isbn: "9780140328721" }, user:)
    expect {
      post recommendation_books_path, params: { search_result_token: token, selected_books: selected }, headers: headers
    }.to change(Book, :count).by(0).and change(Jjaek, :count).by(0)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("recommendations.limit_reached", count: 5))
    expect(Nokogiri::HTML(response.body).css("input[name='selected_books[]'][form='recommendation-jjaek-form']").size).to eq(5)

    sixth = Book.create!(title: "Existing sixth")
    post recommendation_books_path, params: { book_id: book.id, selected_books: [ *selected, sixth.id ] }, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
    delete recommendation_book_path(book.id), params: { selected_books: selected }, headers: headers
    remaining = selected.drop(1)
    post recommendation_books_path, params: { search_result_token: token, selected_books: remaining }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css("input[name='selected_books[]'][form='recommendation-jjaek-form']").size).to eq(5)
    expect(Book.find_by(canonical_isbn: "9780140328721")).to be_nil
    expect(BookActivity.count).to eq(0)
  end

  it "rejects an oversized final recommendation without partially importing external books" do
    selected = [ book, other_book, *3.times.map { |index| Book.create!(title: "Final #{index}") } ].map(&:id)
    token = BookSearches::ResultToken.issue({ title: "External sixth", isbn: "9780140328721" }, user:)
    post recommendation_books_path, params: { search_result_token: token }
    external_keys = Rack::Utils.parse_nested_query(URI.parse(response.location).query).fetch("selected_books")
    expect {
      post jjaeks_path, params: { recommendation: 1, selected_books: [ *selected, *external_keys ], jjaek: { content: "Too many" } },
                        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(Book, :count).by(0).and change(Jjaek, :count).by(0).and change(JjaekRecommendation, :count).by(0)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("activerecord.errors.models.jjaek.attributes.recommended_books.too_many_recommendations", count: 5))
  end

  it "preserves the first authorized return location through searches and final posting" do
    [ [ root_path, nil ], [ user_path(user), nil ], [ group_path(group), group ] ].each do |origin, destination_group|
      entry = destination_group ? new_group_jjaek_path(destination_group) : new_jjaek_path
      get entry, params: { recommendation: 1, search_origin: origin }
      saved_origin = Nokogiri::HTML(response.body).at_css("#recommendation-selection-fields input[name='search_origin']")["value"]
      get book_search_path, params: { recommendation: 1, query: "추천할", page: 2,
                                     group_id: destination_group&.id, selected_books: [ book.id ], search_origin: saved_origin }
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#recommendation-selection-fields input[name='search_origin']")["value"]).to eq(origin)
      destination = destination_group ? group_jjaeks_path(destination_group) : jjaeks_path
      accept = destination_group ? "text/vnd.turbo-stream.html" : "text/html"
      post destination,
           params: { recommendation: 1, selected_books: [ book.id ], search_origin: saved_origin, jjaek: { content: "Return to origin" } },
           headers: { "Accept" => accept }
      if destination_group
        completion = Nokogiri::HTML(response.body).at_css("[data-recommendation-composer-target='completed']")
        expect(completion["data-location"]).to eq(origin)
      else
        expect(response).to redirect_to(origin)
      end
      expect(Jjaek.order(:id).last.group).to eq(destination_group)
    end
  end

  it "rejects external, intermediate search, and inaccessible return locations" do
    private_group = Group.create!(group_admin: outsider, name: "Inaccessible", group_type: :private_group, lifecycle_status: :active)
    [ "https://example.com/evil", "//example.com/evil", book_search_path(query: "intermediate"), group_path(private_group) ].each do |origin|
      post jjaeks_path, params: { recommendation: 1, selected_books: [ book.id ], search_origin: origin, jjaek: { content: "Safe return" } }
      expect(response).to redirect_to(root_path)
    end
  end

  it "updates the floating selection and background results with streams while preserving the reason form" do
    headers = { "Accept" => "text/vnd.turbo-stream.html" }
    expect {
      post recommendation_books_path, params: { book_id: other_book.id, query: "추천할", selected_books: [ book.id ] }, headers: headers
    }.to change(Book, :count).by(0).and change(Jjaek, :count).by(0)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    page = Nokogiri::HTML(response.body)
    expect(page.css("turbo-stream").map { |stream| stream["target"] }).to include("recommendation-selected-books", "recommendation-selection-fields", "recommendation-search-results")
    expect(page.css("input[name='selected_books[]'][form='recommendation-jjaek-form']").map { |input| input["value"] }).to eq([ book.id.to_s, other_book.id.to_s ])
    expect(page.css("textarea, #recommendation-jjaek-form")).to be_empty
    expect(page.css("turbo-stream[target='recommendation-search-results'] article").text).to include(book.title, other_book.title)

    expect {
      delete recommendation_book_path(book.id), params: { query: "추천할", selected_books: [ book.id, other_book.id ] }, headers: headers
    }.not_to change(Book, :count)
    page = Nokogiri::HTML(response.body)
    expect(page.css("input[name='selected_books[]'][form='recommendation-jjaek-form']").map { |input| input["value"] }).to eq([ other_book.id.to_s ])
    removed_result = page.at_css("turbo-stream[target='recommendation-search-results'] article[data-book-id='#{book.id}']")
    expect(removed_result.at_css("[data-recommendation-add]")["hidden"]).to be_nil
  end

  it "separates recommendation selection from ordinary book search and preserves the selection across searches and pages" do
    get book_search_path, params: { query: "추천할", recommendation: 1 }
    page = Nokogiri::HTML(response.body)
    expect(page.css("main article input[type='submit']").map { |input| input["value"] }).to include(I18n.t("recommendations.add"))
    expect(page.css("main article a[href]")).to be_empty
    expect(page.css("main article input[type='submit']").map { |input| input["value"] }).not_to include(I18n.t("book_search.actions.add_to_shelf"))

    post recommendation_books_path, params: { book_id: book.id, query: "추천할" }
    follow_redirect!
    page = Nokogiri::HTML(response.body)
    search_form = page.at_css("#recommendation-window form[method='get']")
    expect(search_form.css("input[name='selected_books[]']").map { |input| input["value"] }).to eq([ book.id.to_s ])
    next_link = page.css("main a[href]").find { |link| link.text == I18n.t("book_search.pagination.next") }
    get next_link["href"]
    expect(Nokogiri::HTML(response.body).css("#recommendation-window input[name='selected_books[]']").map { |input| input["value"] }).to include(book.id.to_s)

    post recommendation_books_path, params: { book_id: other_book.id, selected_books: [ book.id ], query: "둘째" }
    follow_redirect!
    expect(response.body).to include(I18n.t("recommendations.reason"), book.title, other_book.title)
    expect(Jjaek.count).to eq(0)

    get book_search_path, params: { recommendation: 1, selected_books: [ book.id, other_book.id ] }
    remove = Nokogiri::HTML(response.body).at_css("button[aria-label='#{I18n.t('recommendations.remove_book', title: book.title)}']").ancestors("form").first
    delete remove["action"], params: { selected_books: [ book.id, other_book.id ] }
    follow_redirect!
    expect(response.body).to include(other_book.title)
    expect(response.body).not_to include(book.title)
    expect(user.bookshelf_entries).to be_empty

    get book_search_path, params: { query: "추천할" }
    expect(response.body).not_to include(I18n.t("recommendations.add"))
    expect(Nokogiri::HTML(response.body).css("main article form").map { |form| form["action"] }).to include(bookshelf_entries_path)
  end

  it "keeps external selections temporary and short through searching, removal, and cancellation" do
    result = { title: "External recommendation", isbn: "9780140328721", url: "https://example.com/recommended-book",
               contents_excerpt: "긴 책 소개 " * 1000 }
    token = BookSearches::ResultToken.issue(result, user:)

    expect {
      post recommendation_books_path, params: { search_result_token: token }
    }.to change(Book, :count).by(0).and change(BookshelfEntry, :count).by(0).and change(BookActivity, :count).by(0)
    keys = Rack::Utils.parse_nested_query(URI.parse(response.location).query).fetch("selected_books")
    expect(response.location.bytesize).to be < 1024
    expect(response.location).not_to include(token, "External", "recommended-book")
    post recommendation_books_path, params: { search_result_token: token, selected_books: keys, query: "다른 검색" }
    follow_redirect!
    inputs = Nokogiri::HTML(response.body).at_css("#recommendation-window form[method='get']").css("input[name='selected_books[]']")
    expect(inputs.map { |input| input["value"] }).to eq(keys)
    next_link = Nokogiri::HTML(response.body).css("main a[href]").find { |link| link.text == I18n.t("book_search.pagination.next") }
    get next_link["href"]
    expect(response.body).to include(result[:title])
    get new_jjaek_path, params: { recommendation: 1, selected_books: keys }
    expect(response.body).to include(result[:title], I18n.t("recommendations.reason"))

    get book_search_path, params: { recommendation: 1, selected_books: keys }
    remove = Nokogiri::HTML(response.body).at_css("button[aria-label='#{I18n.t('recommendations.remove_book', title: result[:title])}']").ancestors("form").first
    delete remove["action"], params: { selected_books: keys }
    follow_redirect!
    expect(response.body).not_to include(result[:title])
    get root_path
    expect(Book.find_by(canonical_isbn: "9780140328721")).to be_nil
    expect(Jjaek.count).to eq(0)

    foreign_token = BookSearches::ResultToken.issue(result.merge(isbn: nil, url: "https://example.com/foreign"), user: outsider)
    expect { post recommendation_books_path, params: { search_result_token: foreign_token } }.not_to change(Book, :count)
    expect(flash[:alert]).to eq(I18n.t("recommendations.invalid_selection"))
  end

  it "saves new external books and ordered links only when the recommendation is published" do
    token = BookSearches::ResultToken.issue({ title: "New external book", isbn: "9780140328721" }, user:)
    post recommendation_books_path, params: { search_result_token: token, selected_books: [ book.id ] }
    keys = Rack::Utils.parse_nested_query(URI.parse(response.location).query).fetch("selected_books")
    post recommendation_books_path, params: { book_id: other_book.id, selected_books: keys }
    keys = Rack::Utils.parse_nested_query(URI.parse(response.location).query).fetch("selected_books")

    expect {
      post jjaeks_path, params: { recommendation: 1, selected_books: keys, jjaek: { content: "한" * 201 } }
    }.to change(Book, :count).by(0).and change(Jjaek, :count).by(0).and change(JjaekRecommendation, :count).by(0)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("New external book", "한" * 201)
    expect(Nokogiri::HTML(response.body).css("input[name='selected_books[]'][form='recommendation-jjaek-form']").map { |input| input["value"] }).to eq(keys)

    expect {
      post jjaeks_path, params: { recommendation: 1, selected_books: keys, jjaek: { content: "세 권을 함께 추천" } },
                        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to change(Book, :count).by(1).and change(Jjaek, :count).by(1).and change(JjaekRecommendation, :count).by(3)
    recommendation = Jjaek.order(:id).last
    imported = Book.find_by!(canonical_isbn: "9780140328721")
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    completion = Nokogiri::HTML(response.body).at_css("[data-recommendation-composer-target='completed']")
    expect(completion["data-location"]).to eq(root_path)
    expect(recommendation.recommended_books).to eq([ book, imported, other_book ])
    expect(BookshelfEntry.count).to eq(0)
    expect(BookActivity.count).to eq(0)
  end

  it "reuses a book registered after external selection and removes duplicate selections at posting" do
    result = { title: "Search metadata", isbn: "9780140328721" }
    post recommendation_books_path, params: { search_result_token: BookSearches::ResultToken.issue(result, user:) }
    keys = Rack::Utils.parse_nested_query(URI.parse(response.location).query).fetch("selected_books")
    existing = Book.create!(title: "Existing metadata", isbn: result[:isbn])

    expect {
      post jjaeks_path, params: { recommendation: 1, selected_books: [ *keys, existing.id ], jjaek: { content: "추천합니다" } }
    }.to change(Book, :count).by(0).and change(JjaekRecommendation, :count).by(1)
    expect(Jjaek.order(:id).last.recommended_books).to eq([ existing ])
    expect(existing.reload.title).to eq("Existing metadata")
  end

  it "rejects forged references, other users' references, and expired external selections before saving" do
    result = { title: "Temporary book", isbn: "9780140328721" }
    post recommendation_books_path, params: { search_result_token: BookSearches::ResultToken.issue(result, user:) }
    keys = Rack::Utils.parse_nested_query(URI.parse(response.location).query).fetch("selected_books")

    [ [ "external:#{'0' * 32}" ], [ result.to_json ] ].each do |invalid_keys|
      expect {
        post jjaeks_path, params: { recommendation: 1, selected_books: invalid_keys, jjaek: { content: "위변조" } }
      }.to change(Book, :count).by(0).and change(Jjaek, :count).by(0)
      expect(response).to redirect_to(book_search_path(recommendation: 1))
    end
    sign_in outsider
    expect {
      post jjaeks_path, params: { recommendation: 1, selected_books: keys, jjaek: { content: "다른 사용자" } }
    }.to change(Book, :count).by(0).and change(Jjaek, :count).by(0)
    expect(flash[:alert]).to eq(I18n.t("recommendations.invalid_selection"))

    sign_in user
    travel 31.minutes do
      expect {
        post jjaeks_path, params: { recommendation: 1, selected_books: keys, jjaek: { content: "만료된 선택" } }
      }.to change(Book, :count).by(0).and change(Jjaek, :count).by(0)
      expect(flash[:alert]).to eq(I18n.t("recommendations.invalid_selection"))
    end
  end

  it "resets expired floating selections with a stream so the user can choose books again" do
    token = BookSearches::ResultToken.issue({ title: "Temporary", isbn: "9780140328721" }, user:)
    post recommendation_books_path, params: { search_result_token: token }
    keys = Rack::Utils.parse_nested_query(URI.parse(response.location).query).fetch("selected_books")
    travel 31.minutes do
      expect {
        post recommendation_books_path, params: { book_id: book.id, selected_books: keys },
                                        headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change(Book, :count).by(0).and change(Jjaek, :count).by(0)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      page = Nokogiri::HTML(response.body)
      expect(page.css("input[name='selected_books[]'][form='recommendation-jjaek-form']")).to be_empty
      expect(page.at_css("turbo-stream[target='recommendation-selection-alert']").text).to include(I18n.t("recommendations.invalid_selection"))
    end
  end

  it "publishes ordered recommendations through HTML and Turbo and reuses the feed and detail interactions" do
    [ "text/html", "text/vnd.turbo-stream.html" ].each do |accept|
      expect {
        post jjaeks_path, params: { recommendation: 1, selected_books: [ other_book.id, book.id, other_book.id ],
                                   jjaek: { content: "두 권을 함께 추천합니다 #함께읽기", visibility: :public_jjaek } },
                          headers: { "Accept" => accept }
      }.to change(Jjaek, :count).by(1).and change(JjaekRecommendation, :count).by(2)
      recommendation = Jjaek.order(:id).last
      expect(recommendation).to be_recommendation
      expect(recommendation.recommended_books).to eq([ other_book, book ])
      expect(recommendation.book_id).to be_nil
      if accept == "text/html"
        expect(response).to redirect_to(root_path)
      else
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        completion = Nokogiri::HTML(response.body).at_css("[data-recommendation-composer-target='completed']")
        expect(completion["data-location"]).to eq(root_path)
      end
      get jjaek_path(recommendation)
      expect(response.body).to include(book_path(book), book_path(other_book), "#함께읽기", jjaek_like_path(recommendation))
      post jjaek_like_path(recommendation)
      post jjaek_comments_path(recommendation), params: { comment: { content: "고마워요" } }
      expect(recommendation.likes.exists?(user:)).to be(true)
      expect(recommendation.comments.exists?(user:, content: "고마워요")).to be(true)
    end
    get root_path
    expect(response.body).to include("두 권을 함께 추천합니다", book.title, other_book.title)
    expect(user.bookshelf_entries).to be_empty
  end

  it "keeps the selected books and entered reason on validation failure without saving partial posts" do
    [ "text/html", "text/vnd.turbo-stream.html" ].each do |accept|
      expect {
        post jjaeks_path, params: { recommendation: 1, query: "추천할", selected_books: [ book.id, other_book.id ],
                                   jjaek: { content: "한" * 201, visibility: :private_jjaek } }, headers: { "Accept" => accept }
      }.not_to change(Jjaek, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq(accept == "text/html" ? "text/html" : "text/vnd.turbo-stream.html")
      expect(response.body).to include(book.title, other_book.title, "한" * 201)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#recommendation-query")["value"]).to eq("추천할")
      expect(page.at_css("[data-recommendation-composer-target='panel']")["data-step"]).to eq("writing")
      expect(page.css("#recommendation-selected-books").text).to include(book.title, other_book.title)
      expect(page.at_css("#recommendation-jjaek-form select[name='jjaek[visibility]'] option[selected]")["value"]).to eq("private_jjaek")
    end
    expect(JjaekRecommendation.count).to eq(0)
    post jjaeks_path, params: { recommendation: 1, jjaek: { content: "책이 없는 추천" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Jjaek.count).to eq(0)
  end

  it "keeps recommendation books fixed during edits and applies personal visibility" do
    post jjaeks_path, params: { recommendation: 1, selected_books: [ book.id ],
                               jjaek: { content: "Private recommendation", visibility: :private_jjaek } }
    recommendation = Jjaek.order(:id).last
    patch jjaek_path(recommendation), params: { selected_books: [ other_book.id ],
                                               jjaek: { content: "Edited reason", recommendation: false, book_id: other_book.id } }
    expect(recommendation.reload.content).to eq("Edited reason")
    expect(recommendation).to be_recommendation
    expect(recommendation.recommended_books).to eq([ book ])
    sign_in outsider
    get jjaek_path(recommendation)
    expect(response).to redirect_to(root_path)
    expect { post jjaek_like_path(recommendation) }.not_to change(Like, :count)
    expect { post jjaek_comments_path(recommendation), params: { comment: { content: "Forbidden" } } }.not_to change(Comment, :count)
  end

  it "uses the existing group creation and read boundaries at selection, composition, and posting" do
    group.group_memberships.create!(user: outsider, status: :active)
    sign_in outsider
    get book_search_path, params: { recommendation: 1, group_id: group.id, selected_books: [ book.id ] }
    expect(response).to have_http_status(:ok)
    get new_group_jjaek_path(group), params: { recommendation: 1, selected_books: [ book.id ] }
    expect(response.body).to include(group.name, I18n.t("recommendations.reason"))
    post group_jjaeks_path(group), params: { recommendation: 1, selected_books: [ book.id ],
                                            jjaek: { content: "동아리 추천", visibility: :private_jjaek } }
    recommendation = Jjaek.order(:id).last
    expect(response).to redirect_to(group_path(group))
    expect(recommendation).to have_attributes(group:, visibility: "public_jjaek", recommendation: true)
    get group_path(group)
    expect(Nokogiri::HTML(response.body).css("main article").text).to include(recommendation.content, book.title)

    group.group_memberships.find_by!(user: outsider).destroy!
    get jjaek_path(recommendation)
    expect(response).to have_http_status(:not_found)
    get book_search_path, params: { recommendation: 1, group_id: group.id }
    expect(response).not_to have_http_status(:ok)
    get new_group_jjaek_path(group), params: { recommendation: 1, selected_books: [ book.id ] }
    expect(response).not_to have_http_status(:ok)
    expect {
      post group_jjaeks_path(group), params: { recommendation: 1, selected_books: [ book.id ], jjaek: { content: "Forbidden" } }
    }.not_to change(Jjaek, :count)
    expect {
      post recommendation_books_path, params: { group_id: group.id, book_id: other_book.id }
    }.not_to change(Book, :count)
    expect(response).not_to have_http_status(:ok)
  end

  it "rejects a mixed book or requote context rather than creating another post type" do
    expect {
      post jjaeks_path, params: { recommendation: 1, selected_books: [ book.id ],
                                 jjaek: { content: "Mixed", book_id: book.id } }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)
    source = user.jjaeks.create!(content: "Original post")
    expect {
      post jjaeks_path, params: { recommendation: 1, selected_books: [ book.id ],
                                 jjaek: { content: "Mixed quote", quoted_jjaek_id: source.id } }
    }.not_to change(Jjaek, :count)
    get new_jjaek_path, params: { recommendation: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("recommendations.choose_books"), I18n.t("recommendations.reason"))
  end

  it "rejects missing selected books without publishing a partial recommendation" do
    missing_id = Book.maximum(:id) + 1
    expect {
      post jjaeks_path, params: { recommendation: 1, selected_books: [ book.id, missing_id ],
                                 jjaek: { content: "Incomplete selection" } }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(book_search_path(recommendation: 1))
    expect(flash[:alert]).to eq(I18n.t("recommendations.invalid_selection"))
  end

  it "classifies recommendation text and tags separately while preserving search permissions" do
    post jjaeks_path, params: { recommendation: 1, selected_books: [ book.id ],
                               jjaek: { content: "추천검색 #추천태그" } }
    recommendation = Jjaek.order(:id).last
    user.jjaeks.create!(content: "일반검색")
    get search_path, params: { q: "추천검색", type: "recommendation_jjaeks" }
    expect(Nokogiri::HTML(response.body).css("main article").text).to include(recommendation.content, book.title)
    get search_path, params: { q: "추천검색", type: "jjaeks" }
    expect(Nokogiri::HTML(response.body).css("main article").text).not_to include(recommendation.content)
    get search_path, params: { tag: "추천태그", type: "recommendation_jjaeks" }
    expect(response.body).to include("추천검색", book.title)
    recommendation.update!(visibility: :private_jjaek)
    sign_in outsider
    get search_path, params: { tag: "추천태그", type: "recommendation_jjaeks" }
    expect(response.body).not_to include("추천검색", book.title)
  end
end
