require "rails_helper"

RSpec.describe "Private group invitations from profiles", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "profile-invite-admin@example.com", password: "password123!") }
  let!(:target) { User.create!(name: "Target", email: "profile-invite-target@example.com", password: "password123!") }
  let!(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Reading club", group_type: :private_group) }

  before { sign_in group_admin }

  it "does not show an invitation action on the admin's own profile" do
    get user_path(group_admin)

    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{invite_group_group_memberships_path(group)}"]))).to be_nil
  end

  it "shows one direct invitation action and returns to the target profile after inviting" do
    get user_path(target)
    form = Nokogiri::HTML(response.body).at_css(%(form[action="#{invite_group_group_memberships_path(group)}"]))
    expect(form.text).to include(I18n.t("users.profile.invite_to_group", group_name: group.name))
    expect(form.at_css('input[name="user_id"]')["value"]).to eq(target.id.to_s)
    expect(form.at_css('input[name="return_context"]')["value"]).to eq("profile")

    expect {
      post invite_group_group_memberships_path(group), params: { user_id: target.id, return_context: "profile" }
    }.to change(GroupMembership, :count).by(1)
    expect(response).to redirect_to(user_path(target))
    expect(group.group_memberships.find_by!(user: target)).to be_invited
    expect(GroupMembershipEvent.exists?(group:, user: target, event_type: :invited)).to be(true)

    get user_path(target)
    invitation = group.group_memberships.find_by!(user: target)
    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{invite_group_group_memberships_path(group)}"]))).to be_nil
    cancel_form = Nokogiri::HTML(response.body).at_css(%(form[action="#{revoke_group_group_membership_path(group, invitation)}"]))
    expect(cancel_form.text).to include(I18n.t("users.profile.cancel_group_invitation", group_name: group.name))
    expect(cancel_form.at_css('input[name="return_context"]')["value"]).to eq("profile")
    expect(cancel_form.at_css('button')["class"]).to eq("rounded-full border border-red-200 px-3 py-1.5 text-sm font-medium text-red-700")
  end

  it "cancels an invitation from the profile and offers a new invitation again" do
    invitation = group.group_memberships.create!(user: target, status: :invited)

    delete revoke_group_group_membership_path(group, invitation), params: { return_context: "profile" }

    expect(response).to redirect_to(user_path(target))
    expect(GroupMembership.exists?(invitation.id)).to be(false)
    event = group.group_membership_events.invitation_revoked.sole
    expect(event).to have_attributes(user: target, actor: group_admin, group:)
    get user_path(target)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(%(form[action="#{revoke_group_group_membership_path(group, invitation)}"]))).to be_nil
    expect(page.at_css(%(form[action="#{invite_group_group_memberships_path(group)}"]))).to be_present
  end

  it "lets the admin choose exactly one of multiple eligible private groups" do
    second_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Writers club", group_type: :private_group)
    get user_path(target)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("details summary").text).to include(I18n.t("users.profile.invite_to_group_menu"))
    expect(page.at_css(%(form[action="#{invite_group_group_memberships_path(group)}"]))).to be_present
    expect(page.at_css(%(form[action="#{invite_group_group_memberships_path(second_group)}"]))).to be_present

    post invite_group_group_memberships_path(second_group), params: { user_id: target.id, return_context: "profile" }
    expect(response).to redirect_to(user_path(target))
    expect(second_group.group_memberships.find_by!(user: target)).to be_invited
    expect(group.group_memberships.find_by(user: target)).to be_nil
  end

  it "shows cancel actions for invited groups alongside the existing invite menu" do
    second_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Writers club", group_type: :private_group)
    third_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Poetry club", group_type: :private_group)
    invitation = group.group_memberships.create!(user: target, status: :invited)
    another_invitation = second_group.group_memberships.create!(user: target, status: :invited)

    get user_path(target)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css(%(form[action="#{revoke_group_group_membership_path(group, invitation)}"]))).to be_present
    expect(page.at_css(%(form[action="#{revoke_group_group_membership_path(second_group, another_invitation)}"]))).to be_present
    expect(page.at_css(%(form[action="#{invite_group_group_memberships_path(group)}"]))).to be_nil
    expect(page.at_css(%(form[action="#{invite_group_group_memberships_path(second_group)}"]))).to be_nil
    expect(page.at_css(%(form[action="#{invite_group_group_memberships_path(third_group)}"]))).to be_present
  end

  it "does not show a cancel action when the admin cannot revoke the invitation" do
    invitation = group.group_memberships.create!(user: target, status: :invited)
    group.update!(operation_suspended_at: Time.current)

    get user_path(target)

    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{revoke_group_group_membership_path(group, invitation)}"]))).to be_nil
  end

  it "does not show a former admin's cancel action after an admin change" do
    invitation = group.group_memberships.create!(user: target, status: :invited)
    new_admin = User.create!(name: "New admin", email: "profile-invite-new-admin@example.com", password: "password123!")
    group.group_memberships.create!(user: new_admin, status: :active)
    group.update!(group_admin: new_admin)

    get user_path(target)

    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{revoke_group_group_membership_path(group, invitation)}"]))).to be_nil
  end

  it "keeps cancel available after the invitee turns off new invitations" do
    invitation = group.group_memberships.create!(user: target, status: :invited)
    target.update!(accepts_group_invitations: false)

    get user_path(target)

    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{revoke_group_group_membership_path(group, invitation)}"]))).to be_present
  end

  it "keeps a cancel action on a failed profile Jjaek submission" do
    invitation = group.group_memberships.create!(user: target, status: :invited)
    another_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Another club", group_type: :private_group)
    BookFriendship.create!(requester: group_admin, addressee: target, status: :accepted)

    post jjaeks_path, params: {
      jjaek: { target_user_id: target.id, content: "", visibility: :book_friends }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{revoke_group_group_membership_path(group, invitation)}"]))).to be_present
    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{invite_group_group_memberships_path(another_group)}"]))).to be_present
  end

  it "hides ineligible groups, including existing memberships, bans, and suspended operation" do
    member_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Member club", group_type: :private_group)
    member_group.group_memberships.create!(user: target, status: :active)
    banned_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Banned club", group_type: :private_group)
    banned_group.group_member_bans.create!(user: target)
    suspended_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Suspended club", group_type: :private_group, operation_suspended_at: Time.current)
    get user_path(target)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css(%(form[action="#{invite_group_group_memberships_path(group)}"]))).to be_present
    [ member_group, banned_group, suspended_group ].each do |ineligible_group|
      expect(page.at_css(%(form[action="#{invite_group_group_memberships_path(ineligible_group)}"]))).to be_nil
    end
    member_membership = member_group.group_memberships.find_by!(user: target)
    expect(page.at_css(%(form[action="#{revoke_group_group_membership_path(member_group, member_membership)}"]))).to be_nil
  end

  it "excludes pending and invited memberships from new invitation actions" do
    pending_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Pending club", group_type: :private_group)
    invited_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Invited club", group_type: :private_group)
    pending_group.group_memberships.create!(user: target, status: :pending)
    invited_group.group_memberships.create!(user: target, status: :invited)

    get user_path(target)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(%(form[action="#{invite_group_group_memberships_path(pending_group)}"]))).to be_nil
    expect(page.at_css(%(form[action="#{invite_group_group_memberships_path(invited_group)}"]))).to be_nil
  end

  it "hides the action for an opted-out user and blocks a crafted invitation" do
    target.update!(accepts_group_invitations: false)
    get user_path(target)
    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{invite_group_group_memberships_path(group)}"]))).to be_nil

    expect {
      post invite_group_group_memberships_path(group), params: { user_id: target.id, return_context: "profile" }
    }.not_to change(GroupMembership, :count)
    expect(response).to redirect_to(user_path(target))
  end

  it "ignores unrecognized return context and preserves the existing members redirect" do
    post invite_group_group_memberships_path(group), params: { user_id: target.id, return_context: "https://example.com" }
    expect(response).to redirect_to(group_members_path(group))
  end

  it "ignores an unrecognized revoke return context and keeps the members redirect" do
    invitation = group.group_memberships.create!(user: target, status: :invited)

    delete revoke_group_group_membership_path(group, invitation), params: { return_context: "https://example.com" }

    expect(response).to redirect_to(group_members_path(group))
    expect(group.group_membership_events.invitation_revoked.sole.user).to eq(target)
  end
end
