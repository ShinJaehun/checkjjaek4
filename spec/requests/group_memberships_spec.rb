require "rails_helper"

RSpec.describe "Group memberships", type: :request do
  let!(:owner) { User.create!(name: "Owner", email: "group-memberships-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:member) { User.create!(name: "Member", email: "group-memberships-member@example.com", password: "password123!", password_confirmation: "password123!") }

  it "joins a public group immediately" do
    group = Group.create!(owner: owner, name: "Public", group_type: :public_group)
    sign_in member

    expect {
      post group_group_memberships_path(group)
    }.to change(GroupMembership, :count).by(1)

    expect(group.group_memberships.find_by(user: member)).to be_active
  end

  it "creates a pending request for an approval group" do
    group = Group.create!(owner: owner, name: "Approval", group_type: :approval_group)
    sign_in member

    post group_group_memberships_path(group)

    expect(group.group_memberships.find_by(user: member)).to be_pending
  end

  it "does not create duplicate memberships or requests" do
    group = Group.create!(owner: owner, name: "Approval", group_type: :approval_group)
    group.group_memberships.create!(user: member, status: :pending)
    sign_in member

    expect {
      post group_group_memberships_path(group)
    }.not_to change(GroupMembership, :count)
  end

  it "does not expose a private group through nested membership create" do
    group = Group.create!(owner: owner, name: "Private", group_type: :private_group)
    sign_in member

    expect {
      post group_group_memberships_path(group)
    }.not_to change(GroupMembership, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "does not expose a private group through nested membership update" do
    private_member = User.create!(name: "Private member", email: "private-group-member@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(owner: owner, name: "Private", group_type: :private_group)
    membership = group.group_memberships.create!(user: private_member, status: :pending)
    sign_in member

    patch group_group_membership_path(group, membership)

    expect(response).to have_http_status(:not_found)
    expect(membership.reload).to be_pending
  end

  it "does not expose a private group through nested membership destroy" do
    private_member = User.create!(name: "Private member", email: "private-group-member-destroy@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(owner: owner, name: "Private", group_type: :private_group)
    membership = group.group_memberships.create!(user: private_member, status: :active)
    sign_in member

    expect {
      delete group_group_membership_path(group, membership)
    }.not_to change(GroupMembership, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "lets the owner approve a pending request" do
    group = Group.create!(owner: owner, name: "Approval", group_type: :approval_group)
    membership = group.group_memberships.create!(user: member, status: :pending)
    sign_in owner

    patch group_group_membership_path(group, membership)

    expect(membership.reload).to be_active
  end

  it "does not let another user approve a pending request" do
    other_user = User.create!(name: "Other", email: "membership-approver@example.com", password: "password123!", password_confirmation: "password123!")
    Group.create!(owner: other_user, name: "Other group", group_type: :approval_group)
    group = Group.create!(owner: owner, name: "Approval", group_type: :approval_group)
    membership = group.group_memberships.create!(user: member, status: :pending)
    sign_in other_user

    patch group_group_membership_path(group, membership)

    expect(membership.reload).to be_pending
    expect(response).to redirect_to(root_path)
  end

  it "does not approve an active membership again" do
    group = Group.create!(owner: owner, name: "Approval", group_type: :approval_group)
    membership = group.group_memberships.create!(user: member, status: :active)
    sign_in owner

    patch group_group_membership_path(group, membership)

    expect(response).to redirect_to(root_path)
    expect(membership.reload).to be_active
  end

  it "lets a user cancel their own pending request" do
    group = Group.create!(owner: owner, name: "Approval", group_type: :approval_group)
    membership = group.group_memberships.create!(user: member, status: :pending)
    sign_in member

    expect {
      delete group_group_membership_path(group, membership)
    }.to change(GroupMembership, :count).by(-1)
  end

  it "lets a regular member leave" do
    group = Group.create!(owner: owner, name: "Public", group_type: :public_group)
    membership = group.group_memberships.create!(user: member, status: :active)
    sign_in member

    expect {
      delete group_group_membership_path(group, membership)
    }.to change(GroupMembership, :count).by(-1)
  end

  it "does not let the owner leave" do
    group = Group.create!(owner: owner, name: "Public", group_type: :public_group)
    membership = group.group_memberships.find_by!(user: owner)
    sign_in owner

    expect {
      delete group_group_membership_path(group, membership)
    }.not_to change(GroupMembership, :count)

    expect(response).to redirect_to(root_path)
  end

  it "does not let a user destroy another user's membership" do
    other_user = User.create!(name: "Other", email: "membership-other@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(owner: owner, name: "Public", group_type: :public_group)
    membership = group.group_memberships.create!(user: member, status: :active)
    sign_in other_user

    expect {
      delete group_group_membership_path(group, membership)
    }.not_to change(GroupMembership, :count)
  end

  describe "private group invitations" do
    let(:group) { Group.create!(owner: owner, name: "Private", group_type: :private_group) }

    it "lets the owner invite a user without granting group access" do
      group
      sign_in owner

      expect {
        post invite_group_group_memberships_path(group), params: { user_id: member.id }
      }.to change(GroupMembership, :count).by(1)

      invitation = group.group_memberships.find_by!(user: member)
      expect(invitation).to be_invited

      sign_in member
      get group_path(group)
      expect(response).to have_http_status(:not_found)
    end

    it "blocks duplicate and self invitations" do
      group.group_memberships.create!(user: member, status: :invited)
      sign_in owner

      expect {
        post invite_group_group_memberships_path(group), params: { user_id: member.id }
        post invite_group_group_memberships_path(group), params: { user_id: owner.id }
      }.not_to change(GroupMembership, :count)
    end

    it "blocks invitations by members and in public or approval groups" do
      regular_member = User.create!(name: "Regular", email: "regular-inviter@example.com", password: "password123!", password_confirmation: "password123!")
      group.group_memberships.create!(user: regular_member, status: :active)
      sign_in regular_member

      expect {
        post invite_group_group_memberships_path(group), params: { user_id: member.id }
      }.not_to change(GroupMembership, :count)

      sign_in owner
      %i[public_group approval_group].each do |group_type|
        discoverable_group = Group.create!(owner: owner, name: group_type.to_s, group_type: group_type)
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
      jjaek = owner.jjaeks.create!(group: group, content: "Private club activity")
      sign_in member

      get jjaek_path(jjaek)

      expect(response).to have_http_status(:not_found)
      expect(invitation.reload).to be_invited
    end

    it "lets the invitee accept and then access the group and its Jjaek" do
      invitation = group.group_memberships.create!(user: member, status: :invited)
      jjaek = owner.jjaeks.create!(group: group, content: "Private club activity")
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


  describe "owner membership management" do
    it "deactivates an approval group member and revokes internal content access" do
      group = Group.create!(owner: owner, name: "Remove approval", group_type: :approval_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      jjaek = owner.jjaeks.create!(group: group, content: "Members only")
      sign_in owner

      expect {
        patch deactivate_group_group_membership_path(group, membership)
      }.not_to change(GroupMembership, :count)
      expect(membership.reload).to be_inactive

      sign_in member

      get group_path(group)
      expect(response).to have_http_status(:ok)

      get jjaek_path(jjaek)
      expect(response).to have_http_status(:not_found)
    end

    it "lets a deactivated private member see basic group status without management access" do
      group = Group.create!(owner: owner, name: "Remove private", group_type: :private_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      sign_in owner

      expect {
        patch deactivate_group_group_membership_path(group, membership)
      }.not_to change(GroupMembership, :count)
      expect(membership.reload).to be_inactive

      sign_out owner
      sign_in member

      expect(group.reload.active_member?(member)).to be(false)
      expect(GroupPolicy.new(member, group).read_jjaeks?).to be(false)
      expect(GroupPolicy.new(member, group).create_jjaek?).to be(false)

      get group_path(group)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("활동 중지")
      expect(response.body).not_to include("동아리 구성원", "다시 활성화", "내보내기")
    end

    it "deactivates a private group member and revokes Jjaek access" do
      group = Group.create!(owner: owner, name: "Remove private", group_type: :private_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      jjaek = owner.jjaeks.create!(group: group, content: "Private members only")
      sign_in owner

      expect {
        patch deactivate_group_group_membership_path(group, membership)
      }.not_to change(GroupMembership, :count)
      expect(membership.reload).to be_inactive

      sign_out owner
      sign_in member

      expect(group.reload.active_member?(member)).to be(false)
      expect(JjaekPolicy.new(member, jjaek.reload).show?).to be(false)

      get jjaek_path(jjaek)
      expect(response).to have_http_status(:not_found)
    end

    it "keeps public read access but removes public write access while inactive" do
      group = Group.create!(owner: owner, name: "Public removal", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      sign_in owner
      patch deactivate_group_group_membership_path(group, membership)

      sign_in member
      get group_path(group)
      expect(response).to have_http_status(:ok)
      expect(GroupPolicy.new(member, group).create_jjaek?).to be(false)
    end

    it "blocks deactivation by non-owners and deactivation of the owner" do
      other = User.create!(name: "Other manager", email: "other-manager@example.com", password: "password123!", password_confirmation: "password123!")
      group = Group.create!(owner: owner, name: "Removal guards", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      owner_membership = group.group_memberships.find_by!(user: owner)
      sign_in other

      patch deactivate_group_group_membership_path(group, membership)
      expect(membership.reload).to be_active

      sign_in owner
      patch deactivate_group_group_membership_path(group, owner_membership)
      expect(owner_membership.reload).to be_active
    end

    it "reactivates an inactive member and restores private group access" do
      group = Group.create!(owner: owner, name: "Reactivate", group_type: :private_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      membership.update!(status: :inactive)
      sign_in owner

      patch reactivate_group_group_membership_path(group, membership)

      expect(membership.reload).to be_active
      sign_in member
      get group_path(group)
      expect(response).to have_http_status(:ok)
    end

    it "requires inactive status before final removal" do
      group = Group.create!(owner: owner, name: "Two step removal", group_type: :public_group)
      membership = group.group_memberships.create!(user: member, status: :active)
      sign_in owner

      expect {
        delete remove_group_group_membership_path(group, membership)
      }.not_to change(GroupMembership, :count)

      membership.update!(status: :inactive)
      expect {
        delete remove_group_group_membership_path(group, membership)
      }.to change(GroupMembership, :count).by(-1)
    end

    it "does not let an inactive member bypass status through another membership flow" do
      public_group = Group.create!(owner: owner, name: "Inactive public", group_type: :public_group)
      approval_group = Group.create!(owner: owner, name: "Inactive approval", group_type: :approval_group)
      private_group = Group.create!(owner: owner, name: "Inactive private", group_type: :private_group)
      [public_group, approval_group, private_group].each do |group|
        membership = group.group_memberships.create!(user: member, status: :active)
        membership.update!(status: :inactive)
      end
      sign_in member

      expect {
        post group_group_memberships_path(public_group)
        post group_group_memberships_path(approval_group)
      }.not_to change(GroupMembership, :count)

      inactive_membership = public_group.group_memberships.find_by!(user: member)
      expect {
        delete group_group_membership_path(public_group, inactive_membership)
      }.not_to change(GroupMembership, :count)

      sign_in owner
      expect {
        post invite_group_group_memberships_path(private_group), params: { user_id: member.id }
      }.not_to change(GroupMembership, :count)
    end

    it "rejects an approval request without preventing a later request" do
      group = Group.create!(owner: owner, name: "Reject request", group_type: :approval_group)
      membership = group.group_memberships.create!(user: member, status: :pending)
      sign_in owner

      expect {
        delete reject_group_group_membership_path(group, membership)
      }.to change(GroupMembership, :count).by(-1)

      delete reject_group_group_membership_path(group, membership)
      expect(response).to have_http_status(:not_found)

      sign_in member
      expect {
        post group_group_memberships_path(group)
      }.to change(GroupMembership, :count).by(1)
      expect(group.group_memberships.find_by!(user: member)).to be_pending
    end

    it "revokes a private invitation and removes it from the invitee's index" do
      group = Group.create!(owner: owner, name: "Revoked invitation", group_type: :private_group)
      invitation = group.group_memberships.create!(user: member, status: :invited)
      sign_in owner

      expect {
        delete revoke_group_group_membership_path(group, invitation)
      }.to change(GroupMembership, :count).by(-1)

      sign_in member
      get groups_path
      expect(response.body).not_to include(group.name)
    end

    it "blocks reject and revoke for the wrong actor, state, or group type" do
      approval = Group.create!(owner: owner, name: "Approval guards", group_type: :approval_group)
      pending = approval.group_memberships.create!(user: member, status: :pending)
      private_group = Group.create!(owner: owner, name: "Private guards", group_type: :private_group)
      invitation = private_group.group_memberships.create!(user: member, status: :invited)
      other = User.create!(name: "Other actions", email: "other-actions@example.com", password: "password123!", password_confirmation: "password123!")
      sign_in other

      expect {
        delete reject_group_group_membership_path(approval, pending)
        delete revoke_group_group_membership_path(private_group, invitation)
      }.not_to change(GroupMembership, :count)

      sign_in owner
      pending.update!(status: :active)
      invitation.update!(status: :active)
      wrong_reject_group = Group.create!(owner: owner, name: "Public reject", group_type: :public_group)
      wrong_reject = wrong_reject_group.group_memberships.create!(user: member, status: :pending)
      wrong_revoke = approval.group_memberships.create!(user: other, status: :invited)
      expect {
        delete reject_group_group_membership_path(approval, pending)
        delete revoke_group_group_membership_path(private_group, invitation)
        delete reject_group_group_membership_path(wrong_reject_group, wrong_reject)
        delete revoke_group_group_membership_path(approval, wrong_revoke)
      }.not_to change(GroupMembership, :count)
    end

    it "shows approval and invitation management actions to owners" do
      approval = Group.create!(owner: owner, name: "Approval UI", group_type: :approval_group)
      approval.group_memberships.create!(user: member, status: :pending)
      sign_in owner
      get group_path(approval)
      expect(response.body).to include("승인", "거절")

      private_group = Group.create!(owner: owner, name: "Invitation UI", group_type: :private_group)
      private_group.group_memberships.create!(user: member, status: :invited)
      get group_path(private_group)
      expect(response.body).to include("보낸 초대", "초대 취소")
    end
  end
end
