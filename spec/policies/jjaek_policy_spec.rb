require "rails_helper"

RSpec.describe JjaekPolicy do
  let(:viewer) { User.create!(name: "Reader", email: "jjaek-policy-reader@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:original_author) { User.create!(name: "Original", email: "jjaek-policy-original@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "ReJjaek policy book", authors_text: "Author") }
  let(:friendship) { BookFriendship.create!(requester: viewer, addressee: original_author, status: :accepted) }
  let(:original) { original_author.jjaeks.create!(book:, content: "ORIGINAL_BOOK_FRIENDS_SOURCE", visibility: :book_friends) }
  let(:requote) { viewer.jjaeks.create!(book:, content: "VIEWER_REQUOTE_BODY", quoted_jjaek: original, visibility: :private_jjaek) }

  before do
    friendship
  end

  describe "#show?" do
    it "hides a user's own requote when the original is no longer visible to them" do
      friendship.destroy!

      expect(described_class.new(viewer, requote).show?).to be(false)
    end

    it "shows a requote when the original is still visible to the viewer" do
      expect(described_class.new(viewer, requote).show?).to be(true)
    end
  end

  describe "#requote?" do
    it "allows requoting a visible non-private original" do
      expect(described_class.new(viewer, original).requote?).to be(true)
    end

    it "does not allow requoting a private original" do
      private_original = original_author.jjaeks.create!(
        book:,
        content: "PRIVATE_REQUOTE_SOURCE",
        visibility: :private_jjaek
      )

      expect(described_class.new(original_author, private_original).requote?).to be(false)
    end

    it "does not allow requoting another requote" do
      expect(described_class.new(viewer, requote).requote?).to be(false)
    end
  end

  describe "#create?" do
    it "allows creating a general jjaek without a book" do
      jjaek = viewer.jjaeks.build(content: "GENERAL_POLICY_JJAEK")

      expect(described_class.new(viewer, jjaek).create?).to be(true)
    end

    it "allows creating a book-linked jjaek when the user has the book in their shelf" do
      viewer.bookshelf_entries.create!(book:)
      jjaek = viewer.jjaeks.build(book:, content: "BOOK_POLICY_JJAEK")

      expect(described_class.new(viewer, jjaek).create?).to be(true)
    end

    it "does not allow creating a book-linked jjaek without a shelf entry" do
      jjaek = viewer.jjaeks.build(book:, content: "NO_SHELF_BOOK_POLICY_JJAEK")

      expect(described_class.new(viewer, jjaek).create?).to be(false)
    end

    it "allows creating a profile-context jjaek for an accepted book friend" do
      jjaek = viewer.jjaeks.build(
        target_user: original_author,
        content: "PROFILE_CONTEXT_POLICY_JJAEK",
        visibility: :book_friends
      )

      expect(described_class.new(viewer, jjaek).create?).to be(true)
    end

    it "does not allow creating a profile-context jjaek for an unrelated user" do
      friendship.destroy!
      jjaek = viewer.jjaeks.build(
        target_user: original_author,
        content: "UNRELATED_PROFILE_CONTEXT_POLICY_JJAEK",
        visibility: :book_friends
      )

      expect(described_class.new(viewer, jjaek).create?).to be(false)
    end

    it "does not allow creating a private profile-context jjaek for another user" do
      jjaek = viewer.jjaeks.build(
        target_user: original_author,
        content: "PRIVATE_PROFILE_CONTEXT_POLICY_JJAEK",
        visibility: :private_jjaek
      )

      expect(described_class.new(viewer, jjaek).create?).to be(false)
    end
  end

  describe described_class::Scope do
    it "shows only public jjaeks from another profile to an unrelated user" do
      friendship.destroy!
      public_jjaek = original_author.jjaeks.create!(content: "PUBLIC_PROFILE_SCOPE", visibility: :public_jjaek)
      private_jjaek = original_author.jjaeks.create!(content: "PRIVATE_PROFILE_SCOPE", visibility: :private_jjaek)

      resolved = described_class.new(viewer, original_author.jjaeks).resolve

      expect(resolved).to include(public_jjaek)
      expect(resolved).not_to include(original)
      expect(resolved).not_to include(private_jjaek)
    end

    it "shows only public jjaeks from another profile to a follow-only user" do
      friendship.destroy!
      viewer.active_follows.create!(followee: original_author)
      public_jjaek = original_author.jjaeks.create!(content: "FOLLOW_PUBLIC_PROFILE_SCOPE", visibility: :public_jjaek)
      private_jjaek = original_author.jjaeks.create!(content: "FOLLOW_PRIVATE_PROFILE_SCOPE", visibility: :private_jjaek)

      resolved = described_class.new(viewer, original_author.jjaeks).resolve

      expect(resolved).to include(public_jjaek)
      expect(resolved).not_to include(original)
      expect(resolved).not_to include(private_jjaek)
    end

    it "shows book-friends jjaeks from another profile to an accepted book friend" do
      public_jjaek = original_author.jjaeks.create!(content: "FRIEND_PUBLIC_PROFILE_SCOPE", visibility: :public_jjaek)

      resolved = described_class.new(viewer, original_author.jjaeks).resolve

      expect(resolved).to include(public_jjaek)
      expect(resolved).to include(original)
    end

    it "shows all jjaeks from your own profile" do
      private_jjaek = viewer.jjaeks.create!(content: "SELF_PRIVATE_PROFILE_SCOPE", visibility: :private_jjaek)

      resolved = described_class.new(viewer, viewer.jjaeks).resolve

      expect(resolved).to include(private_jjaek)
    end

    it "excludes a requote when the original is no longer visible to the viewer" do
      friendship.destroy!

      resolved = described_class.new(viewer, Jjaek.all).resolve

      expect(resolved).not_to include(requote)
    end

    it "includes a requote when the original is still visible to the viewer" do
      resolved = described_class.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(requote)
    end
  end

  describe described_class::FeedScope do
    it "includes jjaeks targeted at the viewer" do
      targeted = original_author.jjaeks.create!(
        target_user: viewer,
        content: "TARGETED_AT_VIEWER_POLICY_FEED",
        visibility: :book_friends
      )

      resolved = described_class.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(targeted)
    end

    it "excludes a requote when the original is no longer visible to the viewer" do
      friendship.destroy!

      resolved = described_class.new(viewer, Jjaek.all).resolve

      expect(resolved).not_to include(requote)
    end

    it "includes a requote when the original is still visible to the viewer" do
      resolved = described_class.new(viewer, Jjaek.all).resolve

      expect(resolved).to include(requote)
    end
  end
end
