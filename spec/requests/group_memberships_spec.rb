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
end
