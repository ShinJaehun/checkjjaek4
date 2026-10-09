require "rails_helper"

RSpec.describe "Group sharing and quotes", type: :request do
  let(:writer) { User.create!(name: "Writer", email: "group-share-writer@example.com", password: "password123!") }
  let(:source_author) { User.create!(name: "Source author", email: "group-share-source@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Source book", authors_text: "Source writer") }

  it "offers only writable, not-yet-used groups and creates a B share without copying the source book" do
    available = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Available readers", group_type: :public_group)
    already_used = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Already used readers", group_type: :public_group)
    suspended = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Suspended readers", group_type: :public_group)
    unjoined = Group.create!(lifecycle_status: :active, group_admin: source_author, name: "Unjoined readers", group_type: :public_group)
    suspended.update!(operation_suspended_at: Time.current)
    source = source_author.jjaeks.create!(book:, content: "PUBLIC_BOOK_SOURCE")
    writer.jjaeks.create!(group: already_used, quoted_jjaek: source, content: "Earlier share")
    sign_in writer

    get jjaek_path(source)
    links = Nokogiri::HTML(response.body).css("a").map { |link| link["href"] }
    expect(links).to include(new_jjaek_path(quoted_jjaek_id: source.id))
    expect(links).to include(new_jjaek_path(quoted_jjaek_id: source.id, share_to_group: 1))
    expect(response.body).to include(I18n.t("jjaeks.actions.requote"), I18n.t("jjaeks.actions.share_to_group"))

    writer.jjaeks.create!(quoted_jjaek: source, content: "Personal requote")
    get new_jjaek_path(quoted_jjaek_id: source.id, share_to_group: 1)

    page = Nokogiri::HTML(response.body)
    choices = page.css('select[name="jjaek[group_id]"] option').map { |option| option["value"] }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("PUBLIC_BOOK_SOURCE", book.title)
    expect(response.body).to include(I18n.t("jjaeks.actions.share_to_group"), I18n.t("jjaeks.form.destination_group"))
    expect(response.body).not_to include('name="jjaek[visibility]"')
    expect(choices).to include(available.id.to_s)
    expect(choices).not_to include(already_used.id.to_s, suspended.id.to_s, unjoined.id.to_s)

    expect {
      post jjaeks_path(quoted_jjaek_id: source.id), params: {
        jjaek: { group_id: unjoined.id, quoted_jjaek_id: source.id, content: "Unjoined share" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)

    expect {
      post jjaeks_path(quoted_jjaek_id: source.id), params: {
        jjaek: {
          group_id: available.id, quoted_jjaek_id: source.id,
          content: "MY_GROUP_OPINION", book_id: book.id, visibility: :private_jjaek
        }
      }
    }.to change(Jjaek, :count).by(1).and change(Notification, :count).by(1)

    share = Jjaek.last
    expect(share.group).to eq(available)
    expect(share.quoted_jjaek).to eq(source)
    expect(share.content).to eq("MY_GROUP_OPINION")
    expect(share.book).to be_nil
    expect(share).to be_public_jjaek
    expect(response).to redirect_to(group_path(available))
    expect(Notification.last).to be_requote_created

      get group_path(available)
      expect(
        Nokogiri::HTML(response.body).at_css("article#jjaek_#{share.id}")
      ).to be_present

    get jjaek_path(share)
    card = Nokogiri::HTML(response.body).at_css("article#jjaek_#{share.id}")
    expect(card.text).to include("에 다시짹", source_author.name, available.name)

    source.destroy!
    get jjaek_path(share)
    card = Nokogiri::HTML(response.body).at_css("article#jjaek_#{share.id}")
    expect(card.text).to include(I18n.t("jjaeks.labels.deleted_quoted_source"), available.name)
    expect(card.text).not_to include(source_author.name, book.title)
  end

  it "creates a C quote only in its source group and sends an accessible notification" do
    group = Group.create!(lifecycle_status: :active, group_admin: source_author, name: "Private readers", group_type: :private_group)
    group.group_memberships.create!(user: writer, status: :active)
    source = source_author.jjaeks.create!(group:, book:, content: "PRIVATE_GROUP_SOURCE")
    sign_in writer

    get jjaek_path(source)
    links = Nokogiri::HTML(response.body).css("a").map { |link| link["href"] }
    expect(links).to include(new_group_jjaek_path(group, quoted_jjaek_id: source.id))
    expect(links).not_to include(new_jjaek_path(quoted_jjaek_id: source.id))
    expect(response.body).to include(I18n.t("jjaeks.actions.quote_in_group"))

    get new_group_jjaek_path(group, quoted_jjaek_id: source.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("PRIVATE_GROUP_SOURCE", group.name)
    expect(response.body).to include(I18n.t("jjaeks.actions.quote_in_group"))
    expect(response.body).not_to include('name="jjaek[visibility]"', 'name="jjaek[group_id]"')

    post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
      jjaek: { quoted_jjaek_id: source.id, content: "" }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("PRIVATE_GROUP_SOURCE", group.name)

    expect {
      post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
        jjaek: { quoted_jjaek_id: source.id, content: "MY_PRIVATE_GROUP_QUOTE" }
      }
    }.to change(Jjaek, :count).by(1).and change(Notification, :count).by(1)

    quote = Jjaek.last
    expect(quote.group).to eq(group)
    expect(quote.book).to be_nil
    expect(quote.quoted_jjaek).to eq(source)
    expect(Notification.last.recipient).to eq(source_author)

    get jjaek_path(quote)
    card = Nokogiri::HTML(response.body).at_css("article#jjaek_#{quote.id}")
    expect(card.text).to include(
      "#{group.name}에서 #{source_author.name}님의",
      "을 다시짹"
    )

    expect {
      post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
        jjaek: { quoted_jjaek_id: source.id, content: "Duplicate group quote" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to have_http_status(:unprocessable_content)

    source.destroy!
    get jjaek_path(quote)
    card = Nokogiri::HTML(response.body).at_css("article#jjaek_#{quote.id}")
    expect(card.text).to include(I18n.t("jjaeks.labels.deleted_quoted_source"), group.name)
    expect(card.text).not_to include(source_author.name, book.title)
  end

  it "keeps source and destination on a failed B submission and rejects duplicate destinations" do
    first_group = Group.create!(lifecycle_status: :active, group_admin: writer, name: "First readers", group_type: :public_group)
    second_group = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Second readers", group_type: :public_group)
    source = source_author.jjaeks.create!(content: "PUBLIC_SOURCE")
    sign_in writer

    post jjaeks_path(quoted_jjaek_id: source.id), params: {
      jjaek: { group_id: first_group.id, quoted_jjaek_id: source.id, content: "" }
    }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("PUBLIC_SOURCE", first_group.name)
    expect(response.body).to include('name="jjaek[group_id]"')

    post jjaeks_path(quoted_jjaek_id: source.id), params: {
      jjaek: { group_id: first_group.id, quoted_jjaek_id: source.id, content: "First opinion" }
    }
    expect(response).to redirect_to(group_path(first_group))

    notifications_before_duplicate = Notification.count
    expect {
      post jjaeks_path(quoted_jjaek_id: source.id), params: {
        jjaek: { group_id: first_group.id, quoted_jjaek_id: source.id, content: "Duplicate opinion" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(first_group.name)
    expect(Notification.count).to eq(notifications_before_duplicate)

    post jjaeks_path(quoted_jjaek_id: source.id), params: {
      jjaek: { group_id: second_group.id, quoted_jjaek_id: source.id, content: "Second opinion" }
    }
    expect(response).to redirect_to(group_path(second_group))
    expect(Jjaek.where(user: writer, quoted_jjaek: source).where.not(group_id: nil).count).to eq(2)
  end

  it "rejects changed source and destination IDs and lost Group write access" do
    group = Group.create!(lifecycle_status: :active, group_admin: source_author, name: "Private readers", group_type: :private_group)
    other_group = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Other readers", group_type: :public_group)
    membership = group.group_memberships.create!(user: writer, status: :active)
    source = source_author.jjaeks.create!(group:, content: "PRIVATE_SOURCE")
    other_source = writer.jjaeks.create!(group: other_group, content: "OTHER_SOURCE")
    sign_in writer

    get new_group_jjaek_path(other_group, quoted_jjaek_id: source.id)
    expect(response).to redirect_to(root_path)

    expect {
      post group_jjaeks_path(other_group, quoted_jjaek_id: source.id), params: {
        jjaek: { quoted_jjaek_id: source.id, content: "Cross-group quote" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)

    expect {
      post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
        jjaek: { group_id: other_group.id, quoted_jjaek_id: source.id, content: "Changed destination" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)

    expect {
      post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
        jjaek: { quoted_jjaek_id: other_source.id, content: "Changed source" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)

    expect {
      post jjaeks_path, params: { jjaek: { group_id: other_group.id, content: "Missing source" } }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)

    membership.destroy!
    expect {
      post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
        jjaek: { quoted_jjaek_id: source.id, content: "After leaving" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "rejects restricted and nested sources for B and handles a DB duplicate conflict" do
    group = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Readers", group_type: :public_group)
    public_source = source_author.jjaeks.create!(content: "PUBLIC_SOURCE")
    restricted_source = source_author.jjaeks.create!(content: "FRIENDS_SOURCE", visibility: :book_friends)
    nested_source = source_author.jjaeks.create!(content: "NESTED_SOURCE", quoted_jjaek: public_source)
    sign_in writer

    get new_jjaek_path(quoted_jjaek_id: restricted_source.id, share_to_group: 1)
    expect(response).to redirect_to(root_path)
    get new_jjaek_path(quoted_jjaek_id: nested_source.id, share_to_group: 1)
    expect(response).to redirect_to(root_path)

    allow_any_instance_of(Jjaek).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)
    expect {
      post jjaeks_path(quoted_jjaek_id: public_source.id), params: {
        jjaek: { group_id: group.id, quoted_jjaek_id: public_source.id, content: "Racing share" }
      }
    }.not_to change(Notification, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(public_source.content, group.name)
  end

  it "rejects a group quote when the group becomes suspended after opening the form" do
    group = Group.create!(lifecycle_status: :active, group_admin: source_author, name: "Readers", group_type: :public_group)
    group.group_memberships.create!(user: writer, status: :active)
    source = source_author.jjaeks.create!(group:, content: "GROUP_SOURCE")
    sign_in writer

    get new_group_jjaek_path(group, quoted_jjaek_id: source.id)
    expect(response).to have_http_status(:ok)
    group.update!(operation_suspended_at: Time.current)

    expect {
      post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
        jjaek: { quoted_jjaek_id: source.id, content: "Too late" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)
  end
end
