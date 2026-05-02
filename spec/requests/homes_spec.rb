require "rails_helper"

RSpec.describe "Homes", type: :request do
  let(:viewer) { User.create!(name: "Viewer", email: "home-viewer@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book_friend) { User.create!(name: "Book Friend", email: "home-book-friend@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:followee) { User.create!(name: "Followee", email: "home-followee@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:stranger) { User.create!(name: "Stranger", email: "home-stranger@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:viewer_book) { Book.create!(title: "내 활동 책", authors_text: "저자") }
  let(:friend_book) { Book.create!(title: "책친구 활동 책", authors_text: "저자") }
  let(:followee_book) { Book.create!(title: "소식받기 활동 책", authors_text: "저자") }
  let(:stranger_book) { Book.create!(title: "낯선 활동 책", authors_text: "저자") }

  describe "GET /" do
    it "shows the viewer's own BookActivity in the home feed" do
      BookActivity.create!(user: viewer, book: viewer_book, action: :added_to_shelf)
      sign_in viewer

      get root_path

      expect(response.body).to include("Viewer님이 『내 활동 책』를 서재에 담았습니다.")
    end

    it "shows an accepted book friend's BookActivity in the home feed" do
      BookFriendship.create!(requester: viewer, addressee: book_friend, status: :accepted)
      BookActivity.create!(user: book_friend, book: friend_book, action: :added_to_shelf)
      sign_in viewer

      get root_path

      expect(response.body).to include("Book Friend님이 『책친구 활동 책』를 서재에 담았습니다.")
    end

    it "does not show a follow-only user's BookActivity in the home feed" do
      viewer.active_follows.create!(followee:)
      BookActivity.create!(user: followee, book: followee_book, action: :added_to_shelf)
      sign_in viewer

      get root_path

      expect(response.body).not_to include("소식받기 활동 책")
    end

    it "does not show a stranger's BookActivity in the home feed" do
      BookActivity.create!(user: stranger, book: stranger_book, action: :added_to_shelf)
      sign_in viewer

      get root_path

      expect(response.body).not_to include("낯선 활동 책")
    end

    it "still shows existing Jjaeks in the home feed" do
      viewer.jjaeks.create!(content: "HOME_FEED_EXISTING_JJAEK", visibility: :public_jjaek)
      sign_in viewer

      get root_path

      expect(response.body).to include("HOME_FEED_EXISTING_JJAEK")
    end

    it "orders Jjaeks and BookActivities together by created_at" do
      old_jjaek = viewer.jjaeks.create!(
        content: "HOME_FEED_OLD_JJAEK",
        visibility: :public_jjaek,
        created_at: 3.hours.ago
      )
      middle_activity = BookActivity.create!(
        user: viewer,
        book: viewer_book,
        action: :added_to_shelf,
        created_at: 2.hours.ago
      )
      new_jjaek = viewer.jjaeks.create!(
        content: "HOME_FEED_NEW_JJAEK",
        visibility: :public_jjaek,
        created_at: 1.hour.ago
      )
      sign_in viewer

      get root_path

      new_index = response.body.index(new_jjaek.content)
      activity_index = response.body.index("Viewer님이 『#{middle_activity.book.title}』를 서재에 담았습니다.")
      old_index = response.body.index(old_jjaek.content)

      expect(new_index).to be < activity_index
      expect(activity_index).to be < old_index
    end
  end
end
