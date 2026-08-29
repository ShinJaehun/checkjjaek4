require "rails_helper"

RSpec.describe "Groups", type: :request do
  let!(:user) { User.create!(name: "Reader", email: "groups-reader@example.com", password: "password123!", password_confirmation: "password123!") }

  it "requires sign in" do
    get groups_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "lets a signed-in user create a public group with an group_admin membership" do
    sign_in user

    expect {
      post groups_path, params: { group: { name: "Readers", description: "Read together", group_type: "public_group", application_purpose: "Build a reading community" } }
    }.to change(Group, :count).by(1).and change(GroupMembership, :count).by(1)

    group = Group.last
    expect(group.group_admin).to eq(user)
    expect(group).to be_pending_approval
    expect(group.application_purpose).to eq("Build a reading community")
    expect(group.group_memberships.find_by(user: user)).to be_active
    event = group.lifecycle_events.sole
    expect(event).to be_opening_requested
    expect(event.actor).to eq(user)
    expect(event.detail).to eq("Build a reading community")
    expect(response).to redirect_to(group_path(group))
  end

  it "renders 422 when an application purpose is missing" do
    sign_in user

    post groups_path, params: { group: { name: "Readers", group_type: "public_group", application_purpose: "" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(Group.find_by(name: "Readers")).to be_nil
  end

  it "rolls back the group and group_admin membership when opening event creation fails" do
    sign_in user
    allow(GroupLifecycleEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(GroupLifecycleEvent.new))
    group_count = Group.count
    membership_count = GroupMembership.count
    event_count = GroupLifecycleEvent.count
    post groups_path, params: {
      group: {
        name: "Atomic application",
        group_type: "public_group",
        application_purpose: "Test transactions"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(Group.count).to eq(group_count)
    expect(GroupMembership.count).to eq(membership_count)
    expect(GroupLifecycleEvent.count).to eq(event_count)
  end

  it "shows a pending group to its group_admin but not to another user" do
    group = Group.create!(group_admin: user, name: "Pending application", group_type: :public_group, application_purpose: "Read more together")
    other_user = User.create!(name: "Other", email: "pending-group-other@example.com", password: "password123!", password_confirmation: "password123!")

    sign_in user
    get groups_path
    expect(response.body).to include(group.name, "승인 대기")

    sign_in other_user
    get groups_path
    expect(response.body).not_to include(group.name)
    get group_path(group)
    expect(response).to have_http_status(:not_found)
  end

  it "allows private group creation with an group_admin membership" do
    sign_in user

    expect {
      post groups_path, params: { group: { name: "Private", group_type: "private_group", application_purpose: "Private reading circle" } }
    }.to change(Group, :count).by(1).and change(GroupMembership, :count).by(1)

    expect(Group.last.group_memberships.find_by(user: user)).to be_active
    expect(response).to redirect_to(group_path(Group.last))
  end


  it "shows only the current user's invitations outside the discoverable list" do
    group_admin = User.create!(name: "Group admin", email: "invitation-group_admin@example.com", password: "password123!", password_confirmation: "password123!")
    other = User.create!(name: "Other", email: "invitation-other@example.com", password: "password123!", password_confirmation: "password123!")
    invited_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Invitation only", group_type: :private_group)
    other_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Someone else's invitation", group_type: :private_group)
    invited_group.group_memberships.create!(user: user, status: :invited)
    other_group.group_memberships.create!(user: other, status: :invited)
    sign_in user

    get groups_path

    expect(response.body).to include("받은 동아리 초대", invited_group.name)
    expect(response.body).not_to include(other_group.name)
    expect(GroupPolicy::Scope.new(user, Group.all).resolve).not_to include(invited_group)
  end

  it "lists public, approval, and joined private groups only" do
    other_group_admin = User.create!(name: "Group admin", email: "groups-group_admin@example.com", password: "password123!", password_confirmation: "password123!")
    public_group = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Public group", group_type: :public_group)
    approval_group = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Approval group", group_type: :approval_group)
    joined_private = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Joined private", group_type: :private_group)
    hidden_private = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Hidden private", group_type: :private_group)
    joined_private.group_memberships.create!(user: user, status: :active)
    sign_in user

    get groups_path

    expect(response.body).to include(public_group.name, approval_group.name, joined_private.name)
    expect(response.body).not_to include(hidden_private.name)
  end

  it "does not expose a private group to a non-member by direct URL" do
    other_group_admin = User.create!(name: "Group admin", email: "private-group_admin@example.com", password: "password123!", password_confirmation: "password123!")
    private_group = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Hidden private", group_type: :private_group)
    sign_in user

    get group_path(private_group)

    expect(response).to have_http_status(:not_found)
  end

  it "lets a global admin inspect jjaeks in a private group without membership" do
    global_admin = User.create!(name: "Global admin", email: "private-group-global-admin@example.com", password: "password123!", global_admin: true)
    group_admin = User.create!(name: "Group admin", email: "private-content-group-admin@example.com", password: "password123!")
    private_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Private investigation", group_type: :private_group)
    jjaek = group_admin.jjaeks.create!(group: private_group, content: "PRIVATE GROUP INVESTIGATION CONTENT")
    sign_in global_admin

    get group_path(private_group)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(jjaek.content)
  end

  it "shows only the current activity suspension public reason to the affected member" do
    group_admin = User.create!(name: "Group admin", email: "activity-reason-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Activity reason", group_type: :private_group)
    membership = group.group_memberships.create!(user:, status: :active, moderation_status: :activity_suspended)
    ModerationAction.create!(
      target: membership,
      actor: group_admin,
      action_type: :suspend_activity,
      public_reason: "MEMBER_VISIBLE_REASON",
      internal_note: "OPERATIONS_ONLY_NOTE"
    )
    sign_in user

    get group_path(group)

    expect(response.body).to include("동아리 활동 정지", "공개 사유: MEMBER_VISIBLE_REASON")
    expect(response.body).not_to include("OPERATIONS_ONLY_NOTE")

    GroupMemberships::RestoreActivity.new(
      membership,
      actor: group_admin,
      public_reason: "Resolved"
    ).call!
    get group_path(group)
    expect(response.body).not_to include("동아리 활동 정지", "MEMBER_VISIBLE_REASON", "OPERATIONS_ONLY_NOTE")
  end

  it "does not expose application or closure details on general group screens" do
    other_group_admin = User.create!(name: "Group admin", email: "private-details-group_admin@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Public details", group_type: :public_group, application_purpose: "ADMIN PURPOSE", closure_reason: "GROUP ADMIN CLOSURE")
    sign_in user

    get groups_path
    expect(response.body).not_to include("ADMIN PURPOSE", "GROUP ADMIN CLOSURE")

    get group_path(group)
    expect(response.body).not_to include("ADMIN PURPOSE", "GROUP ADMIN CLOSURE")
  end


  it "shows the invitation form only to a private group group_admin" do
    invitee = User.create!(name: "Invitee", email: "invite-form-user@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Private invitations", group_type: :private_group)
    sign_in user

    get group_members_path(group)
    expect(response.body).to include("동아리 초대", invitee.name)

    group.group_memberships.create!(user: invitee, status: :active)
    sign_in invitee
    get group_members_path(group)
    expect(response.body).not_to include("동아리 초대")
  end

  describe "member management" do
    let(:group) { Group.create!(lifecycle_status: :active, group_admin: user, name: "Managed members", group_type: :approval_group) }
    let!(:member) { User.create!(name: "Active member", email: "managed-active@example.com", password: "password123!") }

    before do
      group.group_memberships.create!(user: member, status: :active)
    end

    it "allows the group admin and global admin but blocks members and non-members" do
      inactive_user = User.create!(name: "Inactive member", email: "managed-inactive@example.com", password: "password123!")
      pending_user = User.create!(name: "Pending member", email: "managed-pending@example.com", password: "password123!")
      inactive_membership = group.group_memberships.create!(user: inactive_user, status: :inactive)
      pending_membership = group.group_memberships.create!(user: pending_user, status: :pending)
      sign_in user
      get group_members_path(group)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("회원 관리", member.name, inactive_user.name, pending_user.name, "활동 회원", "동아리 관리자")

      global_admin = User.create!(name: "Global admin", email: "members-global-admin@example.com", password: "password123!", global_admin: true)
      sign_in global_admin
      get group_members_path(group)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(member.name, inactive_user.name, pending_user.name)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css(%(form[action="#{deactivate_group_group_membership_path(group, group.group_memberships.find_by!(user: member))}"]))).to be_nil
      expect(page.at_css(%(form[action="#{reactivate_group_group_membership_path(group, inactive_membership)}"]))).to be_nil
      expect(page.at_css(%(form[action="#{group_group_membership_path(group, pending_membership)}"]))).to be_nil

      private_group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Private members", group_type: :private_group)
      private_group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
      get group_members_path(private_group)
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{invite_group_group_memberships_path(private_group)}"]))).to be_nil

      pending_group = Group.create!(group_admin: user, name: "Pending members", group_type: :public_group, application_purpose: "Pending")
      get group_members_path(pending_group)
      expect(response).to have_http_status(:ok)

      sign_in member
      get group_members_path(group)
      expect(response).to redirect_to(root_path)

      outsider = User.create!(name: "Outsider", email: "members-outsider@example.com", password: "password123!")
      sign_in outsider
      get group_members_path(group)
      expect(response).to redirect_to(root_path)
    end

    it "keeps membership management off the group detail" do
      sign_in user
      get group_path(group)

      page = Nokogiri::HTML(response.body)
      expect(page.at_css(%(a[href="#{group_members_path(group)}"]))).to be_present
      expect(response.body).not_to include(member.name, "가입 요청", "활동 회원")
    end
  end


  describe "group_admin management" do
    let(:group) { Group.create!(lifecycle_status: :active, group_admin: user, name: "Original", description: "Before", group_type: :approval_group) }

    it "lets the group_admin edit name and description without changing group type" do
      sign_in user

      get edit_group_path(group)
      expect(response).to have_http_status(:ok)

      patch group_path(group), params: { group: { name: "Updated", description: "After", group_type: "private_group" } }

      expect(response).to redirect_to(group_path(group))
      expect(group.reload).to have_attributes(name: "Updated", description: "After", group_type: "approval_group")
    end

    it "lets a pending group_admin view and update the application purpose only in management" do
      pending_group = Group.create!(group_admin: user, name: "Pending management", group_type: :public_group, application_purpose: "Initial purpose")
      opening_event = pending_group.lifecycle_events.create!(actor: user, event_type: :opening_requested, detail: "Initial purpose")
      sign_in user

      get group_path(pending_group)
      expect(response.body).not_to include("Initial purpose")
      expect(response.body).to include("동아리 관리")

      get edit_group_path(pending_group)
      opening_card = Nokogiri::HTML(response.body).css("article").find { |node| node.text.include?("동아리 개설") }
      expect(response.body).to include("승인 대기", "Initial purpose")
      expect(opening_card.text).to include("신청", I18n.l(opening_event.created_at, format: :short))
      expect(opening_card.text).not_to include("승인")
      expect(response.body.scan("개설 목적").size).to eq(1)

      patch group_path(pending_group), params: { group: { name: pending_group.name, application_purpose: "Updated purpose" } }
      expect(pending_group.reload.application_purpose).to eq("Updated purpose")
      expect(opening_event.reload.detail).to eq("Updated purpose")
      expect(pending_group.lifecycle_events.count).to eq(1)

      pending_group.active!
      pending_group.lifecycle_events.create!(actor: user, event_type: :opening_approved)
      get edit_group_path(pending_group)
      opening_card = Nokogiri::HTML(response.body).css("article").find { |node| node.text.include?("동아리 개설") }
      expect(opening_card.text).to include("신청", "승인")
      expect(response.body).not_to include("Updated purpose", "개설 목적")
    end

    it "renders edit with 422 when validation fails" do
      sign_in user

      patch group_path(group), params: { group: { name: "", description: "After" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).not_to include("동아리 종류")
    end

    it "blocks a non-group_admin from edit and update" do
      group.group_memberships.create!(user: other_user = User.create!(name: "Member", email: "group-edit-member@example.com", password: "password123!", password_confirmation: "password123!"), status: :active)
      sign_in other_user

      get edit_group_path(group)
      expect(response).to redirect_to(root_path)

      patch group_path(group), params: { group: { name: "Hijacked" } }
      expect(response).to redirect_to(root_path)
      expect(group.reload.name).to eq("Original")
    end

    it "links member management for the group admin without exposing it to members" do
      member = User.create!(name: "Listed member", email: "listed-member@example.com", password: "password123!", password_confirmation: "password123!")
      group.group_memberships.create!(user: member, status: :active)
      sign_in user

      get group_path(group)
      expect(response.body).to include("회원 관리", "동아리 관리")
      expect(response.body).not_to include(member.name, "활동 회원", "비활성 회원")
      expect(response.body).not_to include("동아리 운영 종료", "재활성화 요청")
      expect(response.body).not_to include("운영 이력")
      expect(response.body).not_to include("내보내기")

      group.group_memberships.find_by!(user: member).update!(status: :inactive)
      get group_members_path(group)
      expect(response.body).to include("비활성 회원", "회원 활성화", "내보내기")

      sign_in member
      get group_path(group)
      expect(response.body).to include("비활성 회원")
      page = Nokogiri::HTML(response.body)
      expect(page.at_css(%(a[href="#{edit_group_path(group)}"]))).to be_nil
      expect(response.body).not_to include("회원 관리", "회원 활성화", "내보내기")
    end

    it "lets only the group_admin close an active group and request reactivation" do
      member = User.create!(name: "Member", email: "lifecycle-member@example.com", password: "password123!", password_confirmation: "password123!")
      group.group_memberships.create!(user: member, status: :active)
      jjaek = user.jjaeks.create!(group: group, content: "Existing group content")
      sign_in member

      patch close_group_path(group)
      expect(response).to redirect_to(root_path)
      expect(group.reload).to be_active

      sign_in user
      get edit_group_path(group)
      expect(response.body).to include("동아리 운영 종료", "운영 종료 사유", "data-turbo-confirm")

      patch close_group_path(group), params: { group: { closure_reason: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(group.reload).to be_active
      expect(group.closure_reason).to be_nil
      expect(group.closed_at).to be_nil

      invalid_reason = "a" * 501
      patch close_group_path(group), params: { group: { closure_reason: invalid_reason } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(invalid_reason)
      expect(group.reload).to be_active

      expect {
        patch close_group_path(group), params: { group: { closure_reason: "The reading program finished" } }
      }.not_to change(Group, :count)
      expect(group.reload).to be_inactive
      expect(group.closure_reason).to eq("The reading program finished")
      expect(group.closed_at).to be_present
      expect(group.group_memberships.count).to eq(2)
      expect(group.jjaeks).to contain_exactly(jjaek)
      first_close = group.lifecycle_events.operations_closed.sole
      expect(first_close.actor).to eq(user)
      expect(first_close.detail).to eq("The reading program finished")

      get edit_group_path(group)
      expect(response.body).to include("운영 종료", "종료", "재활성화 요청", "운영 이력")
      expect(response.body).not_to include("The reading program finished", "운영 종료 사유")

      get group_path(group)
      expect(response.body).not_to include("운영 이력", "The reading program finished")

      closed_at = group.closed_at
      patch request_reactivation_group_path(group)
      expect(group.reload).to be_pending_approval
      expect(group.closure_reason).to eq("The reading program finished")
      expect(group.closed_at).to eq(closed_at)
      expect(group.group_memberships.count).to eq(2)
      expect(group.jjaeks).to contain_exactly(jjaek)
      expect(group.lifecycle_events.reactivation_requested.sole.actor).to eq(user)

      group.active!
      get edit_group_path(group)
      closure_reason_field =
        Nokogiri::HTML(response.body).at_css('textarea[name="group[closure_reason]"]')

      expect(closure_reason_field).to be_present
      expect(closure_reason_field.text).to be_blank
      expect(response.body).not_to include("The reading program finished")
      lifecycle_history =
        Nokogiri::HTML(response.body).css("section").find do |section|
          section.at_css("h2")&.text&.strip == "운영 이력"
        end

      expect(lifecycle_history).to be_present
      expect(lifecycle_history.text).not_to include("운영 종료 사유")
    end

    it "rolls back a close when lifecycle event creation fails" do
      sign_in user
      allow(GroupLifecycleEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(GroupLifecycleEvent.new))
      event_count = GroupLifecycleEvent.count
      patch close_group_path(group), params: {
        group: { closure_reason: "Close atomically" }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(group.reload).to be_active
      expect(group.closed_at).to be_nil
      expect(group.closure_reason).to be_nil
      expect(GroupLifecycleEvent.count).to eq(event_count)
    end
  end

  describe "group admin transfer" do
    let(:group) { Group.create!(lifecycle_status: :active, group_admin: user, name: "Admin transfer", group_type: :public_group) }
    let(:new_admin) { User.create!(name: "New admin", email: "request-new-admin@example.com", password: "password123!", password_confirmation: "password123!") }

    it "transfers to an active member and lets the former admin leave normally" do
      new_admin_membership = group.group_memberships.create!(user: new_admin, status: :active)
      former_admin_membership = group.group_memberships.find_by!(user: user)
      jjaek = user.jjaeks.create!(group: group, content: "Existing content")
      sign_in user

      get group_members_path(group)
      expect(response.body).to include("동아리 관리자", "현재 관리자: #{user.name}", new_admin.name, "data-turbo-confirm")

      get edit_group_path(group)
      expect(response.body).not_to include("현재 관리자: #{user.name}", new_admin.name, "관리자 권한 이전")

      patch transfer_admin_group_path(group), params: { new_admin_id: new_admin.id }

      expect(response).to redirect_to(group_path(group))
      expect(group.reload.group_admin).to eq(new_admin)
      expect(former_admin_membership.reload).to be_active
      expect(new_admin_membership.reload).to be_active

      get edit_group_path(group)
      expect(response).to redirect_to(root_path)

      sign_in new_admin
      get edit_group_path(group)
      expect(response).to have_http_status(:ok)

      sign_in user
      expect {
        delete group_group_membership_path(group, former_admin_membership)
      }.to change(GroupMembership, :count).by(-1)
      expect(group.reload.group_admin).to eq(new_admin)
      expect(new_admin_membership.reload).to be_active
      expect(group.jjaeks).to contain_exactly(jjaek)
      expect(jjaek.reload.user).to eq(user)
    end

    it "lets a global admin transfer a private inactive group through general scope" do
      global_admin = User.create!(name: "Global admin", email: "request-transfer-global-admin@example.com", password: "password123!", global_admin: true)
      group.update!(group_type: :private_group)
      group.group_memberships.create!(user: new_admin, status: :active)
      group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
      sign_in global_admin

      patch transfer_admin_group_path(group), params: { new_admin_id: new_admin.id }

      expect(response).to redirect_to(admin_group_path(group))
      expect(group.reload.group_admin).to eq(new_admin)
    end

    it "blocks non-admin, non-active targets, and pending groups" do
      active_member = new_admin
      group.group_memberships.create!(user: active_member, status: :active)
      inactive_member = User.create!(name: "Inactive", email: "request-inactive-admin@example.com", password: "password123!", password_confirmation: "password123!")
      group.group_memberships.create!(user: inactive_member, status: :inactive)
      outsider = User.create!(name: "Outsider", email: "request-outsider-admin@example.com", password: "password123!", password_confirmation: "password123!")

      sign_in active_member
      patch transfer_admin_group_path(group), params: { new_admin_id: active_member.id }
      expect(response).to redirect_to(root_path)
      expect(group.reload.group_admin).to eq(user)

      sign_in user
      [ inactive_member, outsider ].each do |target|
        patch transfer_admin_group_path(group), params: { new_admin_id: target.id }
        expect(response).to redirect_to(group_path(group))
        expect(group.reload.group_admin).to eq(user)
      end

      pending_group = Group.create!(group_admin: user, name: "Pending transfer", group_type: :public_group, application_purpose: "Pending")
      pending_group.group_memberships.create!(user: active_member, status: :active)
      get edit_group_path(pending_group)
      expect(response.body).not_to include("관리자 권한 이전")
      patch transfer_admin_group_path(pending_group), params: { new_admin_id: active_member.id }
      expect(response).to redirect_to(root_path)
      expect(pending_group.reload.group_admin).to eq(user)
    end
  end
end
