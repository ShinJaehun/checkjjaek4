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

  it "does not allow private group creation through the user endpoint" do
    sign_in user

    expect {
      post groups_path, params: { group: { name: "Private", group_type: "private_group" } }
    }.not_to change(Group, :count)

    expect(response).to redirect_to(root_path)
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
end
