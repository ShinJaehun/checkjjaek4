require "rails_helper"

RSpec.describe "Admin Jjaek moderation", type: :request do
  let!(:author) { User.create!(name: "Author", email: "admin-jjaek-author@example.com", password: "password123!") }
  let!(:viewer) { User.create!(name: "Viewer", email: "admin-jjaek-viewer@example.com", password: "password123!") }
  let!(:admin) { User.create!(name: "Admin", email: "admin-jjaek-moderator@example.com", password: "password123!", global_admin: true) }

  it "lets only a global admin hide from the existing investigation detail" do
    jjaek = author.jjaeks.create!(content: "ADMIN_HIDE_TARGET")
    sign_in viewer

    patch hide_admin_jjaek_path(jjaek), params: { moderation_action: { public_reason: "other" } }
    expect(jjaek.reload).not_to be_hidden

    sign_in admin
    get jjaek_path(jjaek)
    document = Nokogiri::HTML(response.body)
    reason_select = document.at_css("select[name='moderation_action[public_reason]']")
    expect(document.at_css("#admin_moderation_state").text.squish).to include("콘텐츠 관리", "현재 상태: 공개")
    expect(response.body).to include("숨김")
    expect(reason_select.css("option").map { |option| option["value"] }).to include(*Jjaek::MODERATION_HIDE_REASONS)
    expect(document.at_css("textarea[name='moderation_action[public_reason]']")).to be_nil

    expect {
      patch hide_admin_jjaek_path(jjaek), params: { moderation_action: { public_reason: "undefined_reason" } }
    }.not_to change(ModerationAction, :count)
    expect(jjaek.reload).not_to be_hidden

    patch hide_admin_jjaek_path(jjaek), params: {
      moderation_action: { public_reason: "personal_information", internal_note: "INTERNAL HIDE NOTE" }
    }

    expect(response).to redirect_to(jjaek_path(jjaek))
    expect(jjaek.reload).to be_hidden
    expect(jjaek.current_hide_action).to have_attributes(actor: admin, public_reason: "personal_information", internal_note: "INTERNAL HIDE NOTE")

    get jjaek_path(jjaek)
    document = Nokogiri::HTML(response.body)
    hidden_article = document.at_css("#jjaek_#{jjaek.id}")
    expect(response.body).to include("숨김", "ADMIN_HIDE_TARGET", "개인정보 노출", "INTERNAL HIDE NOTE", admin.name, "좋아요 0개", "댓글 0개")
    expect(hidden_article.at_css("#comment_action_jjaek_#{jjaek.id}")).to be_present
    expect(hidden_article.text).to include("좋아요 0개", "댓글 0개")
    expect(hidden_article.text).not_to include("댓글 보기", "글 보기")
    expect(document.at_css("#admin_moderation_state").text.squish).to include("현재 상태: 숨김")
    expect(document.at_css("#admin_moderation_state #admin_moderation_history")).to be_nil
    expect(document.at_css("#admin_moderation_history_section [data-role='internal-note']")).to be_present
    expect(response.body.index(%(id="jjaek_#{jjaek.id}"))).to be < response.body.index(%(id="comments_panel_jjaek_#{jjaek.id}"))
    expect(response.body.index(%(id="comments_panel_jjaek_#{jjaek.id}"))).to be < response.body.index(%(id="admin_moderation_state"))
    expect(response.body.index(%(id="admin_moderation_state"))).to be < response.body.index(%(id="admin_moderation_history_section"))
    expect(response.body).not_to include(%(action="#{hide_admin_jjaek_path(jjaek)}"))

    expect {
      patch hide_admin_jjaek_path(jjaek), params: { moderation_action: { public_reason: "other" } }
    }.not_to change(ModerationAction, :count)
  end

  it "does not let a global admin hide or restore their own jjaek" do
    own_jjaek = admin.jjaeks.create!(content: "ADMIN OWN MODERATION TARGET")
    sign_in admin

    get jjaek_path(own_jjaek)
    expect(response.body).not_to include(%(action="#{hide_admin_jjaek_path(own_jjaek)}"))

    expect {
      patch hide_admin_jjaek_path(own_jjaek), params: { moderation_action: { public_reason: "other" } }
    }.not_to change(ModerationAction, :count)

    other_admin = User.create!(name: "Other admin", email: "other-admin-hide@example.com", password: "password123!", global_admin: true)
    Jjaeks::Hide.new(own_jjaek, actor: other_admin, public_reason: "other", internal_note: "ADMIN ONLY").call!

    get jjaek_path(own_jjaek)
    expect(response.body).to include("ADMIN OWN MODERATION TARGET", "시스템 관리자에 의해 숨겨진 짹입니다.", "기타", "좋아요 0개", "댓글 0개")
    expect(response.body).not_to include("댓글 보기", "글 보기")
    expect(response.body).not_to include("ADMIN ONLY", "운영 이력", %(action="#{restore_admin_jjaek_path(own_jjaek)}"))

    expect {
      patch restore_admin_jjaek_path(own_jjaek), params: { moderation_action: { public_reason: "Self restore" } }
    }.not_to change(ModerationAction, :count)
    expect(own_jjaek.reload).to be_hidden
  end

  it "restores another user's hidden jjaek with a separate reason and audit history" do
    jjaek = author.jjaeks.create!(content: "RESTORE_REQUEST_TARGET", visibility: :book_friends)
    hide = Jjaeks::Hide.new(
      jjaek,
      actor: admin,
      public_reason: "personal_information",
      internal_note: "HIDE INTERNAL"
    ).call!.current_hide_action
    sign_in admin

    get jjaek_path(jjaek)
    expect(response.body).to include(%(action="#{restore_admin_jjaek_path(jjaek)}"), "복구 사유", "HIDE INTERNAL")

    expect {
      patch restore_admin_jjaek_path(jjaek), params: { moderation_action: { public_reason: "" } }
    }.not_to change(ModerationAction, :count)
    expect(jjaek.reload).to be_hidden

    patch restore_admin_jjaek_path(jjaek), params: {
      moderation_action: { public_reason: "검토 결과 공개 가능", internal_note: "RESTORE INTERNAL" }
    }

    expect(response).to redirect_to(jjaek_path(jjaek))
    expect(jjaek.reload).to have_attributes(hidden_at: nil, visibility: "book_friends")
    restore = jjaek.moderation_actions.action_type_restore.sole
    expect(restore).to have_attributes(reversal_of: hide, public_reason: "검토 결과 공개 가능", internal_note: "RESTORE INTERNAL")
    expect(hide.reload).to have_attributes(public_reason: "personal_information", internal_note: "HIDE INTERNAL")

    get jjaek_path(jjaek)
    expect(response.body).to include("운영 이력", "복구", "개인정보 노출", "검토 결과 공개 가능", "HIDE INTERNAL", "RESTORE INTERNAL")
  end

  it "shows platform and group moderation history with immutable authority sources" do
    group_admin = User.create!(name: "Group moderator", email: "admin-history-group@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "History group", group_type: :private_group)
    group.group_memberships.create!(user: author, status: :active)
    jjaek = author.jjaeks.create!(group:, content: "COMBINED HISTORY TARGET")

    Jjaeks::Hide.new(jjaek, actor: group_admin, public_reason: "other", internal_note: "GROUP HIDE NOTE").call!
    Jjaeks::Restore.new(jjaek, actor: group_admin, public_reason: "Group restore", internal_note: "GROUP RESTORE NOTE").call!
    group_admin.update!(global_admin: true)
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "spam_advertising", internal_note: "PLATFORM HIDE NOTE").call!
    Jjaeks::Restore.new(jjaek, actor: admin, public_reason: "Platform restore", internal_note: "PLATFORM RESTORE NOTE").call!
    sign_in admin

    get jjaek_path(jjaek)

    history = Nokogiri::HTML(response.body).at_css("#admin_moderation_history")
    expect(history).to be_present
    entries = history.css("li")
    actions = jjaek.moderation_actions.order(created_at: :asc, id: :asc)
    expect(entries.map { |entry| entry["data-moderation-action-id"].to_i }).to eq(actions.ids)
    expect(entries[0].text.squish).to include("숨김", "동아리 관리자", "Group moderator", "기타", "GROUP HIDE NOTE", I18n.l(actions[0].created_at, format: :short))
    expect(entries[1].text.squish).to include("복구", "동아리 관리자", "Group moderator", "Group restore", "GROUP RESTORE NOTE", I18n.l(actions[1].created_at, format: :short))
    expect(entries[2].text.squish).to include("숨김", "시스템 관리자", "Admin", "스팸·광고", "PLATFORM HIDE NOTE", I18n.l(actions[2].created_at, format: :short))
    expect(entries[3].text.squish).to include("복구", "시스템 관리자", "Admin", "Platform restore", "PLATFORM RESTORE NOTE", I18n.l(actions[3].created_at, format: :short))
    expect(history.text).not_to include("조치 주체:", "실제 처리자:", "처리 시각:")
  end

  it "does not add unrelated personal or group jjaeks to the home feed after a platform hide" do
    unrelated_author = User.create!(name: "Unrelated author", email: "hidden-feed-unrelated@example.com", password: "password123!")
    unrelated_group = Group.create!(lifecycle_status: :active, group_admin: unrelated_author, name: "Unrelated public group", group_type: :public_group)
    personal_jjaek = unrelated_author.jjaeks.create!(content: "UNRELATED PERSONAL FEED BODY")
    group_jjaek = unrelated_author.jjaeks.create!(group: unrelated_group, content: "UNRELATED GROUP FEED BODY")
    sign_in viewer

    get root_path
    expect(response.body).not_to include(%(id="jjaek_#{personal_jjaek.id}"), %(id="jjaek_#{group_jjaek.id}"))

    Jjaeks::Hide.new(personal_jjaek, actor: admin, public_reason: "other").call!
    Jjaeks::Hide.new(group_jjaek, actor: admin, public_reason: "other").call!

    get root_path
    expect(response.body).not_to include(%(id="jjaek_#{personal_jjaek.id}"), %(id="jjaek_#{group_jjaek.id}"))
    expect(response.body).not_to include("UNRELATED PERSONAL FEED BODY", "UNRELATED GROUP FEED BODY")
  end

  it "shows platform-hidden placeholders in existing feed, profile, book, group, and detail boundaries" do
    book = Book.create!(title: "HIDDEN_CONTEXT_BOOK", authors_text: "Author")
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Hidden context group", group_type: :public_group)
    general = author.jjaeks.create!(content: "HIDDEN_GENERAL_CONTEXT")
    book_jjaek = author.jjaeks.create!(book:, content: "HIDDEN_BOOK_CONTEXT")
    group_jjaek = author.jjaeks.create!(group:, content: "HIDDEN_GROUP_CONTEXT")
    general.likes.create!(user: author)
    general.comments.create!(user: author, content: "EXISTING PLATFORM HIDDEN COMMENT")
    viewer.active_follows.create!(followee: author)
    group.group_memberships.create!(user: viewer, status: :active)
    [ general, book_jjaek, group_jjaek ].each do |jjaek|
      Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "inappropriate_content", internal_note: "PRIVATE PLATFORM NOTE").call!
    end
    admin.update!(global_admin: false)
    sign_in viewer

    get root_path
    home_card = Nokogiri::HTML(response.body).at_css("#jjaek_#{general.id}")
    expect(home_card.text).to include("시스템 관리자에 의해 숨겨진 짹입니다.", "부적절한 내용", "좋아요 1개", "댓글 1개", "댓글 보기", "글 보기")
    expect(home_card.at_css("#comment_action_jjaek_#{general.id}")).to be_present
    expect(home_card.text).not_to include(general.content, "PRIVATE PLATFORM NOTE", "운영 이력", "다시짹")
    expect(home_card.at_css(%(a[href="#{jjaek_comments_path(general, comments_context: :home)}"]))).to be_present
    expect(home_card.at_css(%(a[href="#{jjaek_path(general)}"]))).to be_present
    expect(home_card.at_css(%(form[action="#{jjaek_like_path(general)}"]))).to be_nil
    home_group_card = Nokogiri::HTML(response.body).at_css("#jjaek_#{group_jjaek.id}")
    expect(home_group_card.text).to include("시스템 관리자에 의해 숨겨진 짹입니다.", "부적절한 내용")
    expect(home_group_card.text).not_to include(group_jjaek.content, "PRIVATE PLATFORM NOTE")

    get user_path(author)
    profile = Nokogiri::HTML(response.body)
    [ general, book_jjaek, group_jjaek ].each do |jjaek|
      card = profile.at_css("#jjaek_#{jjaek.id}")
      hidden_title = jjaek.book.present? ? "시스템 관리자에 의해 숨겨진 책짹입니다." : "시스템 관리자에 의해 숨겨진 짹입니다."
      expect(card.text).to include(hidden_title, "부적절한 내용", "댓글 보기", "글 보기")
      expect(card.text).not_to include(jjaek.content, "PRIVATE PLATFORM NOTE")
      expect(card.at_css(%(a[href="#{jjaek_comments_path(jjaek, comments_context: :profile, profile_user_id: author.id)}"]))).to be_present
    end

    get book_path(book)
    book_card = Nokogiri::HTML(response.body).at_css("#jjaek_#{book_jjaek.id}")
    expect(book_card.text).to include("시스템 관리자에 의해 숨겨진 책짹입니다.", "부적절한 내용", "댓글 보기", "글 보기")
    expect(book_card.text).not_to include(book_jjaek.content, "PRIVATE PLATFORM NOTE")
    expect(book_card.at_css(%(a[href="#{jjaek_comments_path(book_jjaek, comments_context: :book, book_id: book.id)}"]))).to be_present

    get group_path(group)
    group_card = Nokogiri::HTML(response.body).at_css("#jjaek_#{group_jjaek.id}")
    expect(group_card.text).to include("시스템 관리자에 의해 숨겨진 짹입니다.", "부적절한 내용", "댓글 보기", "글 보기")
    expect(group_card.text).not_to include(group_jjaek.content, "PRIVATE PLATFORM NOTE")
    expect(group_card.at_css(%(a[href="#{jjaek_comments_path(group_jjaek, comments_context: :group)}"]))).to be_present

    get jjaek_path(general)
    expect(response).to have_http_status(:ok)
    detail = Nokogiri::HTML(response.body)
    expect(detail.text).to include("시스템 관리자에 의해 숨겨진 짹입니다.", "부적절한 내용", "EXISTING PLATFORM HIDDEN COMMENT")
    expect(detail.text).not_to include(general.content, "PRIVATE PLATFORM NOTE", "운영 이력")
    expect(detail.at_css(%(form[action="#{jjaek_comments_path(general)}"]))).to be_nil
    expect(detail.at_css(%(form[action="#{jjaek_like_path(general)}"]))).to be_nil
  end

  it "does not widen private group access for a platform-hidden jjaek" do
    group_admin = User.create!(name: "Private admin", email: "hidden-private-admin@example.com", password: "password123!")
    private_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Hidden private group", group_type: :private_group)
    jjaek = group_admin.jjaeks.create!(group: private_group, content: "PRIVATE GROUP HIDDEN BODY")
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "other").call!
    sign_in viewer

    get group_path(private_group)
    expect(response).to have_http_status(:not_found)
    get jjaek_path(jjaek)
    expect(response).to have_http_status(:redirect)
  end

  it "returns a restored platform-hidden jjaek to ordinary visibility" do
    jjaek = author.jjaeks.create!(content: "RESTORED PLATFORM BODY")
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "other").call!
    Jjaeks::Restore.new(jjaek, actor: admin, public_reason: "Visible again").call!
    viewer.active_follows.create!(followee: author)
    sign_in viewer

    get root_path
    expect(response.body).to include("RESTORED PLATFORM BODY")
    expect(response.body).not_to include("시스템 관리자에 의해 숨겨진 짹입니다.")
  end

  it "shows the author the hidden source and public reason while preserving delete" do
    book = Book.create!(title: "AUTHOR_HIDDEN_BOOK", authors_text: "Hidden author")
    jjaek = author.jjaeks.create!(book:, content: "AUTHOR_HIDDEN_BODY")
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "spam_advertising", internal_note: "ADMIN ONLY NOTE").call!
    action = jjaek.current_hide_action
    sign_in author

    get user_path(author)
    expect(response.body).to include("시스템 관리자에 의해 숨겨진 책짹입니다.", "스팸·광고", "AUTHOR_HIDDEN_BODY", "AUTHOR_HIDDEN_BOOK")
    expect(response.body).not_to include("ADMIN ONLY NOTE")
    expect(response.body.scan(%(id="jjaek_#{jjaek.id}")).size).to eq(1)
    expect(response.body.scan("AUTHOR_HIDDEN_BODY").size).to eq(1)

    get jjaek_path(jjaek)
    expect(response.body).to include("시스템 관리자에 의해 숨겨진 책짹입니다.", "스팸·광고", "AUTHOR_HIDDEN_BODY", "AUTHOR_HIDDEN_BOOK", "삭제")
    expect(response.body).not_to include("ADMIN ONLY NOTE")
    expect(response.body).not_to include(%(href="#{edit_jjaek_path(jjaek)}"))
    patch jjaek_path(jjaek), params: { jjaek: { content: "CHANGED" } }
    expect(jjaek.reload.content).to eq("AUTHOR_HIDDEN_BODY")

    expect { delete jjaek_path(jjaek) }.to change(Jjaek, :count).by(-1)
    expect(ModerationAction.find(action.id)).to have_attributes(target_type: "Jjaek", target_id: jjaek.id, public_reason: "spam_advertising")
  end

  it "keeps read-only actions for the author across every hidden jjaek type" do
    book = Book.create!(title: "AUTHOR READ ACTIONS BOOK", authors_text: "Author")
    group = Group.create!(lifecycle_status: :active, group_admin: viewer, name: "Author read actions group", group_type: :public_group)
    group.group_memberships.create!(user: author, status: :active)
    jjaeks = [
      author.jjaeks.create!(content: "HIDDEN AUTHOR GENERAL"),
      author.jjaeks.create!(book:, content: "HIDDEN AUTHOR BOOK"),
      author.jjaeks.create!(group:, content: "HIDDEN AUTHOR GROUP"),
      author.jjaeks.create!(group:, book:, content: "HIDDEN AUTHOR GROUP BOOK")
    ]

    jjaeks.each do |jjaek|
      jjaek.likes.create!(user: viewer)
      jjaek.comments.create!(user: viewer, content: "READABLE COMMENT #{jjaek.id}")
      Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "other", internal_note: "AUTHOR HIDDEN NOTE").call!
    end
    sign_in author

    get user_path(author)
    profile = Nokogiri::HTML(response.body)
    jjaeks.each do |jjaek|
      card = profile.at_css("#jjaek_#{jjaek.id}")
      expect(card.text).to include(jjaek.content, "좋아요 1개", "댓글 1개", "댓글 보기", "글 보기")
      expect(card.text).not_to include("AUTHOR HIDDEN NOTE", "다시짹")
      expect(card.at_css(%(form[action="#{jjaek_like_path(jjaek)}"]))).to be_nil
    end

    jjaeks.each do |jjaek|
      get jjaek_path(jjaek)
      detail = Nokogiri::HTML(response.body)
      expect(detail.text).to include(jjaek.content, "좋아요 1개", "댓글 1개")
      expect(detail.text).not_to include("댓글 보기", "글 보기")
      expect(detail.text).not_to include("AUTHOR HIDDEN NOTE", "운영 이력", "다시짹")
      expect(detail.at_css(%(form[action="#{jjaek_like_path(jjaek)}"]))).to be_nil
      expect(detail.at_css(%(form[action="#{jjaek_comments_path(jjaek)}"]))).to be_nil
      expect(detail.at_css(%(a[href="#{edit_jjaek_path(jjaek)}"]))).to be_nil
    end
  end

  it "wraps a hidden group jjaek with its source for global admin lists" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Admin hidden list", group_type: :public_group)
    jjaek = author.jjaeks.create!(group:, content: "ADMIN GROUP HIDDEN SOURCE")
    jjaek.likes.create!(user: author)
    jjaek.comments.create!(user: author, content: "ADMIN READABLE COMMENT")
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "other").call!
    sign_in admin

    get group_path(group)

    document = Nokogiri::HTML(response.body)
    wrapper = document.at_css("#jjaek_#{jjaek.id}")
    expect(wrapper.text).to include("시스템 관리자에 의해 숨겨진 짹입니다.", "기타", "ADMIN GROUP HIDDEN SOURCE", "좋아요 1개", "댓글 1개", "댓글 보기", "글 보기")
    expect(response.body.scan(%(id="jjaek_#{jjaek.id}")).size).to eq(1)
    expect(response.body.scan("ADMIN GROUP HIDDEN SOURCE").size).to eq(1)
    expect(wrapper.at_css(%(a[href="#{jjaek_comments_path(jjaek, comments_context: :group)}"]))).to be_present
    expect(wrapper.at_css(%(a[href="#{jjaek_path(jjaek)}"]))).to be_present
    expect(wrapper.at_css(%(form[action="#{jjaek_like_path(jjaek)}"]))).to be_nil
    expect(wrapper.at_css(%(a[href="#{new_jjaek_path(quoted_jjaek_id: jjaek.id)}"]))).to be_nil

    get jjaek_comments_path(jjaek, comments_context: :group),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).to include(%(target="comments_panel_group_jjaek_#{jjaek.id}"), "ADMIN READABLE COMMENT")
    expect(response.body).not_to include(%(action="#{jjaek_comments_path(jjaek)}"))
  end


  it "shows a group admin hidden content in their readable group without internal notes" do
    group_admin = User.create!(name: "Group admin", email: "hidden-group-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Moderated group", group_type: :private_group)
    group.group_memberships.create!(user: author, status: :active)
    jjaek = author.jjaeks.create!(group:, content: "GROUP ADMIN HIDDEN SOURCE")
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "service_disruption", internal_note: "GLOBAL ADMIN INTERNAL").call!
    sign_in group_admin

    get group_path(group)
    expect(response.body).to include("GROUP ADMIN HIDDEN SOURCE", "시스템 관리자에 의해 숨겨진 짹입니다.", "서비스 운영 방해", "좋아요 0개", "댓글 0개", "댓글 보기", "글 보기")
    expect(response.body).not_to include("GLOBAL ADMIN INTERNAL")

    get jjaek_path(jjaek)
    expect(response.body).to include("GROUP ADMIN HIDDEN SOURCE", "서비스 운영 방해", "좋아요 0개", "댓글 0개")
    expect(response.body).not_to include("댓글 보기", "글 보기")
    expect(response.body).not_to include("GLOBAL ADMIN INTERNAL", %(id="admin_moderation_history"), %(action="#{restore_admin_jjaek_path(jjaek)}"))
  end

  it "blocks new interactions and hidden-source disclosure without changing existing rows" do
    source = author.jjaeks.create!(content: "HIDDEN_REQUOTE_SOURCE")
    existing_comment = source.comments.create!(user: viewer, content: "EXISTING COMMENT")
    existing_like = source.likes.create!(user: viewer)
    existing_requote = viewer.jjaeks.create!(content: "EXISTING REQUOTE", quoted_jjaek: source)
    Jjaeks::Hide.new(source, actor: admin, public_reason: "service_disruption").call!
    sign_in viewer

    expect {
      post jjaek_comments_path(source), params: { comment: { content: "BLOCKED COMMENT" } }
    }.not_to change(Comment, :count)
    expect { post jjaek_like_path(source) }.not_to change(Like, :count)
    expect {
      post jjaeks_path, params: { jjaek: { content: "BLOCKED REQUOTE", quoted_jjaek_id: source.id } }
    }.not_to change(Jjaek, :count)

    get jjaek_path(existing_requote)
    expect(response.body).not_to include("HIDDEN_REQUOTE_SOURCE", "EXISTING REQUOTE")
    expect(existing_comment.reload).to be_persisted
    expect(existing_like.reload).to be_persisted
    expect(existing_requote.reload).to have_attributes(quoted_jjaek_id: source.id, quoted_source_deleted_at: nil)

    expect { delete jjaek_like_path(source) }.to change(Like, :count).by(-1)
    expect { delete jjaek_comment_path(source, existing_comment) }.to change(Comment, :count).by(-1)
  end
end
