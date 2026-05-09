require "rails_helper"

RSpec.describe UsersHelper, type: :helper do
  it "returns a 128px default avatar path" do
    user = User.new(default_avatar_index: 7)

    expect(helper.user_avatar_path(user, size: 128)).to eq("avatars/user_profile_07_128.png")
  end

  it "returns a 512px default avatar path" do
    user = User.new(default_avatar_index: 7)

    expect(helper.user_avatar_path(user, size: 512)).to eq("avatars/user_profile_07_512.png")
  end

  it "falls back to the first avatar when the index is missing or out of range" do
    expect(helper.user_avatar_path(User.new, size: 128)).to eq("avatars/user_profile_01_128.png")
    expect(helper.user_avatar_path(User.new(default_avatar_index: 99), size: 128)).to eq("avatars/user_profile_01_128.png")
  end

  it "returns an avatar image tag" do
    user = User.new(default_avatar_index: 3)

    expect(helper.user_avatar_image(user, size: 128, alt: "Reader")).to include("img")
    expect(helper.user_avatar_image(user, size: 128, alt: "Reader")).to include("avatars/user_profile_03_128")
  end

  it "keeps bookshelf tab color mapping keys aligned with Bookshelf color keys" do
    expect(described_class::BOOKSHELF_TAB_CLASSES_BY_COLOR_KEY.keys).to match_array(Bookshelf::COLOR_KEYS)
  end
end
