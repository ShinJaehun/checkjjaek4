require "rails_helper"

RSpec.describe "Private profile conversations", type: :request do
  let(:author) { User.create!(name: "Conversation author", email: "conversation-author@example.com", password: "password123!") }
  let(:owner) { User.create!(name: "Profile owner", email: "conversation-owner@example.com", password: "password123!") }
  let(:third_party) { User.create!(name: "Third reader", email: "conversation-third@example.com", password: "password123!") }
  let!(:friendship) { BookFriendship.create!(requester: author, addressee: owner, status: :accepted) }
  let!(:conversation) do
    author.jjaeks.create!(target_user: owner, content: "PRIVATE_CONVERSATION_BODY #둘만의대화",
                         visibility: :public_jjaek, created_at: 2.days.ago)
  end
  let!(:reply) { conversation.comments.create!(user: owner, content: "PRIVATE_CONVERSATION_REPLY") }
  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }

  it "keeps the conversation and replies on both profiles, home, and detail after friendship ends" do
    friendship.destroy!

    [ author, owner ].each do |participant|
      sign_in participant
      [ root_path, user_path(author), user_path(owner), jjaek_path(conversation) ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("PRIVATE_CONVERSATION_BODY")
      end
      get jjaek_comments_path(conversation), headers: turbo_headers
      expect(response.body).to include(reply.content)
      sign_out participant
    end
  end

  it "excludes the conversation from a mutual friend's lists, search, tag search, detail, and comments" do
    BookFriendship.create!(requester: third_party, addressee: author, status: :accepted)
    BookFriendship.create!(requester: third_party, addressee: owner, status: :accepted)
    third_party.active_follows.create!(followee: author)
    sign_in third_party

    [ root_path, user_path(author), user_path(owner),
      search_path(q: "PRIVATE_CONVERSATION"), search_path(tag: "둘만의대화"), discovery_path ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("PRIVATE_CONVERSATION_BODY", reply.content)
      expect(response.body).not_to include(%(id="jjaek_#{conversation.id}"))
    end
    get jjaek_path(conversation)
    expect(response).to redirect_to(root_path)
    [ {}, turbo_headers ].each do |headers|
      get jjaek_comments_path(conversation), headers: headers
      expect(response).to redirect_to(root_path)
      expect(response.body).not_to include(conversation.content, reply.content)
    end
  end

  it "ignores forged visibility on creation and editing and blocks new conversations after friendship ends" do
    sign_in author
    expect {
      post jjaeks_path, params: { jjaek: { target_user_id: owner.id, content: "New private conversation", visibility: :public_jjaek } }
    }.to change(Jjaek, :count).by(1)
    created = Jjaek.last
    expect(created).to be_book_friends
    expect(created.target_user).to eq(owner)
    expect(Notification.last).to have_attributes(recipient: owner, actor: author, action: "profile_jjaek_created")

    patch jjaek_path(conversation), params: { jjaek: { content: "Edited conversation", visibility: :private_jjaek, target_user_id: third_party.id } }
    expect(conversation.reload).to have_attributes(content: "Edited conversation", visibility: "public_jjaek", target_user_id: owner.id)
    get edit_jjaek_path(conversation)
    expect(response.body).to include(I18n.t("jjaeks.form.profile_conversation"))
    expect(Nokogiri::HTML(response.body).css("[name='jjaek[visibility]']")).to be_empty

    friendship.destroy!
    expect {
      post jjaeks_path, params: { jjaek: { target_user_id: owner.id, content: "Forbidden new conversation" } }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)
    expect(JjaekPolicy.new(owner, conversation)).to be_show
  end

  it "blocks new third-party comments and likes and disallows editing a historical third-party comment" do
    old_comment = conversation.comments.create!(user: third_party, content: "Old third-party comment")
    sign_in third_party

    expect {
      post jjaek_comments_path(conversation), params: { comment: { content: "Forbidden reply" } }, headers: turbo_headers
    }.not_to change(Comment, :count)
    expect(response).to redirect_to(root_path)
    expect { post jjaek_like_path(conversation) }.not_to change(Like, :count)
    expect(response).to redirect_to(root_path)
    expect {
      post jjaeks_path, params: { jjaek: { quoted_jjaek_id: conversation.id, content: "Forbidden quote" } }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)
    patch jjaek_comment_path(conversation, old_comment), params: { comment: { content: "Forbidden edit" } }
    expect(old_comment.reload.content).to eq("Old third-party comment")
    expect(CommentPolicy.new(third_party, old_comment)).not_to be_update
  end

  it "only offers historical own reactions at the existing detail URL and safely removes them in HTML and Turbo" do
    own_comment = conversation.comments.create!(user: third_party, content: "MY_OLD_COMMENT")
    own_like = conversation.likes.create!(user: third_party)
    owner_like = conversation.likes.create!(user: owner)
    sign_in third_party

    get jjaek_path(conversation)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_comment.content, jjaek_comment_path(conversation, own_comment), jjaek_like_path(conversation))
    expect(response.body).not_to include("PRIVATE_CONVERSATION_BODY", reply.content, author.name, owner.name)
    expect { delete jjaek_comment_path(conversation, reply) }.not_to change(Comment, :count)
    expect(response).to redirect_to(root_path)

    expect { delete jjaek_comment_path(conversation, own_comment), headers: turbo_headers }.to change(Comment, :count).by(-1)
    expect(response).to redirect_to(jjaek_path(conversation))
    expect(response.body).not_to include("PRIVATE_CONVERSATION_BODY", reply.content)
    follow_redirect!
    expect(response.body).not_to include("PRIVATE_CONVERSATION_BODY", reply.content)

    expect { delete jjaek_like_path(conversation) }.to change(Like, :count).by(-1)
    expect(response).to redirect_to(root_path)
    expect(Like.exists?(own_like.id)).to be(false)
    expect(owner_like.reload).to be_persisted
    get jjaek_path(conversation)
    expect(response).to redirect_to(root_path)
  end

  it "does not render a like summary or other comments in a Turbo unlike response to a hidden tombstone" do
    own_like = conversation.likes.create!(user: third_party)
    moderator = User.create!(name: "Moderator", email: "conversation-moderator@example.com", password: "password123!", global_admin: true)
    Jjaeks::Hide.new(conversation, actor: moderator, public_reason: "other").call!
    conversation.destroy_or_tombstone!

    [ author, owner ].each do |participant|
      sign_in participant
      get jjaek_path(conversation)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(reply.content)
      expect(response.body).not_to include("PRIVATE_CONVERSATION_BODY")
      sign_out participant
    end
    sign_in third_party

    expect { delete jjaek_like_path(conversation), headers: turbo_headers }.to change(Like, :count).by(-1)
    expect(response).to redirect_to(root_path)
    expect(response.body).not_to include(reply.content, "like_action_jjaek", "comments_panel")
    expect(Like.exists?(own_like.id)).to be(false)
    expect(reply.reload).to be_persisted
    get jjaek_path(conversation)
    expect(response).to redirect_to(root_path)
  end

  it "notifies the other participant on replies in either direction after friendship ends" do
    friendship.destroy!

    [ [ owner, author ], [ author, owner ] ].each do |actor, recipient|
      sign_in actor
      expect {
        post jjaek_comments_path(conversation), params: { comment: { content: "Reply from #{actor.name}" } }
      }.to change(Notification, :count).by(1)
      expect(Notification.last).to have_attributes(actor:, recipient:, action: "comment_created", notifiable: Comment.last)
      expect { post jjaek_like_path(conversation) }.to change(Like, :count).by(1)
      sign_out actor
    end
    expect(Notification.where(recipient_id: third_party.id)).to be_empty
  end

  it "blocks new personal quotes and group shares for participants at GET and POST endpoints" do
    group = Group.create!(group_admin: owner, name: "Writable destination", lifecycle_status: :active)
    [ author, owner ].each do |participant|
      group.group_memberships.create!(user: participant, status: :active) unless participant == owner
      sign_in participant
      [ new_jjaek_path(quoted_jjaek_id: conversation.id), new_jjaek_path(quoted_jjaek_id: conversation.id, share_to_group: 1) ].each do |path|
        get path
        expect(response).to redirect_to(root_path)
        expect(response.body).not_to include("PRIVATE_CONVERSATION_BODY")
      end
      [ { quoted_jjaek_id: conversation.id }, { quoted_jjaek_id: conversation.id, group_id: group.id } ].each do |attributes|
        expect {
          post jjaeks_path, params: { jjaek: attributes.merge(content: "Forbidden quote") }
        }.not_to change(Jjaek, :count)
      end
      sign_out participant
    end
  end

  it "preserves legacy personal and group quotes but hides their source, replies, and notifications from third parties" do
    source = author.jjaeks.create!(content: "LEGACY_CONVERSATION_SOURCE")
    group = Group.create!(group_admin: third_party, name: "LEGACY_SHARE_GROUP", lifecycle_status: :active)
    personal = third_party.jjaeks.create!(quoted_jjaek: source, content: "LEGACY_PERSONAL_QUOTE")
    shared = third_party.jjaeks.create!(group:, quoted_jjaek: source, content: "LEGACY_GROUP_QUOTE")
    comment = shared.comments.create!(user: owner, content: "LEGACY_QUOTE_REPLY")
    Notification.create!(recipient: third_party, actor: author, action: :profile_jjaek_created, notifiable: source)
    Notification.create!(recipient: third_party, actor: owner, action: :comment_created, notifiable: comment)
    Notification.create!(recipient: third_party, actor: author, action: :requote_created, notifiable: shared)
    source.update!(target_user: owner)
    sign_in third_party

    [ root_path, user_path(third_party), group_path(group), search_path(q: "LEGACY") ].each do |path|
      get path
      expect(response.body).not_to include(source.content, personal.content, shared.content, comment.content)
    end
    get jjaek_path(personal)
    expect(response).to redirect_to(root_path)
    get jjaek_path(shared)
    expect(response).to have_http_status(:not_found)
    get jjaek_comments_path(shared), headers: turbo_headers
    expect(response).to have_http_status(:not_found)
    get notifications_path
    expect(response.body).to include(I18n.t("notifications.messages.profile_jjaek_unavailable"), I18n.t("notifications.messages.comment_unavailable"), I18n.t("notifications.messages.requote_unavailable"))
    expect(response.body).not_to include(source.content, group.name, comment.content, author.name, owner.name)
    expect(personal.reload.quoted_jjaek_id).to eq(source.id)
    expect(shared.reload.quoted_jjaek_id).to eq(source.id)
    expect(comment.reload).to be_persisted
  end
end
