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

    badge = parse_html.at_css("#notification-badge")
    expect(badge).not_to be_nil
    expect(badge.text.strip).to eq("1")
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
  end

  it "links a requote notification to the new requote" do
    original = recipient.jjaeks.create!(content: "REQUOTE_SOURCE")
    requote = actor.jjaeks.create!(content: "REQUOTE_NOTIFICATION", quoted_jjaek: original)
    Notification.notify_requote_created(requote)
    sign_in recipient

    get notifications_path

    expect(response.body).to include(jjaek_path(requote))
  end
end
