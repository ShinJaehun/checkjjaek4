require "rails_helper"

RSpec.describe "Admin group approvals", type: :request do
  let!(:owner) { User.create!(name: "Owner", email: "admin-group-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:group) { Group.create!(owner: owner, name: "Pending club", group_type: :public_group, application_purpose: "Create a reading circle") }
  let!(:admin) { User.create!(name: "Admin", email: "group-admin@example.com", password: "password123!", password_confirmation: "password123!", global_admin: true) }
  let!(:opening_event) { group.lifecycle_events.create!(actor: owner, event_type: :opening_requested, detail: group.application_purpose) }

  it "blocks a non-admin from the approval list and approve action" do
    sign_in owner

    get admin_groups_path
    expect(response).to redirect_to(root_path)

    get admin_group_path(group)
    expect(response).to redirect_to(root_path)

    patch approve_admin_group_path(group)
    expect(response).to redirect_to(root_path)
    expect(group.reload).to be_pending_approval
  end

  it "lets a global admin list and approve pending groups" do
    sign_in admin

    get admin_groups_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(group.name, owner.name, "개설 신청", "운영 승인", "운영 정보 보기")
    expect(response.body).not_to include("운영 이력", "Create a reading circle")
    expect(response.body).not_to include("신청 정보 갱신")

    get admin_group_path(group)
    opening_card = Nokogiri::HTML(response.body).css("article").find { |node| node.text.include?("동아리 개설") }
    expect(response.body).to include("승인 대기", "운영 이력")
    expect(opening_card.text).to include("개설 목적", "Create a reading circle", "신청", I18n.l(opening_event.created_at, format: :short))
    expect(opening_card.text).not_to include("승인")

    patch approve_admin_group_path(group)
    expect(group.reload).to be_active
    approval = group.lifecycle_events.opening_approved.sole
    expect(approval.actor).to eq(admin)
    expect(approval.created_at).to be_present

    get admin_group_path(group)
    expect(response.body.scan("동아리 개설").size).to eq(1)
    opening_card = Nokogiri::HTML(response.body).css("article").find { |node| node.text.include?("동아리 개설") }
    expect(opening_card.text).to include("신청", "승인", I18n.l(approval.created_at, format: :short))
  end

  it "shows a reactivation request with previous closure details" do
    legacy_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Returning club", group_type: :public_group)
    closed_at = Time.current
    legacy_group.update!(lifecycle_status: :inactive, closure_reason: "The first season ended", closed_at: closed_at)
    legacy_group.update!(lifecycle_status: :pending_approval)
    legacy_group.lifecycle_events.create!(actor: owner, event_type: :operations_closed, detail: "The first season ended", created_at: closed_at)
    legacy_group.lifecycle_events.create!(actor: owner, event_type: :reactivation_requested)
    sign_in admin

    get admin_groups_path

    expect(response.body).to include("재활성화 요청", "운영 정보 보기", "운영 승인")
    expect(response.body).not_to include("운영 이력", "The first season ended")

    get admin_group_path(legacy_group)
    expect(response.body).to include("승인 대기", "동아리 운영 종료", "동아리 재운영", "The first season ended", I18n.l(closed_at, format: :short), "운영 이력")
    reactivation_card = Nokogiri::HTML(response.body).css("article").find { |node| node.text.include?("동아리 재운영") }
    expect(reactivation_card.text).to include("신청")
    expect(reactivation_card.text).not_to include("승인")

    patch approve_admin_group_path(legacy_group)
    expect(legacy_group.reload).to be_active
    reapproval = legacy_group.lifecycle_events.reactivation_approved.sole
    expect(reapproval.actor).to eq(admin)

    get admin_group_path(legacy_group)
    expect(response.body.scan("동아리 재운영").size).to eq(1)
    reactivation_card = Nokogiri::HTML(response.body).css("article").find { |node| node.text.include?("동아리 재운영") }
    expect(reactivation_card.text).to include("신청", "승인", I18n.l(reapproval.created_at, format: :short))
  end

  it "falls back to the current purpose on admin details for a legacy pending group without events" do
    legacy_group = Group.create!(owner: owner, name: "Legacy application", group_type: :public_group, application_purpose: "Legacy purpose")
    sign_in admin

    get admin_group_path(legacy_group)

    expect(response.body).to include("Legacy purpose", "기록된 운영 이력이 없습니다.")
  end

  it "shows an approval-only opening stage for a legacy pending group" do
    legacy_group = Group.create!(owner: owner, name: "Legacy approval", group_type: :public_group, application_purpose: "Legacy purpose")
    sign_in admin

    patch approve_admin_group_path(legacy_group)
    approval = legacy_group.lifecycle_events.opening_approved.sole
    get admin_group_path(legacy_group)

    expect(response.body).to include("동아리 개설", "신청", "기록 없음", "승인", I18n.l(approval.created_at, format: :short))
  end

  it "shows read-only operations details for every group" do
    active_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Active club", group_type: :private_group)
    sign_in admin

    get admin_groups_path
    expect(response.body).to include(active_group.name, "운영 정보 보기")

    get admin_group_path(group)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(group.name, group.application_purpose, "운영 이력")
    expect(response.body).not_to include("동아리 운영 종료", "재활성화 요청", "수정하기")
  end

  it "does not grant owner lifecycle actions through global admin status" do
    active_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Owner only", group_type: :public_group)
    inactive_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Closed owner only", group_type: :public_group)
    inactive_group.update!(lifecycle_status: :inactive, closure_reason: "Finished", closed_at: Time.current)
    sign_in admin

    get edit_group_path(active_group)
    expect(response).to redirect_to(root_path)
    patch group_path(active_group), params: { group: { name: "Admin edit" } }
    expect(response).to redirect_to(root_path)
    patch close_group_path(active_group), params: { group: { closure_reason: "Admin close" } }
    expect(response).to redirect_to(root_path)
    patch request_reactivation_group_path(inactive_group)
    expect(response).to have_http_status(:not_found)

    expect(active_group.reload.name).to eq("Owner only")
    expect(active_group).to be_active
    expect(inactive_group.reload).to be_inactive
  end

  it "preserves every close event across repeated operations cycles" do
    sign_in admin
    patch approve_admin_group_path(group)

    sign_in owner
    patch close_group_path(group), params: { group: { closure_reason: "First season ended" } }
    patch request_reactivation_group_path(group)

    sign_in admin
    patch approve_admin_group_path(group)

    sign_in owner
    patch close_group_path(group), params: { group: { closure_reason: "Second season ended" } }
    patch request_reactivation_group_path(group)

    sign_in admin
    patch approve_admin_group_path(group)

    expect(group.lifecycle_events.operations_closed.order(:created_at, :id).pluck(:detail)).to eq([ "First season ended", "Second season ended" ])
    expect(group.lifecycle_events.reactivation_requested.count).to eq(2)
    expect(group.lifecycle_events.reactivation_approved.count).to eq(2)

    get admin_group_path(group)
    opening_position = response.body.index("동아리 개설")
    first_close_position = response.body.index("First season ended")
    reactivation_position = response.body.index("동아리 재운영")
    second_close_position = response.body.index("Second season ended")
    expect([ opening_position, first_close_position, reactivation_position, second_close_position ]).to eq(
      [ opening_position, first_close_position, reactivation_position, second_close_position ].sort
    )
    expect(response.body.scan("동아리 재운영").size).to eq(2)
    expect(response.body).to include("운영 종료 사유", "First season ended", "Second season ended")
  end

  it "does not approve a group that is not pending" do
    group.active!
    sign_in admin

    patch approve_admin_group_path(group)

    expect(response).to redirect_to(root_path)
    expect(group.reload).to be_active
  end
end
