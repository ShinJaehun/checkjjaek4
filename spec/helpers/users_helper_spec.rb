require "rails_helper"

RSpec.describe UsersHelper, type: :helper do
  it "provides shared user role labels and badge colors" do
    expect(helper.user_role_badge_classes(:global_admin)).to include("bg-amber-100")
    expect(helper.user_role_badge_classes(:group_admin)).to include("bg-sky-100")
    expect(helper.user_role_badge_classes(:regular)).to include("bg-stone-100")
    expect(helper.user_role_label(:group_admin)).to eq("동아리 관리자")
    I18n.with_locale(:en) { expect(helper.user_role_label(:global_admin)).to eq("System admin") }
  end

  it "renders bookshelf visibility labels and badges without database queries" do
    badge_colors = {
      "public" => %w[border-blue-200 bg-blue-50 text-blue-800],
      "book_friends" => %w[border-green-200 bg-green-50 text-green-800],
      "private" => %w[border-stone-200 bg-stone-100 text-stone-700]
    }
    shelves = Bookshelf.visibilities.keys.map { |visibility| Bookshelf.new(visibility: visibility) }
    queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      %i[ko en].each do |locale|
        I18n.with_locale(locale) do
          shelves.each do |shelf|
            badge = Nokogiri::HTML.fragment(helper.bookshelf_visibility_badge(shelf)).at_css("span")
            expect(badge.text).to eq(I18n.t("bookshelves.visibility.#{shelf.visibility}"))
            expect(badge["data-bookshelf-visibility"]).to eq(shelf.visibility)
            expect(badge["class"].split).to include("rounded-full", *badge_colors.fetch(shelf.visibility))
          end
        end
      end
    end
    expect(queries).to be_empty
  end

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

  it "uses one anonymous avatar for withdrawn users regardless of a legacy avatar index" do
    user = User.new(default_avatar_index: 7, withdrawn_at: Time.current)

    expect(helper.user_avatar_path(user, size: 128)).to eq("avatars/withdrawn_user.svg")
    expect(helper.user_avatar_path(user, size: 512)).to eq("avatars/withdrawn_user.svg")
  end

  it "returns an avatar image tag" do
    user = User.new(default_avatar_index: 3)

    expect(helper.user_avatar_image(user, size: 128, alt: "Reader")).to include("img")
    expect(helper.user_avatar_image(user, size: 128, alt: "Reader")).to include("avatars/user_profile_03_128")
  end

  it "uses square 128px and 512px variants for an uploaded avatar" do
    user = User.create!(name: "Avatar helper", email: "avatar-helper@example.com", password: "password123!")
    File.open(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png")) do |file|
      user.avatar.attach(io: file, filename: "avatar.png", content_type: "image/png")
    end

    [ 128, 512 ].each do |size|
      image = helper.user_avatar_image(user, size:, alt: user.name)
      expect(image).to include(user_avatar_image_path(user, size: size))
      expect(image).not_to include("avatars/user_profile_")
    end
  end

  it "keeps the withdrawn placeholder even if an uploaded blob has not yet been purged" do
    user = User.create!(name: "Former avatar", email: "former-avatar-helper@example.com", password: "password123!")
    File.open(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png")) do |file|
      user.avatar.attach(io: file, filename: "avatar.png", content_type: "image/png")
    end
    user.update_columns(withdrawn_at: Time.current)

    expect(helper.user_avatar_image(user, size: 128, alt: user.name)).to include(helper.asset_path("avatars/withdrawn_user.svg"))
  end

  it "keeps bookshelf tab color mapping keys aligned with Bookshelf color keys" do
    expect(described_class::BOOKSHELF_TAB_CLASSES_BY_COLOR_KEY.keys).to match_array(Bookshelf::COLOR_KEYS)
  end
end
