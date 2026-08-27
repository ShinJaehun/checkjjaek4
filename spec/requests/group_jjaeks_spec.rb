require "rails_helper"

RSpec.describe "Group Jjaeks", type: :request do
  let!(:owner) { User.create!(name: "Owner", email: "group-jjaeks-owner@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:member) { User.create!(name: "Member", email: "group-jjaeks-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:pending_user) { User.create!(name: "Pending", email: "group-jjaeks-pending@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:non_member) { User.create!(name: "Non-member", email: "group-jjaeks-non-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let!(:book) { Book.create!(title: "Group Book", authors_text: "Author") }

  it "lets an active member create a group jjaek without a book" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    sign_in member

    expect {
      post group_jjaeks_path(group), params: { jjaek: { content: "Group jjaek" } }
    }.to change(group.jjaeks, :count).by(1)

    expect(group.jjaeks.last.book_id).to be_nil
    expect(response).to redirect_to(group_path(group))
  end

  it "does not create a Jjaek while the group is pending or inactive" do
    group = Group.create!(owner: owner, name: "Lifecycle", group_type: :public_group, application_purpose: "Read together")
    sign_in owner

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
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    member.bookshelf_entries.create!(book: book)
    sign_in member

    expect {
      post group_jjaeks_path(group), params: { jjaek: { book_id: book.id, content: "Group book jjaek" } }
    }.to change(group.jjaeks, :count).by(1)

    expect(group.jjaeks.last.book).to eq(book)
  end

  it "does not create a group book jjaek for a book outside the member's shelf" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    sign_in member

    expect {
      post group_jjaeks_path(group), params: { jjaek: { book_id: book.id, content: "No shelf" } }
    }.not_to change(Jjaek, :count)

    expect(response).to redirect_to(root_path)
  end

  it "does not let a non-member create either kind of group jjaek" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    non_member.bookshelf_entries.create!(book: book)
    sign_in non_member

    expect {
      post group_jjaeks_path(group), params: { jjaek: { content: "General" } }
      post group_jjaeks_path(group), params: { jjaek: { book_id: book.id, content: "Book" } }
    }.not_to change(Jjaek, :count)
  end

  it "does not let a pending user create either kind of group jjaek" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Approval", group_type: :approval_group)
    group.group_memberships.create!(user: pending_user, status: :pending)
    pending_user.bookshelf_entries.create!(book: book)
    sign_in pending_user

    expect {
      post group_jjaeks_path(group), params: { jjaek: { content: "General" } }
      post group_jjaeks_path(group), params: { jjaek: { book_id: book.id, content: "Book" } }
    }.not_to change(Jjaek, :count)
  end

  it "uses the nested route group instead of a body group_id" do
    route_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Route group", group_type: :public_group)
    other_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Other group", group_type: :public_group)
    sign_in owner

    post group_jjaeks_path(route_group), params: { jjaek: { group_id: other_group.id, content: "Scoped" } }

    expect(Jjaek.last.group).to eq(route_group)
  end

  it "does not treat a group_id on the regular endpoint as group context" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Group", group_type: :public_group)
    sign_in owner

    post jjaeks_path, params: { group_id: group.id, jjaek: { content: "Regular endpoint" } }

    expect(Jjaek.last.group_id).to be_nil
  end

  it "allows a non-member to view both kinds in a public group" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    general = owner.jjaeks.create!(group:, content: "Public general")
    book_jjaek = owner.jjaeks.create!(group:, book:, content: "Public book")
    sign_in non_member

    get jjaek_path(general)
    expect(response).to have_http_status(:ok)
    get jjaek_path(book_jjaek)
    expect(response).to have_http_status(:ok)
  end

  it "denies direct access to a group jjaek for an approval group non-member" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Approval", group_type: :approval_group)
    general = owner.jjaeks.create!(group:, content: "Approval general")
    sign_in non_member

    get jjaek_path(general)
    expect(response).to have_http_status(:not_found)
  end

  it "denies direct access to a group book jjaek for an approval group non-member" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Approval", group_type: :approval_group)
    book_jjaek = owner.jjaeks.create!(group:, book:, content: "Approval book")
    sign_in non_member

    get jjaek_path(book_jjaek)

    expect(response).to have_http_status(:not_found)
  end

  it "denies direct access to a group jjaek for a private group non-member" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Private", group_type: :private_group)
    general = owner.jjaeks.create!(group:, content: "Private general")
    sign_in non_member

    get jjaek_path(general)

    expect(response).to have_http_status(:not_found)
  end

  it "denies direct access to a group book jjaek for a private group non-member" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Private", group_type: :private_group)
    book_jjaek = owner.jjaeks.create!(group:, book:, content: "Private book")
    sign_in non_member

    get jjaek_path(book_jjaek)

    expect(response).to have_http_status(:not_found)
  end

  it "allows active members to access approval and private group jjaeks directly" do
    approval_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Approval", group_type: :approval_group)
    private_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Private", group_type: :private_group)
    approval_group.group_memberships.create!(user: member, status: :active)
    private_group.group_memberships.create!(user: member, status: :active)
    approval_jjaek = owner.jjaeks.create!(group: approval_group, content: "Approval member content")
    private_jjaek = owner.jjaeks.create!(group: private_group, content: "Private member content")
    sign_in member

    get jjaek_path(approval_jjaek)
    expect(response).to have_http_status(:ok)
    get jjaek_path(private_jjaek)
    expect(response).to have_http_status(:ok)
  end

  it "shows edit and delete actions to an active author in the existing header action area" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Group jjaek")
    sign_in member

    get group_path(group)

    header = Nokogiri::HTML(response.body).at_css("article > div:first-child")
    expect(header.to_html).to include(edit_jjaek_path(jjaek), jjaek_path(jjaek))
    expect(header.text).to match(/수정.*삭제/m)
  end

  it "does not show edit or delete actions for another user's group jjaek" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Member jjaek")
    sign_in owner

    get group_path(group)

    expect(response.body).not_to include(edit_jjaek_path(jjaek))
    expect(response.body).not_to include(%(action="#{jjaek_path(jjaek)}"))
  end

  it "edits only the content of a group jjaek without showing visibility" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    other_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Other", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Before", visibility: :public_jjaek)
    quoted_jjaek = owner.jjaeks.create!(content: "Quoted")
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
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, book:, content: "Before")
    sign_in member

    patch jjaek_path(jjaek), params: { jjaek: { content: "After", book_id: other_book.id } }

    expect(jjaek.reload.content).to eq("After")
    expect(jjaek.book).to eq(book)
  end

  it "rerenders an invalid group edit with the entered content and no visibility field" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Before")
    sign_in member

    patch jjaek_path(jjaek), params: { jjaek: { content: "" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(%(name="jjaek[content]"))
    expect(response.body).not_to include(%(name="jjaek[visibility]"))
    expect(jjaek.reload.content).to eq("Before")
  end

  it "returns not found when an inactive author tries to update" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Approval", group_type: :approval_group)
    group.group_memberships.create!(user: member, status: :inactive)
    jjaek = member.jjaeks.create!(group:, content: "Before")
    sign_in member

    patch jjaek_path(jjaek), params: { jjaek: { content: "Inactive change" } }

    expect(response).to have_http_status(:not_found)
    expect(jjaek.reload.content).to eq("Before")
  end

  it "returns not found when a former author tries to update" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Approval", group_type: :approval_group)
    jjaek = member.jjaeks.create!(group:, content: "Before")
    sign_in member

    patch jjaek_path(jjaek), params: { jjaek: { content: "Former change" } }

    expect(response).to have_http_status(:not_found)
    expect(jjaek.reload.content).to eq("Before")
  end

  it "lets an inactive author delete an old private-group jjaek and redirects to the group" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Private", group_type: :private_group)
    group.group_memberships.create!(user: member, status: :inactive)
    jjaek = member.jjaeks.create!(group:, content: "Inactive secret")
    sign_in member

    expect { delete jjaek_path(jjaek) }.to change(Jjaek, :count).by(-1)
    expect(response).to redirect_to(group_path(group))
    expect(response.body).not_to include("Inactive secret")
  end

  it "lets a former author delete an inaccessible old private-group jjaek and redirects safely" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Private", group_type: :private_group)
    jjaek = member.jjaeks.create!(group:, content: "Former secret")
    sign_in member

    expect { delete jjaek_path(jjaek) }.to change(Jjaek, :count).by(-1)
    expect(response).to redirect_to(groups_path)
    expect(response.body).not_to include("Former secret")
  end

  it "tombstones a group book jjaek with comments and preserves its book and conversation" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, book:, content: "Group discussion")
    comment = jjaek.comments.create!(user: owner, content: "Existing comment")
    sign_in member

    expect { delete jjaek_path(jjaek) }.not_to change(Jjaek, :count)

    expect(jjaek.reload).to be_deleted
    expect(jjaek.book).to eq(book)
    expect(jjaek.comments).to contain_exactly(comment)
    expect(response).to redirect_to(group_path(group))
  end

  it "does not let the owner delete another member's group jjaek" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Member jjaek")
    sign_in owner

    expect { delete jjaek_path(jjaek) }.not_to change(Jjaek, :count)
  end

  it "keeps group book jjaeks out of the general book timeline" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    group_book_jjaek = owner.jjaeks.create!(group:, book:, content: "Group-only book jjaek")
    sign_in non_member

    get book_path(book)

    expect(response.body).not_to include(group_book_jjaek.content)
  end

  it "shows group jjaeks on the author profile only when the viewer can read the group" do
    public_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    approval_group = Group.create!(lifecycle_status: :active, owner: owner, name: "Approval", group_type: :approval_group)
    public_jjaek = owner.jjaeks.create!(group: public_group, content: "Profile public group jjaek")
    approval_jjaek = owner.jjaeks.create!(group: approval_group, book:, content: "Profile approval group book jjaek")
    sign_in non_member

    get user_path(owner)

    expect(response.body).to include(public_jjaek.content)
    expect(response.body).not_to include(approval_jjaek.content)

    approval_group.group_memberships.create!(user: non_member, status: :active)
    get user_path(owner)

    expect(response.body).to include(public_jjaek.content, approval_jjaek.content)
  end

  it "renders comments and likes but not unsupported requotes for group jjaeks" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
    jjaek = owner.jjaeks.create!(group:, content: "Read only group jjaek")
    sign_in owner

    get group_path(group)

    expect(response.body).to include(edit_jjaek_path(jjaek))
    expect(response.body).to include(
      jjaek_comments_path(jjaek, comments_context: "group")
    )
    expect(response.body).to include(jjaek_like_path(jjaek))
    expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: jjaek.id))
  end

  it "shows the book search context only to an active member" do
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
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
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
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
    group = Group.create!(lifecycle_status: :active, owner: owner, name: "Public", group_type: :public_group)
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
