require "rails_helper"

RSpec.describe "Production seeds" do
  it "creates only the default stickers and preserves users and content when rerun" do
    user = User.create!(name: "Existing Reader", email: "a@a", password: "password123!")
    jjaek = Jjaek.create!(user: user, content: "Existing content", visibility: :public_jjaek)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    load Rails.root.join("db/seeds.rb").to_s
    sticker_count = StickerDefinition.count
    load Rails.root.join("db/seeds.rb").to_s

    expect(StickerDefinition.count).to eq(sticker_count)
    expect(StickerDefinition.where(key: %w[
      loved_it really_loved_it stayed_with_me want_to_reread recommended_to_me want_to_recommend
    ]).count).to eq(6)
    expect(User.find_by!(email: "a@a").id).to eq(user.id)
    expect(user.reload.name).to eq("Existing Reader")
    expect(jjaek.reload.content).to eq("Existing content")
    expect(User.where(email: %w[b@b c@c d@d])).to be_empty
  end
end
