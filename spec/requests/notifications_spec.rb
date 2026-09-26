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

    expect(response.body).to include("/relationships#received-book-friend-requests")
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
