require "rails_helper"

RSpec.describe "Notifications", type: :request do
  let!(:recipient) { User.create!(name: "Recipient", email: "recipient-notifications@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:actor) { User.create!(name: "Actor", email: "actor-notifications@example.com", password: "password123!", password_confirmation: "password123!") }

  def parse_html
    Nokogiri::HTML.parse(response.body)
  end

  it "redirects guests to sign in" do
    get notifications_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows the unread notification count in the navigation" do
    actor.jjaeks.create!(target_user: recipient, content: "PROFILE_NOTIFICATION", visibility: :book_friends).tap do |jjaek|
      Notification.notify_profile_jjaek_created(jjaek)
    end
    sign_in recipient

    get root_path

    container = parse_html.at_css("#notification-badge-container")
    badge = container.at_css("#notification-badge")
    expect(container).not_to be_nil
    expect(badge).not_to be_nil
    expect(badge.text.strip).to eq("1")
  end

  it "renders the notification badge container when there are no unread notifications" do
    sign_in recipient

    get root_path

    container = parse_html.at_css("#notification-badge-container")
    expect(container).not_to be_nil
    expect(container.at_css("#notification-badge")).to be_nil
  end

  it "shows the current user's notification list" do
    jjaek = actor.jjaeks.create!(target_user: recipient, content: "PROFILE_NOTIFICATION", visibility: :book_friends)
    Notification.notify_profile_jjaek_created(jjaek)
    sign_in recipient

    get notifications_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("notifications.title"))
    expect(response.body).to include(I18n.t("notifications.messages.profile_jjaek_created", actor_name: actor.name))
    expect(response.body).to include("user_profile_")
    expect(response.body).to include("_128")
    expect(response.body).to include(%(alt="#{actor.name}"))
    expect(response.body).to include(jjaek_path(jjaek))
  end

  it "shows an applicant identity and links a membership request to current member management" do
    group = Group.create!(group_admin: recipient, name: "Approval circle", group_type: :approval_group, lifecycle_status: :active)
    event = GroupMembershipEvent.create!(group:, user: actor, actor:, event_type: :requested_to_join)
    Notification.create!(recipient:, actor:, action: :group_membership_requested_to_join, notifiable: event)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(actor.name, group.name, "가입을 신청했습니다")
    expect(article.at_css("img")["alt"]).to eq(actor.name)
    expect(article.at_css("a")["href"]).to eq(group_members_path(group))
  end

  it "falls back for a membership request when the recipient is no longer group admin" do
    group = Group.create!(group_admin: actor, name: "Other circle", group_type: :approval_group, lifecycle_status: :active)
    event = GroupMembershipEvent.create!(group:, user: actor, actor:, event_type: :requested_to_join)
    Notification.create!(recipient:, actor:, action: :group_membership_requested_to_join, notifiable: event)
    sign_in recipient

    get notifications_path

    expect(parse_html.at_css("article a")["href"]).to eq(groups_path)
  end

  it "shows membership approval without the admin identity and links to the readable group" do
    group = Group.create!(group_admin: actor, name: "Approved circle", group_type: :approval_group, lifecycle_status: :active)
    event = GroupMembershipEvent.create!(group:, user: recipient, actor:, event_type: :approved)
    Notification.create!(recipient:, actor:, action: :group_membership_approved, notifiable: event)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include("동아리 운영진", group.name, "가입을 승인했습니다")
    expect(article.text).not_to include(actor.name)
    expect(article.at_css("img")).to be_nil
    expect(article.at_css("a")["href"]).to eq(group_path(group))

    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    get notifications_path
    expect(parse_html.at_css("article a")["href"]).to eq(groups_path)
  end

  it "keeps a rejection notification readable after the membership is deleted" do
    group = Group.create!(group_admin: actor, name: "Declined circle", group_type: :approval_group, lifecycle_status: :active)
    membership = group.group_memberships.create!(user: recipient, status: :pending)
    event = GroupMembershipEvent.create!(group:, user: recipient, actor:, event_type: :request_rejected)
    membership.destroy!
    Notification.create!(recipient:, actor:, action: :group_membership_request_rejected, notifiable: event)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(group.name, "가입 신청이 거절되었습니다")
    expect(article.text).not_to include(actor.name, "사유")
    expect(article.at_css("img")).to be_nil
    expect(article.at_css("a")["href"]).to eq(group_path(group))

    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    get notifications_path
    expect(parse_html.at_css("article a")["href"]).to eq(groups_path)
  end

  it "shows a cancelled join request with applicant identity and current members access" do
    group = Group.create!(group_admin: recipient, name: "Approval circle", group_type: :approval_group, lifecycle_status: :active)
    event = GroupMembershipEvent.create!(group:, user: actor, actor:, event_type: :join_request_cancelled)
    Notification.create!(recipient:, actor:, action: :group_membership_join_request_cancelled, notifiable: event)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(actor.name, group.name, "가입 신청을 취소했습니다")
    expect(article.at_css("img")["alt"]).to eq(actor.name)
    expect(article.at_css("a")["href"]).to eq(group_members_path(group))

    group.group_memberships.create!(user: actor, status: :active)
    group.update!(group_admin: actor)
    get notifications_path
    expect(parse_html.at_css("article a")["href"]).to eq(groups_path)
  end

  it "shows removal without the admin identity after membership deletion" do
    group = Group.create!(group_admin: actor, name: "Private circle", group_type: :private_group, lifecycle_status: :active)
    membership = group.group_memberships.create!(user: recipient, status: :active)
    event = GroupMembershipEvent.create!(group:, user: recipient, actor:, event_type: :removed)
    GroupMembershipRemoval.create!(group:, user: recipient, removed_by: actor)
    membership.destroy!
    Notification.create!(recipient:, actor:, action: :group_membership_removed, notifiable: event)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include("동아리 운영진", group.name, "회원님을 내보냈습니다")
    expect(article.text).not_to include(actor.name, "사유")
    expect(article.at_css("img")).to be_nil
    expect(article.at_css("a")["href"]).to eq(groups_path)
  end

  it "shows a ban from its audit attribution without the admin identity or internal note" do
    group = Group.create!(group_admin: actor, name: "Private circle", group_type: :private_group, lifecycle_status: :active)
    membership = group.group_memberships.create!(user: recipient, status: :active)
    ban = group.group_member_bans.create!(user: recipient)
    action = ModerationAction.create!(target: ban, actor:, action_type: :ban_from_group,
                                      public_reason: "Group rule", internal_note: "PRIVATE_NOTE")
    membership.destroy!
    Notification.create!(recipient:, actor:, action: :group_member_banned, notifiable: action)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include("동아리 운영진", group.name, "Group rule")
    expect(article.text).not_to include(actor.name, "PRIVATE_NOTE")
    expect(article.at_css("img")).to be_nil
    expect(article.at_css("a")["href"]).to eq(groups_path)
  end

  it "shows an unban after the ban row is deleted without restoring private group access" do
    group = Group.create!(group_admin: actor, name: "Private circle", group_type: :private_group, lifecycle_status: :active)
    ban = group.group_member_bans.create!(user: recipient)
    original = ModerationAction.create!(target: ban, actor:, action_type: :ban_from_group, public_reason: "Rule")
    action = ModerationAction.create!(target: ban, actor:, action_type: :unban_from_group,
                                      public_reason: "Resolved", internal_note: "PRIVATE_NOTE", reversal_of: original)
    ban.destroy!
    Notification.create!(recipient:, actor:, action: :group_member_unbanned, notifiable: action)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include("동아리 운영진", group.name, "회원 자격은 자동으로 복구되지 않습니다", "Resolved")
    expect(article.text).not_to include(actor.name, "PRIVATE_NOTE")
    expect(article.at_css("img")).to be_nil
    expect(article.at_css("a")["href"]).to eq(groups_path)
  end

  it "links an unban to a currently readable group after the ban row is deleted" do
    group = Group.create!(group_admin: actor, name: "Public circle", group_type: :public_group, lifecycle_status: :active)
    ban = group.group_member_bans.create!(user: recipient)
    original = ModerationAction.create!(target: ban, actor:, action_type: :ban_from_group, public_reason: "Rule")
    action = ModerationAction.create!(target: ban, actor:, action_type: :unban_from_group,
                                      public_reason: "Resolved", reversal_of: original)
    ban.destroy!
    Notification.create!(recipient:, actor:, action: :group_member_unbanned, notifiable: action)
    sign_in recipient

    get notifications_path

    expect(parse_html.at_css("article a")["href"]).to eq(group_path(group))
  end

  it "shows the inviting admin and links an invitation to the club list" do
    group = Group.create!(group_admin: actor, name: "Reading circle", group_type: :private_group, lifecycle_status: :active)
    event = GroupMembershipEvent.create!(group:, user: recipient, actor:, event_type: :invited)
    Notification.create!(recipient:, actor:, action: :group_membership_invited, notifiable: event)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(I18n.t("notifications.messages.group_membership_invited", actor_name: actor.name, group_name: group.name))
    expect(article.at_css("img")["alt"]).to eq(actor.name)
    expect(article.at_css("a")["href"]).to eq(groups_path)
  end

  it "shows invitation acceptance to the current admin and falls back after an admin change" do
    group = Group.create!(group_admin: recipient, name: "Reading circle", group_type: :private_group, lifecycle_status: :active)
    group.group_memberships.create!(user: actor, status: :active)
    event = GroupMembershipEvent.create!(group:, user: actor, actor:, event_type: :invitation_accepted)
    Notification.create!(recipient:, actor:, action: :group_membership_invitation_accepted, notifiable: event)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(I18n.t("notifications.messages.group_membership_invitation_accepted", actor_name: actor.name, group_name: group.name))
    expect(article.at_css("img")["alt"]).to eq(actor.name)
    expect(article.at_css("a")["href"]).to eq(group_members_path(group))

    group.update!(group_admin: actor)
    get notifications_path
    expect(parse_html.at_css("article a")["href"]).to eq(group_path(group))
  end

  it "shows invitation decline after membership deletion and falls back when the former admin loses access" do
    group = Group.create!(group_admin: recipient, name: "Reading circle", group_type: :private_group, lifecycle_status: :active)
    invitation = group.group_memberships.create!(user: actor, status: :invited)
    event = GroupMembershipEvent.create!(group:, user: actor, actor:, event_type: :invitation_declined)
    invitation.destroy!
    Notification.create!(recipient:, actor:, action: :group_membership_invitation_declined, notifiable: event)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(I18n.t("notifications.messages.group_membership_invitation_declined", actor_name: actor.name, group_name: group.name))
    expect(article.at_css("img")["alt"]).to eq(actor.name)
    expect(article.at_css("a")["href"]).to eq(group_members_path(group))

    group.group_memberships.create!(user: actor, status: :active)
    group.update!(group_admin: actor)
    group.group_memberships.find_by!(user: recipient).destroy!
    get notifications_path
    expect(parse_html.at_css("article a")["href"]).to eq(groups_path)
  end

  it "shows invitation revocation after membership deletion and links to the club list" do
    group = Group.create!(group_admin: actor, name: "Reading circle", group_type: :private_group, lifecycle_status: :active)
    invitation = group.group_memberships.create!(user: recipient, status: :invited)
    event = GroupMembershipEvent.create!(group:, user: recipient, actor:, event_type: :invitation_revoked)
    invitation.destroy!
    Notification.create!(recipient:, actor:, action: :group_membership_invitation_revoked, notifiable: event)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(I18n.t("notifications.messages.group_membership_invitation_revoked", actor_name: actor.name, group_name: group.name))
    expect(article.text).to include("초대를 취소했습니다")
    expect(article.text).not_to include("철회")
    expect(article.at_css("img")["alt"]).to eq(actor.name)
    expect(article.at_css("a")["href"]).to eq(groups_path)
  end

  %w[group_membership_invitation_accepted group_membership_invitation_declined].each do |action|
    it "links #{action} to members when the recipient is a global admin" do
      recipient.update!(global_admin: true)
      group = Group.create!(group_admin: actor, name: "Reading circle", group_type: :private_group, lifecycle_status: :active)
      invitee = User.create!(name: "Invitee", email: "#{action}-invitee@example.com", password: "password123!")
      event_type = action.delete_prefix("group_membership_")
      event = GroupMembershipEvent.create!(group:, user: invitee, actor: invitee, event_type:)
      Notification.create!(recipient:, actor: invitee, action:, notifiable: event)
      sign_in recipient

      get notifications_path

      expect(parse_html.at_css("article a")["href"]).to eq(group_members_path(group))
    end
  end

  it "renders a lifecycle request without actor identity or application detail and links eligible admins to review" do
    recipient.update!(global_admin: true)
    group = Group.create!(group_admin: actor, name: "Review club", group_type: :public_group, application_purpose: "PRIVATE_APPLICATION")
    event = GroupLifecycleEvent.create!(group:, actor:, event_type: :opening_requested, detail: "PRIVATE_DETAIL")
    Notification.create!(recipient:, actor:, action: :group_opening_requested, notifiable: event)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include("새 동아리 개설 신청", group.name)
    expect(article.text).not_to include(actor.name, "PRIVATE_APPLICATION", "PRIVATE_DETAIL")
    expect(article.at_css("img")).to be_nil
    expect(article.at_css("a")["href"]).to eq(admin_group_path(group))

    recipient.update!(global_admin: false)
    get notifications_path
    expect(parse_html.at_css("article a")["href"]).to eq(groups_path)
  end

  it "shows a closure without its reason and falls back when the club is unreadable" do
    group = Group.create!(group_admin: actor, name: "Private club", group_type: :private_group, lifecycle_status: :active)
    event = GroupLifecycleEvent.create!(group:, actor:, event_type: :operations_closed, detail: "PRIVATE_CLOSURE")
    Notification.create!(recipient:, actor:, action: :group_operations_closed, notifiable: event)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include("동아리 운영진", group.name)
    expect(article.text).not_to include(actor.name, "PRIVATE_CLOSURE")
    expect(article.at_css("img")).to be_nil
    expect(article.at_css("a")["href"]).to eq(groups_path)
  end

  it "links lifecycle approvals and admin-role changes only to a currently readable group" do
    group = Group.create!(group_admin: actor, name: "Public club", group_type: :public_group, lifecycle_status: :active)
    approval = GroupLifecycleEvent.create!(group:, actor:, event_type: :opening_approved)
    role_change = GroupMembershipEvent.create!(group:, user: recipient, actor:, event_type: :admin_role_granted)
    Notification.create!(recipient:, actor:, action: :group_opening_approved, notifiable: approval)
    Notification.create!(recipient:, actor:, action: :group_admin_role_granted, notifiable: role_change)
    sign_in recipient

    get notifications_path
    articles = parse_html.css("article")
    expect(articles.map { |article| article.at_css("a")["href"] }).to eq([ group_path(group), group_path(group) ])
    expect(articles.map(&:text).join).to include("운영팀", "관리자 권한")
    expect(articles.flat_map { |article| article.css("img") }).to be_empty

    group.update!(group_type: :private_group)
    get notifications_path
    expect(parse_html.css("article a").map { |link| link["href"] }).to eq([ groups_path, groups_path ])
  end

  it "marks unread notifications as read when opening the list" do
    jjaek = actor.jjaeks.create!(target_user: recipient, content: "PROFILE_NOTIFICATION", visibility: :book_friends)
    notification = Notification.notify_profile_jjaek_created(jjaek)
    sign_in recipient

    get notifications_path

    expect(notification.reload.read_at).to be_present
  end

  it "renders newly unread notifications clearly before marking them read" do
    jjaek = actor.jjaeks.create!(target_user: recipient, content: "PROFILE_NOTIFICATION", visibility: :book_friends)
    Notification.notify_profile_jjaek_created(jjaek)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article["class"]).not_to include("opacity-60")
  end

  it "renders already read notifications with weaker visual weight" do
    jjaek = actor.jjaeks.create!(target_user: recipient, content: "PROFILE_NOTIFICATION", visibility: :book_friends)
    Notification.notify_profile_jjaek_created(jjaek).update!(read_at: Time.current)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article["class"]).to include("opacity-60")
  end

  it "does not change a pending book friendship when reading its notification" do
    friendship = actor.requested_book_friendships.create!(addressee: recipient)
    Notification.notify_book_friendship_requested(friendship)
    sign_in recipient

    get notifications_path

    expect(friendship.reload).to be_pending
  end

  it "links a book friendship request notification to the received requests section" do
    friendship = actor.requested_book_friendships.create!(addressee: recipient)
    Notification.notify_book_friendship_requested(friendship)
    sign_in recipient

    get notifications_path

    expect(response.body).to include("/account/relationships#received-book-friend-requests")
  end

  it "shows an accepted request with the actor avatar and profile link after the friendship is deleted" do
    friendship = recipient.requested_book_friendships.create!(addressee: actor, status: :accepted)
    notification = Notification.notify_book_friendship_accepted(friendship)
    friendship.destroy!
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(notification.reload).to be_book_friendship_accepted
    expect(article.text).to include(I18n.t("notifications.messages.book_friendship_accepted", actor_name: actor.name))
    expect(article.at_css("img")["alt"]).to eq(actor.name)
    expect(article.at_css("a")["href"]).to eq(user_path(actor))
  end

  it "links a comment notification to the commented jjaek" do
    jjaek = recipient.jjaeks.create!(content: "COMMENTED_JJAEK")
    comment = jjaek.comments.create!(user: actor, content: "COMMENT_NOTIFICATION")
    Notification.notify_comment_created(comment)
    sign_in recipient

    get notifications_path

    expect(response.body).to include(jjaek_path(jjaek))
    expect(response.body).to include(I18n.t("notifications.messages.comment_created", actor_name: actor.name))
  end

  it "shows the club name for a group comment notification" do
    group = Group.create!(lifecycle_status: :active, group_admin: recipient, name: "함께 읽기", group_type: :private_group)
    group.group_memberships.create!(user: actor, status: :active)
    jjaek = recipient.jjaeks.create!(group:, content: "GROUP_COMMENTED_JJAEK")
    comment = jjaek.comments.create!(user: actor, content: "GROUP_COMMENT_NOTIFICATION")
    Notification.notify_comment_created(comment)
    sign_in recipient

    get notifications_path

    expect(response.body).to include(
      I18n.t("notifications.messages.group_comment_created", actor_name: actor.name, group_name: group.name)
    )
    expect(response.body).to include(jjaek_path(jjaek))
  end

  it "links a requote notification to the new requote" do
    original = recipient.jjaeks.create!(content: "REQUOTE_SOURCE")
    requote = actor.jjaeks.create!(content: "REQUOTE_NOTIFICATION", quoted_jjaek: original)
    Notification.notify_requote_created(requote)
    sign_in recipient

    get notifications_path

    expect(response.body).to include(jjaek_path(requote))
  end

  it "shows platform moderation without the actor identity or internal note" do
    actor.update!(global_admin: true)
    action = ModerationAction.create!(target: recipient, actor:, action_type: :suspend,
                                      public_reason: "other", internal_note: "PRIVATE_INTERNAL_NOTE")
    Notification.create!(recipient:, actor:, action: :user_account_suspended, notifiable: action)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(I18n.t("notifications.authorities.platform"))
    expect(article.text).to include(User.suspension_reason_label("other"))
    expect(article.text).not_to include(actor.name, "PRIVATE_INTERNAL_NOTE")
    expect(article.at_css("img")).to be_nil
    expect(article.at_css("a")["href"]).to eq(user_path(recipient))
  end

  it "shows group moderation as the club team while preserving the jjaek destination" do
    group = Group.create!(lifecycle_status: :active, group_admin: actor, name: "Reading club", group_type: :public_group)
    group.group_memberships.create!(user: recipient, status: :active)
    jjaek = recipient.jjaeks.create!(group:, content: "Moderated post")
    action = ModerationAction.create!(target: jjaek, actor:, action_type: :hide,
                                      public_reason: "other", moderation_authority: "group", internal_note: "PRIVATE_INTERNAL_NOTE")
    Notification.create!(recipient:, actor:, action: :jjaek_hidden, notifiable: action)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(I18n.t("notifications.authorities.group"))
    expect(article.text).to include(I18n.t("jjaeks.moderation.reasons.other"))
    expect(article.text).not_to include(actor.name, "PRIVATE_INTERNAL_NOTE")
    expect(article.at_css("img")).to be_nil
    expect(article.at_css("a")["href"]).to eq(jjaek_path(jjaek))
  end

  it "falls back to the club list when a group operation target is no longer readable" do
    group = Group.create!(lifecycle_status: :active, group_admin: actor, name: "Private club", group_type: :private_group)
    action = ModerationAction.create!(target: group, actor:, action_type: :suspend_group_operation, public_reason: "other")
    Notification.create!(recipient:, actor:, action: :group_operation_suspended, notifiable: action)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(group.name, Group.suspension_reason_label("other"))
    expect(article.at_css("a")["href"]).to eq(groups_path)
  end

  it "falls back safely when a moderated comment has been deleted" do
    jjaek = recipient.jjaeks.create!(content: "Parent")
    comment = jjaek.comments.create!(user: recipient, content: "Comment")
    action = ModerationAction.create!(target: comment, actor:, action_type: :hide,
                                      public_reason: "other", moderation_authority: "platform")
    Notification.create!(recipient:, actor:, action: :comment_hidden, notifiable: action)
    comment.destroy!
    sign_in recipient

    get notifications_path

    expect(parse_html.at_css("article a")["href"]).to eq(user_path(recipient))
  end

  it "links a moderated comment to its readable parent context" do
    jjaek = recipient.jjaeks.create!(content: "Parent")
    comment = jjaek.comments.create!(user: recipient, content: "Comment")
    action = ModerationAction.create!(target: comment, actor:, action_type: :hide,
                                      public_reason: "other", moderation_authority: "platform")
    Notification.create!(recipient:, actor:, action: :comment_hidden, notifiable: action)
    sign_in recipient

    get notifications_path

    expect(parse_html.at_css("article a")["href"]).to eq(jjaek_path(jjaek, anchor: "comment_#{comment.id}"))
  end

  it "does not link to a moderated jjaek that the recipient can no longer read" do
    jjaek = actor.jjaeks.create!(content: "Private post", visibility: :private_jjaek)
    action = ModerationAction.create!(target: jjaek, actor:, action_type: :hide,
                                      public_reason: "other", moderation_authority: "platform")
    Notification.create!(recipient:, actor:, action: :jjaek_hidden, notifiable: action)
    sign_in recipient

    get notifications_path

    expect(parse_html.at_css("article a")["href"]).to eq(user_path(recipient))
  end

  it "shows membership activity suspension as a club action without revealing the admin" do
    group = Group.create!(lifecycle_status: :active, group_admin: actor, name: "Reading circle", group_type: :private_group)
    membership = group.group_memberships.create!(user: recipient, status: :active)
    action = ModerationAction.create!(target: membership, actor:, action_type: :suspend_activity,
                                      public_reason: "Group rule", internal_note: "PRIVATE_INTERNAL_NOTE")
    Notification.create!(recipient:, actor:, action: :group_member_activity_suspended, notifiable: action)
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(I18n.t("notifications.authorities.group"), group.name, "Group rule")
    expect(article.text).not_to include(actor.name, "PRIVATE_INTERNAL_NOTE")
    expect(article.at_css("img")).to be_nil
    expect(article.at_css("a")["href"]).to eq(group_path(group))
  end

  it "shows membership activity restoration and falls back safely after membership removal" do
    group = Group.create!(lifecycle_status: :active, group_admin: actor, name: "Private circle", group_type: :private_group)
    membership = group.group_memberships.create!(user: recipient, status: :active)
    suspension = ModerationAction.create!(target: membership, actor:, action_type: :suspend_activity, public_reason: "Original")
    restoration = ModerationAction.create!(target: membership, actor:, action_type: :restore_activity,
                                           public_reason: "Resolved", internal_note: "PRIVATE_RESTORE_NOTE", reversal_of: suspension)
    Notification.create!(recipient:, actor:, action: :group_member_activity_restored, notifiable: restoration)
    membership.destroy!
    sign_in recipient

    get notifications_path

    article = parse_html.at_css("article")
    expect(article.text).to include(I18n.t("notifications.authorities.group"), group.name, "Resolved")
    expect(article.text).not_to include(actor.name, "PRIVATE_RESTORE_NOTE")
    expect(article.at_css("img")).to be_nil
    expect(article.at_css("a")["href"]).to eq(groups_path)
  end
end
