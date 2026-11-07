require "rails_helper"

RSpec.describe "Group sharing and quotes", type: :request do
  let(:writer) { User.create!(name: "Writer", email: "group-share-writer@example.com", password: "password123!") }
  let(:source_author) { User.create!(name: "Source author", email: "group-share-source@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Source book", authors_text: "Source writer") }

  it "rejects a B share if membership is suspended after the sharing form was opened" do
    group = Group.create!(lifecycle_status: :active, group_admin: source_author, name: "Readers", group_type: :private_group)
    membership = group.group_memberships.create!(user: writer, status: :active)
    source = source_author.jjaeks.create!(content: "PUBLIC_SOURCE")
    sign_in writer
    get new_jjaek_path(quoted_jjaek_id: source.id, share_to_group: 1)
    expect(response).to have_http_status(:ok)

    membership.update!(moderation_status: :activity_suspended)
    expect {
      post jjaeks_path(quoted_jjaek_id: source.id), params: {
        jjaek: { group_id: group.id, quoted_jjaek_id: source.id, content: "Stale permission" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)
  end

  it "keeps A and C independent in either creation order for a public group original" do
    sign_in writer

    %i[personal_first group_first].each do |order|
      group = Group.create!(lifecycle_status: :active, group_admin: source_author, name: "Readers #{order}", group_type: :public_group)
      group.group_memberships.create!(user: writer, status: :active)
      source = source_author.jjaeks.create!(group:, content: "SOURCE_#{order}")

      create_personal = -> do
        get new_jjaek_path(quoted_jjaek_id: source.id)
        expect(response).to have_http_status(:ok)
        post jjaeks_path(quoted_jjaek_id: source.id), params: {
          jjaek: { quoted_jjaek_id: source.id, content: "PERSONAL_#{order}" }
        }
        expect(response).to redirect_to(jjaek_path(Jjaek.last))
      end
      create_in_group = -> do
        get new_group_jjaek_path(group, quoted_jjaek_id: source.id)
        expect(response).to have_http_status(:ok)
        post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
          jjaek: { quoted_jjaek_id: source.id, content: "GROUP_#{order}" }
        }
        expect(response).to redirect_to(group_path(group))
      end

      get jjaek_path(source)
      expect(response.body).to include(new_jjaek_path(quoted_jjaek_id: source.id),
                                       new_group_jjaek_path(group, quoted_jjaek_id: source.id))

      if order == :personal_first
        create_personal.call
        get jjaek_path(source)
        expect(response.body).to include(new_group_jjaek_path(group, quoted_jjaek_id: source.id))
        create_in_group.call
      else
        create_in_group.call
        get jjaek_path(source)
        expect(response.body).to include(new_jjaek_path(quoted_jjaek_id: source.id))
        create_personal.call
      end

      expect(writer.jjaeks.where(quoted_jjaek: source).order(:group_id).pluck(:group_id)).to contain_exactly(nil, group.id)
      get jjaek_path(source)
      expect(response.body).to include(I18n.t("jjaeks.meta.requotes", count: 2))
      expect(response.body).not_to include(new_jjaek_path(quoted_jjaek_id: source.id),
                                           new_group_jjaek_path(group, quoted_jjaek_id: source.id))
    end
  end

  it "allows one C in an approval group and rejects nonmembers or suspended members" do
    group = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Approval readers", group_type: :approval_group)
    group.group_memberships.create!(user: source_author, status: :active)
    source = source_author.jjaeks.create!(group:, content: "APPROVAL_SOURCE")
    sign_in writer

    get jjaek_path(source)
    links = Nokogiri::HTML(response.body).css("a[href]").map { |link| link["href"] }
    expect(links).to include(
      new_group_jjaek_path(group, quoted_jjaek_id: source.id, return_to: jjaek_path(source))
    )
    expect(links).not_to include(
      a_string_starting_with(new_jjaek_path(quoted_jjaek_id: source.id))
    )
    get new_group_jjaek_path(group, quoted_jjaek_id: source.id)
    expect(response).to have_http_status(:ok)

    post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
      jjaek: { quoted_jjaek_id: source.id, content: "APPROVAL_C" }
    }
    expect(response).to redirect_to(group_path(group))
    expect(writer.jjaeks.where(group:, quoted_jjaek: source).count).to eq(1)

    get jjaek_path(source)
    links = Nokogiri::HTML(response.body).css("a[href]").map { |link| link["href"] }
    expect(links).not_to include(
      a_string_starting_with(new_group_jjaek_path(group, quoted_jjaek_id: source.id))
    )
    expect {
      post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
        jjaek: { quoted_jjaek_id: source.id, content: "DUPLICATE_C" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to have_http_status(:unprocessable_content)

    outsider = User.create!(name: "Outsider", email: "approval-c-outsider@example.com", password: "password123!")
    sign_in outsider
    get new_group_jjaek_path(group, quoted_jjaek_id: source.id)
    expect(response).to redirect_to(root_path)
    expect {
      post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
        jjaek: { quoted_jjaek_id: source.id, content: "OUTSIDER_C" }
      }
    }.not_to change(Jjaek, :count)

    membership = group.group_memberships.find_by!(user: source_author)
    membership.update!(moderation_status: :activity_suspended)
    sign_in source_author
    get jjaek_path(source)
    expect(response.body).not_to include(new_group_jjaek_path(group, quoted_jjaek_id: source.id))
    get new_group_jjaek_path(group, quoted_jjaek_id: source.id)
    expect(response).to redirect_to(root_path)
    expect {
      post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
        jjaek: { quoted_jjaek_id: source.id, content: "SUSPENDED_C" }
      }
    }.not_to change(Jjaek, :count)
  end

  it "offers only writable, not-yet-used groups and creates a B share without copying the source book" do
    available = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Available readers", group_type: :public_group)
    approval = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Approval readers", group_type: :approval_group)
    private_group = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Private readers", group_type: :private_group)
    already_used = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Already used readers", group_type: :public_group)
    suspended = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Suspended readers", group_type: :public_group)
    unjoined = Group.create!(lifecycle_status: :active, group_admin: source_author, name: "Unjoined readers", group_type: :public_group)
    suspended.update!(operation_suspended_at: Time.current)
    source = create_jjaek_with_books(legacy_source_kind: "book", books: [book], user: source_author, content: "PUBLIC_BOOK_SOURCE")
    writer.jjaeks.create!(group: already_used, quoted_jjaek: source, content: "Earlier share")
    sign_in writer

    get jjaek_path(source)
    links = Nokogiri::HTML(response.body).css("a").map { |link| link["href"] }
    expect(links).to include(
      new_jjaek_path(quoted_jjaek_id: source.id, return_to: jjaek_path(source))
    )
    expect(links).to include(
      new_jjaek_path(quoted_jjaek_id: source.id, share_to_group: 1, return_to: jjaek_path(source))
    )
    expect(response.body).to include(I18n.t("jjaeks.actions.requote"), I18n.t("jjaeks.actions.share_to_group"))

    writer.jjaeks.create!(quoted_jjaek: source, content: "Personal requote")
    get new_jjaek_path(quoted_jjaek_id: source.id, share_to_group: 1)

    page = Nokogiri::HTML(response.body)
    radios = page.css('input[type="radio"][name="jjaek[group_id]"]')
    choices = radios.map { |radio| radio["value"] }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("PUBLIC_BOOK_SOURCE", book.title)
    expect(response.body).to include(I18n.t("jjaeks.form.destination_group"))
    form = page.at_css("#jjaek-publish-form")
    expect(URI.parse(form["action"]).path).to eq(jjaeks_path)
    expect(Rack::Utils.parse_query(URI.parse(form["action"]).query)).to include("share_to_group" => "1", "quoted_jjaek_id" => source.id.to_s)
    expect(form.at_css("input[name='jjaek[quoted_jjaek_id]']")["value"]).to eq(source.id.to_s)
    expect(page.at_css("button[type='submit'][form='#{form['id']}']").text).to eq(I18n.t("jjaeks.actions.publish_short"))
    expect(page.css("#jjaek-composer [data-book-selection-open], #jjaek-composer input[name='selected_books[]']")).to be_empty
    expect(response.body).not_to include('name="jjaek[visibility]"')
    expect(choices).to include(available.id.to_s, approval.id.to_s, private_group.id.to_s)
    expect(choices).not_to include(already_used.id.to_s, suspended.id.to_s, unjoined.id.to_s)
    expect(radios.select { |radio| radio["checked"] }).to be_empty
    [ available, approval, private_group ].each do |group|
      radio = radios.find { |input| input["value"] == group.id.to_s }
      expect(radio["required"]).to be_present
      label = radio.ancestors("label").first
      expect(label.text).to include(group.name, I18n.t("groups.types.#{group.group_type}"),
        I18n.t("jjaeks.form.group_sharing.#{group.public_group? ? 'public' : 'members'}"))
    end

    expect {
      post jjaeks_path(quoted_jjaek_id: source.id), params: {
        jjaek: { group_id: unjoined.id, quoted_jjaek_id: source.id, content: "Unjoined share" }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to redirect_to(root_path)

    expect {
      post jjaeks_path(quoted_jjaek_id: source.id, share_to_group: 1), params: {
        jjaek: { group_id: available.id, quoted_jjaek_id: source.id, content: "x" * 201 }
      }
    }.not_to change(Jjaek, :count)
    expect(response).to have_http_status(:unprocessable_content)
    failed_form = Nokogiri::HTML(response.body).at_css("#jjaek-publish-form")
    expect(failed_form.at_css("input[type='radio'][name='jjaek[group_id]'][checked]")["value"]).to eq(available.id.to_s)
    expect(failed_form.at_css("textarea").text.strip).to eq("x" * 201)

    expect {
      post jjaeks_path(quoted_jjaek_id: source.id, share_to_group: 1), params: { jjaek: { group_id: available.id, quoted_jjaek_id: source.id, content: "MY_GROUP_OPINION", visibility: :private_jjaek } }
    }.to change(Jjaek, :count).by(1).and change(Notification, :count).by(1)

    share = Jjaek.last
    expect(share.group).to eq(available)
    expect(share.quoted_jjaek).to eq(source)
    expect(share.content).to eq("MY_GROUP_OPINION")
    expect(share.attached_books).to be_empty
    expect(source.reload.attached_books).to eq([book])
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
    source = create_jjaek_with_books(legacy_source_kind: "book", books: [book], user: source_author, group:, content: "PRIVATE_GROUP_SOURCE")
    sign_in writer

    get jjaek_path(source)
    links = Nokogiri::HTML(response.body).css("a").map { |link| link["href"] }
    expect(links).to include(
      new_group_jjaek_path(group, quoted_jjaek_id: source.id, return_to: jjaek_path(source))
    )
    expect(links).not_to include(
      a_string_starting_with(new_jjaek_path(quoted_jjaek_id: source.id))
    )
    expect(response.body).to include(I18n.t("jjaeks.actions.quote_in_group"))

    get new_group_jjaek_path(group, quoted_jjaek_id: source.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("PRIVATE_GROUP_SOURCE")

    page = Nokogiri::HTML(response.body)
    form = page.at_css("#jjaek-publish-form")
    expect(form["action"]).to eq(group_jjaeks_path(group))
    expect(form.at_css("input[name='jjaek[quoted_jjaek_id]']")["value"]).to eq(source.id.to_s)
    expect(page.at_css("#jjaek-composer")["data-group-id"]).to eq(group.id.to_s)
    expect(page.at_css("button[type='submit'][form='#{form['id']}']").text).to eq(I18n.t("jjaeks.actions.publish_short"))
    expect(page.css("#jjaek-composer [data-book-selection-open], #jjaek-composer input[name='selected_books[]']")).to be_empty
    expect(response.body).not_to include('name="jjaek[visibility]"', 'name="jjaek[group_id]"')

    post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
      jjaek: { quoted_jjaek_id: source.id, content: "" }
    }
    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.text).to include("PRIVATE_GROUP_SOURCE")
    expect(page.at_css("#jjaek-publish-form")["action"]).to eq(group_jjaeks_path(group))
    expect(page.at_css("#jjaek-composer")["data-group-id"]).to eq(group.id.to_s)

    expect {
      post group_jjaeks_path(group, quoted_jjaek_id: source.id), params: {
        jjaek: { quoted_jjaek_id: source.id, content: "MY_PRIVATE_GROUP_QUOTE" }
      }
    }.to change(Jjaek, :count).by(1).and change(Notification, :count).by(1)

    quote = Jjaek.last
    expect(quote.group).to eq(group)
    expect(quote.attached_books).to be_empty
    expect(quote.quoted_jjaek).to eq(source)
    expect(Notification.last.recipient).to eq(source_author)

    get jjaek_path(quote)
    card = Nokogiri::HTML(response.body).at_css("article#jjaek_#{quote.id}")
    expect(card.text).to include(
      "#{source_author.name}님의 짹을 동아리 #{group.name}에 다시짹"
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

  it "rejects new attachments on both B shares and C quotes" do
    group = Group.create!(lifecycle_status: :active, group_admin: writer, name: "Readers", group_type: :public_group)
    group.group_memberships.create!(user: source_author, status: :active)
    personal_source = create_jjaek_with_books(legacy_source_kind: "book", books: [book], user: source_author, content: "PERSONAL_SOURCE")
    group_source = create_jjaek_with_books(legacy_source_kind: "book", books: [book], user: source_author, group:, content: "GROUP_SOURCE")
    sign_in writer

    [ [ jjaeks_path(quoted_jjaek_id: personal_source.id), personal_source ],
     [ group_jjaeks_path(group, quoted_jjaek_id: group_source.id), group_source ] ].each do |path, source|
      expect {
        post path, params: {
          selected_books: [ book.id ],
          jjaek: { group_id: group.id, quoted_jjaek_id: source.id, content: "Forbidden attachment" }
        }
      }.to change(Jjaek, :count).by(0).and change(JjaekBookAttachment, :count).by(0).and change(Notification, :count).by(0)
    end
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
    expect(response.body).to include(I18n.t("errors.messages.taken"), "Duplicate opinion")
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
    }.to change(Jjaek, :count).by(0).and change(Notification, :count).by(0)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(public_source.content, group.name)
    expect(response.body).to include(I18n.t("errors.messages.taken"), "Racing share")
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
