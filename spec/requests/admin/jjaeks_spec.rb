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
    expect(response.body).to include("숨김", "ADMIN_HIDE_TARGET", "개인정보 노출", "INTERNAL HIDE NOTE", admin.name)
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
    expect(response.body).to include("ADMIN OWN MODERATION TARGET", "시스템 관리자에 의해 숨겨진 짹입니다.", "기타")
    expect(response.body).not_to include("ADMIN ONLY", "숨김 이력", %(action="#{restore_admin_jjaek_path(own_jjaek)}"))

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
    expect(response.body).to include("숨김 이력", "숨김 해제", "개인정보 노출", "검토 결과 공개 가능", "HIDE INTERNAL", "RESTORE INTERNAL")
  end

  it "removes hidden jjaeks from ordinary feed, profile, book, group, and direct reads" do
    book = Book.create!(title: "HIDDEN_CONTEXT_BOOK", authors_text: "Author")
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Hidden context group", group_type: :public_group)
    general = author.jjaeks.create!(content: "HIDDEN_GENERAL_CONTEXT")
    book_jjaek = author.jjaeks.create!(book:, content: "HIDDEN_BOOK_CONTEXT")
    group_jjaek = author.jjaeks.create!(group:, content: "HIDDEN_GROUP_CONTEXT")
    viewer.active_follows.create!(followee: author)
    [ general, book_jjaek, group_jjaek ].each do |jjaek|
      Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "inappropriate_content").call!
    end
    sign_in viewer

    get root_path
    expect(response.body).not_to include(general.content)
    get user_path(author)
    expect(response.body).not_to include(general.content, book_jjaek.content, group_jjaek.content)
    get book_path(book)
    expect(response.body).not_to include(book_jjaek.content)
    get group_path(group)
    expect(response.body).not_to include(group_jjaek.content)
    get jjaek_path(general)
    expect(response.body).not_to include(general.content)
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

  it "wraps a hidden group jjaek with its source for global admin lists" do
    group = Group.create!(lifecycle_status: :active, group_admin: author, name: "Admin hidden list", group_type: :public_group)
    jjaek = author.jjaeks.create!(group:, content: "ADMIN GROUP HIDDEN SOURCE")
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "other").call!
    sign_in admin

    get group_path(group)

    document = Nokogiri::HTML(response.body)
    wrapper = document.at_css("#jjaek_#{jjaek.id}")
    expect(wrapper.text).to include("시스템 관리자에 의해 숨겨진 짹입니다.", "기타", "ADMIN GROUP HIDDEN SOURCE")
    expect(response.body.scan(%(id="jjaek_#{jjaek.id}")).size).to eq(1)
    expect(response.body.scan("ADMIN GROUP HIDDEN SOURCE").size).to eq(1)
    expect(wrapper.at_css(%(a[href="#{jjaek_comments_path(jjaek)}"]))).to be_nil
    expect(wrapper.at_css(%(a[href="#{new_jjaek_path(quoted_jjaek_id: jjaek.id)}"]))).to be_nil
  end


  it "shows a group admin hidden content in their readable group without internal notes" do
    group_admin = User.create!(name: "Group admin", email: "hidden-group-admin@example.com", password: "password123!")
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Moderated group", group_type: :private_group)
    group.group_memberships.create!(user: author, status: :active)
    jjaek = author.jjaeks.create!(group:, content: "GROUP ADMIN HIDDEN SOURCE")
    Jjaeks::Hide.new(jjaek, actor: admin, public_reason: "service_disruption", internal_note: "GLOBAL ADMIN INTERNAL").call!
    sign_in group_admin

    get group_path(group)
    expect(response.body).to include("GROUP ADMIN HIDDEN SOURCE", "시스템 관리자에 의해 숨겨진 짹입니다.", "서비스 운영 방해")
    expect(response.body).not_to include("GLOBAL ADMIN INTERNAL")

    get jjaek_path(jjaek)
    expect(response.body).to include("GROUP ADMIN HIDDEN SOURCE", "서비스 운영 방해")
    expect(response.body).not_to include("GLOBAL ADMIN INTERNAL", %(action="#{restore_admin_jjaek_path(jjaek)}"))
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
