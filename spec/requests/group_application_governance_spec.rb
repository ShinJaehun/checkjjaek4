require "rails_helper"

RSpec.describe "Group opening application governance", type: :request do
  let!(:owner) { User.create!(name: "Applicant", email: "governance-owner@example.com", password: "password123!") }
  let!(:admin) { User.create!(name: "Reviewer", email: "governance-admin@example.com", password: "password123!", global_admin: true) }
  let!(:other) { User.create!(name: "Other reader", email: "governance-other@example.com", password: "password123!") }
  let(:application) do
    group = Group.create!(group_admin: owner, name: "Opening application", application_purpose: "Read and discuss books")
    group.lifecycle_events.create!(actor: owner, event_type: :opening_requested, detail: group.application_purpose)
    group
  end

  def submit_application(name = "New club")
    post groups_path, params: { group: { name:, group_type: "public_group", application_purpose: "Read together" } }
  end

  describe "one pending initial application" do
    it "creates the first application and explains the limit on both GET and POST" do
      sign_in owner
      submit_application
      first = Group.find_by!(name: "New club")
      expect(response).to redirect_to(group_path(first))
      expect(first).to be_pending_opening_application
      expect(first.lifecycle_events.opening_requested.sole.actor).to eq(owner)

      get new_group_path
      document = Nokogiri::HTML(response.body)
      expect(document.text).to include(I18n.t("groups.applications.limit_reached"))
      expect(document.at_css("a[href='#{group_path(first)}']")).to be_present
      expect(document.at_css("form[action='#{groups_path}']")).to be_nil

      counts = [ Group.count, GroupMembership.count, GroupLifecycleEvent.count, Notification.count ]
      submit_application("Second application")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("groups.applications.limit_reached"), group_path(first))
      expect([ Group.count, GroupMembership.count, GroupLifecycleEvent.count, Notification.count ]).to eq(counts)
    end

    %i[active inactive reactivation_pending rejected cancelled].each do |status|
      it "allows a new application after #{status}" do
        existing = application
        case status
        when :active, :inactive, :reactivation_pending
          existing.update!(lifecycle_status: :active)
          existing.update!(lifecycle_status: :inactive, closed_at: Time.current, closure_reason: "Finished") unless status == :active
          existing.update!(lifecycle_status: :pending_approval) if status == :reactivation_pending
        else
          existing.update!(lifecycle_status: status)
        end
        sign_in owner

        get new_group_path
        expect(Nokogiri::HTML(response.body).at_css("form[action='#{groups_path}']")).to be_present
        submit_application

        expect(response).to redirect_to(group_path(Group.find_by!(name: "New club")))
        expect(owner.administered_groups.pending_opening_applications.count).to eq(1)
        expect(existing.reload.lifecycle_status).to eq(status == :reactivation_pending ? "pending_approval" : status.to_s)
      end
    end

    it "exempts direct global admin creation even when that user has an earlier pending application" do
      application
      owner.update!(global_admin: true)
      sign_in owner
      2.times do |index|
        submit_application("Direct club #{index}")
        expect(response).to have_http_status(:redirect)
      end
      expect(owner.administered_groups.active.count).to eq(2)
      expect(owner.administered_groups.pending_opening_applications.count).to eq(1)
    end

    it "does not prevent joining another group while an opening application is pending" do
      application
      group = Group.create!(group_admin: other, name: "Public club", lifecycle_status: :active)
      sign_in owner
      post group_group_memberships_path(group)
      expect(response).to redirect_to(group_path(group))
      expect(group.group_memberships.find_by!(user: owner)).to be_active
    end
  end

  describe "rejection" do
    it "preserves filters, the rejection reason, the audit row, and the applicant notification" do
      group = application
      callbacks = []
      allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&callback| callbacks << callback }
      sign_in admin
      filters = { q: "Opening", group_type: "public_group", status: "pending_approval", sort: "oldest", page: 2 }
      navigation = filters.merge(return_to: "inventory")
      get new_admin_group_approval_path(group, navigation)
      form = Nokogiri::HTML(response.body).at_css("form[action*='/approvals/reject']")
      expect(form.at_css("textarea[name='group_lifecycle_event[detail]']")["maxlength"]).to eq("500")
      expect(form["action"]).to include("return_to=inventory", "q=Opening")

      post reject_admin_group_approvals_path(group, navigation), params: { group_lifecycle_event: { detail: "Please clarify the reading plan" } }

      expect(response).to redirect_to(admin_groups_path(filters))
      expect(group.reload).to be_rejected
      expect(group.closed_at).to be_nil
      rejection = group.lifecycle_events.opening_rejected.sole
      expect(rejection).to have_attributes(actor: admin, detail: "Please clarify the reading plan")
      expect(rejection.created_at).to be_within(5.seconds).of(Time.current)
      expect(group.lifecycle_events.opening_requested.sole.detail).to eq("Read and discuss books")
      expect(Notification.where(notifiable: rejection)).to be_empty
      callbacks.each(&:call)
      notification = Notification.find_by!(notifiable: rejection)
      expect(notification).to have_attributes(recipient: owner, actor: admin, action: "group_opening_rejected")

      sign_in owner
      get notifications_path
      expect(response.body).to include("Please clarify the reading plan", group_path(group))
      submit_application
      expect(response).to redirect_to(group_path(Group.find_by!(name: "New club")))
    end

    [ "", " " * 3, "a" * 501 ].each do |reason|
      it "rejects an invalid #{reason.length}-character reason without lifecycle or notification effects" do
        group = application
        sign_in admin
        expect(Notifications::GroupLifecycleNotifier).not_to receive(:schedule)
        counts = [ GroupLifecycleEvent.count, Notification.count ]

        post reject_admin_group_approvals_path(group), params: { group_lifecycle_event: { detail: reason } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(group.reload).to be_pending_opening_application
        expect([ GroupLifecycleEvent.count, Notification.count ]).to eq(counts)
        form = Nokogiri::HTML(response.body).at_css("form[action*='/approvals/reject']")
        expect(form.at_css("textarea").text.delete_prefix("\n")).to eq(reason)
      end
    end

    it "does not allow an ordinary user to reject an application" do
      group = application
      sign_in owner
      post reject_admin_group_approvals_path(group), params: { group_lifecycle_event: { detail: "No" } }
      expect(response).to redirect_to(root_path)
      expect(group.reload).to be_pending_opening_application
      expect(group.lifecycle_events.opening_rejected).to be_empty
    end

    it "does not offer or accept rejection of a reactivation request" do
      group = application
      group.update!(lifecycle_status: :active)
      group.update!(lifecycle_status: :inactive, closed_at: Time.current, closure_reason: "Finished")
      group.update!(lifecycle_status: :pending_approval)
      sign_in admin
      get new_admin_group_approval_path(group)
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("form[action*='/approvals/reject']")).to be_nil
      post reject_admin_group_approvals_path(group), params: { group_lifecycle_event: { detail: "No" } }
      expect(response).to redirect_to(root_path)
      expect(group.reload).to be_pending_approval
      expect(group.lifecycle_events.opening_rejected).to be_empty
      sign_in owner
      post group_application_cancellation_path(group)
      expect(response).to redirect_to(root_path)
      expect(group.reload).to be_pending_approval
      expect(group.lifecycle_events.opening_cancelled).to be_empty
    end
  end

  describe "cancellation and terminal access" do
    it "requires confirmation, records cancellation, notifies reviewers, and allows a new application" do
      group = application
      callbacks = []
      allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&callback| callbacks << callback }
      sign_in owner
      get group_path(group)
      form = Nokogiri::HTML(response.body).at_css("form[action='#{group_application_cancellation_path(group)}']")
      expect(form["data-turbo-confirm"]).to eq(I18n.t("groups.applications.cancel_confirmation"))

      post group_application_cancellation_path(group)

      expect(response).to redirect_to(group_path(group))
      expect(group.reload).to be_cancelled
      cancellation = group.lifecycle_events.opening_cancelled.sole
      expect(cancellation).to have_attributes(actor: owner, detail: nil)
      expect(cancellation.created_at).to be_within(5.seconds).of(Time.current)
      expect(group.lifecycle_events.opening_requested.count).to eq(1)
      expect(Notification.where(notifiable: cancellation)).to be_empty
      callbacks.each(&:call)
      expect(Notification.find_by!(notifiable: cancellation)).to have_attributes(recipient: admin, actor: owner, action: "group_opening_cancelled")
      submit_application
      expect(response).to redirect_to(group_path(Group.find_by!(name: "New club")))
    end

    it "does not let another applicant cancel the request" do
      group = application
      sign_in other
      post group_application_cancellation_path(group)
      expect(response).to have_http_status(:not_found)
      expect(group.reload).to be_pending_opening_application
      expect(group.lifecycle_events.opening_cancelled).to be_empty
    end

    it "does not let the global admin cancel another user's application" do
      group = application
      sign_in admin
      post group_application_cancellation_path(group)
      expect(response).to redirect_to(root_path)
      expect(group.reload).to be_pending_opening_application
    end

    %i[rejected cancelled].each do |decision|
      it "rolls back #{decision} when its audit event cannot be saved" do
        group = application
        count = group.lifecycle_events.count
        allow_any_instance_of(GroupLifecycleEvent).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(GroupLifecycleEvent.new))
        expect(Notifications::GroupLifecycleNotifier).not_to receive(:schedule)

        if decision == :rejected
          sign_in admin
          post reject_admin_group_approvals_path(group), params: { group_lifecycle_event: { detail: "Valid reason" } }
          expect(response).to have_http_status(:unprocessable_content)
        else
          sign_in owner
          post group_application_cancellation_path(group)
          expect(response).to redirect_to(group_path(group))
        end

        expect(group.reload).to be_pending_opening_application
        expect(group.lifecycle_events.count).to eq(count)
      end
    end

    it "rejects both decisions after approval" do
      group = application
      sign_in admin
      post admin_group_approvals_path(group)
      expect(group.reload).to be_active
      event_count = group.lifecycle_events.count
      post reject_admin_group_approvals_path(group), params: { group_lifecycle_event: { detail: "Too late" } }
      expect(response).to redirect_to(root_path)
      sign_in owner
      post group_application_cancellation_path(group)
      expect(response).to redirect_to(root_path)
      expect(group.reload).to be_active
      expect(group.lifecycle_events.count).to eq(event_count)
    end

    %i[rejected cancelled].each do |status|
      it "keeps #{status} results private and immutable and outside ordinary lists" do
        group = application
        if status == :rejected
          sign_in admin
          post reject_admin_group_approvals_path(group), params: { group_lifecycle_event: { detail: "Private decision" } }
        else
          sign_in owner
          post group_application_cancellation_path(group)
        end
        event_count = group.lifecycle_events.count
        sign_in owner
        get groups_path
        expect(response.body).not_to include(group.name)
        get new_group_path
        expect(Nokogiri::HTML(response.body).at_css("a[href='#{group_path(group)}']")).to be_present
        get group_path(group)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("groups.current_statuses.#{status}"), "group_operation_history")
        expect(response.body).to include("Private decision") if status == :rejected
        get edit_group_path(group)
        expect(response).to redirect_to(root_path)
        patch group_path(group), params: { group: { name: "Changed" } }
        expect(response).to redirect_to(root_path)
        post group_application_cancellation_path(group)
        expect(response).to redirect_to(root_path)
        post group_reactivation_requests_path(group)
        expect(response).to redirect_to(root_path)
        post group_group_memberships_path(group)
        expect(response).to redirect_to(root_path)
        expect(group.reload.name).to eq("Opening application")

        sign_in other
        get group_path(group)
        expect(response).to redirect_to(groups_path)
        expect(response.body).not_to include("Private decision")
        get new_group_path
        expect(response.body).not_to include(group.name)
        sign_in admin
        get admin_group_path(group)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Private decision") if status == :rejected
        get admin_groups_path(status:)
        expect(Nokogiri::HTML(response.body).at_css("#group_#{group.id}")).to be_present
        post admin_group_approvals_path(group)
        expect(response).to redirect_to(root_path)
        post reject_admin_group_approvals_path(group), params: { group_lifecycle_event: { detail: "Again" } }
        expect(response).to redirect_to(root_path)
        expect(group.reload.lifecycle_status).to eq(status.to_s)
        expect(group.lifecycle_events.count).to eq(event_count)
      end
    end

    %i[approve reject cancel].each do |decision|
      it "rechecks the database state under the #{decision} decision lock" do
        group = application
        sign_in(decision == :cancel ? owner : admin)
        winning_status = decision == :approve ? :cancelled : :active
        # Cancellation locks User before Group, so simulate the competing
        # decision before entering the outer User transaction.
        lock_model = decision == :cancel ? User : Group
        allow_any_instance_of(lock_model).to receive(:with_lock).and_wrap_original do |method, &block|
          # Another decision commits after the initial policy check, before this request acquires the lock.
          Group.find(group.id).update!(lifecycle_status: winning_status)
          method.call(&block)
        end
        expect(Notifications::GroupLifecycleNotifier).not_to receive(:schedule)

        case decision
        when :approve
          post admin_group_approvals_path(group)
        when :reject
          post reject_admin_group_approvals_path(group), params: { group_lifecycle_event: { detail: "Too late" } }
        when :cancel
          post group_application_cancellation_path(group)
        end

        expect(response).to redirect_to(root_path)
        expect(group.reload.lifecycle_status).to eq(winning_status.to_s)
        expect(group.lifecycle_events.pluck(:event_type)).to eq([ "opening_requested" ])
      end
    end
  end
end
