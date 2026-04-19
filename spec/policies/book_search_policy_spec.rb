require "rails_helper"

RSpec.describe BookSearchPolicy do
  let(:user) { User.create!(name: "Reader", email: "book-policy@example.com", password: "password123!", password_confirmation: "password123!") }

  it "lets a signed-in user access book search" do
    expect(described_class.new(user, :book_search).show?).to be(true)
  end

  it "does not let a guest access book search" do
    expect(described_class.new(nil, :book_search).show?).to be(false)
  end
end
