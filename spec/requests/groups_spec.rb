require "rails_helper"

RSpec.describe "Groups", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "groups-reader@example.com", password: "password123!", password_confirmation: "password123!") }

  it "requires sign in" do
    get groups_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "lets a signed-in user create a public group with an owner membership" do
    sign_in user

    expect {
      post groups_path, params: { group: { name: "Readers", description: "Read together", group_type: "public_group" } }
    }.to change(Group, :count).by(1).and change(GroupMembership, :count).by(1)

    group = Group.last
    expect(group.owner).to eq(user)
    expect(group.group_memberships.find_by(user: user)).to be_active
    expect(response).to redirect_to(group_path(group))
  end

  it "allows private group creation with an owner membership" do
    sign_in user

    expect {
      post groups_path, params: { group: { name: "Private", group_type: "private_group" } }
    }.to change(Group, :count).by(1).and change(GroupMembership, :count).by(1)

    expect(Group.last.group_memberships.find_by(user: user)).to be_active
    expect(response).to redirect_to(group_path(Group.last))
  end


  it "shows only the current user's invitations outside the discoverable list" do
    owner = User.create!(name: "Owner", email: "invitation-owner@example.com", password: "password123!", password_confirmation: "password123!")
    other = User.create!(name: "Other", email: "invitation-other@example.com", password: "password123!", password_confirmation: "password123!")
    invited_group = Group.create!(owner: owner, name: "Invitation only", group_type: :private_group)
    other_group = Group.create!(owner: owner, name: "Someone else's invitation", group_type: :private_group)
    invited_group.group_memberships.create!(user: user, status: :invited)
    other_group.group_memberships.create!(user: other, status: :invited)
    sign_in user

    get groups_path

    expect(response.body).to include("받은 동아리 초대", invited_group.name)
    expect(response.body).not_to include(other_group.name)
    expect(GroupPolicy::Scope.new(user, Group.all).resolve).not_to include(invited_group)
  end

  it "lists public, approval, and joined private groups only" do
    other_owner = User.create!(name: "Owner", email: "groups-owner@example.com", password: "password123!", password_confirmation: "password123!")
    public_group = Group.create!(owner: other_owner, name: "Public group", group_type: :public_group)
    approval_group = Group.create!(owner: other_owner, name: "Approval group", group_type: :approval_group)
    joined_private = Group.create!(owner: other_owner, name: "Joined private", group_type: :private_group)
    hidden_private = Group.create!(owner: other_owner, name: "Hidden private", group_type: :private_group)
    joined_private.group_memberships.create!(user: user, status: :active)
    sign_in user

    get groups_path

    expect(response.body).to include(public_group.name, approval_group.name, joined_private.name)
    expect(response.body).not_to include(hidden_private.name)
  end

  it "does not expose a private group to a non-member by direct URL" do
    other_owner = User.create!(name: "Owner", email: "private-owner@example.com", password: "password123!", password_confirmation: "password123!")
    private_group = Group.create!(owner: other_owner, name: "Hidden private", group_type: :private_group)
    sign_in user

    get group_path(private_group)

    expect(response).to have_http_status(:not_found)
  end


  it "shows the invitation form only to a private group owner" do
    invitee = User.create!(name: "Invitee", email: "invite-form-user@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(owner: user, name: "Private invitations", group_type: :private_group)
    sign_in user

    get group_path(group)
    expect(response.body).to include("동아리 초대", invitee.name)

    group.group_memberships.create!(user: invitee, status: :active)
    sign_in invitee
    get group_path(group)
    expect(response.body).not_to include("동아리 초대")
  end


  describe "owner management" do
    let(:group) { Group.create!(owner: user, name: "Original", description: "Before", group_type: :approval_group) }

    it "lets the owner edit name and description without changing group type" do
      sign_in user

      get edit_group_path(group)
      expect(response).to have_http_status(:ok)

      patch group_path(group), params: { group: { name: "Updated", description: "After", group_type: "private_group" } }

      expect(response).to redirect_to(group_path(group))
      expect(group.reload).to have_attributes(name: "Updated", description: "After", group_type: "approval_group")
    end

    it "renders edit with 422 when validation fails" do
      sign_in user

      patch group_path(group), params: { group: { name: "", description: "After" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).not_to include("동아리 종류")
    end

    it "blocks a non-owner from edit and update" do
      group.group_memberships.create!(user: other_user = User.create!(name: "Member", email: "group-edit-member@example.com", password: "password123!", password_confirmation: "password123!"), status: :active)
      sign_in other_user

      get edit_group_path(group)
      expect(response).to redirect_to(root_path)

      patch group_path(group), params: { group: { name: "Hijacked" } }
      expect(response).to redirect_to(root_path)
      expect(group.reload.name).to eq("Original")
    end

    it "shows owner controls and member list only to the owner" do
      member = User.create!(name: "Listed member", email: "listed-member@example.com", password: "password123!", password_confirmation: "password123!")
      group.group_memberships.create!(user: member, status: :active)
      sign_in user

      get group_path(group)
      expect(response.body).to include("동아리 수정", "동아리 구성원", member.name, "활동 중지")
      expect(response.body).not_to include("내보내기")

      group.group_memberships.find_by!(user: member).update!(status: :inactive)
      get group_path(group)
      expect(response.body).to include("활동 중지된 구성원", "다시 활성화", "내보내기")

      sign_in member
      get group_path(group)
      expect(response.body).to include("활동 중지")
      expect(response.body).not_to include("동아리 수정", "동아리 구성원", "다시 활성화", "내보내기")
    end
  end
end
