require "rails_helper"

RSpec.describe "Group content inventory", type: :request do
  let(:group_admin) { User.create!(name: "Group admin", email: "content-inventory-admin@example.com", password: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Reading club", group_type: :private_group) }

  it "requires authentication" do
    get content_group_path(group)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "renders the inventory entry page for the current admin of an active group" do
    sign_in group_admin

    get content_group_path(group)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("groups.content_inventory.title"))
  end

  it "lets the current admin inspect an inactive group" do
    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    sign_in group_admin

    get content_group_path(group)

    expect(response).to have_http_status(:ok)
  end

  it "lets the current admin inspect an operation-suspended group" do
    group.update!(operation_suspended_at: Time.current)
    sign_in group_admin

    get content_group_path(group)

    expect(response).to have_http_status(:ok)
  end

  it "rejects the admin of a pending group" do
    pending = Group.create!(group_admin: group_admin, name: "Pending club", group_type: :private_group, application_purpose: "Read together")
    sign_in group_admin

    get content_group_path(pending)

    expect(response).to redirect_to(root_path)
  end

  it "rejects an ordinary member" do
    member = User.create!(name: "Member", email: "content-inventory-member@example.com", password: "password123!")
    group.group_memberships.create!(user: member, status: :active)
    sign_in member

    get content_group_path(group)

    expect(response).to redirect_to(root_path)
  end

  it "rejects the admin of another group" do
    other_admin = User.create!(name: "Other admin", email: "content-inventory-other-admin@example.com", password: "password123!")
    Group.create!(lifecycle_status: :active, group_admin: other_admin, name: "Other club", group_type: :public_group)
    sign_in other_admin

    get content_group_path(group)

    expect(response).to redirect_to(root_path)
  end

  it "rejects a global admin who does not administer the group" do
    global_admin = User.create!(name: "Global admin", email: "content-inventory-global-only@example.com", password: "password123!", global_admin: true)
    sign_in global_admin

    get content_group_path(group)

    expect(response).to redirect_to(root_path)
  end

  it "allows a global admin who is also the group's current admin" do
    global_admin = User.create!(name: "Global owner", email: "content-inventory-global-owner@example.com", password: "password123!", global_admin: true)
    owned_group = Group.create!(lifecycle_status: :active, group_admin: global_admin, name: "Owned club", group_type: :private_group)
    sign_in global_admin

    get content_group_path(owned_group)

    expect(response).to have_http_status(:ok)
  end

  it "moves inventory access to the new admin after transfer" do
    new_admin = User.create!(name: "New admin", email: "content-inventory-new-admin@example.com", password: "password123!")
    group.group_memberships.create!(user: new_admin, status: :active)
    sign_in group_admin

    get content_group_path(group)
    expect(response).to have_http_status(:ok)

    post group_admin_transfers_path(group), params: { new_admin_id: new_admin.id }
    expect(group.reload.group_admin).to eq(new_admin)

    get content_group_path(group)
    expect(response).to redirect_to(root_path)

    sign_in new_admin
    get content_group_path(group)
    expect(response).to have_http_status(:ok)
  end
end
