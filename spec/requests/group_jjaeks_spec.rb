require "rails_helper"

RSpec.describe "Group Jjaeks", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "group-jjaeks-group_admin@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:member) { User.create!(name: "Member", email: "group-jjaeks-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:pending_user) { User.create!(name: "Pending", email: "group-jjaeks-pending@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:non_member) { User.create!(name: "Non-member", email: "group-jjaeks-non-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "Group Book", authors_text: "Author") }

  it "lets an active member create a group jjaek without a book" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    sign_in member

    expect {
      post group_jjaeks_path(group), params: { jjaek: { content: "Group jjaek" } }
    }.to change(group.jjaeks, :count).by(1)

    expect(group.jjaeks.last.book_id).to be_nil
    expect(response).to redirect_to(group_path(group))
  end

  it "does not create a Jjaek while the group is pending or inactive" do
    group = Group.create!(group_admin: group_admin, name: "Lifecycle", group_type: :public_group, application_purpose: "Read together")
    sign_in group_admin

    expect {
      post group_jjaeks_path(group), params: { jjaek: { content: "Pending" } }
    }.not_to change(Jjaek, :count)

    group.active!
    group.update!(
      lifecycle_status: :inactive,
      closure_reason: "Test closure",
      closed_at: Time.current
    )
    expect {
      post group_jjaeks_path(group), params: { jjaek: { content: "Inactive" } }
    }.not_to change(Jjaek, :count)
  end

  it "lets an active member create a group book jjaek for a shelved book" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    member.bookshelf_entries.create!(book: book)
    sign_in member

    expect {
      post group_jjaeks_path(group), params: { jjaek: { book_id: book.id, content: "Group book jjaek" } }
    }.to change(group.jjaeks, :count).by(1)

    expect(group.jjaeks.last.book).to eq(book)
  end

  it "does not let an activity-suspended member create either kind of group jjaek" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Moderated", group_type: :private_group)
    membership = group.group_memberships.create!(user: member, status: :active, moderation_status: :activity_suspended)
    existing = group_admin.jjaeks.create!(group:, content: "Still readable")
    member.bookshelf_entries.create!(book: book)
    sign_in member

    get group_path(group)
    expect(response.body).to include(existing.content)
    expect(membership).to be_active

    expect {
      post group_jjaeks_path(group), params: { jjaek: { content: "Blocked" } }
      post group_jjaeks_path(group), params: { jjaek: { book_id: book.id, content: "Blocked book" } }
    }.not_to change(Jjaek, :count)
  end

  it "blocks update but allows deletion of an activity-suspended member's group jjaek" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Moderated edits", group_type: :private_group)
    group.group_memberships.create!(user: member, status: :active, moderation_status: :activity_suspended)
    jjaek = member.jjaeks.create!(group:, content: "Before")
    sign_in member

    patch jjaek_path(jjaek), params: { jjaek: { content: "Blocked update" } }
    expect(jjaek.reload.content).to eq("Before")

    expect { delete jjaek_path(jjaek) }.to change(Jjaek, :count).by(-1)
  end

  it "blocks both kinds of new Jjaek and editing during group operation suspension but preserves read and deletion" do
    admin = User.create!(name: "Global admin", email: "group-operation-jjaek-admin@example.com", password: "password123!", global_admin: true)
    group = Group.create!(lifecycle_status: :active, group_admin:, name: "Operation suspended", group_type: :private_group)
    group.group_memberships.create!(user: member, status: :active)
    member.bookshelf_entries.create!(book:)
    existing = member.jjaeks.create!(group:, content: "Preserved")
    Groups::SuspendOperation.new(group, actor: admin, public_reason: "Safety").call!
    sign_in member

    get jjaek_path(existing)
    expect(response).to have_http_status(:ok)
    expect {
      post group_jjaeks_path(group), params: { jjaek: { content: "Blocked" } }
      post group_jjaeks_path(group), params: { jjaek: { book_id: book.id, content: "Blocked book" } }
    }.not_to change(Jjaek, :count)
    patch jjaek_path(existing), params: { jjaek: { content: "Blocked edit" } }
    expect(existing.reload.content).to eq("Preserved")
    expect { delete jjaek_path(existing) }.to change(Jjaek, :count).by(-1)
  end

  it "does not create a group book jjaek for a book outside the member's shelf" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    sign_in member

    expect {
      post group_jjaeks_path(group), params: { jjaek: { book_id: book.id, content: "No shelf" } }
    }.not_to change(Jjaek, :count)

    expect(response).to redirect_to(root_path)
  end

  it "does not let a non-member create either kind of group jjaek" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    non_member.bookshelf_entries.create!(book: book)
    sign_in non_member

    expect {
      post group_jjaeks_path(group), params: { jjaek: { content: "General" } }
      post group_jjaeks_path(group), params: { jjaek: { book_id: book.id, content: "Book" } }
    }.not_to change(Jjaek, :count)
  end

  it "does not let a pending user create either kind of group jjaek" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    group.group_memberships.create!(user: pending_user, status: :pending)
    pending_user.bookshelf_entries.create!(book: book)
    sign_in pending_user

    expect {
      post group_jjaeks_path(group), params: { jjaek: { content: "General" } }
      post group_jjaeks_path(group), params: { jjaek: { book_id: book.id, content: "Book" } }
    }.not_to change(Jjaek, :count)
  end

  it "uses the nested route group instead of a body group_id" do
    route_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Route group", group_type: :public_group)
    other_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Other group", group_type: :public_group)
    sign_in group_admin

    post group_jjaeks_path(route_group), params: { jjaek: { group_id: other_group.id, content: "Scoped" } }

    expect(Jjaek.last.group).to eq(route_group)
  end

  it "does not treat a group_id on the regular endpoint as group context" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Group", group_type: :public_group)
    sign_in group_admin

    post jjaeks_path, params: { group_id: group.id, jjaek: { content: "Regular endpoint" } }

    expect(Jjaek.last.group_id).to be_nil
  end

  it "allows a non-member to view both kinds in a public group" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    general = group_admin.jjaeks.create!(group:, content: "Public general")
    book_jjaek = group_admin.jjaeks.create!(group:, book:, content: "Public book")
    sign_in non_member

    get jjaek_path(general)
    expect(response).to have_http_status(:ok)
    get jjaek_path(book_jjaek)
    expect(response).to have_http_status(:ok)
  end

  it "keeps public content readable after a ban without changing existing content" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Banned public", group_type: :public_group)
    membership = group.group_memberships.create!(user: non_member, status: :active)
    general = non_member.jjaeks.create!(group:, content: "Preserved public content")
    comment = general.comments.create!(user: non_member, content: "Preserved comment")
    like = general.likes.create!(user: non_member)

    GroupMemberBans::Ban.new(membership, actor: group_admin, public_reason: "Rule").call!
    sign_in non_member
    get jjaek_path(general)

    expect(response).to have_http_status(:ok)
    expect(Jjaek.exists?(general.id)).to be(true)
    expect(Comment.exists?(comment.id)).to be(true)
    expect(Like.exists?(like.id)).to be(true)
  end

  it "removes approval content access after a ban" do
    approval_group = Group.create!(
    lifecycle_status: :active,
    group_admin: group_admin,
    name: "Banned approval",
    group_type: :approval_group
    )
    approval_membership = approval_group.group_memberships.create!(
    user: member,
    status: :active
    )
    approval_jjaek = group_admin.jjaeks.create!(
    group: approval_group,
    content: "Approval restricted"
    )

    GroupMemberBans::Ban.new(
    approval_membership,
    actor: group_admin,
    public_reason: "Rule"
    ).call!

    sign_in member

    get jjaek_path(approval_jjaek)

    expect(response).to have_http_status(:not_found)
    end

  it "removes private content access after a ban" do
    private_group = Group.create!(
    lifecycle_status: :active,
    group_admin: group_admin,
    name: "Banned private",
    group_type: :private_group
    )
    private_membership = private_group.group_memberships.create!(
    user: member,
    status: :active
    )
    private_jjaek = group_admin.jjaeks.create!(
    group: private_group,
    content: "Private restricted"
    )

    GroupMemberBans::Ban.new(
    private_membership,
    actor: group_admin,
    public_reason: "Rule"
    ).call!

    sign_in member

    get jjaek_path(private_jjaek)

    expect(response).to have_http_status(:not_found)
  end


  it "denies direct access to a group jjaek for an approval group non-member" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    general = group_admin.jjaeks.create!(group:, content: "Approval general")
    sign_in non_member

    get jjaek_path(general)
    expect(response).to have_http_status(:not_found)
  end

  it "denies direct access to a group book jjaek for an approval group non-member" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    book_jjaek = group_admin.jjaeks.create!(group:, book:, content: "Approval book")
    sign_in non_member

    get jjaek_path(book_jjaek)

    expect(response).to have_http_status(:not_found)
  end

  it "denies direct access to a group jjaek for a private group non-member" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    general = group_admin.jjaeks.create!(group:, content: "Private general")
    sign_in non_member

    get jjaek_path(general)

    expect(response).to have_http_status(:not_found)
  end

  it "denies direct access to a group book jjaek for a private group non-member" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    book_jjaek = group_admin.jjaeks.create!(group:, book:, content: "Private book")
    sign_in non_member

    get jjaek_path(book_jjaek)

    expect(response).to have_http_status(:not_found)
  end

  it "allows active members to access approval and private group jjaeks directly" do
    approval_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    approval_group.group_memberships.create!(user: member, status: :active)
    private_group.group_memberships.create!(user: member, status: :active)
    approval_jjaek = group_admin.jjaeks.create!(group: approval_group, content: "Approval member content")
    private_jjaek = group_admin.jjaeks.create!(group: private_group, content: "Private member content")
    sign_in member

    get jjaek_path(approval_jjaek)
    expect(response).to have_http_status(:ok)
    get jjaek_path(private_jjaek)
    expect(response).to have_http_status(:ok)
  end

  it "shows edit and delete actions to an active author in the existing header action area" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Group jjaek")
    sign_in member

    get group_path(group)

    header = Nokogiri::HTML(response.body).at_css("article > div:first-child")
    expect(header.to_html).to include(edit_jjaek_path(jjaek), jjaek_path(jjaek))
    expect(header.text).to match(/수정.*삭제/m)
  end

  it "does not show edit or delete actions for another user's group jjaek" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Member jjaek")
    sign_in group_admin

    get group_path(group)

    expect(response.body).not_to include(edit_jjaek_path(jjaek))
    expect(response.body).not_to include(%(action="#{jjaek_path(jjaek)}"))
  end

  it "edits only the content of a group jjaek without showing visibility" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    other_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Other", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Before", visibility: :public_jjaek)
    quoted_jjaek = group_admin.jjaeks.create!(content: "Quoted")
    sign_in member

    get edit_jjaek_path(jjaek)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(group.name)
    expect(response.body).not_to include(%(name="jjaek[visibility]"))

    patch jjaek_path(jjaek), params: {
      jjaek: {
        content: "Changed",
        visibility: :private_jjaek,
        group_id: other_group.id,
        quoted_jjaek_id: quoted_jjaek.id,
        target_user_id: non_member.id
      }
    }

    expect(response).to redirect_to(jjaek_path(jjaek))
    expect(jjaek.reload.content).to eq("Changed")
    expect(jjaek.visibility).to eq("public_jjaek")
    expect(jjaek.group).to eq(group)
    expect(jjaek.quoted_jjaek).to be_nil
    expect(jjaek.target_user).to be_nil
  end

  it "keeps the book association while editing a group book jjaek" do
    other_book = Book.create!(title: "Other Book", authors_text: "Other Author")
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, book:, content: "Before")
    sign_in member

    patch jjaek_path(jjaek), params: { jjaek: { content: "After", book_id: other_book.id } }

    expect(jjaek.reload.content).to eq("After")
    expect(jjaek.book).to eq(book)
  end

  it "rerenders an invalid group edit with the entered content and no visibility field" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Before")
    sign_in member

    patch jjaek_path(jjaek), params: { jjaek: { content: "" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(%(name="jjaek[content]"))
    expect(response.body).not_to include(%(name="jjaek[visibility]"))
    expect(jjaek.reload.content).to eq("Before")
  end

  it "returns not found when a former author tries to update" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    jjaek = member.jjaeks.create!(group:, content: "Before")
    sign_in member

    patch jjaek_path(jjaek), params: { jjaek: { content: "Former change" } }

    expect(response).to have_http_status(:not_found)
    expect(jjaek.reload.content).to eq("Before")
  end

  it "lets a former author delete an inaccessible old private-group jjaek and redirects safely" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    jjaek = member.jjaeks.create!(group:, content: "Former secret")
    sign_in member

    expect { delete jjaek_path(jjaek) }.to change(Jjaek, :count).by(-1)
    expect(response).to redirect_to(groups_path)
    expect(response.body).not_to include("Former secret")
  end

  it "tombstones a group book jjaek with comments and preserves its book and conversation" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, book:, content: "Group discussion")
    comment = jjaek.comments.create!(user: group_admin, content: "Existing comment")
    sign_in member

    expect { delete jjaek_path(jjaek) }.not_to change(Jjaek, :count)

    expect(jjaek.reload).to be_deleted
    expect(jjaek.book).to eq(book)
    expect(jjaek.comments).to contain_exactly(comment)
    expect(response).to redirect_to(group_path(group))
  end

  it "does not let the group_admin delete another member's group jjaek" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Member jjaek")
    sign_in group_admin

    expect { delete jjaek_path(jjaek) }.not_to change(Jjaek, :count)
  end

  it "keeps group book jjaeks out of the general book timeline" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group_book_jjaek = group_admin.jjaeks.create!(group:, book:, content: "Group-only book jjaek")
    sign_in non_member

    get book_path(book)

    expect(response.body).not_to include(group_book_jjaek.content)
  end

  it "shows group jjaeks on the author profile only when the viewer can read the group" do
    public_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    approval_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    public_jjaek = group_admin.jjaeks.create!(group: public_group, content: "Profile public group jjaek")
    approval_jjaek = group_admin.jjaeks.create!(group: approval_group, book:, content: "Profile approval group book jjaek")
    sign_in non_member

    get user_path(group_admin)

    expect(response.body).to include(public_jjaek.content)
    expect(response.body).not_to include(approval_jjaek.content)

    approval_group.group_memberships.create!(user: non_member, status: :active)
    get user_path(group_admin)

    expect(response.body).to include(public_jjaek.content, approval_jjaek.content)
  end

  it "renders comments and likes but not unsupported requotes for group jjaeks" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    jjaek = group_admin.jjaeks.create!(group:, content: "Read only group jjaek")
    sign_in group_admin

    get group_path(group)

    expect(response.body).to include(edit_jjaek_path(jjaek))
    expect(response.body).to include(
      jjaek_comments_path(jjaek, comments_context: "group")
    )
    expect(response.body).to include(jjaek_like_path(jjaek))
    expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: jjaek.id))
  end

  it "shows the book search context only to an active member" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)

    sign_in member
    get book_search_path(group_id: group.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(group.name)

    sign_in non_member
    get book_search_path(group_id: group.id)
    expect(response).to redirect_to(root_path)
  end

  it "shows the group book jjaek form without a visibility selector for a shelved book" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    member.bookshelf_entries.create!(book: book)
    sign_in member

    get book_path(book, group_id: group.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("groups.jjaeks.tabs.general"), I18n.t("groups.jjaeks.tabs.book"))
    expect(response.body).not_to include(%(name="jjaek[visibility]"))
    expect(response.body).to include(group_jjaeks_path(group))
  end

  it "keeps group context while adding a searched book to the shelf" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    sign_in member

    get book_path(book, group_id: group.id)

    expect(response.body).not_to include(group_jjaeks_path(group))
    expect(response.body).to include(%(name="group_id"))
    expect(response.body).to include(%(value="#{group.id}"))

    post bookshelf_entries_path, params: { book_id: book.id, group_id: group.id }

    expect(response).to redirect_to(book_path(book, group_id: group.id))
    expect(member.bookshelf_entries.exists?(book: book)).to be(true)
  end
end
