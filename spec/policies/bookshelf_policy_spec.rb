require "rails_helper"

RSpec.describe BookshelfPolicy do
  let(:viewer) { User.create!(name: "Viewer", email: "viewer-bookshelf-scope@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:profile_user) { User.create!(name: "Profile", email: "profile-bookshelf-scope@example.com", password: "password123!", password_confirmation: "password123!") }

  describe "#show?" do
    it "allows public bookshelves for strangers" do
      bookshelf = profile_user.default_bookshelf

      expect(described_class.new(viewer, bookshelf).show?).to be(true)
    end

    it "allows book_friends bookshelves for accepted book friends" do
      bookshelf = profile_user.bookshelves.create!(name: "Friends", visibility: :book_friends)
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)

      expect(described_class.new(viewer, bookshelf).show?).to be(true)
    end

    it "does not allow private bookshelves for accepted book friends" do
      bookshelf = profile_user.bookshelves.create!(name: "Private", visibility: :private)
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)

      expect(described_class.new(viewer, bookshelf).show?).to be(false)
    end

    it "allows a global admin to read a private bookshelf without granting mutations" do
      global_admin = User.create!(name: "Global admin", email: "bookshelf-global-admin@example.com", password: "password123!", global_admin: true)
      bookshelf = profile_user.bookshelves.create!(name: "Private", visibility: :private)
      policy = described_class.new(global_admin, bookshelf)

      expect(policy.show?).to be(true)
      expect(policy.create?).to be(false)
      expect(policy.update?).to be(false)
      expect(policy.destroy?).to be(false)
      expect(policy.move_up?).to be(false)
      expect(policy.move_down?).to be(false)
    end
  end

  describe described_class::Scope do
    it "includes all own bookshelves" do
      public_bookshelf = viewer.default_bookshelf
      private_bookshelf = viewer.bookshelves.create!(name: "Private", visibility: :private)

      resolved = described_class.new(viewer, Bookshelf.all).resolve

      expect(resolved).to include(public_bookshelf, private_bookshelf)
    end

    it "includes public and book_friends bookshelves for accepted book friends" do
      public_bookshelf = profile_user.default_bookshelf
      book_friends_bookshelf = profile_user.bookshelves.create!(name: "Friends", visibility: :book_friends)
      private_bookshelf = profile_user.bookshelves.create!(name: "Private", visibility: :private)
      BookFriendship.create!(requester: viewer, addressee: profile_user, status: :accepted)

      resolved = described_class.new(viewer, Bookshelf.all).resolve

      expect(resolved).to include(public_bookshelf, book_friends_bookshelf)
      expect(resolved).not_to include(private_bookshelf)
    end

    it "includes only public bookshelves for strangers" do
      public_bookshelf = profile_user.default_bookshelf
      book_friends_bookshelf = profile_user.bookshelves.create!(name: "Friends", visibility: :book_friends)
      private_bookshelf = profile_user.bookshelves.create!(name: "Private", visibility: :private)

      resolved = described_class.new(viewer, Bookshelf.all).resolve

      expect(resolved).to include(public_bookshelf)
      expect(resolved).not_to include(book_friends_bookshelf)
      expect(resolved).not_to include(private_bookshelf)
    end

    it "includes every bookshelf visibility for a global admin" do
      global_admin = User.create!(name: "Global admin", email: "bookshelf-scope-global-admin@example.com", password: "password123!", global_admin: true)
      public_bookshelf = profile_user.default_bookshelf
      book_friends_bookshelf = profile_user.bookshelves.create!(name: "Friends", visibility: :book_friends)
      private_bookshelf = profile_user.bookshelves.create!(name: "Private", visibility: :private)

      resolved = described_class.new(global_admin, profile_user.bookshelves).resolve

      expect(resolved).to include(public_bookshelf, book_friends_bookshelf, private_bookshelf)
    end
  end
end
