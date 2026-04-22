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

  describe described_class::Scope do
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
