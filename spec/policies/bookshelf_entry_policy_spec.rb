require "rails_helper"

RSpec.describe BookshelfEntryPolicy do
  let(:viewer) { User.create!(name: "Viewer", email: "viewer-bookshelf-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book_friend) { User.create!(name: "Friend", email: "friend-bookshelf-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:stranger) { User.create!(name: "Stranger", email: "stranger-bookshelf-policy@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:viewer_book) { Book.create!(title: "Viewer Book", authors_text: "Author") }
  let(:friend_book) { Book.create!(title: "Friend Book", authors_text: "Author") }
  let(:stranger_book) { Book.create!(title: "Stranger Book", authors_text: "Author") }

  describe described_class::Scope do
    it "includes the viewer and accepted book friends but not unrelated users" do
      viewer_entry = viewer.bookshelf_entries.create!(book: viewer_book)
      friend_entry = book_friend.bookshelf_entries.create!(book: friend_book)
      stranger_entry = stranger.bookshelf_entries.create!(book: stranger_book)
      BookFriendship.create!(requester: viewer, addressee: book_friend, status: :accepted)

      resolved = described_class.new(viewer, BookshelfEntry.all).resolve

      expect(resolved).to include(viewer_entry, friend_entry)
      expect(resolved).not_to include(stranger_entry)
    end
  end
end
