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

  it "creates a global admin's group as active without an approval request" do
    global_admin = User.create!(name: "Global admin", email: "group-creator-global-admin@example.com", password: "password123!", global_admin: true)
    sign_in global_admin

    post groups_path, params: { group: { name: "Admin readers", group_type: "public_group", application_purpose: "Operate directly" } }

    group = Group.find_by!(name: "Admin readers")
    expect(group).to be_active
    expect(group.group_memberships.find_by!(user: global_admin)).to be_active
    expect(group.lifecycle_events.sole).to have_attributes(event_type: "opening_approved", actor: global_admin)
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
    get group_path(group)
    identity = Nokogiri::HTML(response.body).at_css("[data-group-identity-summary]")
    expect(identity.at_css("[data-field='active-member-count']").text.strip).to eq("회원 0명")
    expect(identity.at_css("[data-member-preview]")).to be_nil

    sign_in other_user
    get groups_path
    expect(response.body).not_to include(group.name)
    get group_path(group)
    expect(response).to redirect_to(groups_path)
    expect(flash[:alert]).to eq(I18n.t("groups.alerts.not_found_or_inaccessible"))
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
    active_invited_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Active invitation", group_type: :private_group)
    other_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Someone else's invitation", group_type: :private_group)
    suspended_invitation = invited_group.group_memberships.create!(user: user, status: :invited)
    active_invitation = active_invited_group.group_memberships.create!(user: user, status: :invited)
    other_group.group_memberships.create!(user: other, status: :invited)
    invited_group.update!(operation_suspended_at: Time.current)
    sign_in user

    get groups_path

    page = Nokogiri::HTML(response.body)
    suspended_card = page.css("article").find { |node| node.text.include?(invited_group.name) }
    active_card = page.css("article").find { |node| node.text.include?(active_invited_group.name) }
    expect(response.body).to include("받은 동아리 초대", invited_group.name, active_invited_group.name)
    expect(response.body).not_to include(other_group.name)
    expect(suspended_card.text).to include("운영 정지", "운영 정지 중에는 초대를 수락할 수 없습니다.")
    expect(suspended_card.at_css(%(form[action="#{accept_group_group_membership_path(invited_group, suspended_invitation)}"]))).to be_nil
    expect(suspended_card.at_css(%(form[action="#{decline_group_group_membership_path(invited_group, suspended_invitation)}"]))).to be_present
    expect(active_card.text).to include("운영 중")
    expect(active_card.at_css(%(form[action="#{accept_group_group_membership_path(active_invited_group, active_invitation)}"]))).to be_present
    expect(active_card.at_css(%(form[action="#{decline_group_group_membership_path(active_invited_group, active_invitation)}"]))).to be_present
    expect(GroupPolicy::Scope.new(user, Group.all).resolve).not_to include(invited_group)
  end

  it "lists only groups with an active membership" do
    other_group_admin = User.create!(name: "Group admin", email: "groups-group_admin@example.com", password: "password123!", password_confirmation: "password123!")
    public_group = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Public group", group_type: :public_group)
    joined_private = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Joined private", group_type: :private_group)
    joined_private.group_memberships.create!(user: user, status: :active)
    sign_in user

    get groups_path

    expect(response.body).to include("내 동아리", joined_private.name)
    expect(response.body).not_to include(public_group.name)
  end

  it "shows shared group badges and the current admin on three-column group cards" do
    groups = {
      public_group: Group.create!(lifecycle_status: :active, group_admin: user, name: "Public readers", description: "Read together", group_type: :public_group),
      approval_group: Group.create!(lifecycle_status: :active, group_admin: user, name: "Approval readers", group_type: :approval_group),
      private_group: Group.create!(lifecycle_status: :active, group_admin: user, name: "Private readers", group_type: :private_group)
    }
    sign_in user

    get groups_path

    page = Nokogiri::HTML(response.body)
    group_grid = page.css(".grid").find { |node| node["class"].include?("lg:grid-cols-3") }
    expect(group_grid["class"]).to include("grid-cols-1", "md:grid-cols-2")
    {
      public_group: [ "공개 동아리", "bg-sky-100" ],
      approval_group: [ "승인 동아리", "bg-amber-100" ],
      private_group: [ "비공개 동아리", "bg-violet-100" ]
    }.each do |type, (label, color)|
      group = groups.fetch(type)
      card = page.at_css("[data-group-type='#{type}']").ancestors("article").first
      type_badge = card.at_css("[data-group-type='#{type}']")
      status_badge = card.at_css("[data-field='current-status']")

      expect(card.at_css(%(a[href="#{group_path(group)}"])).text.strip).to eq(group.name)
      expect(type_badge.text.strip).to eq(label)
      expect(type_badge["class"]).to include(color)
      expect(status_badge.text.strip).to eq("운영 중")
      expect(status_badge["class"]).to include("bg-emerald-100")
      expect(card.at_css("[data-field='membership-status']")).to be_present
      expect(card.text).to include("동아리 관리자")
      admin_link = card.at_css(%(a[href="#{user_path(user)}"] img[alt="#{user.name}"]))
      expect(admin_link).to be_present
      expect(admin_link.parent.text).to include(user.name)
    end
    expect(page.at_css(%(a[href="#{group_path(groups.fetch(:public_group))}"])).ancestors("article").first.text).not_to include("Read together")
  end

  it "shows shared type and current-status badges in the group title card" do
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Detailed readers", description: "Detailed description", group_type: :public_group)
    members = 6.times.map do |index|
      member = User.create!(name: "Preview member #{index}", email: "group-preview-#{index}@example.com", password: "password123!")
      group.group_memberships.create!(user: member, status: :active)
      member
    end
    sign_in user

    get group_path(group)

    title_card = Nokogiri::HTML(response.body).at_css("section > section:first-child")
    type_badge = title_card.at_css("[data-group-type='public_group']")
    status_badge = title_card.at_css("[data-field='current-status']")
    expect(title_card.at_css("h1").text.strip).to eq(group.name)
    expect(type_badge.text.strip).to eq(I18n.t("groups.types.public_group"))
    expect(type_badge["class"]).to include("bg-sky-100")
    expect(status_badge.text.strip).to eq(I18n.t("groups.current_statuses.active"))
    expect(status_badge["class"]).to include("bg-emerald-100")
    admin_link = title_card.at_css(%(a[data-group-admin-avatar][href="#{user_path(user)}"]))
    expect(admin_link.at_css(%(img[alt="#{user.name}"]))).to be_present
    expect(admin_link["title"]).to eq(I18n.t("groups.group_admin", name: user.name))
    expect(admin_link["aria-label"]).to eq(I18n.t("groups.group_admin", name: user.name))
    expect(title_card.css("[data-group-identity-summary] img").first["alt"]).to eq(user.name)
    expect(title_card.at_css("[data-group-identity-summary]").text).not_to include(user.name)
    preview_links = title_card.css("[data-member-preview] a")
    expect(preview_links.map { |link| link["href"] }).to eq(members.first(5).map { |member| user_path(member) })
    preview_links.zip(members.first(5)).each do |link, member|
      expect(link["title"]).to eq(member.name)
      expect(link["aria-label"]).to eq(member.name)
      expect(link.at_css("img")["alt"]).to eq(member.name)
    end
    expect(title_card.at_css("[data-field='active-member-count']").text.strip).to eq("회원 6명")
    expect(title_card.text).to include("Detailed description")
    expect(title_card.at_css("span.bg-stone-900")).to be_nil
    expect(title_card.at_css(%(a[href="#{group_members_path(group)}"]))).to be_present
    expect(title_card.at_css(%(a[href="#{edit_group_path(group)}"]))).to be_present
  end

  it "shows joined group activity in stable reverse chronological order" do
    group_admin = User.create!(name: "Activity admin", email: "groups-activity-admin@example.com", password: "password123!")
    hidden_author = User.create!(name: "Hidden author", email: "groups-hidden-author@example.com", password: "password123!")
    first_group = Group.create!(lifecycle_status: :active, group_admin:, name: "First joined group", group_type: :private_group)
    second_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Second joined group", group_type: :private_group)
    other_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Other public group", group_type: :public_group)
    invited_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Invited group", group_type: :private_group)
    [ first_group, second_group ].each { |group| group.group_memberships.create!(user:, status: :active) }
    invited_group.group_memberships.create!(user:, status: :invited)
    book = Book.create!(title: "GROUP ACTIVITY BOOK", authors_text: "Author")
    older = first_group.jjaeks.create!(user: group_admin, content: "OLDER GROUP ACTIVITY", created_at: 2.hours.ago)
    newer = second_group.jjaeks.create!(user: group_admin, book:, content: "NEWER GROUP BOOK ACTIVITY", created_at: 1.hour.ago)
    other_group.jjaeks.create!(user: group_admin, content: "OTHER GROUP ACTIVITY")
    first_group.group_memberships.create!(user: hidden_author, status: :active)
    invited_group.jjaeks.create!(user: group_admin, content: "INVITED GROUP ACTIVITY")
    hidden = first_group.jjaeks.create!(user: hidden_author, content: "HIDDEN GROUP ACTIVITY")
    Jjaeks::Hide.new(hidden, actor: group_admin, public_reason: "other").call!
    sign_in user

    get groups_path

    expect(response.body).to include("최근 동아리 활동", newer.content, older.content, book.title, "동아리 관리자에 의해 숨겨진 짹입니다.")
    expect(response.body.index(newer.content)).to be < response.body.index(older.content)
    expect(response.body).not_to include("OTHER GROUP ACTIVITY", "INVITED GROUP ACTIVITY", hidden.content)
  end

  it "shows separate empty states for memberships and activity" do
    sign_in user

    get groups_path

    expect(response.body).to include("아직 가입한 동아리가 없습니다.", "아직 동아리 활동이 없습니다.")

    group_admin = User.create!(name: "Empty admin", email: "groups-empty-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Empty joined group", group_type: :private_group)
    group.group_memberships.create!(user:, status: :active)

    get groups_path

    expect(response.body).to include(group.name, "아직 동아리 활동이 없습니다.")
    expect(response.body).not_to include("아직 가입한 동아리가 없습니다.")
  end

  it "does not expose a private group to a non-member by direct URL" do
    other_group_admin = User.create!(name: "Group admin", email: "private-group_admin@example.com", password: "password123!", password_confirmation: "password123!")
    private_group = Group.create!(lifecycle_status: :active, group_admin: other_group_admin, name: "Hidden private", group_type: :private_group)
    sign_in user

    get group_path(private_group)

    expect(response).to redirect_to(groups_path)
    expect(flash[:alert]).to eq(I18n.t("groups.alerts.not_found_or_inaccessible"))
  end

  it "redirects a removed private group member's stale URL with an explanation" do
    group_admin = User.create!(name: "Group admin", email: "removed-private-group-admin@example.com", password: "password123!")
    private_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Removed private", group_type: :private_group)
    membership = private_group.group_memberships.create!(user:, status: :active)

    sign_in group_admin
    delete remove_group_group_membership_path(private_group, membership)

    sign_in user
    get group_path(private_group)

    expect(response).to redirect_to(groups_path)
    expect(flash[:alert]).to eq(I18n.t("group_memberships.alerts.removed"))

    get group_path(private_group)
    expect(response).to redirect_to(groups_path)
    expect(flash[:alert]).to eq(I18n.t("group_memberships.alerts.removed"))
  end

  it "prioritizes a current private group ban over removal UX and shows only the public reason" do
    group_admin = User.create!(name: "Group admin", email: "banned-private-group-admin@example.com", password: "password123!")
    private_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Banned private", group_type: :private_group)
    membership = private_group.group_memberships.create!(user:, status: :active)
    GroupMembershipRemoval.create!(group: private_group, user:, removed_by: group_admin)
    GroupMemberBans::Ban.new(
      membership,
      actor: group_admin,
      public_reason: "MEMBER BAN REASON",
      internal_note: "PRIVATE OPERATIONS NOTE"
    ).call!
    sign_in user

    get group_path(private_group)

    expect(response).to redirect_to(groups_path)
    expect(flash[:alert]).to eq(I18n.t("group_member_bans.alerts.access_restricted", reason: "MEMBER BAN REASON"))
    expect(flash[:alert]).not_to include("PRIVATE OPERATIONS NOTE")
    expect(GroupMembershipRemoval.exists?(group: private_group, user:)).to be(false)
  end

  it "keeps public and approval details visible to banned users without participation actions" do
    group_admin = User.create!(name: "Group admin", email: "banned-visible-group-admin@example.com", password: "password123!")
    public_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Banned public", group_type: :public_group)
    approval_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Banned approval", group_type: :approval_group)

    [ public_group, approval_group ].each do |group|
      membership = group.group_memberships.create!(user:, status: :active)
      GroupMemberBans::Ban.new(
        membership,
        actor: group_admin,
        public_reason: "VISIBLE BAN REASON",
        internal_note: "HIDDEN BAN NOTE"
      ).call!
    end
    sign_in user

    [ public_group, approval_group ].each do |group|
      get group_path(group)
      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("동아리 이용 제한", "VISIBLE BAN REASON")
      expect(response.body).not_to include("HIDDEN BAN NOTE")
      expect(page.at_css(%(form[action="#{group_group_memberships_path(group)}"]))).to be_nil
    end
  end

  it "shows an operation suspension reason without internal notes while preserving existing visibility" do
    admin = User.create!(name: "Global admin", email: "group-operation-global@example.com", password: "password123!", global_admin: true)
    group_admin = User.create!(name: "Group admin", email: "group-operation-owner@example.com", password: "password123!")
    groups = %i[public_group approval_group private_group].map do |group_type|
      group = Group.create!(lifecycle_status: :active, group_admin:, name: "Suspended #{group_type}", group_type:)
      group.group_memberships.create!(user:, status: :active)
      Groups::SuspendOperation.new(group, actor: admin, public_reason: "other", internal_note: "HIDDEN OPERATION NOTE").call!
      group
    end
    sign_in user

    groups.each do |group|
      get group_path(group)
      expect(response).to have_http_status(:ok)
      title_card = Nokogiri::HTML(response.body).at_css("section > section:first-child")
      expect(title_card.at_css("[data-field='current-status']").text.strip).to eq(I18n.t("groups.current_statuses.suspended"))
      expect(title_card.at_css("[data-field='current-status']")["class"]).to include("bg-red-50")
      expect(response.body).to include(
        "운영 정지",
        "이 동아리는 현재 운영이 정지되었습니다.",
        Group.suspension_reason_label("other")
      )
      expect(response.body).not_to include(">other<")
      expect(response.body).not_to include("HIDDEN OPERATION NOTE")
      expect(response.body).not_to include("수정하기")
    end

    get groups_path
    groups.each do |group|
      card = Nokogiri::HTML(response.body).css("article").find { |node| node.text.include?(group.name) }
      expect(card.text).to include("운영 정지")
    end

    sign_in admin
    get group_path(groups.last)
    expect(response).to have_http_status(:ok)
  end

  it "hides new participation while suspended and preserves cleanup actions" do
    group_admin = User.create!(name: "Group admin", email: "suspended-actions-admin@example.com", password: "password123!")
    public_group = Group.create!(lifecycle_status: :active, operation_suspended_at: Time.current, group_admin:, name: "Suspended public", group_type: :public_group)
    approval_group = Group.create!(lifecycle_status: :active, operation_suspended_at: Time.current, group_admin:, name: "Suspended approval", group_type: :approval_group)
    normal_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Operating public", group_type: :public_group)
    sign_in user

    [ public_group, approval_group ].each do |group|
      get group_path(group)
      expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{group_group_memberships_path(group)}"]))).to be_nil
    end

    get group_path(normal_group)
    expect(response.body).to include("운영 중")
    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{group_group_memberships_path(normal_group)}"]))).to be_present

    active_membership = public_group.group_memberships.create!(user:, status: :active)
    get group_path(public_group)
    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{group_group_membership_path(public_group, active_membership)}"]))).to be_present

    active_membership.destroy!
    pending_membership = approval_group.group_memberships.create!(user:, status: :pending)
    get group_path(approval_group)
    expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{group_group_membership_path(approval_group, pending_membership)}"]))).to be_present
  end

  it "blocks group settings, lifecycle closure, and admin transfer while operation is suspended" do
    admin = User.create!(name: "Global admin", email: "group-operation-mutation-admin@example.com", password: "password123!", global_admin: true)
    group_admin = User.create!(name: "Group admin", email: "group-operation-mutation-owner@example.com", password: "password123!")
    replacement = User.create!(name: "Replacement", email: "group-operation-replacement@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Original name", group_type: :public_group)
    group.group_memberships.create!(user: replacement, status: :active)
    Groups::SuspendOperation.new(group, actor: admin, public_reason: "other").call!
    sign_in group_admin

    patch group_path(group), params: { group: { name: "Changed" } }
    get new_group_closure_path(group)
    expect(response).to redirect_to(root_path)
    post group_closures_path(group), params: { group: { closure_reason: "Closed" } }
    get new_group_admin_transfer_path(group)
    expect(response).to redirect_to(root_path)
    post group_admin_transfers_path(group), params: { new_admin_id: replacement.id }

    expect(group.reload).to have_attributes(name: "Original name", lifecycle_status: "active", group_admin: group_admin)
  end

  it "does not expose a private group stale URL after the member leaves" do
    group_admin = User.create!(name: "Group admin", email: "left-private-group-admin@example.com", password: "password123!")
    private_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Left private", group_type: :private_group)
    membership = private_group.group_memberships.create!(user:, status: :active)

    sign_in user
    delete group_group_membership_path(private_group, membership)
    expect(GroupMembershipRemoval.where(group: private_group, user:)).to be_empty
    get group_path(private_group)

    expect(response).to redirect_to(groups_path)
    expect(flash[:alert]).to eq(I18n.t("groups.alerts.not_found_or_inaccessible"))
  end

  it "keeps a nonexistent group indistinguishable from an unauthorized group" do
    sign_in user

    get group_path(Group.maximum(:id).to_i + 1)

    expect(response).to redirect_to(groups_path)
    expect(flash[:alert]).to eq(I18n.t("groups.alerts.not_found_or_inaccessible"))
  end

  it "keeps public and approval group details visible after membership ends" do
    group_admin = User.create!(name: "Group admin", email: "visible-former-group-admin@example.com", password: "password123!")
    public_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Former public", group_type: :public_group)
    approval_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Former approval", group_type: :approval_group)
    public_membership = public_group.group_memberships.create!(user:, status: :active)
    approval_membership = approval_group.group_memberships.create!(user:, status: :active)
    public_membership.destroy!
    approval_membership.destroy!
    sign_in user

    get group_path(public_group)
    expect(response).to have_http_status(:ok)
    get group_path(approval_group)
    expect(response).to have_http_status(:ok)
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


  it "keeps sent invitation management on private group members without a new invitation form" do
    invitee = User.create!(name: "Invitee", email: "invite-form-user@example.com", password: "password123!", password_confirmation: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Private invitations", group_type: :private_group)
    sign_in user

    get group_members_path(group)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include(I18n.t("groups.invitations.sent_title"))
    expect(page.at_css(%(form[action="#{invite_group_group_memberships_path(group)}"]))).to be_nil
    expect(page.at_css("select[name='user_id']")).to be_nil
    expect(page.text).not_to include(invitee.name)

    group.group_memberships.create!(user: invitee, status: :active)
    sign_in invitee
    get group_members_path(group)
    expect(response).to redirect_to(root_path)
  end

  describe "member management" do
    let(:group) { Group.create!(lifecycle_status: :active, group_admin: user, name: "Managed members", group_type: :approval_group) }
    let!(:member) { User.create!(name: "Active member", email: "managed-active@example.com", password: "password123!") }

    before do
      group.group_memberships.create!(user: member, status: :active)
    end

    it "allows the group admin and global admin but blocks members and non-members" do
      pending_user = User.create!(name: "Pending member", email: "managed-pending@example.com", password: "password123!")
      pending_membership = group.group_memberships.create!(user: pending_user, status: :pending)
      sign_in user
      get group_members_path(group)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("회원 관리", member.name, pending_user.name, "가입 승인 대기")
      expect(Nokogiri::HTML(response.body).at_css(%(form[action="#{remove_group_group_membership_path(group, group.group_memberships.find_by!(user: member))}"]))).to be_present

      global_admin = User.create!(name: "Global admin", email: "members-global-admin@example.com", password: "password123!", global_admin: true)
      sign_in global_admin
      get group_members_path(group)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(member.name, pending_user.name, "회원 운영 이력")
      page = Nokogiri::HTML(response.body)
      expect(page.at_css(%(form[action="#{remove_group_group_membership_path(group, group.group_memberships.find_by!(user: member))}"]))).to be_nil
      expect(page.at_css(%(form[action="#{group_group_membership_path(group, pending_membership)}"]))).to be_nil
      expect(page.at_css(%(a[href="#{new_group_admin_transfer_path(group)}"]))).to be_nil
      expect(page.at_css(%(a[href="#{new_group_group_membership_activity_suspension_path(group, group.group_memberships.find_by!(user: member))}"]))).to be_nil
      expect(page.at_css(%(a[href="#{new_group_group_membership_member_ban_path(group, group.group_memberships.find_by!(user: member))}"]))).to be_nil

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

    it "shows group identity and compact member actions without repeated descriptions" do
      sign_in user

      get group_members_path(group)

      page = Nokogiri::HTML(response.body)
      header = page.at_css("section > section:first-child")
      admin_row = page.at_css("#group_membership_#{group.group_memberships.find_by!(user: user).id}")
      member_row = page.at_css("#group_membership_#{group.group_memberships.find_by!(user: member).id}")

      expect(header.at_css("h1").text).to eq(group.name)
      expect(header.text).to include("회원 관리", "승인 동아리", "운영 중", "현재 관리자", user.name)
      expect(header.at_css("[data-group-type='approval_group']")["class"]).to include("bg-amber-100")
      expect(header.at_css("[data-field='current-status']")["class"]).to include("bg-emerald-100")
      expect(header.at_css(%(a[href="#{group_path(group)}"])).text.strip).to eq("동아리로 돌아가기")
      expect(page.css(%(a[href="#{group_path(group)}"])).one?).to be(true)
      expect(header.at_css(%(img[alt="#{user.name}"]))).to be_present
      expect(header.at_css("[data-membership-role='admin']").text.strip).to eq("동아리 관리자")
      expect(header.at_css("[data-membership-role='admin']")["class"]).to include("bg-sky-100")
      expect(admin_row.at_css(%(img[alt="#{user.name}"]))).to be_present
      expect(admin_row.at_css("[data-membership-role='admin']").text.strip).to eq("동아리 관리자")
      expect(admin_row.at_css("[data-activity-status='normal']")["class"]).to include("bg-emerald-100")
      expect(admin_row.at_css(%(a[href="#{new_group_admin_transfer_path(group)}"]))).to be_present
      expect(admin_row.at_css("[data-member-management]")).to be_nil
      expect(member_row.at_css(%(img[alt="#{member.name}"]))).to be_present
      expect(member_row.at_css("[data-membership-role='member']").text.strip).to eq("회원")
      expect(member_row.at_css("[data-membership-role='member']")["class"]).to include("bg-stone-100")
      expect(member_row.at_css("[data-activity-status='normal']").text.strip).to eq("정상 활동")
      expect(member_row.text).to include("활동 정지", "내보내기", "동아리 이용 제한")
      expect(member_row.at_css(%(a[href="#{new_group_group_membership_activity_suspension_path(group, group.group_memberships.find_by!(user: member))}"]))).to be_present
      expect(member_row.at_css(%(form[action="#{remove_group_group_membership_path(group, group.group_memberships.find_by!(user: member))}"]))).to be_present
      expect(member_row.at_css(%(a[href="#{new_group_group_membership_member_ban_path(group, group.group_memberships.find_by!(user: member))}"]))).to be_present
      expect(page.css("h2").map(&:text)).not_to include("동아리 관리자")
      expect(page.text).not_to include("회원 자격은 유지하고 동아리 활동만 정지합니다.", "동아리에서 내보냅니다. 다시 가입할 수 있습니다.")
    end

    it "uses admin return navigation only for a global admin with admin context" do
      global_admin = User.create!(name: "Global admin", email: "members-navigation-admin@example.com", password: "password123!", global_admin: true)
      sign_in global_admin

      get group_members_path(group, context: "admin")

      page = Nokogiri::HTML(response.body)
      header = page.at_css("section > section:first-child")
      expect(header.at_css(%(a[href="#{admin_groups_path}"])).text.strip).to eq("동아리 관리로")
      expect(page.at_css(%(a[href="#{group_path(group)}"]))).to be_nil

      sign_in user
      get group_members_path(group, context: "admin")

      member_page = Nokogiri::HTML(response.body)
      member_header = member_page.at_css("section > section:first-child")
      expect(member_header.at_css(%(a[href="#{group_path(group)}"])).text.strip).to eq("동아리로 돌아가기")
      expect(member_page.at_css(%(a[href="#{admin_groups_path}"]))).to be_nil
    end

    it "hides empty pending and ban sections" do
      sign_in user

      get group_members_path(group)

      page = Nokogiri::HTML(response.body)
      expect(page.css("h2").map(&:text)).not_to include("가입 승인 대기", "이용 제한 사용자")
      expect(page.text).not_to include("대기 중인 가입 요청이 없습니다.", "현재 이용이 제한된 사용자가 없습니다.")
    end

    it "shows the operation suspension as the current group status" do
      group.update!(operation_suspended_at: Time.current)
      sign_in user

      get group_members_path(group)

      header = Nokogiri::HTML(response.body).at_css("section > section:first-child")
      expect(header.text).to include(group.name, "승인 동아리", "운영 정지")
      expect(header.text).not_to include("운영 중")
    end

    it "shows pending approval actions and the current ban reason with an unban link" do
      pending_user = User.create!(name: "Pending member", email: "pending-ui@example.com", password: "password123!")
      banned_user = User.create!(name: "Banned member", email: "banned-ui@example.com", password: "password123!")
      pending_membership = group.group_memberships.create!(user: pending_user, status: :pending)
      banned_membership = group.group_memberships.create!(user: banned_user, status: :active)
      GroupMemberBans::Ban.new(banned_membership, actor: user, public_reason: "Current ban reason").call!
      ban = group.group_member_bans.find_by!(user: banned_user)
      sign_in user

      get group_members_path(group)

      page = Nokogiri::HTML(response.body)
      expect(page.css("h2").map(&:text)).to include("가입 승인 대기", "이용 제한 사용자")
      expect(page.at_css(%(img[alt="#{pending_user.name}"]))).to be_present
      expect(page.at_css("[data-membership-status='pending']")["class"]).to include("bg-amber-100")
      expect(page.at_css(%(form[action="#{group_group_membership_path(group, pending_membership)}"]))).to be_present
      expect(page.at_css(%(form[action="#{reject_group_group_membership_path(group, pending_membership)}"]))).to be_present
      ban_row = page.at_css("#group_member_ban_#{ban.id}")
      expect(ban_row.at_css(%(img[alt="#{banned_user.name}"]))).to be_present
      expect(ban_row.text).to include("동아리 이용 제한", "Current ban reason")
      expect(ban_row.at_css("[data-restriction-status='banned']")["class"]).to include("bg-red-50")
      expect(ban_row.element_children.first.at_css(%(a[data-member-action="unban_from_group"][href="#{new_group_group_member_ban_restoration_path(group, ban)}"]))).to be_present
    end

    it "shows a suspended member's current reason and restore action" do
      membership = group.group_memberships.find_by!(user: member)
      GroupMemberships::SuspendActivity.new(membership, actor: user, public_reason: "Current suspension reason").call!
      sign_in user

      get group_members_path(group)

      member_row = Nokogiri::HTML(response.body).at_css("#group_membership_#{membership.id}")
      expect(member_row.text).to include("활동 정지", "공개 사유", "Current suspension reason")
      expect(member_row.at_css("[data-activity-status='activity_suspended']")["class"]).to include("bg-red-50")
      expect(member_row.at_css(%(a[href="#{new_group_group_membership_activity_restoration_path(group, membership)}"]))).to be_present
      expect(member_row.at_css(%(a[href="#{new_group_group_membership_activity_suspension_path(group, membership)}"]))).to be_nil
    end

    it "keeps membership management off the group detail" do
      sign_in user
      get group_path(group)

      page = Nokogiri::HTML(response.body)
      membership = group.group_memberships.find_by!(user: member)

      expect(page.at_css(%(a[href="#{group_members_path(group)}"]))).to be_present
      expect(
        page.at_css(%([data-member-preview] a[href="#{user_path(member)}"] img[alt="#{member.name}"]))
      ).to be_present
      expect(page.at_css("#group_membership_#{membership.id}")).to be_nil
      expect(response.body).not_to include("가입 요청", "활동 회원")
    end
  end


  describe "group_admin management" do
    let(:group) { Group.create!(lifecycle_status: :active, group_admin: user, name: "Original", description: "Before", group_type: :approval_group) }

    it "lets the group_admin edit name and description without changing group type" do
      sign_in user

      get edit_group_path(group)
      expect(response).to have_http_status(:ok)
      title_card = Nokogiri::HTML(response.body).at_css("section > section:first-child")
      expect(title_card.at_css("[data-group-type='approval_group']").text.strip).to eq(I18n.t("groups.types.approval_group"))
      expect(title_card.at_css("[data-group-type='approval_group']")["class"]).to include("bg-amber-100")
      expect(title_card.at_css("[data-field='current-status']").text.strip).to eq(I18n.t("groups.current_statuses.active"))
      expect(title_card.at_css("[data-field='current-status']")["class"]).to include("bg-emerald-100")

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
      page = Nokogiri::HTML(response.body)
      title_card = page.at_css("section > section:first-child")
      expect(title_card.at_css("[data-group-type='public_group']").text.strip).to eq(I18n.t("groups.types.public_group"))
      expect(title_card.at_css("[data-field='current-status']").text.strip).to eq(I18n.t("groups.current_statuses.pending_approval"))
      expect(title_card.at_css("[data-field='current-status']")["class"]).to include("bg-amber-100")
      opening_card = page.at_css("#group_operation_history [data-history-entry='opening_requested']")
      expect(response.body).to include("승인 대기", "Initial purpose")
      expect(opening_card.text).to include("신청", I18n.l(opening_event.created_at, format: :short))
      expect(opening_card.text).not_to include("승인")
      expect(opening_card.text).to include("개설 목적", "Initial purpose")
      expect(page.at_css('textarea[name="group[application_purpose]"]')).to be_present

      patch group_path(pending_group), params: { group: { name: pending_group.name, application_purpose: "Updated purpose" } }
      expect(pending_group.reload.application_purpose).to eq("Updated purpose")
      expect(opening_event.reload.detail).to eq("Updated purpose")
      expect(pending_group.lifecycle_events.count).to eq(1)

      pending_group.active!
      pending_group.lifecycle_events.create!(actor: user, event_type: :opening_approved)
      get edit_group_path(pending_group)
      page = Nokogiri::HTML(response.body)
      opening_request_entry = page.at_css("#group_operation_history [data-history-entry='opening_requested']")
      opening_approval_entry = page.at_css("#group_operation_history [data-history-entry='opening_approved']")
      expect(opening_request_entry.text).to include("개설 신청", "개설 목적", "Updated purpose")
      expect(opening_approval_entry.text).to include("승인")
      expect(opening_approval_entry.text).not_to include("개설 목적")
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
      membership = group.group_memberships.create!(user: member, status: :active)

      sign_in user

      get group_path(group)
      page = Nokogiri::HTML(response.body)

      expect(response.body).to include("회원 관리", "동아리 관리")
      expect(
        page.at_css(%([data-member-preview] a[href="#{user_path(member)}"] img[alt="#{member.name}"]))
      ).to be_present
      expect(page.at_css("#group_membership_#{membership.id}")).to be_nil
      expect(response.body).not_to include("활동 회원")
      expect(response.body).not_to include("동아리 운영 종료", "재운영 요청")
      expect(response.body).not_to include("운영 이력")
      expect(response.body).not_to include("내보내기")

      sign_in member
      get group_path(group)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css(%(a[href="#{edit_group_path(group)}"]))).to be_nil
      expect(response.body).not_to include("회원 관리", "내보내기")
    end

    it "lets only the group_admin close an active group and request reactivation" do
      member = User.create!(name: "Member", email: "lifecycle-member@example.com", password: "password123!", password_confirmation: "password123!")
      group.group_memberships.create!(user: member, status: :active)
      jjaek = user.jjaeks.create!(group: group, content: "Existing group content")
      sign_in member

      get new_group_closure_path(group)
      expect(response).to redirect_to(root_path)
      post group_closures_path(group)
      expect(response).to redirect_to(root_path)
      expect(group.reload).to be_active

      sign_in user
      get edit_group_path(group)
      edit_page = Nokogiri::HTML(response.body)
      expect(edit_page.at_css(%(a[href="#{new_group_closure_path(group)}"]))).to be_present
      expect(edit_page.at_css(%(form[action="#{group_closures_path(group)}"]))).to be_nil

      get new_group_closure_path(group)
      close_page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      close_context = close_page.at_css("[data-group-action-context]")
      expect(close_context.text).to include(group.name, "동아리 관리자", user.name)
      expect(close_context.at_css(%(img[alt="#{user.name}"]))).to be_present
      expect(close_context.at_css("[data-group-type='approval_group']").text.strip).to eq(I18n.t("groups.types.approval_group"))
      expect(close_context.at_css("[data-field='current-status']").text.strip).to eq(I18n.t("groups.current_statuses.active"))
      expect(close_context.at_css("[data-field='current-status']")["class"]).to include("bg-emerald-100")
      expect(close_page.at_css(%(form[action="#{group_closures_path(group)}"] textarea[name="group[closure_reason]"]))).to be_present

      post group_closures_path(group), params: { group: { closure_reason: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(group.reload).to be_active
      expect(group.closure_reason).to be_nil
      expect(group.closed_at).to be_nil

      invalid_reason = "a" * 501
      post group_closures_path(group), params: { group: { closure_reason: invalid_reason } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(invalid_reason)
      expect(group.reload).to be_active

      expect {
        post group_closures_path(group), params: { group: { closure_reason: "The reading program finished" } }
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
      expect(response.body).to include("운영 종료", "종료", "재운영 요청", "운영 이력")
      expect(response.body).to include("The reading program finished", "운영 종료 사유")

      get group_path(group)
      expect(response.body).not_to include("운영 이력", "The reading program finished")

      closed_at = group.closed_at
      sign_in member
      get new_group_reactivation_request_path(group)
      expect(response).to redirect_to(root_path)

      sign_in user
      get new_group_reactivation_request_path(group)
      reactivation_page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      reactivation_context = reactivation_page.at_css("[data-group-action-context]")
      expect(reactivation_context.text).to include(group.name, "동아리 관리자", user.name)
      expect(reactivation_context.at_css(%(img[alt="#{user.name}"]))).to be_present
      expect(reactivation_context.at_css("[data-field='current-status']").text.strip).to eq(I18n.t("groups.current_statuses.inactive"))
      expect(reactivation_context.at_css("[data-field='current-status']")["class"]).to include("bg-stone-200")
      expect(response.body).to include("The reading program finished")
      expect(reactivation_page.at_css(%(form[action="#{group_reactivation_requests_path(group)}"]))).to be_present

      post group_reactivation_requests_path(group)
      expect(group.reload).to be_pending_approval
      expect(group.closure_reason).to eq("The reading program finished")
      expect(group.closed_at).to eq(closed_at)
      expect(group.group_memberships.count).to eq(2)
      expect(group.jjaeks).to contain_exactly(jjaek)
      expect(group.lifecycle_events.reactivation_requested.sole.actor).to eq(user)

      get edit_group_path(group)
      status_badge = Nokogiri::HTML(response.body).at_css("section > section:first-child [data-field='current-status']")
      expect(status_badge.text.strip).to eq(I18n.t("groups.current_statuses.reactivation_pending"))
      expect(status_badge["class"]).to include("bg-amber-100")

      group.active!
      get edit_group_path(group)
      expect(response.body).to include("The reading program finished")
      lifecycle_history =
        Nokogiri::HTML(response.body).css("section").find do |section|
          section.at_css("h2")&.text&.strip == "운영 이력"
        end

      expect(lifecycle_history).to be_present
      expect(lifecycle_history.text).to include("운영 종료 사유", "The reading program finished")

      get new_group_closure_path(group)
      closure_reason_field =
        Nokogiri::HTML(response.body).at_css('textarea[name="group[closure_reason]"]')

      expect(closure_reason_field).to be_present
      expect(closure_reason_field.text).to be_blank
    end

    it "shows lifecycle and public platform operation events in one chronology" do
      platform_admin = User.create!(
        name: "Platform history admin",
        email: "platform-history-admin@example.com",
        password: "password123!",
        global_admin: true
      )
      base_time = Time.zone.local(2026, 1, 1, 12)
      group.lifecycle_events.create!(
        actor: user,
        event_type: :opening_requested,
        detail: "Opening purpose",
        created_at: base_time
      )
      group.lifecycle_events.create!(
        actor: platform_admin,
        event_type: :opening_approved,
        created_at: base_time + 30.minutes
      )
      suspension = ModerationAction.create!(
        target: group,
        actor: platform_admin,
        action_type: :suspend_group_operation,
        public_reason: "other",
        internal_note: "ADMIN_ONLY_SUSPEND_NOTE",
        created_at: base_time + 1.hour
      )
      group.lifecycle_events.create!(
        actor: user,
        event_type: :operations_closed,
        detail: "Season completed",
        created_at: base_time + 2.hours
      )
      ModerationAction.create!(
        target: group,
        actor: platform_admin,
        action_type: :restore_group_operation,
        public_reason: "Restriction lifted",
        internal_note: "ADMIN_ONLY_RESTORE_NOTE",
        reversal_of: suspension,
        created_at: base_time + 2.hours
      )
      group.lifecycle_events.create!(
        actor: user,
        event_type: :reactivation_requested,
        created_at: base_time + 3.hours
      )
      group.lifecycle_events.create!(
        actor: platform_admin,
        event_type: :reactivation_approved,
        created_at: base_time + 4.hours
      )
      sign_in user

      get edit_group_path(group)

      page = Nokogiri::HTML(response.body)
      history = page.at_css("#group_operation_history")
      entries = history.css("[data-history-entry]")
      expect(entries.map { |entry| entry["data-history-entry"] }).to eq(
        %w[reactivation_approved reactivation_requested restore_group_operation operations_closed suspend_group_operation opening_approved opening_requested]
      )
      expect(entries.map { |entry| entry["data-history-kind"] }).to eq(
        %w[lifecycle lifecycle platform lifecycle platform lifecycle lifecycle]
      )

      opening_request_entry = entries.find { |entry| entry["data-history-entry"] == "opening_requested" }
      opening_approval_entry = entries.find { |entry| entry["data-history-entry"] == "opening_approved" }
      closure_entry = entries.find { |entry| entry["data-history-entry"] == "operations_closed" }
      reactivation_request_entry = entries.find { |entry| entry["data-history-entry"] == "reactivation_requested" }
      reactivation_approval_entry = entries.find { |entry| entry["data-history-entry"] == "reactivation_approved" }

      expect(opening_request_entry.text).to include("개설 신청", "동아리 관리자 #{user.name}", "개설 목적", "Opening purpose")
      expect(opening_approval_entry.text).to include("승인", "시스템 관리자 #{platform_admin.name}")
      expect(opening_approval_entry.text).not_to include("개설 목적", "Opening purpose")
      expect(closure_entry.text).to include("종료", "동아리 관리자 #{user.name}", "운영 종료 사유")
      expect(reactivation_request_entry.text).to include("재운영 신청", "동아리 관리자 #{user.name}")
      expect(reactivation_approval_entry.text).to include("재운영 승인", "시스템 관리자 #{platform_admin.name}")
      expect(history.text).to include(
        "개설 신청",
        "Opening purpose",
        "운영 정지",
        "기타 운영 정책 위반",
        "종료",
        "Season completed",
        "운영 복구",
        "Restriction lifted",
        "재운영 신청",
        "동아리 관리자 #{user.name}",
        "시스템 관리자 #{platform_admin.name}"
      )
      expect(history.text).not_to include(
        "ADMIN_ONLY_SUSPEND_NOTE",
        "ADMIN_ONLY_RESTORE_NOTE",
        "내부 운영 메모"
      )
      expect(entries[6].text).to include("개설 신청", "동아리 관리자 #{user.name}")
      expect(entries[5].text).to include("승인", "시스템 관리자 #{platform_admin.name}")
      expect(entries[3].text).to include("종료", "동아리 관리자 #{user.name}", "Season completed")
      expect(entries[1].text).to include("재운영 신청", "동아리 관리자 #{user.name}")
      expect(entries[0].text).to include("재운영 승인", "시스템 관리자 #{platform_admin.name}")
      expect(page.at_css("a[href='#{new_admin_group_operation_suspension_path(group)}']")).to be_nil
      expect(page.at_css("a[href='#{new_admin_group_operation_restoration_path(group)}']")).to be_nil

      group_admin_signatures = entries.map do |entry|
        [
          entry["data-history-entry"],
          entry.at_css("article > div > p")&.text&.strip,
          entry.at_css("article > div > span")&.text&.strip
        ]
      end

      sign_in platform_admin
      get admin_group_path(group)
      admin_page = Nokogiri::HTML(response.body)
      admin_history = admin_page.at_css("#group_operation_history")
      admin_entries = admin_history.css("[data-history-entry]")
      admin_signatures = admin_entries.map do |entry|
        [
          entry["data-history-entry"],
          entry.at_css("article > div > p")&.text&.strip,
          entry.at_css("article > div > span")&.text&.strip
        ]
      end

      expect(admin_entries.map { |entry| entry["data-history-kind"] }).to eq(
        entries.map { |entry| entry["data-history-kind"] }
      )
      expect(admin_signatures).to eq(group_admin_signatures)
      expect(admin_history.text).to include("ADMIN_ONLY_SUSPEND_NOTE", "ADMIN_ONLY_RESTORE_NOTE")
      expect(admin_page.at_css(%(a[href="#{new_group_closure_path(group)}"]))).to be_nil
      expect(admin_page.at_css(%(a[href="#{new_group_reactivation_request_path(group)}"]))).to be_nil
    end

    it "rolls back a close when lifecycle event creation fails" do
      sign_in user
      allow(GroupLifecycleEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(GroupLifecycleEvent.new))
      event_count = GroupLifecycleEvent.count
      post group_closures_path(group), params: {
        group: { closure_reason: "Close atomically" }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(group.reload).to be_active
      expect(group.closed_at).to be_nil
      expect(group.closure_reason).to be_nil
      expect(GroupLifecycleEvent.count).to eq(event_count)
    end

    it "rolls back a reactivation request when lifecycle event creation fails" do
      group.update!(lifecycle_status: :inactive, closure_reason: "Completed", closed_at: Time.current)
      sign_in user
      allow(GroupLifecycleEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(GroupLifecycleEvent.new))
      event_count = GroupLifecycleEvent.count

      post group_reactivation_requests_path(group)

      expect(response).to have_http_status(:unprocessable_content)
      expect(group.reload).to be_inactive
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
      members_page = Nokogiri::HTML(response.body)
      expect(members_page.at_css("section > section:first-child").text).to include("현재 관리자", user.name)
      expect(members_page.at_css("#group_membership_#{former_admin_membership.id} a[href='#{new_group_admin_transfer_path(group)}']")).to be_present
      expect(members_page.at_css(%(form[action="#{group_admin_transfers_path(group)}"]))).to be_nil

      get new_group_admin_transfer_path(group)
      transfer_page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      transfer_context = transfer_page.at_css("[data-group-action-context]")
      expect(transfer_context.text).to include(group.name, "동아리 관리자", user.name)
      expect(transfer_context.at_css(%(img[alt="#{user.name}"]))).to be_present
      expect(transfer_context.at_css("[data-group-type='public_group']")).to be_present
      expect(transfer_context.at_css("[data-field='current-status']").text.strip).to eq(I18n.t("groups.current_statuses.active"))
      candidate_list = transfer_page.at_css("[data-admin-transfer-candidates]")
      expect(candidate_list["class"]).to include("max-h-80", "overflow-y-auto")
      candidate = transfer_page.at_css(%([data-admin-transfer-candidate] input[name="new_admin_id"][value="#{new_admin.id}"][checked]))
      expect(candidate).to be_present
      candidate_row = candidate.ancestors("label").first
      expect(candidate_row.at_css(%(img[alt="#{new_admin.name}"]))).to be_present
      expect(candidate_row.at_css("[data-membership-role='member']").text.strip).to eq("회원")
      expect(candidate_row.at_css("[data-membership-status='active']").text.strip).to eq("참여 중")

      get edit_group_path(group)
      expect(response.body).not_to include("현재 관리자: #{user.name}", new_admin.name, "관리자 권한 이전")

      post group_admin_transfers_path(group), params: { new_admin_id: new_admin.id }

      expect(response).to redirect_to(group_path(group))
      expect(group.reload.group_admin).to eq(new_admin)
      expect(former_admin_membership.reload).to be_active
      expect(new_admin_membership.reload).to be_active

      sign_in new_admin
      get group_members_path(group)
      expect(response.body).to include(
        "#{user.name}님의 관리자 권한을 해제했습니다",
        "#{new_admin.name}님에게 관리자 권한을 부여했습니다"
      )

      sign_in user
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

      get new_group_admin_transfer_path(group)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(group.name, new_admin.name)

      post group_admin_transfers_path(group), params: { new_admin_id: new_admin.id }

      expect(response).to redirect_to(admin_group_path(group))
      expect(group.reload.group_admin).to eq(new_admin)
    end

    it "keeps the selected candidate when transfer validation fails" do
      other_candidate = User.create!(name: "Other candidate", email: "request-other-admin@example.com", password: "password123!")
      group.group_memberships.create!(user: new_admin, status: :active)
      group.group_memberships.create!(user: other_candidate, status: :active)
      sign_in user
      allow_any_instance_of(Group).to receive(:transfer_admin_to!).and_raise(ActiveRecord::RecordInvalid.new(group))

      post group_admin_transfers_path(group), params: { new_admin_id: other_candidate.id }

      expect(response).to have_http_status(:unprocessable_content)
      page = Nokogiri::HTML(response.body)
      selected_candidate = page.at_css(%(input[name="new_admin_id"][value="#{other_candidate.id}"][checked]))
      expect(selected_candidate).to be_present
      expect(selected_candidate.ancestors("label").first.at_css(%(img[alt="#{other_candidate.name}"]))).to be_present
    end

    it "blocks non-admin, non-active targets, and pending groups" do
      active_member = new_admin
      group.group_memberships.create!(user: active_member, status: :active)
      outsider = User.create!(name: "Outsider", email: "request-outsider-admin@example.com", password: "password123!", password_confirmation: "password123!")

      sign_in active_member
      get new_group_admin_transfer_path(group)
      expect(response).to redirect_to(root_path)
      post group_admin_transfers_path(group), params: { new_admin_id: active_member.id }
      expect(response).to redirect_to(root_path)
      expect(group.reload.group_admin).to eq(user)

      sign_in user
      [ outsider ].each do |target|
        post group_admin_transfers_path(group), params: { new_admin_id: target.id }
        expect(response).to have_http_status(:unprocessable_content)
        expect(group.reload.group_admin).to eq(user)
      end

      pending_group = Group.create!(group_admin: user, name: "Pending transfer", group_type: :public_group, application_purpose: "Pending")
      pending_group.group_memberships.create!(user: active_member, status: :active)
      get edit_group_path(pending_group)
      expect(response.body).not_to include("관리자 권한 이전")
      get new_group_admin_transfer_path(pending_group)
      expect(response).to redirect_to(root_path)
      post group_admin_transfers_path(pending_group), params: { new_admin_id: active_member.id }
      expect(response).to redirect_to(root_path)
      expect(pending_group.reload.group_admin).to eq(user)
    end
  end
end
