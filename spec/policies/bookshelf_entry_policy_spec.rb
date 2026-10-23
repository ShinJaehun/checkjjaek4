require "rails_helper"

RSpec.describe BookshelfEntryPolicy do
  let(:viewer) { User.create!(name: "Viewer", email: "viewer-bookshelf-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book_friend) { User.create!(name: "Friend", email: "friend-bookshelf-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:stranger) { User.create!(name: "Stranger", email: "stranger-bookshelf-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:viewer_book) { Book.create!(title: "Viewer Book", authors_text: "Author") }
  let(:friend_book) { Book.create!(title: "Friend Book", authors_text: "Author") }
  let(:stranger_book) { Book.create!(title: "Stranger Book", authors_text: "Author") }

  describe "#move?" do
    it "allows only the entry owner" do
      entry = viewer.bookshelf_entries.create!(book: viewer_book)

      expect(described_class.new(viewer, entry).move?).to be(true)
      expect(described_class.new(book_friend, entry).move?).to be(false)
    end
  end

  describe described_class::Scope do
    it "includes only the viewer's own bookshelf entries" do
      viewer_entry = viewer.bookshelf_entries.create!(book: viewer_book)
      friend_entry = book_friend.bookshelf_entries.create!(book: friend_book)
      stranger_entry = stranger.bookshelf_entries.create!(book: stranger_book)
      BookFriendship.create!(requester: viewer, addressee: book_friend, status: :accepted)

      resolved = described_class.new(viewer, BookshelfEntry.all).resolve

      expect(resolved).to include(viewer_entry)
      expect(resolved).not_to include(friend_entry)
      expect(resolved).not_to include(stranger_entry)
    end
  end

  describe BookshelfEntryPolicy::ReadingStateScope do
    it "allows own private entries and friends' accessible entries only" do
      own_shelf = viewer.bookshelves.create!(name: "Own private", visibility: :private)
      own = viewer.bookshelf_entries.create!(book: viewer_book, bookshelf: own_shelf)
      friend_shelf = book_friend.bookshelves.create!(name: "Friend reading", visibility: :public)
      friend = book_friend.bookshelf_entries.create!(book: friend_book, bookshelf: friend_shelf)
      stranger.bookshelf_entries.create!(book: stranger_book)
      BookFriendship.create!(requester: viewer, addressee: book_friend, status: :accepted)
      resolve = -> { described_class.new(viewer, BookshelfEntry.all).resolve }

      expect(resolve.call).to contain_exactly(own, friend)
      friend.bookshelf.update!(visibility: :book_friends)
      expect(resolve.call).to contain_exactly(own, friend)
      friend.bookshelf.update!(visibility: :private)
      expect(resolve.call).to contain_exactly(own)
      viewer.update!(global_admin: true)
      expect(resolve.call).to contain_exactly(own)
      expect(described_class.new(nil, BookshelfEntry.all).resolve).to be_empty
    end
  end

  describe BookshelfEntryPolicy::ProfileScope do
    let(:profile_user) { User.create!(name: "Profile", email: "profile-bookshelf-policy@example.com", password: "password123!", password_confirmation: "password123!") }
    let(:public_book) { Book.create!(title: "Public Profile Book", authors_text: "Author") }
    let(:book_friends_book) { Book.create!(title: "Book Friends Profile Book", authors_text: "Author") }
    let(:private_book) { Book.create!(title: "Private Profile Book", authors_text: "Author") }

    it "includes every bookshelf visibility for the owner" do
      public_entry = profile_user.bookshelf_entries.create!(book: public_book)
      book_friends_entry = create_profile_entry(profile_user, book_friends_book, "book_friends")
      private_entry = create_profile_entry(profile_user, private_book, "private")

      resolved = described_class.new(profile_user, profile_user.bookshelf_entries).resolve

      expect(resolved).to include(public_entry, book_friends_entry, private_entry)
    end

    it "includes public and book_friends shelves for an accepted book friend" do
      public_entry = profile_user.bookshelf_entries.create!(book: public_book)
      book_friends_entry = create_profile_entry(profile_user, book_friends_book, "book_friends")
      private_entry = create_profile_entry(profile_user, private_book, "private")
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)

      resolved = described_class.new(viewer, profile_user.bookshelf_entries).resolve

      expect(resolved).to include(public_entry, book_friends_entry)
      expect(resolved).not_to include(private_entry)
    end

    it "includes only public shelves for a stranger" do
      public_entry = profile_user.bookshelf_entries.create!(book: public_book)
      book_friends_entry = create_profile_entry(profile_user, book_friends_book, "book_friends")
      private_entry = create_profile_entry(profile_user, private_book, "private")

      resolved = described_class.new(viewer, profile_user.bookshelf_entries).resolve

      expect(resolved).to include(public_entry)
      expect(resolved).not_to include(book_friends_entry)
      expect(resolved).not_to include(private_entry)
    end

    it "applies normal profile visibility to a global admin without granting mutations" do
      global_admin = User.create!(name: "Global admin", email: "bookshelf-profile-global-admin@example.com", password: "password123!", global_admin: true)
      public_entry = profile_user.bookshelf_entries.create!(book: public_book)
      book_friends_entry = create_profile_entry(profile_user, book_friends_book, "book_friends")
      private_entry = create_profile_entry(profile_user, private_book, "private")

      resolved = described_class.new(global_admin, profile_user.bookshelf_entries).resolve
      mutation_policy = BookshelfEntryPolicy.new(global_admin, private_entry)

      expect(resolved).to include(public_entry)
      expect(resolved).not_to include(book_friends_entry, private_entry)

      BookFriendship.create!(requester: global_admin, addressee: profile_user, status: :accepted)
      resolved = described_class.new(global_admin, profile_user.bookshelf_entries).resolve
      expect(resolved).to include(public_entry, book_friends_entry)
      expect(resolved).not_to include(private_entry)
      expect(mutation_policy.create?).to be(false)
      expect(mutation_policy.move?).to be(false)
      expect(mutation_policy.destroy?).to be(false)
    end

    def create_profile_entry(user, book, visibility)
      bookshelf = user.bookshelves.create!(name: "#{visibility} shelf", visibility: visibility)
      user.bookshelf_entries.create!(book: book, bookshelf: bookshelf)
    end
  end
end
