require "rails_helper"

RSpec.describe "Admin group approvals", type: :request do
  let!(:owner) { User.create!(name: "Owner", email: "admin-group-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:group) { Group.create!(owner: owner, name: "Pending club", group_type: :public_group, application_purpose: "Create a reading circle") }
  let!(:admin) { User.create!(name: "Admin", email: "group-admin@example.com", password: "password123!", password_confirmation: "password123!", global_admin: true) }

  it "blocks a non-admin from the approval list and approve action" do
    sign_in owner

    get admin_groups_path
    expect(response).to redirect_to(root_path)

    patch approve_admin_group_path(group)
    expect(response).to redirect_to(root_path)
    expect(group.reload).to be_pending_approval
  end

  it "lets a global admin list and approve pending groups" do
    sign_in admin

    get admin_groups_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(group.name, owner.name, "개설 신청", "Create a reading circle", "운영 승인")
    expect(response.body).to include(I18n.t("admin.groups.request_updated_at", time: I18n.l(group.updated_at, format: :short)))

    patch approve_admin_group_path(group)
    expect(group.reload).to be_active
  end

  it "shows a reactivation request with previous closure details" do
    legacy_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Returning club", group_type: :public_group)
    closed_at = Time.current
    legacy_group.update!(lifecycle_status: :inactive, closure_reason: "The first season ended", closed_at: closed_at)
    legacy_group.update!(lifecycle_status: :pending_approval)
    sign_in admin

    get admin_groups_path

    expect(response.body).to include("재활성화 요청", "The first season ended", I18n.l(closed_at, format: :short))
    expect(response.body).to include("등록된 동아리 개설 목적이 없습니다.")
  end

  it "does not approve a group that is not pending" do
    group.active!
    sign_in admin

    patch approve_admin_group_path(group)

    expect(response).to redirect_to(root_path)
    expect(group.reload).to be_active
  end
end
