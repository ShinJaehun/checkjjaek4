require "rails_helper"

RSpec.describe "Admin user account actions", type: :request do
  let!(:admin) { User.create!(name: "Global Admin", email: "account-action-admin@example.com", password: "password123!", global_admin: true) }
  let!(:reader) { User.create!(name: "Reader", email: "account-action-reader@example.com", password: "password123!") }
  let!(:ordinary_user) { User.create!(name: "Ordinary", email: "account-action-ordinary@example.com", password: "password123!") }

  def create_suspension!(user, public_reason: "other", internal_note: nil)
    user.update!(suspended_at: Time.current)
    ModerationAction.create!(
      target: user,
      actor: admin,
      action_type: :suspend,
      public_reason:,
      internal_note:
    )
  end

  it "shows only the permitted action link on the user detail without an inline form" do
    sign_in admin

    get admin_user_path(reader)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("a[href='#{new_admin_user_account_suspension_path(reader)}']").text.strip).to eq("계정 정지")
    expect(page.at_css("a[href='#{new_admin_user_account_restoration_path(reader)}']")).to be_nil
    expect(page.at_css("select[name='moderation_action[public_reason]']")).to be_nil
    expect(page.at_css("textarea[name='moderation_action[internal_note]']")).to be_nil

    suspension = create_suspension!(reader, public_reason: "other", internal_note: "Original note")
    get admin_user_path(reader)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("a[href='#{new_admin_user_account_restoration_path(reader)}']").text.strip).to eq("계정 복구")
    expect(page.at_css("a[href='#{new_admin_user_account_suspension_path(reader)}']")).to be_nil
    expect(page.at_css("select[name='moderation_action[public_reason]']")).to be_nil
    expect(page.at_css("textarea[name='moderation_action[internal_note]']")).to be_nil
    expect(page.at_css("#admin_user_identity [data-field='suspended-at']").text).to include(
      I18n.l(reader.suspended_at, format: :short)
    )
    expect(page.at_css("#account_history [data-account-event='suspended']").text).to include(
      admin.name,
      User.suspension_reason_label(suspension.public_reason),
      "Original note"
    )
  end

  it "shows suspension context and creates the audited suspension with its notification" do
    sign_in admin
    new_path = new_admin_user_account_suspension_path(reader)
    create_path = admin_user_account_suspensions_path(reader)

    get new_path
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(reader.name, reader.email, "정상", "일반 사용자", "계정 정지")
    reason_select = page.at_css("form[action='#{create_path}'] select[name='moderation_action[public_reason]']")
    expect(reason_select.css("option").map { |option| option["value"] }).to include(*User::SUSPENSION_REASONS)
    expect(page.at_css("textarea[name='moderation_action[internal_note]']")).to be_present
    expect(page.at_css("a[href='#{admin_user_path(reader)}']")).to be_present

    scheduled = []
    allow(Notifications::ModerationNotifier).to receive(:schedule) do |moderation_action:, recipient_ids:|
      scheduled << [ moderation_action, recipient_ids ]
    end

    expect {
      post create_path, params: {
        moderation_action: { public_reason: "repeated_policy_violations", internal_note: "Case 1" }
      }
    }.to change(ModerationAction, :count).by(1)

    suspension = ModerationAction.last
    expect(reader.reload).to be_suspended
    expect(suspension).to have_attributes(
      target: reader,
      actor: admin,
      action_type: "suspend",
      public_reason: "repeated_policy_violations",
      internal_note: "Case 1"
    )
    expect(scheduled).to eq([ [ suspension, [ reader.id ] ] ])
    expect(response).to redirect_to(admin_user_path(reader))
  end

  it "shows the current suspension and creates a linked restoration with its notification" do
    suspension = create_suspension!(
      reader,
      public_reason: "repeated_policy_violations",
      internal_note: "Original note"
    )
    sign_in admin
    new_path = new_admin_user_account_restoration_path(reader)
    create_path = admin_user_account_restorations_path(reader)

    get new_path
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(reader.name, reader.email, "운영 정지", "현재 정지 정보", "계정 복구")
    current_suspension = page.at_css("[data-account-moderation-action='suspend']")
    expect(current_suspension.text).to include(
      admin.name,
      I18n.l(suspension.created_at, format: :short),
      User.suspension_reason_label(suspension.public_reason),
      "Original note"
    )
    expect(page.at_css("form[action='#{create_path}'] textarea[name='moderation_action[public_reason]']")).to be_present
    expect(page.at_css("a[href='#{admin_user_path(reader)}']")).to be_present

    scheduled = []
    allow(Notifications::ModerationNotifier).to receive(:schedule) do |moderation_action:, recipient_ids:|
      scheduled << [ moderation_action, recipient_ids ]
    end

    expect {
      post create_path, params: {
        moderation_action: { public_reason: "Review complete", internal_note: "Verified" }
      }
    }.to change(ModerationAction, :count).by(1)

    restoration = ModerationAction.last
    expect(reader.reload).not_to be_suspended
    expect(restoration).to have_attributes(
      target: reader,
      actor: admin,
      action_type: "restore",
      public_reason: "Review complete",
      internal_note: "Verified",
      reversal_of: suspension
    )
    expect(scheduled).to eq([ [ restoration, [ reader.id ] ] ])
    expect(response).to redirect_to(admin_user_path(reader))

    get admin_user_path(reader)
    history = Nokogiri::HTML(response.body).at_css("#account_history")
    expect(history.text).to include(
      "계정 정지",
      User.suspension_reason_label(suspension.public_reason),
      "Original note",
      "계정 복구",
      "Review complete",
      "Verified",
      admin.name
    )
    expect(history.css("[data-account-event]").map { |entry| entry["data-account-event"] }).to eq(
      %w[joined suspended restored]
    )
  end

  it "renders each action page with entered values when its service fails" do
    sign_in admin
    suspension_service = instance_double(Users::SuspendAccount)
    allow(Users::SuspendAccount).to receive(:new).and_return(suspension_service)
    allow(suspension_service).to receive(:call!).and_raise(Users::SuspendAccount::InvalidState)

    post admin_user_account_suspensions_path(reader), params: {
      moderation_action: { public_reason: "other", internal_note: "Keep suspension note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(reader.name, reader.email, "정상")
    expect(page.at_css("select[name='moderation_action[public_reason]'] option[selected][value='other']")).to be_present
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep suspension note")
    expect(reader.reload).not_to be_suspended

    suspension = create_suspension!(reader, public_reason: "other", internal_note: "Original note")

    post admin_user_account_restorations_path(reader), params: {
      moderation_action: { public_reason: "", internal_note: "Validation note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    validation_page = Nokogiri::HTML(response.body)
    expect(validation_page.text).to include(
      reader.name,
      "운영 정지",
      User.suspension_reason_label(suspension.public_reason),
      "Original note"
    )
    expect(validation_page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Validation note")
    expect(reader.reload).to be_suspended
    expect(ModerationAction.where(reversal_of: suspension)).to be_empty

    restoration_service = instance_double(Users::RestoreAccount)
    allow(Users::RestoreAccount).to receive(:new).and_return(restoration_service)
    allow(restoration_service).to receive(:call!).and_raise(Users::RestoreAccount::InvalidState)

    post admin_user_account_restorations_path(reader), params: {
      moderation_action: { public_reason: "Retry after review", internal_note: "Keep restoration note" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(
      reader.name,
      "운영 정지",
      User.suspension_reason_label(suspension.public_reason),
      "Original note"
    )
    expect(page.at_css("textarea[name='moderation_action[public_reason]']").text.strip).to eq("Retry after review")
    expect(page.at_css("textarea[name='moderation_action[internal_note]']").text.strip).to eq("Keep restoration note")
    expect(reader.reload).to be_suspended
  end

  it "rejects undefined suspension reasons with 422 without changing state" do
    sign_in admin

    expect {
      post admin_user_account_suspensions_path(reader), params: {
        moderation_action: { public_reason: "undefined_reason", internal_note: "Direct request" }
      }
    }.not_to change(ModerationAction, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("정상")
    expect(reader.reload).not_to be_suspended
  end

  it "denies both pages and mutations to a non-global-admin" do
    suspension = create_suspension!(admin)
    sign_in ordinary_user

    get new_admin_user_account_suspension_path(reader)
    expect(response).to redirect_to(root_path)
    post admin_user_account_suspensions_path(reader), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    expect(reader.reload).not_to be_suspended

    get new_admin_user_account_restoration_path(admin)
    expect(response).to redirect_to(root_path)
    post admin_user_account_restorations_path(admin), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)
    expect(admin.reload).to be_suspended
    expect(ModerationAction.where(reversal_of: suspension)).to be_empty
  end

  it "denies self-suspension on both the page and mutation and hides its detail action" do
    sign_in admin

    get admin_user_path(admin)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("a[href='#{new_admin_user_account_suspension_path(admin)}']")).to be_nil

    get new_admin_user_account_suspension_path(admin)
    expect(response).to redirect_to(root_path)
    post admin_user_account_suspensions_path(admin), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    expect(admin.reload).not_to be_suspended
  end

  it "uses the policies to reject suspended, active, and withdrawn targets in the wrong actions" do
    withdrawn = User.create!(
      name: "Withdrawn",
      email: "account-action-withdrawn@example.com",
      password: "password123!",
      withdrawn_at: Time.current
    )
    sign_in admin

    get new_admin_user_account_restoration_path(reader)
    expect(response).to redirect_to(root_path)
    post admin_user_account_restorations_path(reader), params: { moderation_action: { public_reason: "Not suspended" } }
    expect(response).to redirect_to(root_path)

    create_suspension!(reader)
    get new_admin_user_account_suspension_path(reader)
    expect(response).to redirect_to(root_path)
    post admin_user_account_suspensions_path(reader), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)

    get new_admin_user_account_suspension_path(withdrawn)
    expect(response).to redirect_to(root_path)
    post admin_user_account_suspensions_path(withdrawn), params: { moderation_action: { public_reason: "other" } }
    expect(response).to redirect_to(root_path)
    get new_admin_user_account_restoration_path(withdrawn)
    expect(response).to redirect_to(root_path)
    post admin_user_account_restorations_path(withdrawn), params: { moderation_action: { public_reason: "Blocked" } }
    expect(response).to redirect_to(root_path)

    get admin_user_path(withdrawn)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("a[href='#{new_admin_user_account_suspension_path(withdrawn)}']")).to be_nil
    expect(page.at_css("a[href='#{new_admin_user_account_restoration_path(withdrawn)}']")).to be_nil
  end

  it "keeps legacy suspension reasons verbatim and restoration reasons as free text" do
    create_suspension!(reader, public_reason: "LEGACY_FREE_TEXT_REASON")
    sign_in admin

    get new_admin_user_account_restoration_path(reader)
    expect(response.body).to include("LEGACY_FREE_TEXT_REASON")

    post admin_user_account_restorations_path(reader), params: {
      moderation_action: { public_reason: "other" }
    }
    expect(reader.reload).not_to be_suspended

    get admin_user_path(reader)
    restored_entry = Nokogiri::HTML(response.body).at_css("#account_history [data-account-event='restored']")
    expect(restored_entry.text).to include("other")
    expect(restored_entry.text).not_to include(I18n.t("users.suspension_reasons.other"))
  end

  it "does not recognize the removed legacy PATCH routes" do
    expect {
      Rails.application.routes.recognize_path(
        "/admin/users/#{reader.id}/suspend",
        method: :patch
      )
    }.to raise_error(ActionController::RoutingError)

    expect {
      Rails.application.routes.recognize_path(
        "/admin/users/#{reader.id}/restore",
        method: :patch
      )
    }.to raise_error(ActionController::RoutingError)
  end
end
