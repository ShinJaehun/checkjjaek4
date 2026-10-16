require "rails_helper"

RSpec.describe "Book posting destinations", type: :request do
  let(:user) { User.create!(name: "Posting reader", email: "book-posting@example.com", password: "password123!") }
  let(:admin) { User.create!(name: "Club admin", email: "book-posting-admin@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "게시 위치 책", authors_text: "저자") }
  let!(:entry) { user.bookshelf_entries.create!(book: book, status: :reading) }
  let(:group) { Group.create!(name: "Posting club", group_admin: admin, group_type: :private_group, lifecycle_status: :active) }
  let!(:membership) { group.group_memberships.create!(user: user, status: :active) }

  before { sign_in user }

  it "defaults an ordinary entry to personal posting and disables the group field" do
    get book_path(book)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("input[name='book_post_destination'][checked]")["value"]).to eq("personal")
    expect(page.at_css("select[name='jjaek[group_id]'][disabled]")).to be_present
    expect(page.at_css("input[name='jjaek[visibility]'][disabled]")).to be_nil
    expect(page.at_css("[data-book-posting-target='group'][hidden]")).to be_present
    expect(page.css("input[name='book_post_destination']").map { |input| input["value"] }).to eq(%w[personal group])
    expect(page.css("input[name='jjaek[visibility]']").map { |input| input["value"] }).to eq(Jjaek.visibilities.keys)
    expect(page.css("input[name='book_post_destination']").all? { |input| input.parent.at_css("svg") }).to be(true)
  end

  it "shows only the personal book form when the user has no active club memberships" do
    membership.destroy!

    get book_path(book)

    page = Nokogiri::HTML(response.body)
    form = page.at_css("form[action='#{jjaeks_path}']")
    expect(form.at_css("input[name='book_post_destination']")).to be_nil
    expect(form.at_css("select[name='jjaek[group_id]']")).to be_nil
    expect(form.at_css("input[name='jjaek[visibility]']")).to be_present
    expect(form.at_css("input[name='jjaek[visibility]'][disabled]")).to be_nil
    expect(form.at_css("textarea[name='jjaek[content]']")).to be_present
    expect(form.at_css("input[type='submit']")["value"]).to eq(I18n.t("jjaeks.actions.publish_book"))
    expect(page.at_css("[data-book-posting-target='title']").text).to eq(I18n.t("jjaeks.actions.publish_book"))
    expect(page.at_css("[data-controller='book-posting']")).to be_nil
  end

  it "hides the posting selector when all club memberships are activity suspended" do
    membership.update!(moderation_status: :activity_suspended)

    get book_path(book)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("input[name='book_post_destination']")).to be_nil
    expect(page.at_css("select[name='jjaek[group_id]']")).to be_nil
    expect(page.at_css("input[name='jjaek[visibility]'][disabled]")).to be_nil
    expect(page.at_css("input[name='jjaek[visibility]']")).to be_present
  end

  it "hides the posting selector when every club is operation suspended" do
    group.update!(operation_suspended_at: Time.current)

    get book_path(book)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("input[name='book_post_destination']")).to be_nil
    expect(page.at_css("select[name='jjaek[group_id]']")).to be_nil
    expect(page.at_css("input[name='jjaek[visibility]']")).to be_present
  end

  it "labels the club feed's writing choices as Jjaek and Club Book Jjaek" do
    get group_path(group)

    page = Nokogiri::HTML(response.body)
    form = page.at_css("form[action='#{group_jjaeks_path(group)}']")
    expect(form).to be_present
    writing_section = form.ancestors("section").first
    link = writing_section.at_css("a[href='#{book_search_path(group_id: group.id, search_origin: group_path(group))}']")
    expect(link).to be_present
    expect(link.text).to eq(I18n.t("jjaeks.actions.publish_group_book"))
    expect(form.at_css("input[type='submit']")["value"]).to eq(I18n.t("groups.jjaeks.tabs.general"))
  end

  it "lists only clubs in which the user currently has writing permission" do
    owned = Group.create!(name: "Owned club", group_admin: user, lifecycle_status: :active)
    public_nonmember = Group.create!(name: "Public nonmember club", group_admin: admin, lifecycle_status: :active)
    pending = Group.create!(name: "Pending membership", group_admin: admin, lifecycle_status: :active)
    pending.group_memberships.create!(user: user, status: :pending)
    invited = Group.create!(name: "Invited membership", group_admin: admin, group_type: :private_group, lifecycle_status: :active)
    invited.group_memberships.create!(user: user, status: :invited)
    suspended_member = Group.create!(name: "Suspended member", group_admin: admin, lifecycle_status: :active)
    suspended_member.group_memberships.create!(user: user, status: :active, moderation_status: :activity_suspended)
    suspended_group = Group.create!(name: "Suspended club", group_admin: admin, lifecycle_status: :active, operation_suspended_at: Time.current)
    suspended_group.group_memberships.create!(user: user, status: :active)
    inactive = Group.create!(name: "Inactive club", group_admin: admin, lifecycle_status: :active)
    inactive.group_memberships.create!(user: user, status: :active)
    inactive.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)
    unapproved = Group.create!(name: "Unapproved club", group_admin: user, application_purpose: "Read together")

    get book_path(book)

    page = Nokogiri::HTML(response.body)
    ids = page.css("select[name='jjaek[group_id]'] option").map { |option| option["value"] }.reject(&:blank?)
    expect(ids).to match_array([ group.id.to_s, owned.id.to_s ])
    [ public_nonmember, pending, invited, suspended_member, suspended_group, inactive, unapproved ].each do |excluded|
      expect(GroupPolicy.new(user, excluded).create_jjaek?).to be(false)
    end
  end

  it "creates a personal book post with the selected visibility" do
    expect {
      post jjaeks_path, params: {
        book_post_destination: "personal",
        jjaek: { book_id: book.id, content: "PERSONAL_DESTINATION", visibility: "private_jjaek" }
      }
    }.to change(Jjaek, :count).by(1)

    expect(Jjaek.last).to have_attributes(book: book, user: user, group_id: nil, visibility: "private_jjaek", quoted_jjaek_id: nil)
    expect(response).to redirect_to(jjaek_path(Jjaek.last))
  end

  it "creates an original group book post without creating personal reading activity" do
    activity_count = BookActivity.count
    shelf_state = [ entry.status, entry.bookshelf_id, entry.sticker_definition_ids ]

    expect {
      post jjaeks_path, params: {
        book_post_destination: "group",
        jjaek: { book_id: book.id, group_id: group.id, content: "GROUP_DESTINATION", visibility: "private_jjaek" }
      }
    }.to change(group.jjaeks, :count).by(1)

    expect(Jjaek.last).to have_attributes(book: book, user: user, group: group, visibility: "public_jjaek", quoted_jjaek_id: nil)
    expect(response).to redirect_to(group_path(group))
    expect(BookActivity.count).to eq(activity_count)
    expect([ entry.reload.status, entry.bookshelf_id, entry.sticker_definition_ids ]).to eq(shelf_state)
  end

  it "preserves the selected group and draft after a validation failure" do
    content = "GROUP_DRAFT_".ljust(201, "a")

    expect {
      post jjaeks_path, params: {
        book_post_destination: "group", jjaek: { book_id: book.id, group_id: group.id, content: content }
      }, headers: { "Accept" => "text/html" }
    }.not_to change(Jjaek, :count)

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("textarea[name='jjaek[content]']").text.delete_prefix("\n")).to eq(content)
    expect(page.at_css("input[name='book_post_destination'][checked]")["value"]).to eq("group")
    expect(page.at_css("select[name='jjaek[group_id]'] option[selected]")["value"]).to eq(group.id.to_s)
    expect(page.at_css("input[name='jjaek[visibility]'][disabled]")).to be_present
  end

  it "preserves personal visibility and draft after a validation failure" do
    post jjaeks_path, params: {
      book_post_destination: "personal", jjaek: { book_id: book.id, content: "", visibility: "book_friends" }
    }, headers: { "Accept" => "text/html" }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("input[name='book_post_destination'][checked]")["value"]).to eq("personal")
    expect(page.at_css("input[name='jjaek[visibility]'][checked]")["value"]).to eq("book_friends")
    expect(page.at_css("select[name='jjaek[group_id]'][disabled]")).to be_present
  end

  it "rejects forged or incomplete posting targets instead of falling back to another destination" do
    invalid_params = [
      { book_post_destination: "unknown", jjaek: { book_id: book.id, content: "Invalid" } },
      { book_post_destination: "", jjaek: { book_id: book.id, content: "Invalid" } },
      { book_post_destination: "group", jjaek: { book_id: book.id, content: "No group" } },
      { book_post_destination: "personal", jjaek: { book_id: book.id, group_id: group.id, content: "Conflicting group" } },
      { book_post_destination: "group", jjaek: { group_id: group.id, content: "No book" } },
      { book_post_destination: "group", book_id: book.id, jjaek: { book_id: "", group_id: group.id, content: "Blank book" } },
      { book_post_destination: "personal", jjaek: { book_id: book.id, target_user_id: admin.id, content: "Profile context" } }
    ]

    invalid_params.each do |attributes|
      expect { post jjaeks_path, params: attributes }.not_to change(Jjaek, :count)
      expect(response).to redirect_to(root_path)
    end
  end

  it "rejects a nonmember's public group" do
    other_group = Group.create!(name: "Other public club", group_admin: admin, lifecycle_status: :active)
    expect {
      post jjaeks_path, params: { book_post_destination: "group", jjaek: { book_id: book.id, group_id: other_group.id, content: "Forbidden" } }
    }.not_to change(Jjaek, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "rechecks membership after the book form was opened" do
    get book_path(book)
    expect(response).to have_http_status(:ok)

    membership.update!(moderation_status: :activity_suspended)
    expect {
      post jjaeks_path, params: { book_post_destination: "group", jjaek: { book_id: book.id, group_id: group.id, content: "Revoked" } }
    }.not_to change(Jjaek, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "continues to require the book to be in the personal library" do
    entry.destroy!

    expect {
      post jjaeks_path, params: { book_post_destination: "group", jjaek: { book_id: book.id, group_id: group.id, content: "Unshelved" } }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)
  end

  it "rejects group posting without the new selector on the ordinary endpoint" do
    expect {
      post jjaeks_path, params: { jjaek: { book_id: book.id, group_id: group.id, content: "Missing selector" } }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)
  end

  it "keeps the book quote form separate from the posting selector" do
    source = admin.jjaeks.create!(book: book, content: "Source")

    get book_path(book, quote_id: source.id)

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("input[name='book_post_destination']")).to be_nil
    expect(page.at_css("input[name='jjaek[quoted_jjaek_id]']")["value"]).to eq(source.id.to_s)
    expect(page.at_css("form[action='#{jjaeks_path}']")).to be_present
  end

  it "does not turn the posting selector into a share or requote path" do
    source = admin.jjaeks.create!(book: book, content: "Source")

    expect {
      post jjaeks_path, params: {
        book_post_destination: "group", share_to_group: "1",
        jjaek: { book_id: book.id, group_id: group.id, quoted_jjaek_id: source.id, content: "Share attempt" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)
  end
end
