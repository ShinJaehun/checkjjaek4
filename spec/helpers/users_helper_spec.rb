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
            expect(badge["class"]).to include("rounded-full", "border-stone-200")
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

  it "keeps bookshelf tab color mapping keys aligned with Bookshelf color keys" do
    expect(described_class::BOOKSHELF_TAB_CLASSES_BY_COLOR_KEY.keys).to match_array(Bookshelf::COLOR_KEYS)
  end
end
