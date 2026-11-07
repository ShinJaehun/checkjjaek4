require "rails_helper"

RSpec.describe JjaekRecommendation, type: :model do
  let(:user) { User.create!(name: "Recommender", email: "recommendation-model@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "First recommendation") }
  let(:other_book) { Book.create!(title: "Second recommendation") }
  let(:jjaek) { user.jjaeks.build(recommendation: true, content: "Read these together #독서") }

  it "stores multiple books in selection order without using the single book association" do
    jjaek.jjaek_recommendations.build(book: other_book, position: 1)
    jjaek.jjaek_recommendations.build(book:, position: 0)
    jjaek.save!

    expect(jjaek.reload.recommended_books).to eq([book, other_book])
    expect(jjaek.book_id).to be_nil
    expect(jjaek.content_kind).to eq("recommendation")
    expect(jjaek.tags.pluck(:name)).to eq(["독서"])
    expect(Jjaek.general_posts).not_to include(jjaek)
    expect(user.bookshelf_entries).to be_empty
  end

  it "allows zero books and profile targets while rejecting duplicate books and new requote books" do
    expect(jjaek).to be_valid
    jjaek.target_user = user
    jjaek.jjaek_recommendations.build(book:, position: 0)
    expect(jjaek).to be_valid
    jjaek.quoted_jjaek = user.jjaeks.create!(content: "An original post")
    expect(jjaek).not_to be_valid
    jjaek.quoted_jjaek = nil
    jjaek.jjaek_recommendations.build(book:, position: 1)
    expect(jjaek).not_to be_valid
    expect(jjaek.errors.of_kind?(:recommended_books, :taken)).to be(true)
  end

  it "rejects duplicate books and positions and accepts links on ordinary jjaeks" do
    jjaek.jjaek_recommendations.build(book:, position: 0)
    jjaek.save!
    expect(jjaek.jjaek_recommendations.build(book:, position: 1)).not_to be_valid
    expect(jjaek.jjaek_recommendations.build(book: other_book, position: 0)).not_to be_valid
    ordinary = user.jjaeks.create!(content: "Ordinary post")
    expect(ordinary.jjaek_recommendations.build(book:, position: 0)).to be_valid
  end

  it "preserves the 200 character limit for recommendation reasons" do
    jjaek.jjaek_recommendations.build(book:, position: 0)
    jjaek.content = "한" * 200
    expect(jjaek).to be_valid
    jjaek.content += "!"
    expect(jjaek).not_to be_valid
    expect(jjaek.errors.of_kind?(:content, :too_long)).to be(true)
  end

  it "allows five books and rejects a sixth without saving any new books or links" do
    5.times do |position|
      jjaek.jjaek_recommendations.build(book: Book.new(title: "Recommendation #{position}"), position:)
    end
    expect(jjaek).to be_valid
    jjaek.jjaek_recommendations.build(book: Book.new(title: "Sixth recommendation"), position: 5)
    expect(jjaek.save).to be(false)
    expect(jjaek.errors.of_kind?(:recommended_books, :too_many_recommendations)).to be(true)
    expect(Book.where("title LIKE ?", "Recommendation %")).to be_empty
    expect(Book.find_by(title: "Sixth recommendation")).to be_nil
    expect(described_class.count).to eq(0)
    expect(Jjaek.count).to eq(0)
  end

  it "keeps existing personal requote deletion behavior with the correct source kind" do
    jjaek.jjaek_recommendations.build(book:, position: 0)
    jjaek.save!
    requote = user.jjaeks.create!(content: "My opinion", quoted_jjaek: jjaek)

    jjaek.destroy_or_tombstone!

    expect(described_class.where(jjaek_id: jjaek.id)).to be_empty
    expect(Book.exists?(book.id)).to be(true)
    expect(requote.reload).to have_attributes(quoted_jjaek_id: nil, quoted_source_kind: "recommendation",
                                              visibility: "private_jjaek")
  end
end
