require "rails_helper"

RSpec.describe "Group rate limits", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "group-limit-reader@example.com", password: "password123!") }
  let!(:other_user) { User.create!(name: "Other reader", email: "group-limit-other@example.com", password: "password123!") }
  let(:counter_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:counter_keys) { [] }

  before do
    [ GroupsController, GroupMembershipsController ].each do |controller|
      allow(controller.cache_store).to receive(:increment) do |key, amount, **options|
        counter_keys << key
        counter_store.increment(key, amount, **options)
      end
    end
  end

  it "allows five group openings across types, then returns 429 without side effects or losing the HTML form" do
    sign_in user
    5.times do |index|
      post groups_path, params: { group: {
        name: "Club #{index}", group_type: %w[public_group approval_group private_group][index % 3],
        description: "Reading together", application_purpose: "Read more together"
      } }
      expect(response).to redirect_to(group_path(Group.order(:id).last))
    end

    counts = [ Group.count, GroupMembership.count, GroupLifecycleEvent.count, Notification.count ]
    expect(Notifications::GroupLifecycleNotifier).not_to receive(:schedule)
    post groups_path, params: { group: {
      name: "Unsent club", group_type: "private_group", description: "Keep this description",
      application_purpose: "Keep this purpose"
    } }, headers: { "Accept" => "text/html" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include("Unsent club", "Keep this description", "Keep this purpose",
                                    I18n.t("groups.alerts.rate_limited"))
    expect([ Group.count, GroupMembership.count, GroupLifecycleEvent.count, Notification.count ]).to eq(counts)
  end

  it "applies the opening limit to global admins and keeps user counters separate" do
    user.update!(global_admin: true)
    sign_in user
    5.times do |index|
      post groups_path, params: { group: {
        name: "Admin club #{index}", group_type: "public_group", application_purpose: "Read together"
      } }
    end
    expect(Group.where(group_admin: user, lifecycle_status: :active).count).to eq(5)

    post groups_path, params: { group: { name: "Blocked admin club", group_type: "public_group" } },
                      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include(%(target="flash-messages"), I18n.t("groups.alerts.rate_limited"))

    sign_in other_user
    post groups_path, params: { group: {
      name: "Other user's club", group_type: "public_group", application_purpose: "Read together"
    } }
    expect(response).to redirect_to(group_path(Group.order(:id).last))
  end

  it "shares fifteen join requests across public and approval groups without modifying memberships on 429" do
    admin = other_user
    groups = 16.times.map do |index|
      Group.create!(group_admin: admin, lifecycle_status: :active, name: "Join club #{index}",
                    group_type: index.even? ? :public_group : :approval_group)
    end
    sign_in user
    groups.first(15).each do |group|
      post group_group_memberships_path(group)
      expect(response).to redirect_to(group_path(group))
    end
    expect(GroupMembership.where(user: user, group: groups.first(15)).count).to eq(15)

    counts = [ GroupMembership.count, GroupMembershipEvent.count, Notification.count ]
    expect(Notifications::GroupMembershipNotifier).not_to receive(:schedule)
    post group_group_memberships_path(groups.last), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include(%(target="flash-messages"), I18n.t("group_memberships.alerts.join_rate_limited"))
    expect([ GroupMembership.count, GroupMembershipEvent.count, Notification.count ]).to eq(counts)

    post group_group_memberships_path(groups.last), headers: { "Accept" => "text/html" }
    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include(I18n.t("group_memberships.alerts.join_rate_limited"))

    sign_in admin
    fresh_group = Group.create!(group_admin: user, lifecycle_status: :active,
                                name: "Another join", group_type: :public_group)
    post group_group_memberships_path(fresh_group)
    expect(response).to redirect_to(group_path(fresh_group))
  end

  it "allows invitation acceptance after the join limit is reached" do
    admin = other_user
    joinable_groups = 15.times.map do |index|
      Group.create!(group_admin: admin, lifecycle_status: :active,
                    name: "Join limit #{index}", group_type: :public_group)
    end
    private_group = Group.create!(group_admin: admin, lifecycle_status: :active,
                                  name: "Invitation club", group_type: :private_group)
    invitation = private_group.group_memberships.create!(user:, status: :invited)
    sign_in user
    joinable_groups.each { |group| post group_group_memberships_path(group) }
    expect(response).not_to have_http_status(:too_many_requests)
    # The invitation action uses a different route and must remain available.
    patch accept_group_group_membership_path(private_group, invitation)
    expect(response).to redirect_to(group_path(private_group))
    expect(invitation.reload).to be_active
  end

  it "shares thirty invitations across clubs and targets, then returns an HTML 429 without side effects" do
    first_group = Group.create!(group_admin: user, lifecycle_status: :active,
                                name: "First private club", group_type: :private_group)
    second_group = Group.create!(group_admin: user, lifecycle_status: :active,
                                 name: "Second private club", group_type: :private_group)
    targets = 31.times.map do |index|
      User.create!(name: "Invitee #{index}", email: "group-limit-invitee-#{index}@example.com", password: "password123!")
    end
    sign_in user
    targets.first(30).each_with_index do |target, index|
      group = index.even? ? first_group : second_group
      post invite_group_group_memberships_path(group), params: { user_id: target.id }
      expect(response).to redirect_to(group_members_path(group))
    end

    counts = [ GroupMembership.count, GroupMembershipEvent.count, Notification.count ]
    expect(Notifications::GroupMembershipNotifier).not_to receive(:schedule)
    post invite_group_group_memberships_path(second_group), params: { user_id: targets.last.id },
                                                           headers: { "Accept" => "text/html" }

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include(I18n.t("group_memberships.alerts.invite_rate_limited"))
    expect([ GroupMembership.count, GroupMembershipEvent.count, Notification.count ]).to eq(counts)

    post invite_group_group_memberships_path(first_group), params: { user_id: targets.last.id },
                                                          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include(%(target="flash-messages"), I18n.t("group_memberships.alerts.invite_rate_limited"))
  end

  it "keeps invitation counters separate by inviter and from join counters" do
    first_group = Group.create!(group_admin: user, lifecycle_status: :active,
                                name: "Inviter one", group_type: :private_group)
    second_group = Group.create!(group_admin: other_user, lifecycle_status: :active,
                                 name: "Inviter two", group_type: :private_group)
    target = User.create!(name: "Invitee", email: "group-limit-third@example.com", password: "password123!")
    sign_in user
    30.times { post invite_group_group_memberships_path(first_group), params: { user_id: target.id } }
    expect(response).not_to have_http_status(:too_many_requests)
    public_group = Group.create!(group_admin: other_user, lifecycle_status: :active,
                                 name: "Join after invites", group_type: :public_group)
    post group_group_memberships_path(public_group)
    expect(response).to redirect_to(group_path(public_group))

    sign_in other_user
    post invite_group_group_memberships_path(second_group), params: { user_id: target.id },
                                                            headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to redirect_to(group_members_path(second_group))
  end

  it "does not count unauthenticated or unauthorized group requests" do
    public_group = Group.create!(group_admin: other_user, lifecycle_status: :active,
                                 name: "Public", group_type: :public_group)
    private_group = Group.create!(group_admin: other_user, lifecycle_status: :active,
                                  name: "Private", group_type: :private_group)

    post groups_path, params: { group: { name: "Guest club", group_type: "public_group" } }
    expect(response).to redirect_to(new_user_session_path)
    post group_group_memberships_path(public_group)
    expect(response).to redirect_to(new_user_session_path)
    post invite_group_group_memberships_path(private_group), params: { user_id: user.id }
    expect(response).to redirect_to(new_user_session_path)
    expect(counter_keys).to be_empty

    sign_in user
    post groups_path, params: { group: { name: "Invalid type", group_type: "" } }
    expect(response).to redirect_to(root_path)

    post group_group_memberships_path(private_group)
    expect(response).to have_http_status(:not_found)

    post invite_group_group_memberships_path(private_group), params: { user_id: user.id }
    expect(response).to have_http_status(:not_found)

    post invite_group_group_memberships_path(public_group), params: { user_id: user.id }
    expect(response).to redirect_to(root_path)
    expect(counter_keys).to be_empty

    owned_private_group = Group.create!(group_admin: user, lifecycle_status: :active,
                                        name: "Owned private", group_type: :private_group)

    post invite_group_group_memberships_path(owned_private_group),
         params: { user_id: user.id, return_context: "profile" }
    expect(response).to redirect_to(user_path(user))
    expect(counter_keys).to be_empty
  end
end
