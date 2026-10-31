require "rails_helper"

RSpec.describe "Avatar query counts", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:viewer) { User.create!(name: "Viewer", email: "avatar-queries-viewer@example.com", password: "password123!") }
  let(:group) { Group.create!(name: "Avatar readers", group_admin: viewer, group_type: :public_group, lifecycle_status: :active) }

  def add_author(index)
    author = User.create!(name: "Avatar query author #{index}", email: "avatar-queries-#{index}@example.com", password: "password123!")
    File.open(Rails.root.join("app/assets/images/avatars/user_profile_01_128.png")) do |file|
      author.avatar.attach(io: file, filename: "avatar.png", content_type: "image/png")
    end
    viewer.active_follows.create!(followee: author)
    original = author.jjaeks.create!(content: "Avatar query original #{index}", visibility: :public_jjaek)
    viewer.jjaeks.create!(content: "Avatar query quote #{index}", quoted_jjaek: original, visibility: :public_jjaek)
    group.group_memberships.create!(user: author, status: :active)
    author.jjaeks.create!(group:, content: "Avatar query group post #{index}", visibility: :public_jjaek)
  end

  def avatar_query_count(page)
    queries = []
    subscriber = lambda do |*args|
      payload = args.last
      if payload[:sql].match?(/\bSELECT\b.*\bFROM\s+"active_storage_(?:attachments|blobs)"/im)
        queries << payload[:sql]
      end
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      case page
      when :home then get root_path
      when :profile then get user_path(viewer)
      when :group then get group_path(group)
      when :discovery
        tomorrow_in_seoul = Time.current.in_time_zone("Asia/Seoul").tomorrow.beginning_of_day + 12.hours
        travel_to(tomorrow_in_seoul) { get discovery_path }
      end
    end
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Avatar query author")
    queries.size
  end

  %i[home profile group discovery].each do |page|
    it "keeps attachment and blob queries bounded on #{page} as displayed authors increase" do
      add_author(0)
      sign_in viewer
      # Warm template and application caches before counting database queries.
      avatar_query_count(page)
      baseline = avatar_query_count(page)
      expect(baseline).to be_positive

      add_author(1)
      add_author(2)

      expect(avatar_query_count(page)).to be <= baseline
      expect(response.body).to include("Avatar query author 1", "Avatar query author 2")
    end
  end
end
