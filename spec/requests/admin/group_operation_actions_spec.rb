require "rails_helper"

RSpec.describe "Admin group operation actions", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "operation-action-owner@example.com", password: "password123!") }
  let!(:admin) { User.create!(name: "Platform admin", email: "operation-action-admin@example.com", password: "password123!", global_admin: true) }
  let!(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Readers", group_type: :public_group) }

  it "denies suspension and restoration pages and mutations to a non-global-admin" do
    Groups::SuspendOperation.new(group, actor: admin, public_reason: "other").call!
    sign_in group_admin

    get new_admin_group_operation_restoration_path(group)
    expect(response).to redirect_to(root_path)
    post admin_group_operation_restorations_path(group), params: { moderation_action: { public_reason: "Resolved" } }
    expect(response).to redirect_to(root_path)
    expect(group.reload).to be_operation_suspended

    Groups::RestoreOperation.new(group, actor: admin, public_reason: "Resolved").call!
    get new_admin_group_operation_suspension_path(group)
    expect(response).to redirect_to(root_path)
    post admin_group_operation_suspensions_path(group), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    expect(group.reload).to be_operation_active
    expect(ModerationAction.where(target: group, action_type: :suspend_group_operation).count).to eq(1)
  end

  it "uses the existing policy to reject actions in the wrong operation state" do
    sign_in admin

    get new_admin_group_operation_restoration_path(group)
    expect(response).to redirect_to(root_path)
    post admin_group_operation_restorations_path(group), params: { moderation_action: { public_reason: "Resolved" } }
    expect(response).to redirect_to(root_path)

    Groups::SuspendOperation.new(group, actor: admin, public_reason: "other").call!
    get new_admin_group_operation_suspension_path(group)
    expect(response).to redirect_to(root_path)
    post admin_group_operation_suspensions_path(group), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
  end

  it "shows suspension context and keeps entered values when the service fails" do
    sign_in admin
    return_params = { q: "Readers", group_type: "public_group", status: "active", operation_status: "normal", sort: "name", page: "2" }
    new_path = new_admin_group_operation_suspension_path(group, return_params)
    create_path = admin_group_operation_suspensions_path(group, return_params)
    detail_path = admin_group_path(group, return_params)

    get detail_path
    expect(Nokogiri::HTML(response.body).at_css("#group_operation_moderation a[href='#{new_path}']")).to be_present

    get new_path
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(group.name, group_admin.name, "정상 운영", "운영 정지")
    expect(page.at_css("form[action='#{create_path}'] select[name='moderation_action[public_reason]']")).to be_present
    expect(page.at_css("a[href='#{detail_path}']")).to be_present

    failing_service = instance_double(Groups::SuspendOperation)
    allow(Groups::SuspendOperation).to receive(:new).and_return(failing_service)
    allow(failing_service).to receive(:call!).and_raise(Groups::SuspendOperation::InvalidState)
    post create_path, params: { moderation_action: { public_reason: "other", internal_note: "Keep this note" } }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("select[name='moderation_action[public_reason]'] option[selected][value='other']")).to be_present
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep this note")
    expect(page.at_css("form[action='#{create_path}']")).to be_present
    expect(page.at_css("a[href='#{detail_path}']")).to be_present
    expect(group.reload).to be_operation_active
  end

  it "shows the current suspension on restoration and keeps context after failure" do
    Groups::SuspendOperation.new(group, actor: admin, public_reason: "other", internal_note: "Original note").call!
    sign_in admin
    return_params = { q: "Readers", status: "suspended", page: "3" }
    new_path = new_admin_group_operation_restoration_path(group, return_params)
    create_path = admin_group_operation_restorations_path(group, return_params)
    detail_path = admin_group_path(group, return_params)

    get new_path
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(group.name, group_admin.name, "운영 정지", "현재 정지 조치")
    suspension_entry = page.at_css("section h2 + [data-history-kind='platform'][data-history-entry='suspend_group_operation']")
    expect(suspension_entry).to be_present
    expect(suspension_entry.text).to include("운영 관리", admin.name, "기타 운영 정책 위반", "Original note")
    expect(suspension_entry.at_css("[data-history-detail='reason']")).to be_present
    expect(suspension_entry.at_css("[data-history-detail='memo']")).to be_present
    expect(page.at_css("form[action='#{create_path}'] textarea[name='moderation_action[public_reason]']")).to be_present
    expect(page.at_css("a[href='#{detail_path}']")).to be_present

    post create_path, params: { moderation_action: { public_reason: "", internal_note: "Validation note" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(ModerationAction.where(target: group, action_type: :restore_group_operation)).to be_empty
    validation_page = Nokogiri::HTML(response.body)
    expect(validation_page.text).to include(group.name, group_admin.name, "현재 정지 조치")
    expect(validation_page.at_css("section h2 + [data-history-kind='platform'][data-history-entry='suspend_group_operation']").text)
      .to include("기타 운영 정책 위반", "Original note")
    expect(validation_page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Validation note")
    expect(validation_page.at_css("a[href='#{detail_path}']")).to be_present

    failing_service = instance_double(Groups::RestoreOperation)
    allow(Groups::RestoreOperation).to receive(:new).and_return(failing_service)
    allow(failing_service).to receive(:call!).and_raise(Groups::RestoreOperation::InvalidState)
    post create_path, params: { moderation_action: { public_reason: "Retry after review", internal_note: "Keep this note" } }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(group.name, group_admin.name, "현재 정지 조치")
    suspension_entry = page.at_css("section h2 + [data-history-kind='platform'][data-history-entry='suspend_group_operation']")
    expect(suspension_entry).to be_present
    expect(suspension_entry.text).to include("운영 관리", admin.name, "기타 운영 정책 위반", "Original note")
    expect(suspension_entry.at_css("[data-history-detail='reason']")).to be_present
    expect(suspension_entry.at_css("[data-history-detail='memo']")).to be_present
    expect(page.at_css("textarea[name='moderation_action[public_reason]']").text.strip).to eq("Retry after review")
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep this note")
    expect(page.at_css("form[action='#{create_path}']")).to be_present
    expect(page.at_css("a[href='#{detail_path}']")).to be_present
    expect(group.reload).to be_operation_suspended
  end

  it "returns to the detail with inventory context after both audited actions" do
    sign_in admin
    return_params = { q: "Readers", group_type: "public_group", status: "active", operation_status: "normal", sort: "name", page: "2" }
    scheduled = []
    allow(Notifications::ModerationNotifier).to receive(:schedule) do |moderation_action:, recipient_ids:|
      scheduled << [ moderation_action, recipient_ids ]
    end

    post admin_group_operation_suspensions_path(group, return_params), params: {
      moderation_action: { public_reason: "other", internal_note: "First review" }
    }
    expect(response).to redirect_to(admin_group_path(group, return_params))
    suspension = group.current_operation_suspension_action
    expect(group.reload).to be_operation_suspended
    expect(suspension).to have_attributes(actor: admin, public_reason: "other", internal_note: "First review")
    expect(scheduled.first).to eq([ suspension, [ group_admin.id ] ])

    post admin_group_operation_restorations_path(group, return_params), params: {
      moderation_action: { public_reason: "Review complete", internal_note: "Verified" }
    }
    expect(response).to redirect_to(admin_group_path(group, return_params))
    restoration = ModerationAction.find_by!(reversal_of: suspension)
    expect(group.reload).to be_operation_active
    expect(restoration).to have_attributes(actor: admin, public_reason: "Review complete", internal_note: "Verified")
    expect(scheduled.last).to eq([ restoration, [ group_admin.id ] ])
  end
end
