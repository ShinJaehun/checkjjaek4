require "rails_helper"

RSpec.describe "Group memberships", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "group-memberships-group_admin@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:member) { User.create!(name: "Member", email: "group-memberships-member@example.com", password: "password123!", password_confirmation: "password123!") }

  it "joins a public group immediately" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    sign_in member

    expect {
      post group_group_memberships_path(group)
    }.to change(GroupMembership, :count).by(1)

    expect(group.group_memberships.find_by(user: member)).to be_active
  end

  it "creates a pending request for an approval group" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    sign_in member

    post group_group_memberships_path(group)

    expect(group.group_memberships.find_by(user: member)).to be_pending
  end

  it "does not create duplicate memberships or requests" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    group.group_memberships.create!(user: member, status: :pending)
    sign_in member

    expect {
      post group_group_memberships_path(group)
    }.not_to change(GroupMembership, :count)
  end

  it "does not expose a private group through nested membership create" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    sign_in member

    expect {
      post group_group_memberships_path(group)
    }.not_to change(GroupMembership, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "does not expose a private group through nested membership update" do
    private_member = User.create!(name: "Private member", email: "private-group-member@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    membership = group.group_memberships.create!(user: private_member, status: :pending)
    sign_in member

    patch group_group_membership_path(group, membership)

    expect(response).to have_http_status(:not_found)
    expect(membership.reload).to be_pending
  end

  it "does not expose a private group through nested membership destroy" do
    private_member = User.create!(name: "Private member", email: "private-group-member-destroy@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    membership = group.group_memberships.create!(user: private_member, status: :active)
    sign_in member

    expect {
      delete group_group_membership_path(group, membership)
    }.not_to change(GroupMembership, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "lets the group_admin approve a pending request" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    membership = group.group_memberships.create!(user: member, status: :pending)
    sign_in group_admin

    patch group_group_membership_path(group, membership)

    expect(membership.reload).to be_active
    expect(response).to redirect_to(group_members_path(group))
  end

  it "does not let another user approve a pending request" do
    other_user = User.create!(name: "Other", email: "membership-approver@example.com", password: "password123!", password_confirmation: "password123!")
    Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Other group", group_type: :approval_group)
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    membership = group.group_memberships.create!(user: member, status: :pending)
    sign_in other_user

    patch group_group_membership_path(group, membership)

    expect(membership.reload).to be_pending
    expect(response).to redirect_to(root_path)
  end

  it "does not approve an active membership again" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    membership = group.group_memberships.create!(user: member, status: :active)
    sign_in group_admin

    patch group_group_membership_path(group, membership)

    expect(response).to redirect_to(root_path)
    expect(membership.reload).to be_active
  end

  it "lets a user cancel their own pending request" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    membership = group.group_memberships.create!(user: member, status: :pending)
    sign_in member

    expect {
      delete group_group_membership_path(group, membership)
    }.to change(GroupMembership, :count).by(-1)
  end

  it "lets a regular member leave" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    membership = group.group_memberships.create!(user: member, status: :active)
    sign_in member

    expect {
      delete group_group_membership_path(group, membership)
    }.to change(GroupMembership, :count).by(-1)
  end

  it "lets an activity-suspended member leave and preserves moderation history" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Suspended leave", group_type: :public_group)
    membership = group.group_memberships.create!(user: member, status: :active)
    GroupMemberships::SuspendActivity.new(membership, actor: group_admin, public_reason: "Community rule").call!
    suspension = membership.current_activity_suspension_action
    sign_in member

    expect {
      delete group_group_membership_path(group, membership)
    }.to change(GroupMembership, :count).by(-1)
    expect(ModerationAction.find(suspension.id)).to have_attributes(
      target_type: "GroupMembership",
      target_id: membership.id
    )
  end

  it "allows membership flows again after an ordinary membership ends" do
    public_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Rejoin public", group_type: :public_group)
    approval_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Reapply approval", group_type: :approval_group)
    private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Reinvite private", group_type: :private_group)

    public_membership = public_group.group_memberships.create!(user: member, status: :active)
    approval_membership = approval_group.group_memberships.create!(user: member, status: :active)
    private_membership = private_group.group_memberships.create!(user: member, status: :active)

    sign_in group_admin
    delete remove_group_group_membership_path(public_group, public_membership)
    delete remove_group_group_membership_path(approval_group, approval_membership)
    delete remove_group_group_membership_path(private_group, private_membership)
    expect(GroupMembershipRemoval.where(user: member).count).to eq(3)

    sign_in member
    post group_group_memberships_path(public_group)
    post group_group_memberships_path(approval_group)
    expect(public_group.group_memberships.find_by!(user: member)).to be_active
    expect(approval_group.group_memberships.find_by!(user: member)).to be_pending
    expect(GroupMembershipRemoval.exists?(group: public_group, user: member)).to be(false)
    expect(GroupMembershipRemoval.exists?(group: approval_group, user: member)).to be(true)

    sign_in group_admin
    patch group_group_membership_path(approval_group, approval_group.group_memberships.find_by!(user: member))
    expect(GroupMembershipRemoval.exists?(group: approval_group, user: member)).to be(false)

    expect {
      post invite_group_group_memberships_path(private_group), params: { user_id: member.id }
    }.to change(GroupMembership, :count).by(1)
    invitation = private_group.group_memberships.find_by!(user: member)
    expect(invitation).to be_invited
    expect(GroupMembershipRemoval.exists?(group: private_group, user: member)).to be(true)

    sign_in member
    patch accept_group_group_membership_path(private_group, invitation)
    expect(invitation.reload).to be_active
    expect(GroupMembershipRemoval.exists?(group: private_group, user: member)).to be(false)

    delete group_group_membership_path(private_group, invitation)
    expect(GroupMembershipRemoval.exists?(group: private_group, user: member)).to be(false)
    get group_path(private_group)
    expect(response).to have_http_status(:not_found)
  end

  it "does not let the group_admin leave" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    membership = group.group_memberships.find_by!(user: group_admin)
    sign_in group_admin

    expect {
      delete group_group_membership_path(group, membership)
    }.not_to change(GroupMembership, :count)

    expect(response).to redirect_to(root_path)
  end

  it "does not let a user destroy another user's membership" do
    other_user = User.create!(name: "Other", email: "membership-other@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    membership = group.group_memberships.create!(user: member, status: :active)
    sign_in other_user

    expect {
      delete group_group_membership_path(group, membership)
    }.not_to change(GroupMembership, :count)
  end

  describe "private group invitations" do
    let(:group) { Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group) }

    it "lets the group_admin invite a user without granting group access" do
      group
      sign_in group_admin

      expect {
        post invite_group_group_memberships_path(group), params: { user_id: member.id }
      }.to change(GroupMembership, :count).by(1)

      invitation = group.group_memberships.find_by!(user: member)
      expect(invitation).to be_invited
      expect(response).to redirect_to(group_members_path(group))

      sign_in member
      get group_path(group)
      expect(response).to have_http_status(:not_found)
    end

    it "blocks duplicate and self invitations" do
      group.group_memberships.create!(user: member, status: :invited)
      sign_in group_admin

      expect {
        post invite_group_group_memberships_path(group), params: { user_id: member.id }
        post invite_group_group_memberships_path(group), params: { user_id: group_admin.id }
      }.not_to change(GroupMembership, :count)
    end

    it "blocks invitations by members and in public or approval groups" do
      regular_member = User.create!(name: "Regular", email: "regular-inviter@example.com", password: "password123!", password_confirmation: "password123!")
      group.group_memberships.create!(user: regular_member, status: :active)
      sign_in regular_member

      expect {
        post invite_group_group_memberships_path(group), params: { user_id: member.id }
      }.not_to change(GroupMembership, :count)

      sign_in group_admin
      %i[public_group approval_group].each do |group_type|
        discoverable_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: group_type.to_s, group_type: group_type)
        expect {
          post invite_group_group_memberships_path(discoverable_group), params: { user_id: member.id }
        }.not_to change(GroupMembership, :count)
      end
    end

    it "does not let another user accept an invitation" do
      invitation = group.group_memberships.create!(user: member, status: :invited)
      other = User.create!(name: "Other invitee", email: "other-invitee@example.com", password: "password123!", password_confirmation: "password123!")
      sign_in other

      patch accept_group_group_membership_path(group, invitation)
      expect(response).to have_http_status(:not_found)
      expect(invitation.reload).to be_invited
    end

    it "does not grant Jjaek access before an invitation is accepted" do
      invitation = group.group_memberships.create!(user: member, status: :invited)
      jjaek = group_admin.jjaeks.create!(group: group, content: "Private club activity")
      sign_in member

      get jjaek_path(jjaek)

      expect(response).to have_http_status(:not_found)
      expect(invitation.reload).to be_invited
    end

    it "lets the invitee accept and then access the group and its Jjaek" do
      invitation = group.group_memberships.create!(user: member, status: :invited)
      jjaek = group_admin.jjaeks.create!(group: group, content: "Private club activity")
      sign_in member
      patch accept_group_group_membership_path(group, invitation)

      expect(invitation.reload).to be_active
      expect(response).to redirect_to(group_path(group))

      get group_path(group)
      expect(response).to have_http_status(:ok)

      get jjaek_path(jjaek)
      expect(response).to have_http_status(:ok)
    end

    it "lets only the invitee decline" do
      invitation = group.group_memberships.create!(user: member, status: :invited)
      other = User.create!(name: "Other decliner", email: "other-decliner@example.com", password: "password123!", password_confirmation: "password123!")
      sign_in other

      expect {
        delete decline_group_group_membership_path(group, invitation)
      }.not_to change(GroupMembership, :count)

      sign_in member
      expect {
        delete decline_group_group_membership_path(group, invitation)
      }.to change(GroupMembership, :count).by(-1)
    end
  end


  describe "group_admin membership management" do
    it "lets the group admin suspend and restore member activity with audit history" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Activity moderation", group_type: :private_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      sign_in group_admin

      patch suspend_activity_group_group_membership_path(group, membership), params: {
        moderation_action: { public_reason: "Community rule", internal_note: "Case 10" }
      }

      suspension = membership.current_activity_suspension_action
      expect(membership.reload).to be_activity_suspended
      expect(response).to redirect_to(group_members_path(group))

      get group_members_path(group)
      expect(response.body).to include("동아리 활동 정지", "Community rule", "Case 10", group_admin.name)

      sign_in group_admin
      patch restore_activity_group_group_membership_path(group, membership), params: {
        moderation_action: { public_reason: "Restored", internal_note: "Reviewed" }
      }

      restore = ModerationAction.order(:id).last
      expect(membership.reload).to be_moderation_status_normal
      expect(restore).to have_attributes(action_type: "restore_activity", reversal_of: suspension)
    end

    it "does not let a global admin suspend or restore group membership activity" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Activity boundary", group_type: :private_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      global_admin = User.create!(name: "Global admin", email: "activity-request-global@example.com", password: "password123!", global_admin: true)
      sign_in global_admin

      expect {
        patch suspend_activity_group_group_membership_path(group, membership), params: {
          moderation_action: { public_reason: "Blocked" }
        }
      }.not_to change(ModerationAction, :count)

      membership.update!(moderation_status: :activity_suspended)
      expect {
        patch restore_activity_group_group_membership_path(group, membership), params: {
          moderation_action: { public_reason: "Blocked" }
        }
      }.not_to change(ModerationAction, :count)
    end

    it "blocks activity moderation by a non-admin" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Activity guards", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      other = User.create!(name: "Other", email: "activity-request-other@example.com", password: "password123!")
      sign_in other

      expect {
        patch suspend_activity_group_group_membership_path(group, membership), params: {
          moderation_action: { public_reason: "Blocked" }
        }
      }.not_to change(ModerationAction, :count)
      expect(membership.reload).to be_moderation_status_normal
    end

    it "lets the group_admin remove an active ordinary member directly" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Direct removal", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      sign_in group_admin

      expect {
        delete remove_group_group_membership_path(group, membership)
      }.to change(GroupMembership, :count).by(-1)
        .and change(GroupMembershipRemoval, :count).by(1)
      removal = GroupMembershipRemoval.find_by!(group:, user: member)
      expect(removal).to have_attributes(group:, user: member, removed_by: group_admin)
      expect(response).to redirect_to(group_members_path(group))
    end

    it "lets the group_admin remove an activity-suspended member and preserves moderation history" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Suspended removal", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      GroupMemberships::SuspendActivity.new(
        membership,
        actor: group_admin,
        public_reason: "Community rule"
      ).call!
      suspension = membership.current_activity_suspension_action
      sign_in group_admin

      expect {
        delete remove_group_group_membership_path(group, membership)
      }.to change(GroupMembership, :count).by(-1)
        .and change(GroupMembershipRemoval, :count).by(1)
      expect(ModerationAction.find(suspension.id)).to have_attributes(
        target_type: "GroupMembership",
        target_id: membership.id
      )

      sign_in member
      post group_group_memberships_path(group)
      expect(group.group_memberships.find_by!(user: member)).to be_moderation_status_normal
      expect(GroupMembershipRemoval.exists?(group:, user: member)).to be(false)
    end

    it "blocks removal by ordinary members and global admins and removal of the group_admin" do
      other = User.create!(name: "Other manager", email: "other-manager@example.com", password: "password123!", password_confirmation: "password123!")
      global_admin = User.create!(name: "Global admin", email: "remove-global-admin@example.com", password: "password123!", global_admin: true)
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Removal guards", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      group_admin_membership = group.group_memberships.find_by!(user: group_admin)
      sign_in other

      expect {
        delete remove_group_group_membership_path(group, membership)
      }.not_to change(GroupMembership, :count)

      sign_in global_admin
      expect {
        delete remove_group_group_membership_path(group, membership)
      }.not_to change(GroupMembership, :count)

      sign_in group_admin
      expect {
        delete remove_group_group_membership_path(group, group_admin_membership)
      }.not_to change(GroupMembership, :count)
    end

    it "rejects an approval request without preventing a later request" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Reject request", group_type: :approval_group)
      membership = group.group_memberships.create!(user: member, status: :pending)
      sign_in group_admin

      expect {
        delete reject_group_group_membership_path(group, membership)
      }.to change(GroupMembership, :count).by(-1)
      expect(response).to redirect_to(group_members_path(group))

      delete reject_group_group_membership_path(group, membership)
      expect(response).to have_http_status(:not_found)

      sign_in member
      expect {
        post group_group_memberships_path(group)
      }.to change(GroupMembership, :count).by(1)
      expect(group.group_memberships.find_by!(user: member)).to be_pending
    end

    it "revokes a private invitation and removes it from the invitee's index" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Revoked invitation", group_type: :private_group)
      invitation = group.group_memberships.create!(user: member, status: :invited)
      sign_in group_admin

      expect {
        delete revoke_group_group_membership_path(group, invitation)
      }.to change(GroupMembership, :count).by(-1)
      expect(response).to redirect_to(group_members_path(group))

      sign_in member
      get groups_path
      expect(response.body).not_to include(group.name)
    end

    it "blocks reject and revoke for the wrong actor, state, or group type" do
      approval = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval guards", group_type: :approval_group)
      pending = approval.group_memberships.create!(user: member, status: :pending)
      private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private guards", group_type: :private_group)
      invitation = private_group.group_memberships.create!(user: member, status: :invited)
      other = User.create!(name: "Other actions", email: "other-actions@example.com", password: "password123!", password_confirmation: "password123!")
      sign_in other

      expect {
        delete reject_group_group_membership_path(approval, pending)
        delete revoke_group_group_membership_path(private_group, invitation)
      }.not_to change(GroupMembership, :count)

      sign_in group_admin
      pending.update!(status: :active)
      invitation.update!(status: :active)
      wrong_reject_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public reject", group_type: :public_group)
      wrong_reject = wrong_reject_group.group_memberships.create!(user: member, status: :pending)
      wrong_revoke = approval.group_memberships.create!(user: other, status: :invited)
      expect {
        delete reject_group_group_membership_path(approval, pending)
        delete revoke_group_group_membership_path(private_group, invitation)
        delete reject_group_group_membership_path(wrong_reject_group, wrong_reject)
        delete revoke_group_group_membership_path(approval, wrong_revoke)
      }.not_to change(GroupMembership, :count)
    end

    it "shows approval and invitation management actions to group_admins" do
      approval = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval UI", group_type: :approval_group)
      approval.group_memberships.create!(user: member, status: :pending)
      sign_in group_admin
      get group_members_path(approval)
      expect(response.body).to include("승인", "거절")

      private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Invitation UI", group_type: :private_group)
      private_group.group_memberships.create!(user: member, status: :invited)
      get group_members_path(private_group)
      expect(response.body).to include("보낸 초대", "초대 취소")
    end

    it "keeps invitations read-only when a private group is inactive" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Inactive invitations", group_type: :private_group)
      invitation = group.group_memberships.create!(user: member, status: :invited)
      group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)

      sign_in group_admin
      get group_members_path(group)
      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(member.name, "보낸 초대")
      expect(page.at_css(%(form[action="#{revoke_group_group_membership_path(group, invitation)}"]))).to be_nil

      global_admin = User.create!(name: "Global admin", email: "inactive-invitation-admin@example.com", password: "password123!", global_admin: true)
      sign_in global_admin
      get group_members_path(group)
      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(member.name, "보낸 초대")
      expect(page.at_css(%(form[action="#{revoke_group_group_membership_path(group, invitation)}"]))).to be_nil
    end

    it "blocks invitation acceptance when the group is inactive" do
      group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Closed private", group_type: :private_group)
      invitation = group.group_memberships.create!(user: member, status: :invited)
      group.update!(
        lifecycle_status: :inactive,
        closure_reason: "Test closure",
        closed_at: Time.current
      )
      sign_in member
      get groups_path
      expect(response.body).not_to include(group.name)
      patch accept_group_group_membership_path(group, invitation)
      expect(invitation.reload).to be_invited
    end
  end

  describe "membership lifecycle history" do
    it "records public join, approval request, approval, cancellation, and rejection with the correct actors" do
      public_group = Group.create!(lifecycle_status: :active, group_admin:, name: "History public", group_type: :public_group)
      approval_group = Group.create!(lifecycle_status: :active, group_admin:, name: "History approval", group_type: :approval_group)
      sign_in member

      post group_group_memberships_path(public_group)
      post group_group_memberships_path(approval_group)
      request = approval_group.group_memberships.find_by!(user: member)

      expect(public_group.group_membership_events.recent.first).to have_attributes(event_type: "joined", user: member, actor: member)
      expect(approval_group.group_membership_events.recent.first).to have_attributes(event_type: "requested_to_join", user: member, actor: member)

      delete group_group_membership_path(approval_group, request)
      expect(approval_group.group_membership_events.recent.first).to have_attributes(event_type: "join_request_cancelled", user: member, actor: member)

      post group_group_memberships_path(approval_group)
      request = approval_group.group_memberships.find_by!(user: member)
      sign_in group_admin
      patch group_group_membership_path(approval_group, request)
      expect(approval_group.group_membership_events.recent.first).to have_attributes(event_type: "approved", user: member, actor: group_admin)

      other = User.create!(name: "Rejected", email: "membership-event-rejected@example.com", password: "password123!", password_confirmation: "password123!")
      sign_in other
      post group_group_memberships_path(approval_group)
      rejected_request = approval_group.group_memberships.find_by!(user: other)
      sign_in group_admin
      delete reject_group_group_membership_path(approval_group, rejected_request)
      expect(approval_group.group_membership_events.recent.first).to have_attributes(event_type: "request_rejected", user: other, actor: group_admin)
    end

    it "records private invitation, acceptance, decline, and revocation with the correct actors" do
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "History private", group_type: :private_group)
      declined_user = User.create!(name: "Declined", email: "membership-event-declined@example.com", password: "password123!", password_confirmation: "password123!")
      revoked_user = User.create!(name: "Revoked", email: "membership-event-revoked@example.com", password: "password123!", password_confirmation: "password123!")
      sign_in group_admin

      post invite_group_group_memberships_path(group), params: { user_id: member.id }
      invitation = group.group_memberships.find_by!(user: member)
      expect(group.group_membership_events.recent.first).to have_attributes(event_type: "invited", user: member, actor: group_admin)

      sign_in member
      patch accept_group_group_membership_path(group, invitation)
      expect(group.group_membership_events.recent.first).to have_attributes(event_type: "invitation_accepted", user: member, actor: member)

      sign_in group_admin
      post invite_group_group_memberships_path(group), params: { user_id: declined_user.id }
      declined_invitation = group.group_memberships.find_by!(user: declined_user)
      sign_in declined_user
      delete decline_group_group_membership_path(group, declined_invitation)
      expect(group.group_membership_events.recent.first).to have_attributes(event_type: "invitation_declined", user: declined_user, actor: declined_user)

      sign_in group_admin
      post invite_group_group_memberships_path(group), params: { user_id: revoked_user.id }
      revoked_invitation = group.group_memberships.find_by!(user: revoked_user)
      delete revoke_group_group_membership_path(group, revoked_invitation)
      expect(group.group_membership_events.recent.first).to have_attributes(event_type: "invitation_revoked", user: revoked_user, actor: group_admin)
    end

    it "preserves left and removed events after membership deletion and keeps removal markers separate" do
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "History endings", group_type: :public_group)
      leaving_member = group.group_memberships.create!(user: member, status: :active)
      sign_in member

      delete group_group_membership_path(group, leaving_member)
      expect(group.group_membership_events.recent.first).to have_attributes(event_type: "left", user: member, actor: member)
      expect(GroupMembershipRemoval.exists?(group:, user: member)).to be(false)

      sign_in member
      post group_group_memberships_path(group)
      rejoined_membership = group.group_memberships.find_by!(user: member)
      sign_in group_admin
      delete remove_group_group_membership_path(group, rejoined_membership)

      removed_event = group.group_membership_events.recent.first
      expect(removed_event).to have_attributes(event_type: "removed", user: member, actor: group_admin)
      expect(GroupMembershipRemoval.exists?(group:, user: member)).to be(true)

      sign_in member
      post group_group_memberships_path(group)
      expect(GroupMembershipRemoval.exists?(group:, user: member)).to be(false)
      expect(GroupMembershipEvent.exists?(removed_event.id)).to be(true)
    end

    it "does not duplicate activity moderation in membership history" do
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "History moderation", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      sign_in group_admin
      event_count = GroupMembershipEvent.count

      expect {
        patch suspend_activity_group_group_membership_path(group, membership), params: {
          moderation_action: { public_reason: "Community rule" }
        }
      }.to change(ModerationAction, :count).by(1)
      expect(GroupMembershipEvent.count).to eq(event_count)

      expect {
        patch restore_activity_group_group_membership_path(group, membership), params: {
          moderation_action: { public_reason: "Restored" }
        }
      }.to change(ModerationAction, :count).by(1)
      expect(GroupMembershipEvent.count).to eq(event_count)
    end

    it "rolls back removal marker and membership deletion when event creation fails" do
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "History atomicity", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      sign_in group_admin
      allow(GroupMembershipEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(GroupMembershipEvent.new))

      event_count = GroupMembershipEvent.count

      delete remove_group_group_membership_path(group, membership)

      expect(response).to have_http_status(:unprocessable_content)
      expect(GroupMembership.exists?(membership.id)).to be(true)
      expect(GroupMembershipRemoval.exists?(group:, user: member)).to be(false)
      expect(GroupMembershipEvent.count).to eq(event_count)
    end
  end

  describe "member management history UI" do
    it "combines lifecycle and moderation history after memberships are deleted" do
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "Combined history", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      suspension = GroupMemberships::SuspendActivity.new(
        membership,
        actor: group_admin,
        public_reason: "Public suspension reason",
        internal_note: "Operations note"
      ).call!.current_activity_suspension_action
      GroupMemberships::RestoreActivity.new(
        membership,
        actor: group_admin,
        public_reason: "Public restore reason",
        internal_note: "Restore note"
      ).call!
      sign_in group_admin
      delete remove_group_group_membership_path(group, membership)

      leaving_user = User.create!(name: "Leaving member", email: "history-ui-leaving@example.com", password: "password123!", password_confirmation: "password123!")
      leaving_membership = group.group_memberships.create!(user: leaving_user, status: :active)
      sign_in leaving_user
      delete group_group_membership_path(group, leaving_membership)

      sign_in group_admin
      get group_members_path(group)
      history = Nokogiri::HTML(response.body).at_css("#membership-operations-history")

      expect(history.text).to include(
        "#{group_admin.name}님이 #{member.name}님을 동아리에서 내보냈습니다.",
        "#{group_admin.name}님이 #{member.name}님의 동아리 활동을 정지했습니다.",
        "#{group_admin.name}님이 #{member.name}님의 동아리 활동 정지를 해제했습니다.",
        "#{leaving_user.name}님이 동아리에서 탈퇴했습니다.",
        "Public suspension reason",
        "Public restore reason",
        "Operations note",
        "Restore note"
      )
      expect(history.text).not_to include("suspend_activity", "restore_activity", "removed", "left")
      expect(ModerationAction.for_membership_group(group)).to include(suspension)
    end

    it "orders both sources newest first and deterministically when timestamps match" do
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "Ordered history", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      timestamp = Time.zone.parse("2026-08-30 15:22:00")
      lifecycle = group.group_membership_events.create!(
        user: member,
        actor: member,
        event_type: :joined,
        created_at: timestamp
      )
      moderation = ModerationAction.create!(
        target: membership,
        actor: group_admin,
        action_type: :suspend_activity,
        public_reason: "Same timestamp",
        created_at: timestamp
      )
      newer = group.group_membership_events.create!(
        user: member,
        actor: member,
        event_type: :left,
        created_at: timestamp + 1.second
      )
      sign_in group_admin

      get group_members_path(group)
      history_text = Nokogiri::HTML(response.body).at_css("#membership-operations-history").text
      newer_position = history_text.index("#{member.name}님이 동아리에서 탈퇴했습니다")
      moderation_position = history_text.index("#{group_admin.name}님이 #{member.name}님의 동아리 활동을 정지했습니다")
      lifecycle_position = history_text.index("#{member.name}님이 동아리에 가입했습니다")

      expect(newer).to be_present
      expect(moderation).to be_present
      expect(lifecycle).to be_present
      expect(newer_position).to be < moderation_position
      expect(moderation_position).to be < lifecycle_position
    end

    it "keeps current suspension state and reason without inline history details" do
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "Current suspension", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      GroupMemberships::SuspendActivity.new(
        membership,
        actor: group_admin,
        public_reason: "Current public reason",
        internal_note: "Current internal note"
      ).call!
      sign_in group_admin

      get group_members_path(group)
      page = Nokogiri::HTML(response.body)
      current_members = page.at_css("#current-members")
      history = page.at_css("#membership-operations-history")

      expect(current_members.text).to include(member.name, "동아리 활동 정지", "Current public reason", "활동 복구")
      expect(current_members.text).not_to include(
        I18n.t("group_memberships.moderation.history.title")
      )
      expect(history.text).to include("Current public reason", "Current internal note")
    end
  end

  describe "group member bans" do
    def ban_membership(group, membership, reason: "Rule violation")
      sign_in group.group_admin
      post group_group_member_bans_path(group), params: {
        membership_id: membership.id,
        moderation_action: { public_reason: reason, internal_note: "Operations only" }
      }
      group.group_member_bans.find_by!(user: membership.user)
    end

    it "blocks public joins, approval requests and approvals, and private invitations and acceptance" do
      public_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Ban public", group_type: :public_group)
      approval_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Ban approval", group_type: :approval_group)
      private_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Ban private", group_type: :private_group)

      public_ban = ban_membership(public_group, public_group.group_memberships.create!(user: member, status: :active))
      approval_ban = ban_membership(approval_group, approval_group.group_memberships.create!(user: member, status: :active))
      private_ban = ban_membership(private_group, private_group.group_memberships.create!(user: member, status: :active))
      expect([ public_ban, approval_ban, private_ban ]).to all(be_persisted)

      sign_in member
      expect { post group_group_memberships_path(public_group) }.not_to change(GroupMembership, :count)
      expect { post group_group_memberships_path(approval_group) }.not_to change(GroupMembership, :count)

      sign_in group_admin
      expect {
        post invite_group_group_memberships_path(private_group), params: { user_id: member.id }
      }.not_to change(GroupMembership, :count)

      GroupMembership.insert!({
        group_id: approval_group.id,
        user_id: member.id,
        status: GroupMembership.statuses.fetch("pending"),
        moderation_status: GroupMembership.moderation_statuses.fetch("normal"),
        created_at: Time.current,
        updated_at: Time.current
      })
      pending_id = approval_group.group_memberships.find_by!(user: member).id
      patch group_group_membership_path(approval_group, pending_id)
      expect(GroupMembership.find(pending_id)).to be_pending

      GroupMembership.insert!({
        group_id: private_group.id,
        user_id: member.id,
        status: GroupMembership.statuses.fetch("invited"),
        moderation_status: GroupMembership.moderation_statuses.fetch("normal"),
        created_at: Time.current,
        updated_at: Time.current
      })
      invitation_id = private_group.group_memberships.find_by!(user: member).id
      sign_in member
      patch accept_group_group_membership_path(private_group, invitation_id)
      expect(GroupMembership.find(invitation_id)).to be_invited
    end

    it "removes banned users from invitation candidates" do
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "Ban candidates", group_type: :private_group)
      eligible_user = User.create!(
        name: "Eligible member",
        email: "ban-candidate-eligible@example.com",
        password: "password123!"
      )
      ban_membership(group, group.group_memberships.create!(user: member, status: :invited))

      get group_members_path(group)
      invite_form = Nokogiri::HTML(response.body).at_css(%(form[action="#{invite_group_group_memberships_path(group)}"]))
      expect(invite_form).to be_present
      expect(invite_form.text).to include(eligible_user.name)
      expect(invite_form.text).not_to include(member.name)
    end

    it "unbans without restoring membership and permits each normal participation flow again" do
      public_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Unban public", group_type: :public_group)
      approval_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Unban approval", group_type: :approval_group)
      private_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Unban private", group_type: :private_group)
      bans = [
        ban_membership(public_group, public_group.group_memberships.create!(user: member, status: :active)),
        ban_membership(approval_group, approval_group.group_memberships.create!(user: member, status: :active)),
        ban_membership(private_group, private_group.group_memberships.create!(user: member, status: :active))
      ]

      bans.each do |ban|
        delete group_group_member_ban_path(ban.group, ban), params: {
          moderation_action: { public_reason: "Restriction lifted" }
        }
      end
      expect(GroupMemberBan.where(id: bans.map(&:id))).to be_empty
      expect(GroupMembership.where(user: member, group: [ public_group, approval_group, private_group ])).to be_empty

      get group_members_path(public_group)
      history = Nokogiri::HTML(response.body).at_css("#membership-operations-history").text
      expect(history).to include(
        "#{group_admin.name}님이 #{member.name}님의 동아리 이용을 제한했습니다.",
        "#{group_admin.name}님이 #{member.name}님의 동아리 이용 제한을 해제했습니다.",
        "Restriction lifted"
      )

      sign_in member
      post group_group_memberships_path(public_group)
      post group_group_memberships_path(approval_group)
      expect(public_group.group_memberships.find_by!(user: member)).to be_active
      expect(approval_group.group_memberships.find_by!(user: member)).to be_pending

      sign_in group_admin
      post invite_group_group_memberships_path(private_group), params: { user_id: member.id }
      expect(private_group.group_memberships.find_by!(user: member)).to be_invited
    end

    it "shows current restrictions and ban history to global admins without mutation forms" do
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "Ban inspection", group_type: :public_group)
      ban = ban_membership(group, group.group_memberships.create!(user: member, status: :active), reason: "Visible reason")
      other = User.create!(name: "Other member", email: "ban-global-other@example.com", password: "password123!")
      other_membership = group.group_memberships.create!(user: other, status: :active)
      global_admin = User.create!(name: "Global admin", email: "ban-global@example.com", password: "password123!", global_admin: true)
      sign_in global_admin

      get group_members_path(group)
      page = Nokogiri::HTML(response.body)
      history = page.at_css("#membership-operations-history")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(member.name, "Visible reason", "Operations only")
      expect(history.text).to include("#{group_admin.name}님이 #{member.name}님의 동아리 이용을 제한했습니다.")
      expect(page.at_css(%(form[action="#{group_group_member_ban_path(group, ban)}"]))).to be_nil
      expect(page.at_css(%(form[action="#{group_group_member_bans_path(group)}"]))).to be_nil

      expect {
        post group_group_member_bans_path(group), params: {
          membership_id: other_membership.id,
          moderation_action: { public_reason: "Blocked" }
        }
      }.not_to change(GroupMemberBan, :count)

      expect {
        delete group_group_member_ban_path(group, ban), params: {
          moderation_action: { public_reason: "Blocked" }
        }
      }.not_to change(GroupMemberBan, :count)
    end
  end
end
