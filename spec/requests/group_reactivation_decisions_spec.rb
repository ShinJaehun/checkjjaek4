require "rails_helper"

RSpec.describe "Group reactivation decisions", type: :request do
  let!(:owner) { User.create!(name: "Owner", email: "reactivation-owner@example.com", password: "password123!") }
  let!(:admin) { User.create!(name: "Reviewer", email: "reactivation-admin@example.com", password: "password123!", global_admin: true) }
  let!(:member) { User.create!(name: "Member", email: "reactivation-member@example.com", password: "password123!") }
  let!(:outsider) { User.create!(name: "Outsider", email: "reactivation-outsider@example.com", password: "password123!") }
  let(:group) do
    record = Group.create!(group_admin: owner, name: "Returning readers", lifecycle_status: :active)
    record.group_memberships.create!(user: member, status: :active)
    jjaek = owner.jjaeks.create!(group: record, content: "Preserved reading discussion")
    jjaek.comments.create!(user: member, content: "Preserved reply")
    record.lifecycle_events.create!(actor: admin, event_type: :opening_approved)
    record.update!(lifecycle_status: :inactive, closed_at: Time.current, closure_reason: "Previous closure")
    record.lifecycle_events.create!(actor: owner, event_type: :operations_closed, detail: record.closure_reason)
    record.update!(lifecycle_status: :pending_approval)
    record.lifecycle_events.create!(actor: owner, event_type: :reactivation_requested)
    record
  end

  def submit_decision(decision, reason: "Private rejection reason", as: :html)
    case decision
    when :approve
      post admin_group_approvals_path(group), as:
    when :reject
      post reject_admin_group_approvals_path(group), params: { group_lifecycle_event: { detail: reason } }, as:
    when :withdraw
      post withdraw_group_reactivation_requests_path(group), as:
    end
  end

  it "approves a pending reactivation with the existing approval event and active-member recipients" do
    group
    sign_in admin
    expect(Notifications::GroupLifecycleNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(group.lifecycle_events.reactivation_approved.sole)
      expect(event.actor).to eq(admin)
      expect(recipient_ids).to contain_exactly(owner.id, member.id)
    end

    submit_decision(:approve)

    expect(response).to redirect_to(admin_group_path(group))
    expect(group.reload).to be_active
    expect(group.lifecycle_events.reactivation_rejected).to be_empty
    expect(group.lifecycle_events.reactivation_withdrawn).to be_empty
  end

  it "uses the existing rejection form and notifies only the applicant after commit with the event reason" do
    group
    callbacks = []
    allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&callback| callbacks << callback }
    sign_in admin
    get new_admin_group_approval_path(group, return_to: "inventory", q: "Returning", status: "reactivation_pending")
    form = Nokogiri::HTML(response.body).at_css("form[action*='/approvals/reject']")
    expect(form["action"]).to include("return_to=inventory", "q=Returning")
    reason_field = form.at_css("textarea[name='group_lifecycle_event[detail]']")
    expect(reason_field["required"]).to be_present
    expect(reason_field["maxlength"]).to eq("500")

    submit_decision(:reject)

    expect(response).to redirect_to(admin_group_path(group))
    rejection = group.lifecycle_events.reactivation_rejected.sole
    expect(rejection).to have_attributes(actor: admin, detail: "Private rejection reason")
    expect(rejection.created_at).to be_within(5.seconds).of(Time.current)
    expect(Notification.where(notifiable: rejection)).to be_empty
    callbacks.each(&:call)
    expect(Notification.where(notifiable: rejection).pluck(:recipient_id)).to eq([ owner.id ])
    notification = Notification.find_by!(notifiable: rejection)
    expect(notification).to have_attributes(actor: admin, action: "group_reactivation_rejected")
    expect(notification).to be_group_lifecycle
    expect(notification.show_actor_avatar?).to be(false)

    sign_in owner
    get notifications_path
    expect(response.body).to include(I18n.t("notifications.messages.group_reactivation_rejected", group_name: group.name, reason: rejection.detail))
    expect(Nokogiri::HTML(response.body).at_css("a[href='#{group_path(group)}']")).to be_present
    get edit_group_path(group)
    expect(response.body).to include("Private rejection reason")
    sign_in admin
    get admin_group_path(group)
    expect(response.body).to include("Private rejection reason")
  end

  [ nil, "", "   ", "a" * 501 ].each do |reason|
    it "rejects an invalid #{reason.inspect.truncate(20)} reason without changing state or audit" do
      group
      sign_in admin
      event_count = group.lifecycle_events.count
      expect(Notifications::GroupLifecycleNotifier).not_to receive(:schedule)

      submit_decision(:reject, reason:)

      expect(response).to have_http_status(:unprocessable_content)
      expect(group.reload).to be_pending_reactivation_request
      expect(group.lifecycle_events.count).to eq(event_count)
      form = Nokogiri::HTML(response.body).at_css("form[action*='/approvals/reject']")
      expect(form.at_css("textarea").text.delete_prefix("\n")).to eq(reason.to_s)
      expect(form.at_css("input[type='submit']")["value"]).to eq(I18n.t("admin.groups.actions.reject_reactivation"))
    end
  end

  it "accepts a 500-character reason through Turbo with the same state and event" do
    group
    sign_in admin
    submit_decision(:reject, reason: "가" * 500, as: :turbo_stream)
    expect(response).to redirect_to(admin_group_path(group))
    expect(group.reload).to be_inactive
    expect(group.lifecycle_events.reactivation_rejected.sole.detail).to eq("가" * 500)
  end

  it "renders the rejection form on a Turbo validation failure without changing the pending request" do
    group
    sign_in admin
    expect(Notifications::GroupLifecycleNotifier).not_to receive(:schedule)
    submit_decision(:reject, reason: "", as: :turbo_stream)
    expect(response).to have_http_status(:unprocessable_content)
    expect(Nokogiri::HTML(response.body).at_css("form[action*='/approvals/reject']")).to be_present
    expect(group.reload).to be_pending_reactivation_request
    expect(group.lifecycle_events.reactivation_rejected).to be_empty
  end

  it "confirms withdrawal without a reason and notifies only eligible system admins after commit" do
    group
    User.create!(name: "Suspended", email: "reactivation-suspended@example.com", password: "password123!", global_admin: true, suspended_at: Time.current)
    User.create!(name: "Withdrawn", email: "reactivation-withdrawn@example.com", password: "password123!", global_admin: true, withdrawn_at: Time.current)
    callbacks = []
    allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&callback| callbacks << callback }
    sign_in owner
    get edit_group_path(group)
    form = Nokogiri::HTML(response.body).at_css("form[action='#{withdraw_group_reactivation_requests_path(group)}']")
    expect(form["data-turbo-confirm"]).to eq(I18n.t("groups.reactivation_request.withdraw_confirmation"))
    expect(form.at_css("textarea")).to be_nil

    submit_decision(:withdraw, as: :turbo_stream)

    expect(response).to redirect_to(edit_group_path(group))
    expect(group.reload).to be_inactive
    event = group.lifecycle_events.reactivation_withdrawn.sole
    expect(event).to have_attributes(actor: owner, detail: nil)
    expect(event.created_at).to be_within(5.seconds).of(Time.current)
    expect(Notification.where(notifiable: event)).to be_empty
    callbacks.each(&:call)
    expect(Notification.where(notifiable: event).pluck(:recipient_id)).to eq([ admin.id ])
    expect(Notification.find_by!(notifiable: event)).to have_attributes(actor: owner, action: "group_reactivation_withdrawn")

    sign_in admin
    get notifications_path
    expect(response.body).to include(I18n.t("notifications.messages.group_reactivation_withdrawn", group_name: group.name))
    expect(Nokogiri::HTML(response.body).at_css("a[href='#{admin_group_path(group)}']")).to be_present
    admin.update!(global_admin: false)
    get notifications_path
    expect(Nokogiri::HTML(response.body).at_css("a[href='#{admin_group_path(group)}']")).to be_nil
    expect(Nokogiri::HTML(response.body).at_css("a[href='#{groups_path}']")).to be_present
  end

  %i[reject withdraw].each do |decision|
    it "preserves closure metadata, members, content, and history after #{decision} and permits another request" do
      group
      closure = group.attributes.slice("closed_at", "closure_reason")
      memberships = group.group_memberships.order(:id).map(&:attributes)
      content = group.jjaeks.sole
      content_attributes = content.attributes
      comment_attributes = content.comments.sole.attributes
      history = group.lifecycle_events.map(&:attributes)
      sign_in(decision == :reject ? admin : owner)

      submit_decision(decision)

      expect(group.reload).to be_inactive
      expect(group.attributes.slice("closed_at", "closure_reason")).to eq(closure)
      expect(group.group_memberships.order(:id).map(&:attributes)).to eq(memberships)
      expect(content.reload.attributes).to eq(content_attributes)
      expect(content.comments.sole.attributes).to eq(comment_attributes)
      expect(group.lifecycle_events.first(history.size).map(&:attributes)).to eq(history)
      expect(group.lifecycle_events.opening_rejected).to be_empty
      expect(group.lifecycle_events.opening_cancelled).to be_empty

      sign_in member
      get group_path(group)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(content.content)
      expect(response.body).not_to include("Private rejection reason", "group_operation_history")
      get edit_group_path(group)
      expect(response).to redirect_to(root_path)
      sign_in outsider
      get group_path(group)
      expect(response).to redirect_to(groups_path)
      expect(GroupPolicy::Scope.new(outsider, Group).resolve).not_to include(group)

      sign_in owner
      get new_group_reactivation_request_path(group)
      expect(response).to have_http_status(:ok)
      post group_reactivation_requests_path(group)
      expect(response).to redirect_to(group_path(group))
      expect(group.reload).to be_pending_reactivation_request
      expect(group.attributes.slice("closed_at", "closure_reason")).to eq(closure)
      expect(group.lifecycle_events.reactivation_requested.count).to eq(2)
      count = group.lifecycle_events.count
      post group_reactivation_requests_path(group)
      expect(response).to redirect_to(root_path)
      expect(group.lifecycle_events.count).to eq(count)
    end

    it "rolls back #{decision} when the audit event fails" do
      group
      sign_in(decision == :reject ? admin : owner)
      event_count = group.lifecycle_events.count
      allow_any_instance_of(GroupLifecycleEvent).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(GroupLifecycleEvent.new))
      expect(Notifications::GroupLifecycleNotifier).not_to receive(:schedule)

      submit_decision(decision)

      if decision == :reject
        expect(response).to have_http_status(:unprocessable_content)
      else
        expect(response).to redirect_to(edit_group_path(group))
        expect(flash[:alert]).to eq(I18n.t("groups.alerts.reactivation_withdrawal_failed"))
      end
      expect(group.reload).to be_pending_reactivation_request
      expect(group.lifecycle_events.count).to eq(event_count)
    end
  end

  %i[approve reject withdraw].each do |completed_decision|
    it "blocks approval, rejection, and withdrawal after #{completed_decision}" do
      group
      sign_in(completed_decision == :withdraw ? owner : admin)
      submit_decision(completed_decision)
      status = group.reload.lifecycle_status
      count = group.lifecycle_events.count
      expect(Notifications::GroupLifecycleNotifier).not_to receive(:schedule)

      sign_in admin
      submit_decision(:approve)
      expect(response).to redirect_to(root_path)
      submit_decision(:reject)
      expect(response).to redirect_to(root_path)
      sign_in owner
      submit_decision(:withdraw)
      expect(response).to redirect_to(root_path)
      expect(group.reload.lifecycle_status).to eq(status)
      expect(group.lifecycle_events.count).to eq(count)
    end

    it "rechecks the #{completed_decision} state after acquiring the row lock" do
      group
      sign_in(completed_decision == :withdraw ? owner : admin)
      winning_status = completed_decision == :approve ? :inactive : :active
      if completed_decision == :withdraw
        allow_any_instance_of(GroupPolicy).to receive(:withdraw_reactivation?).and_wrap_original do |method|
          allowed = method.call
          Group.find(group.id).update!(lifecycle_status: winning_status) if allowed
          allowed
        end
      else
        allow_any_instance_of(Group).to receive(:with_lock).and_wrap_original do |method, &block|
          Group.find(group.id).update!(lifecycle_status: winning_status)
          method.call(&block)
        end
      end
      expect(Notifications::GroupLifecycleNotifier).not_to receive(:schedule)

      submit_decision(completed_decision)

      expect(response).to redirect_to(root_path)
      expect(group.reload.lifecycle_status).to eq(winning_status.to_s)
      expect(group.lifecycle_events.count).to eq(3)
    end
  end

  it "rechecks the current group admin under the withdrawal lock" do
    group
    sign_in owner
    allow_any_instance_of(User).to receive(:with_lock).and_wrap_original do |method, &block|
      Group.find(group.id).update!(group_admin: member)
      method.call(&block)
    end
    expect(Notifications::GroupLifecycleNotifier).not_to receive(:schedule)

    submit_decision(:withdraw)

    expect(response).to redirect_to(root_path)
    expect(group.reload).to be_pending_reactivation_request
    expect(group.lifecycle_events.reactivation_withdrawn).to be_empty
  end

  it "denies members, outsiders, guests, and a system admin attempting to withdraw for the owner" do
    group
    [ owner, member, outsider ].each do |actor|
      sign_in actor
      submit_decision(:reject)
      expect(response).to redirect_to(root_path)
    end
    sign_in member
    submit_decision(:withdraw)
    expect(response).to have_http_status(:not_found)

    sign_in admin
    submit_decision(:withdraw)
    expect(response).to redirect_to(root_path)
    sign_in outsider
    submit_decision(:withdraw)
    expect(response).to have_http_status(:not_found)
    sign_out outsider
    %i[reject withdraw].each do |decision|
      submit_decision(decision)
      expect(response).to redirect_to(new_user_session_path)
    end
    expect(group.reload).to be_pending_reactivation_request
    expect(group.lifecycle_events.count).to eq(3)
  end

  it "does not let the reactivation withdrawal endpoint cancel an initial opening application" do
    initial = Group.create!(group_admin: owner, name: "New opening", application_purpose: "Read")
    sign_in owner
    post withdraw_group_reactivation_requests_path(initial)
    expect(response).to redirect_to(root_path)
    expect(initial.reload).to be_pending_opening_application
    expect(initial.lifecycle_events).to be_empty
  end
end
