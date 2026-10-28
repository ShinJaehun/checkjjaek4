require "rails_helper"

RSpec.describe "Books", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:user) { User.create!(name: "Shelf Owner", email: "shelf-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "서재에 있는 책", authors_text: "저자") }

  describe "GET /books/:id" do
    it "allows the shelf owner to open the book page" do
      entry = user.bookshelf_entries.create!(book:, status: :reading)
      stickers = 2.times.map do |index|
        StickerDefinition.create!(key: "book_detail_selected_#{index}", name: "선택 스티커 #{index}")
      end
      entry.sticker_definitions = stickers
      sign_in user

      get book_path(book)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("서재에 있는 책")
      page = Nokogiri::HTML(response.body)
      state = page.at_css("form[action='#{bookshelf_entry_path(entry)}']")
      expect(state).to be_present
      expect(state.at_css('[data-reading-status-card] legend').text).to eq(I18n.t("books.show.status_label"))
      expect(state.at_css('[data-reading-stickers-card] legend').text).to eq(I18n.t("bookshelf_entries.form.stickers"))
      expect(state.ancestors("dialog").first["id"]).to eq("book-reading-dialog")
      expect(state.ancestors("dialog").first["open"]).to be_nil
      expect(state.ancestors("[data-book-modal-auto-open-value='false']")).not_to be_empty
      header = page.at_css("h1").ancestors("section").first
      expect(state.ancestors("section").first).to eq(header)
      expect(header.text).to include(I18n.t("books.show.current_bookshelf"))
      expect(header.css("h2").reject { |heading| heading.ancestors("dialog").any? }).to be_empty
      expect(header.at_css("#book-reading-dialog h2").text).to eq(I18n.t("books.show.reading_record_title"))
      expect(header.at_css("[data-reading-status='reading']")).to be_present
      expect(header.css("[data-reading-sticker]").map { |badge| badge["data-reading-sticker"] }).to match_array(stickers.map(&:key))
      expect(header.text).not_to include(I18n.t("books.show.library_context_title"))
      expect(response.body).to include('name="jjaek[content]"')
      expect(response.body).to include(I18n.t("jjaeks.actions.publish_book"))
    end

    it "renders the cover, bibliography, and expandable description once in the title card" do
      book.update!(title: "긴 제목 " * 12, authors_text: "긴 저자 이름 " * 8,
        publisher: "긴 출판사 이름 " * 8, isbn: "9780000000099",
        thumbnail: "https://example.com/detail-cover.jpg", description: "책 소개 " * 80,
        external_url: "https://example.com/detail")
      user.bookshelf_entries.create!(book:)
      sign_in user

      get book_path(book)

      expect(response).to have_http_status(:ok)
      header = Nokogiri::HTML(response.body).at_css("h1").ancestors("section").first
      expect(header.css("h1").map(&:text)).to eq([ book.title ])
      expect(header.css("img[alt='#{book.title}']").size).to eq(1)
      expect(header.css("dl dd").map(&:text)).to eq([ book.authors_text, book.publisher, book.isbn ])
      expect(header.css("#book-description").map(&:text)).to eq([ book.description ])
      expect(header.css("[data-controller='book-description']").size).to eq(1)
      expect(header.at_css("button[aria-controls='book-description']")["data-action"]).to eq("book-description#toggle")
      expect(header.css("a[href='#{book.external_url}']").map { |link| link.text.strip }).to eq([ I18n.t("books.show.external_link") ])
    end

    it "shows the current bookshelf context for a shelved book" do
      bookshelf = user.bookshelves.create!(name: "상세 책장", visibility: :private)
      user.bookshelf_entries.create!(book:, bookshelf:, status: :reading)
      sign_in user

      get book_path(book)

      expect(response.body).to include(I18n.t("books.show.current_bookshelf"))
      expect(response.body).to include("상세 책장")
    end

    it "shows a bookshelf move form when the user has multiple bookshelves" do
      bookshelf = user.bookshelves.create!(name: "현재 상세 책장", visibility: :private, color_key: "red")
      target_bookshelf = user.bookshelves.create!(name: "옮길 상세 책장", visibility: :private, color_key: "blue")
      entry = user.bookshelf_entries.create!(book:, bookshelf:)
      group = Group.create!(name: "이동 문맥 동아리", group_admin: user, lifecycle_status: :active)
      sign_in user

      get book_path(book, group_id: group.id)

      expect(response.body).to include(%(action="#{move_bookshelf_entry_path(entry)}"))
      expect(response.body).to include(%(name="bookshelf_id"))
      expect(response.body).to include(%(value="book"))
      expect(response.body).to include(target_bookshelf.name)
      page = Nokogiri::HTML(response.body)
      dialog = page.at_css("#book-move-dialog")
      expect(dialog["open"]).to be_nil
      expect(dialog["aria-labelledby"]).to eq("book-move-dialog-title")
      form = dialog.at_css("form")
      expect(form.at_css("input[name='_method']")["value"]).to eq("patch")
      expect(form.at_css("input[name='return_to']")["value"]).to eq("book")
      expect(form.at_css("input[name='group_id']")["value"]).to eq(group.id.to_s)
      choices = form.css("input[type='radio'][name='bookshelf_id']")
      expect(choices.map { |choice| choice["value"] }).to match_array(user.bookshelves.ids.map(&:to_s))
      expect(choices.select { |choice| choice["checked"] }.map { |choice| choice["value"] }).to eq([ bookshelf.id.to_s ])
      current_badge = choices.find { |choice| choice["value"] == bookshelf.id.to_s }.parent
      target_badge = choices.find { |choice| choice["value"] == target_bookshelf.id.to_s }.parent
      expect(current_badge["class"].split).to eq(%w[ui-choice])
      expect(target_badge["class"]).to eq(current_badge["class"])
      expect(form.at_css("input[type='submit']")["value"]).to eq(I18n.t("bookshelf_entries.actions.move"))
    end

    it "shows the book-context label for book-linked jjaeks" do
      user.bookshelf_entries.create!(book:, status: :reading)
      book_jjaek = user.jjaeks.create!(book:, content: "BOOK_CONTEXT_LABEL_BODY")
      sign_in user

      get book_path(book)

      expect(response.body).to include(book_jjaek.content)
      expect(response.body).to include(%(id="comments_panel_book_#{book.id}_jjaek_#{book_jjaek.id}"))
      expect(response.body).to include(%(href="/jjaeks/#{book_jjaek.id}/comments?book_id=#{book.id}&amp;comments_context=book))
      expect(response.body).to include(%(data-turbo-stream="true"))
      expect(response.body).to include(%(href="#{ERB::Util.html_escape(jjaek_path(book_jjaek, return_to: book_path(book), anchor: "comments_panel_jjaek_#{book_jjaek.id}"))}"))
      expect(response.body).to include(user.name)
      expect(response.body).to include(user_path(user))
      expect(response.body).to include(book.title)
      expect(response.body).to include("님의 책짹")

      card = Nokogiri::HTML(response.body).at_css("#jjaek_#{book_jjaek.id}")
      expect(card.text).not_to include(book.title, book.authors_text)
      expect(card.css("img[alt='#{book.title}']")).to be_empty

      get user_path(user)

      feed_card = Nokogiri::HTML(response.body).at_css("#jjaek_#{book_jjaek.id}")
      expect(feed_card.text).to include(book.title, book.authors_text, book_jjaek.content)
    end

    it "shows only original book jjaeks on the book page while keeping the requote count on the original" do
      user.bookshelf_entries.create!(book:, status: :reading)
      original = user.jjaeks.create!(book:, content: "BOOK_ORIGINAL_BODY")
      requote = user.jjaeks.create!(book:, content: "BOOK_REQUOTE_BODY", quoted_jjaek: original)
      sign_in user

      get book_path(book)

      expect(response.body).to include(original.content)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 1))
      expect(response.body).not_to include(requote.content)
    end

    it "shows the book as read-only when the user has no bookshelf entry" do
      other_user = User.create!(name: "Other Reader", email: "other-book-reader@example.com", password: "password123!", password_confirmation: "password123!")
      book.jjaeks.create!(user: other_user, content: "다른 독자의 공개 Jjaek")
      sign_in user

      get book_path(book)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("서재에 있는 책")
      expect(response.body).to include("다른 독자의 공개 Jjaek")
      header = Nokogiri::HTML(response.body).at_css("h1").ancestors("section").first
      expect(header.at_css("button[aria-controls='book-shelf-dialog']")).to be_present
      expect(header.at_css("#book-shelf-dialog")).to be_present
      expect(header.at_css("#book-reading-dialog")).to be_nil
      expect(header.text).not_to include(I18n.t("books.show.library_context_title"), I18n.t("books.show.read_only_description"))
      expect(response.body).to include(%(action="#{bookshelf_entries_path}"))
      expect(response.body).to include(%(name="book_id"))
      expect(response.body).to include(%(value="#{book.id}"))
      expect(response.body).not_to include("/bookshelf_entries/new")
      expect(response.body).to include(I18n.t("bookshelf_entries.new.title"))
      expect(response.body).not_to include('name="bookshelf_entry[status]"')
      expect(response.body).not_to include('name="jjaek[content]"')
    end

    it "keeps the personal writing modal closed with its visibility selector and a separate state save button" do
      user.bookshelf_entries.create!(book: book)
      sign_in user

      get book_path(book)

      page = Nokogiri::HTML(response.body)
      form = page.at_css("form[action='#{jjaeks_path}']")
      expect(form).to be_present
      expect(form.ancestors("dialog").first["id"]).to eq("book-writing-dialog")
      expect(form.ancestors("dialog").first["open"]).to be_nil
      expect(page.at_css("[data-book-modal-auto-open-value='false']")).to be_present
      expect(form.at_css("input[name='jjaek[visibility]']")).to be_present
      expect(form.at_css("input[type='submit']")["value"]).to eq(I18n.t("jjaeks.actions.publish_book"))
      dialog = page.at_css("#book-writing-dialog")
      expect(dialog.css("h2").map(&:text)).to eq([ I18n.t("books.show.write_book_jjaek") ])
      expect(dialog.at_css("[data-book-posting-target='title']")).to be_nil
      expect(page.at_css("form[action='#{bookshelf_entry_path(user.bookshelf_entries.find_by!(book:))}'] input[type='submit']")).to be_present
      header = page.at_css("h1").ancestors("section").first
      expect(header.at_css("button[aria-controls='book-reading-dialog']").text.strip).to eq(I18n.t("books.show.edit_reading_record"))
      expect(header.at_css("button[aria-controls='book-writing-dialog']").ancestors("[data-controller='book-modal']").first).to eq(dialog.parent)
      expect(dialog.parent.css("dialog").map { |modal| modal["id"] }).to eq([ "book-writing-dialog" ])
    end

    it "opens the writing form for a requote and keeps the group and return context" do
      user.bookshelf_entries.create!(book:)
      author = User.create!(name: "Source author", email: "book-source-author@example.com", password: "password123!")
      original = author.jjaeks.create!(book:, content: "QUOTE_SOURCE")
      group = Group.create!(name: "Book club", group_admin: user, group_type: :public_group, lifecycle_status: :active)
      sign_in user

      get book_path(book, group_id: group.id, quote_id: original.id, return_to: root_path)

      page = Nokogiri::HTML(response.body)
      form = page.at_css("form[action='#{group_jjaeks_path(group)}']")
      expect(form).to be_present
      expect(form.ancestors("dialog").first["id"]).to eq("book-writing-dialog")
      expect(form.ancestors("[data-book-modal-auto-open-value='true']")).not_to be_empty
      expect(form.at_css("input[name='jjaek[quoted_jjaek_id]']")["value"]).to eq(original.id.to_s)
      expect(form.at_css("input[name='return_to']")["value"]).to eq(root_path)
      reading_form = page.at_css("form[action='#{bookshelf_entry_path(user.bookshelf_entries.find_by!(book:))}']")
      expect(reading_form.at_css("input[name='group_id']")["value"]).to eq(group.id.to_s)
      expect(reading_form.at_css("input[name='quote_id']")["value"]).to eq(original.id.to_s)
      expect(reading_form.at_css("input[name='return_to']")["value"]).to eq(root_path)

      patch bookshelf_entry_path(user.bookshelf_entries.find_by!(book:)), params: {
        group_id: group.id, quote_id: original.id, return_to: root_path,
        bookshelf_entry: { status: :reading, sticker_definition_ids: [] }
      }
      expect(response).to redirect_to(book_path(book, group_id: group.id, quote_id: original.id, return_to: root_path))
    end

    it "opens the writing form after a validation error" do
      user.bookshelf_entries.create!(book:)
      sign_in user

      post jjaeks_path, params: { jjaek: { book_id: book.id, content: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      form = Nokogiri::HTML(response.body).at_css("form[action='#{jjaeks_path}']")
      expect(form.ancestors("dialog").first["id"]).to eq("book-writing-dialog")
      expect(form.ancestors("[data-book-modal-auto-open-value='true']")).not_to be_empty
    end

    it "reopens the writing modal with the submitted content and length error" do
      user.bookshelf_entries.create!(book:)
      sign_in user

      submitted_content = "x" * 201
      post jjaeks_path, params: { jjaek: { book_id: book.id, content: submitted_content } }

      expect(response).to have_http_status(:unprocessable_content)
      form = Nokogiri::HTML(response.body).at_css("form[action='#{jjaeks_path}']")
      expect(form.at_css("textarea[name='jjaek[content]']").text.strip).to eq(submitted_content)
      expect(form.text).to include(I18n.t("content_form.too_long", count: 200))
      expect(form.ancestors("dialog").first["id"]).to eq("book-writing-dialog")
      expect(form.ancestors("[data-book-modal-auto-open-value='true']")).not_to be_empty
    end

    it "shows only public personal book jjaeks before the book is added to the library" do
      friend = User.create!(name: "Reader friend", email: "book-show-friend@example.com", password: "password123!")
      BookFriendship.create!(requester: user, addressee: friend, status: :accepted)
      public_jjaek = friend.jjaeks.create!(book: book, content: "UNSHELVED_PUBLIC_BOOK")
      friend_jjaek = friend.jjaeks.create!(book: book, content: "UNSHELVED_FRIEND_BOOK", visibility: :book_friends)
      private_jjaek = user.jjaeks.create!(book: book, content: "UNSHELVED_PRIVATE_BOOK", visibility: :private_jjaek)
      sign_in user

      get book_path(book)

      expect(response.body).to include(public_jjaek.content)
      expect(response.body).not_to include(friend_jjaek.content, private_jjaek.content, 'name="bookshelf_entry[status]"', 'name="jjaek[content]"')

      user.bookshelf_entries.create!(book: book)
      get book_path(book)
      expect(response.body).to include(friend_jjaek.content, private_jjaek.content)
    end

    it "redirects guests before showing the library context" do
      user.bookshelf_entries.create!(book:, status: :reading)

      get book_path(book)

      expect(response).to redirect_to(new_user_session_path)
    end

    it "offers single-choice bookshelf badges in a closed registration modal and saves the chosen shelf" do
      target_bookshelf = user.bookshelves.create!(name: "따로 담을 책장", visibility: :private)
      sign_in user

      get book_path(book)

      expect(response.body).to include(I18n.t("bookshelf_entries.form.target_bookshelf"))
      expect(response.body).to include(%(name="bookshelf_entry[bookshelf_id]"))
      expect(response.body).to include("따로 담을 책장")

      page = Nokogiri::HTML(response.body)
      dialog = page.at_css("#book-shelf-dialog")
      expect(dialog["open"]).to be_nil
      expect(dialog["aria-labelledby"]).to eq("book-shelf-dialog-title")
      choices = dialog.css("input[type='radio'][name='bookshelf_entry[bookshelf_id]']")
      expect(choices.map { |choice| choice["value"] }).to match_array(user.bookshelves.ids.map(&:to_s))
      expect(choices.select { |choice| choice["checked"] }.map { |choice| choice["value"] }).to eq([ user.bookshelves.default_first.first.id.to_s ])
      expect(page.at_css("#book-writing-dialog")).to be_nil
      expect(page.at_css("input[name='bookshelf_entry[status]']")).to be_nil

      post bookshelf_entries_path, params: { book_id: book.id, bookshelf_entry: { bookshelf_id: target_bookshelf.id } }

      expect(response).to redirect_to(book_path(book))
      expect(user.bookshelf_entries.find_by!(book:).bookshelf).to eq(target_bookshelf)
    end

    it "adds a read-only book to the shelf and returns to the writable book page" do
      sign_in user

      expect {
        post bookshelf_entries_path, params: {
          book_id: book.id
        }
      }.to change(user.bookshelf_entries, :count).by(1)

      expect(response).to redirect_to(book_path(book))
      expect(user.bookshelf_entries.find_by!(book:).status).to be_nil

      follow_redirect!

      expect(response.body).to include(%(action="#{bookshelf_entry_path(user.bookshelf_entries.find_by!(book:))}"))
      expect(response.body).to include('name="jjaek[content]"')

      document = Nokogiri::HTML(response.body)
      status_select = document.at_css('select[name="bookshelf_entry[status]"]')
      status_choices = document.css('input[type="radio"][name="bookshelf_entry[status]"]')

      expect(status_select).to be_nil
      expect(status_choices.map { |choice| choice["value"] }).to match_array([ "", *BookshelfEntry.statuses.keys ])
      expect(status_choices.select { |choice| choice.attribute("checked") }.map { |choice| choice["value"] }).to eq([ "" ])
    end

    it "shows only accepted friends' visible activity and readable personal book jjaeks" do
      friend = User.create!(name: "Book friend", email: "book-preview-friend@example.com", password: "password123!")
      private_friend = User.create!(name: "Private friend", email: "book-preview-private@example.com", password: "password123!")
      stranger = User.create!(name: "Stranger", email: "book-preview-stranger@example.com", password: "password123!")
      BookFriendship.create!(requester: user, addressee: friend, status: :accepted)
      BookFriendship.create!(requester: user, addressee: private_friend, status: :accepted)
      public_shelf = friend.bookshelves.create!(name: "Open shelf", visibility: :public)
      private_shelf = private_friend.bookshelves.create!(name: "Secret shelf", visibility: :private)
      public_entry = friend.bookshelf_entries.create!(book:, bookshelf: public_shelf)
      private_entry = private_friend.bookshelf_entries.create!(book:, bookshelf: private_shelf)
      visible_activity = public_entry.book_activities.create!(user: friend, book:, action: :added_to_shelf)
      private_activity = private_entry.book_activities.create!(user: private_friend, book:, action: :status_changed)
      own_entry = user.bookshelf_entries.create!(book:)
      own_activity = own_entry.book_activities.create!(user:, book:, action: :added_to_shelf)
      stranger_entry = stranger.bookshelf_entries.create!(book:)
      stranger_activity = stranger_entry.book_activities.create!(user: stranger, book:, action: :added_to_shelf)
      stranger_jjaek = stranger.jjaeks.create!(book:, content: "STRANGER_PUBLIC_PREVIEW")
      public_jjaek = friend.jjaeks.create!(book:, content: "FRIEND_PUBLIC_PREVIEW")
      private_jjaek = friend.jjaeks.create!(book:, content: "FRIEND_PRIVATE_PREVIEW", visibility: :private_jjaek)
      hidden_jjaek = friend.jjaeks.create!(book:, content: "FRIEND_HIDDEN_PREVIEW")
      hidden_jjaek.update_column(:hidden_at, Time.current)
      deleted_jjaek = friend.jjaeks.create!(book:, content: "FRIEND_DELETED_PREVIEW")
      deleted_jjaek.update_columns(content: "", deleted_at: Time.current)
      sign_in user

      get book_path(book)

      page = Nokogiri::HTML(response.body)
      preview = page.css("[data-book-friend-activity]")
      preview_ids = preview.map { |card| card["id"] }
      expect(page.css("h2").map(&:text)).to include("책 친구 활동")
      expect(preview_ids).to include("book_friend_activity_book_activity_#{visible_activity.id}", "book_friend_activity_jjaek_#{public_jjaek.id}")
      excluded_ids = [
        "book_friend_activity_book_activity_#{private_activity.id}", "book_friend_activity_book_activity_#{own_activity.id}",
        "book_friend_activity_book_activity_#{stranger_activity.id}", "book_friend_activity_jjaek_#{private_jjaek.id}",
        "book_friend_activity_jjaek_#{hidden_jjaek.id}", "book_friend_activity_jjaek_#{deleted_jjaek.id}",
        "book_friend_activity_jjaek_#{stranger_jjaek.id}"
      ]
      expect(preview_ids & excluded_ids).to be_empty
      activity_card = preview.at_css("#book_friend_activity_book_activity_#{visible_activity.id}")
      expect(activity_card.at_css("p.leading-6").text).to eq("Book friend님이 이 책을 서재에 담았습니다.")
      expect(activity_card.css("[data-reading-status], [data-reading-sticker]")).to be_empty
      expect(preview.text).to include("FRIEND_PUBLIC_PREVIEW")
      preview_jjaek = preview.at_css("#book_friend_activity_jjaek_#{public_jjaek.id}")
      expect(preview_jjaek.text).to include("Book friend님의 책짹")
      expect(preview_jjaek.at_css("#book_friend_like_action_jjaek_#{public_jjaek.id}")).to be_present
      expect(preview_jjaek.at_css("#book_friend_comment_action_jjaek_#{public_jjaek.id}")).to be_present
      expect(preview_jjaek.at_css("#comments_panel_book_friend_#{book.id}_jjaek_#{public_jjaek.id}")).to be_present
      expect(preview.css("a[href='#{user_path(friend)}']").size).to be >= 2
      expect(preview.css("img[alt='#{friend.name}']").size).to be >= 2
      expect(preview.css("a[href='#{book_path(book)}']")).to be_empty
      expect(preview.text).not_to include(book.title, book.authors_text)
      expect(page.css("#jjaek_#{public_jjaek.id}").size).to eq(1)
    end

    it "keeps duplicate friend and book-list Jjaek actions in separate DOM contexts" do
      friend = User.create!(name: "Card friend", email: "book-preview-actions@example.com", password: "password123!")
      BookFriendship.create!(requester: user, addressee: friend, status: :accepted)
      user.bookshelf_entries.create!(book:)
      jjaek = friend.jjaeks.create!(book:, content: "FRIEND_CARD_ACTIONS")
      user.jjaeks.create!(book:, quoted_jjaek: jjaek, content: "MY_REQUOTE_FOR_FRIEND_CARD")
      sign_in user

      get book_path(book)

      page = Nokogiri::HTML(response.body)
      preview = page.at_css("#book_friend_activity_jjaek_#{jjaek.id}")
      book_list = page.at_css("#jjaek_#{jjaek.id}")
      expect(preview).to be_present
      expect(book_list).to be_present
      expect(preview.text).to include("Card friend님의 책짹", jjaek.content)
      expect(preview.text).to include(I18n.t("jjaeks.meta.requotes", count: 1))
      expect(preview.css("a[href='#{book_path(book)}']")).to be_empty
      expect(preview.css("a").map { |link| link.text.strip }).not_to include(I18n.t("jjaeks.actions.view"))
      expect(book_list.css("a").map { |link| link.text.strip }).to include(I18n.t("jjaeks.actions.view"))
      ids = [ preview, book_list ].flat_map { |card| [ card["id"], *card.css("[id]").map { |node| node["id"] } ] }
      expect(ids.uniq.size).to eq(ids.size)
      expect(preview.at_css("#book_friend_like_action_jjaek_#{jjaek.id}")).to be_present
      expect(book_list.at_css("#like_action_jjaek_#{jjaek.id}")).to be_present
      expect(preview.at_css("#book_friend_comment_action_jjaek_#{jjaek.id}")).to be_present
      expect(book_list.at_css("#comment_action_jjaek_#{jjaek.id}")).to be_present
      expect(preview.at_css("#comments_panel_book_friend_#{book.id}_jjaek_#{jjaek.id}")).to be_present
      expect(book_list.at_css("#comments_panel_book_#{book.id}_jjaek_#{jjaek.id}")).to be_present

      post jjaek_like_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include(%(target="like_action_jjaek_#{jjaek.id}"), %(target="book_friend_like_action_jjaek_#{jjaek.id}"))
      expect(response.body).to include(I18n.t("jjaeks.meta.likes", count: 1))

      post jjaek_comments_path(jjaek),
           params: { comment: { content: "FRIEND_PANEL_COMMENT" }, comments_context: "book_friend", book_id: book.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include(%(target="comments_panel_book_friend_#{book.id}_jjaek_#{jjaek.id}"))
      expect(response.body).to include(%(target="comment_action_jjaek_#{jjaek.id}"), %(target="book_friend_comment_action_jjaek_#{jjaek.id}"))
      expect(response.body).to include(I18n.t("jjaeks.meta.comments", count: 1))
      comment = jjaek.comments.find_by!(content: "FRIEND_PANEL_COMMENT")
      expect(response.body).to include(%(id="book_friend_comment_#{comment.id}"))
      expect(response.body).to include(%(id="book_friend_jjaek_#{jjaek.id}_new_comment"))

      get jjaek_comments_path(jjaek, comments_context: "book", book_id: book.id),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include(%(id="comment_#{comment.id}"))
      expect(response.body).not_to include(%(id="book_friend_comment_#{comment.id}"))

      delete jjaek_like_path(jjaek), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include(%(target="like_action_jjaek_#{jjaek.id}"), %(target="book_friend_like_action_jjaek_#{jjaek.id}"))

      delete jjaek_comment_path(jjaek, comment),
             params: { comments_context: "book", book_id: book.id },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include(%(target="comments_panel_book_#{book.id}_jjaek_#{jjaek.id}"))
      expect(response.body).to include(%(target="comment_action_jjaek_#{jjaek.id}"), %(target="book_friend_comment_action_jjaek_#{jjaek.id}"))
    end

    it "shows recorded status and sticker changes instead of the current bookshelf entry" do
      friend = User.create!(name: "History friend", email: "book-preview-history@example.com", password: "password123!")
      BookFriendship.create!(requester: user, addressee: friend, status: :accepted)
      shelf = friend.bookshelves.create!(name: "Open shelf", visibility: :public)
      entry = friend.bookshelf_entries.create!(book:, bookshelf: shelf, status: :wish)
      added = StickerDefinition.create!(key: "loved_it", name: "좋았어요")
      removed = StickerDefinition.create!(key: "recommended_to_me", name: "추천받았어요")
      current = StickerDefinition.create!(key: "stayed_with_me", name: "마음에 남아요")
      entry.sticker_definitions << current
      activity = entry.book_activities.create!(user: friend, book:, action: :bookshelf_entry_updated, metadata: {
        from_status: "reading", to_status: "finished",
        added_sticker_definition_ids: [ added.id ], added_sticker_names: [ added.name ],
        removed_sticker_definition_ids: [ removed.id ], removed_sticker_names: [ removed.name ]
      })
      legacy_activity = entry.book_activities.create!(user: friend, book:, action: :sticker_removed, metadata: { sticker_name: "옛 스티커" })
      sign_in user

      get book_path(book)

      page = Nokogiri::HTML(response.body)
      card = page.at_css("#book_friend_activity_book_activity_#{activity.id}")
      expect(card.css("[data-reading-status]").map { |badge| badge["data-reading-status"] }).to eq([ "finished" ])
      expect(card.css("[data-reading-sticker]").map { |badge| badge["data-reading-sticker"] }).to eq([ "loved_it", "recommended_to_me" ])
      expect(card.at_css("p.leading-6").css("[data-reading-status], [data-reading-sticker]").size).to eq(3)
      expect(card.text).to include("붙였고", "제거했습니다")
      expect(card.text).not_to include(current.name)
      expect(page.at_css("#book_friend_activity_book_activity_#{legacy_activity.id}").text).to include("옛 스티커")
    end

    it "rechecks the friendship and current bookshelf visibility for old activity" do
      friend = User.create!(name: "Visibility friend", email: "book-preview-visibility@example.com", password: "password123!")
      friendship = BookFriendship.create!(requester: user, addressee: friend, status: :accepted)
      shelf = friend.bookshelves.create!(name: "Changing shelf", visibility: :book_friends)
      entry = friend.bookshelf_entries.create!(book:, bookshelf: shelf)
      activity = entry.book_activities.create!(user: friend, book:, action: :bookshelf_entry_updated, metadata: { from_status: nil, to_status: "reading" })
      sign_in user

      get book_path(book)
      expect(response.body).to include(%(id="book_friend_activity_book_activity_#{activity.id}"))

      shelf.update!(visibility: :private)
      get book_path(book)
      expect(response.body).not_to include(%(id="book_friend_activity_book_activity_#{activity.id}"))

      shelf.update!(visibility: :public)
      friendship.destroy!
      get book_path(book)
      expect(response.body).not_to include(%(id="book_friend_activity_book_activity_#{activity.id}"))
    end

    it "limits the mixed friend preview to three recent records with stable ties" do
      friend = User.create!(name: "Timeline friend", email: "book-preview-order@example.com", password: "password123!")
      BookFriendship.create!(requester: user, addressee: friend, status: :accepted)
      entry = friend.bookshelf_entries.create!(book:)
      time = Time.zone.parse("2026-10-19 12:00:00")
      activities = Array.new(4) do |index|
        entry.book_activities.create!(user: friend, book:, action: :added_to_shelf, created_at: index < 2 ? time : time - 1.second)
      end
      jjaeks = Array.new(4) do |index|
        friend.jjaeks.create!(book:, content: "PREVIEW_ORDER_#{index}", created_at: time)
      end
      sign_in user

      get book_path(book)

      ids = Nokogiri::HTML(response.body).css("[data-book-friend-activity]").map { |card| card["id"] }
      expect(ids).to eq(activities.first(2).reverse.map { |activity| "book_friend_activity_book_activity_#{activity.id}" } + [ "book_friend_activity_jjaek_#{jjaeks.last.id}" ])
    end
  end

  describe "GET /books/lookup" do
    it "previews a new search result without writing and adds it to the shelf on POST" do
      sign_in user
      result = {
        title: "검색한 책", authors_text: "검색 저자", publisher: "검색 출판사",
        thumbnail: "https://example.com/cover.jpg", isbn: "9780000000001",
        contents_excerpt: "검색 설명", url: "https://example.com/books/1"
      }
      token = search_result_token_for(result)

      expect {
        get lookup_books_path, params: { search_result_token: token }
      }.not_to change { [ Book.count, BookshelfEntry.count ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("검색한 책", "검색 저자", "검색 설명", "https://example.com/cover.jpg")
      expect(response.body).to include('name="search_result_token"', I18n.t("bookshelf_entries.new.title"))
      expect(response.body).not_to include('name="book_id"')
      registration = Nokogiri::HTML(response.body).at_css("#book-shelf-dialog form")
      expect(registration.at_css("input[name='search_result_token']")["value"]).to eq(token)

      expect {
        post bookshelf_entries_path, params: { search_result_token: token }
      }.to change(Book, :count).by(1).and change(BookshelfEntry, :count).by(1)

      expect(response).to redirect_to(book_path(Book.find_by!(isbn: "9780000000001")))
    end

    it "redirects to an existing book without changing its metadata" do
      existing_book = Book.create!(
        title: "기존 책",
        authors_text: "기존 저자",
        isbn: "9780000000002",
        external_url: "https://example.com/books/2"
      )
      sign_in user
      token = search_result_token_for({
        title: "기존 책 새 제목", authors_text: "검색 저자", publisher: "검색 출판사",
        thumbnail: nil, isbn: "9780000000002", contents_excerpt: "검색 설명",
        url: "https://example.com/books/2"
      })
      original_attributes = existing_book.attributes

      expect {
        get lookup_books_path, params: { search_result_token: token }
      }.not_to change { [ Book.count, BookshelfEntry.count ] }

      expect(response).to redirect_to(book_path(existing_book))
      expect(existing_book.reload.attributes).to eq(original_attributes)
    end

    it "does not write when search ISBN and URL identify different books" do
      Book.create!(title: "ISBN 책", isbn: "9780000000002")
      Book.create!(title: "URL 책", external_url: "https://example.com/collision")
      sign_in user
      token = search_result_token_for({
        title: "충돌 책", authors_text: "저자", publisher: "", thumbnail: nil,
        isbn: "9780000000002", contents_excerpt: "", url: "https://example.com/collision"
      })

      expect {
        get lookup_books_path, params: { search_result_token: token }
      }.not_to change { [ Book.count, BookshelfEntry.count ] }

      expect(response).to redirect_to(book_search_path)
      expect(flash[:alert]).to eq(I18n.t("book_search.errors.identity_conflict"))
    end

    it "previews a book with unsafe URLs using the default cover without writing" do
      sign_in user
      token = BookSearches::ResultToken.issue({
        title: "표지 없는 책", authors_text: "저자", publisher: "", thumbnail: "javascript:alert(1)",
        isbn: "9780000000002", contents_excerpt: "소개", url: "file:///etc/passwd"
      }, user: user)

      expect {
        get lookup_books_path, params: { search_result_token: token }
      }.not_to change { [ Book.count, BookshelfEntry.count ] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("표지 없는 책", "저자", "소개", I18n.t("books.thumbnail.no_thumbnail"))
      expect(response.body).not_to include("javascript:alert(1)", "file:///etc/passwd")
    end

    it "rejects a tampered or expired search result without writing" do
      sign_in user
      token = search_result_token_for({
        title: "만료 책", authors_text: "저자", publisher: "출판사", thumbnail: nil,
        isbn: "9780000000003", contents_excerpt: "소개", url: "https://example.com/books/3"
      })

      expect {
        get lookup_books_path, params: { search_result_token: "#{token}tampered" }
      }.not_to change { [ Book.count, BookshelfEntry.count ] }
      expect(response).to redirect_to(book_search_path)
      expect(flash[:alert]).to eq(I18n.t("book_search.errors.invalid_result"))

      travel_to(31.minutes.from_now) do
        expect {
          get lookup_books_path, params: { search_result_token: token }
        }.not_to change { [ Book.count, BookshelfEntry.count ] }
        expect(response).to redirect_to(book_search_path)
        expect(flash[:alert]).to eq(I18n.t("book_search.errors.invalid_result"))
      end
    end

    it "keeps the group context through search preview and shelf creation" do
      group_admin = User.create!(name: "Admin", email: "book-lookup-group-admin@example.com", password: "password123!")
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "Readers", group_type: :private_group)
      group.group_memberships.create!(user:, status: :active)
      sign_in user
      token = search_result_token_for(
        {
          title: "동아리 검색 책", authors_text: "저자", publisher: "출판사", thumbnail: nil,
          isbn: "9780000000004", contents_excerpt: "소개", url: "https://example.com/books/4"
        }, group_id: group.id
      )

      get lookup_books_path, params: { search_result_token: token, group_id: group.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="group_id"', "동아리 검색 책")

      post bookshelf_entries_path, params: { search_result_token: token, group_id: group.id }

      expect(response).to redirect_to(book_path(Book.find_by!(isbn: "9780000000004"), group_id: group.id))
    end
  end

  def search_result_token_for(result, group_id: nil)
    allow(BookSearches::SearchService).to receive(:call).with(query: result[:title], page: 1).and_return(
      results: [ result ], meta: { total_count: 1, pageable_count: 1, is_end: true }
    )
    get book_search_path, params: { query: result[:title], group_id: }

    Nokogiri::HTML(response.body).at_css('input[name="search_result_token"]')["value"]
  end
end
