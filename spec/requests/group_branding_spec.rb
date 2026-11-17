require "rails_helper"

RSpec.describe "Group branding", type: :request do
  let(:admin) { User.create!(name: "Branding admin", email: "branding-admin@example.com", password: "password123!") }
  let(:reader) { User.create!(name: "Branding reader", email: "branding-reader@example.com", password: "password123!") }
  let(:group) { Group.create!(group_admin: admin, name: "Branded readers", lifecycle_status: :active, group_type: :private_group) }

  def image_upload(format = "png")
    source = Rails.root.join("app/assets/images/avatars/user_profile_01_128.png")
    return Rack::Test::UploadedFile.new(source, "image/png") if format == "png"

    file = Tempfile.new([ "group-branding", ".#{format}" ])
    Vips::Image.new_from_file(source.to_s).write_to_file(file.path)
    Rack::Test::UploadedFile.new(file.path, format == "jpg" ? "image/jpeg" : "image/webp")
  ensure
    file&.close!
  end

  def upload_branding(target = group)
    sign_in admin
    patch group_path(target), params: { group: { profile_image_file: image_upload, cover_image_file: image_upload } }
    expect(response).to have_http_status(:found)
    target.reload
  end

  after do
    ActiveStorage::Blob.where("metadata::jsonb @> ?", { group_image: true }.to_json).find_each do |blob|
      blob.variant_records.each { |variant| variant.image.blob.delete if variant.image.attached? }
      blob.delete
    end
  end

  it "gives information and branding separate PATCH forms while preserving the single application form" do
    sign_in admin
    get edit_group_path(group)
    page = Nokogiri::HTML(response.body)
    forms = page.css("form[action='#{group_path(group)}']")
    expect(forms.size).to eq(2)
    information = page.at_css("#group-information-form")
    fields = information.css("input[name^='group['], textarea, select").map { |field| field["name"] }
    expect(fields).to contain_exactly("group[name]", "group[description]")
    branding = page.at_css("#group-branding-form")
    expect(branding.css("input[type='file']").size).to eq(2)
    expect(branding.at_css("input[name='group[name]'], textarea, select")).to be_nil
    forms.each do |form|
      expect(form.at_css("input[name='_method']")["value"]).to eq("patch")
      expect(form.at_css("input[type='submit']")["value"]).to eq(I18n.t("groups.actions.update"))
      expect(form.css("form")).to be_empty
    end

    get new_group_path
    page = Nokogiri::HTML(response.body)
    form = page.at_css("form[action='#{groups_path}']")
    expect(page.css("form[action='#{groups_path}']").size).to eq(1)
    expect(form.at_css("input[name='group[name]']")).to be_present
    expect(form.at_css("select[name='group[group_type]']")).to be_present
    expect(form.at_css("textarea[name='group[application_purpose]']")).to be_present
    expect(page.at_css("#group-branding-settings")).to be_nil
    expect(form.at_css("input[type='submit']")["value"]).to eq(I18n.t("groups.actions.create"))
  end

  it "saves information and branding independently and keeps failed inputs and existing images" do
    upload_branding
    group.update!(description: "Before", brand_color: "blue")
    original_ids = [ group.profile_image_attachment.id, group.cover_image_attachment.id ]

    patch group_path(group), params: { group: { name: "Updated readers", description: "After" } }
    expect(response).to redirect_to(group_path(group.reload))
    expect(group).to have_attributes(name: "Updated readers", description: "After", brand_color: "blue")
    expect([ group.profile_image_attachment.id, group.cover_image_attachment.id ]).to eq(original_ids)

    patch group_path(group), params: { group: { name: "", description: "Unsaved description" } }
    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#group-information-form [role='alert']:not([hidden])")).to be_present
    expect(page.at_css("#group-branding-form [role='alert']:not([hidden])")).to be_nil
    expect(page.at_css("#group-information-form textarea").text.strip).to eq("Unsaved description")
    expect(group.reload).to have_attributes(name: "Updated readers", description: "After", brand_color: "blue")
    expect([ group.profile_image_attachment.id, group.cover_image_attachment.id ]).to eq(original_ids)

    patch group_path(group), params: { group: { brand_color: "invalid", profile_image_file: image_upload, remove_cover_image: "1" } }
    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#group-branding-form [role='alert']:not([hidden])")).to be_present
    expect(page.at_css("#group-information-form [role='alert']:not([hidden])")).to be_nil
    expect(group.reload).to have_attributes(name: "Updated readers", description: "After", brand_color: "blue")
    expect([ group.profile_image_attachment.id, group.cover_image_attachment.id ]).to eq(original_ids)

    patch group_path(group), params: { group: { brand_color: "teal", profile_image_file: image_upload, remove_cover_image: "1" } }
    expect(response).to redirect_to(group_path(group.reload))
    expect(group).to have_attributes(name: "Updated readers", description: "After", brand_color: "teal")
    expect(group.profile_image_attachment.id).not_to eq(original_ids.first)
    expect(group.cover_image).not_to be_attached
  end

  it "uploads, independently replaces, and removes both images while saving an allowed color" do
    upload_branding
    profile_id = group.profile_image_attachment.id
    cover_id = group.cover_image_attachment.id

    patch group_path(group), params: { group: { profile_image_file: image_upload("jpg"), brand_color: "blue" } }
    expect(response).to redirect_to(group_path(group))
    expect(group.reload.profile_image_attachment.id).not_to eq(profile_id)
    expect(group.cover_image_attachment.id).to eq(cover_id)
    expect(group.brand_color).to eq("blue")
    get group_image_path(group, profile_id, size: :card)
    expect(response).to have_http_status(:not_found)

    profile_id = group.profile_image_attachment.id
    patch group_path(group), params: { group: { cover_image_file: image_upload("webp") } }
    expect(response).to redirect_to(group_path(group))
    expect(group.reload.cover_image_attachment.id).not_to eq(cover_id)
    expect(group.profile_image_attachment.id).to eq(profile_id)

    patch group_path(group), params: { group: { remove_profile_image: "1" } }
    expect(response).to redirect_to(group_path(group))
    expect(group.reload.profile_image).not_to be_attached
    expect(group.cover_image).to be_attached
    patch group_path(group), params: { group: { remove_cover_image: "1" } }
    expect(response).to redirect_to(group_path(group))
    expect(group.reload.cover_image).not_to be_attached
  end

  it "preserves both attachments and settings if a replacement fails validation" do
    upload_branding
    ids = [ group.profile_image_attachment.id, group.cover_image_attachment.id ]

    patch group_path(group), params: { group: {
      name: "Do not save", brand_color: "#123456", profile_image_file: image_upload, remove_cover_image: "1"
    } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(group.reload.name).to eq("Branded readers")
    expect(group.brand_color).to be_nil
    expect([ group.profile_image_attachment.id, group.cover_image_attachment.id ]).to eq(ids)
    expect(response.body).to include("/images/#{ids.first}?size=card")
  end

  it "rejects damaged, unsupported, oversized, and signed-blob uploads without changing existing images" do
    upload_branding
    ids = [ group.profile_image_attachment.id, group.cover_image_attachment.id ]
    invalid_files = [ [ "broken.png", "image/png", "not an image" ],
      [ "vector.svg", "image/svg+xml", '<svg xmlns="http://www.w3.org/2000/svg"></svg>' ],
      [ "large.png", "image/png", "x" * (5.megabytes + 1) ] ]

    invalid_files.each do |filename, content_type, contents|
      Tempfile.create([ "invalid-group-image", File.extname(filename) ]) do |file|
        file.binmode
        file.write(contents)
        file.flush
        %w[profile_image_file cover_image_file].each do |field|
          patch group_path(group), params: { group: { name: "Do not save", field => Rack::Test::UploadedFile.new(file.path, content_type) } }
          expect(response).to have_http_status(:unprocessable_content)
          expect(group.reload.name).to eq("Branded readers")
          expect([ group.profile_image_attachment.id, group.cover_image_attachment.id ]).to eq(ids)
        end
      end
    end
    patch group_path(group), params: { group: { profile_image_file: group.profile_image.blob.signed_id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(group.reload.profile_image_attachment.id).to eq(ids.first)
  end

  it "allows only the current group administrator to change branding" do
    upload_branding
    group.group_memberships.create!(user: reader, status: :active)
    sign_in reader
    profile_id = group.profile_image_attachment.id
    patch group_path(group), params: { group: { brand_color: "red", remove_profile_image: "1", cover_image_file: image_upload } }
    expect(response).to redirect_to(root_path)
    expect(group.reload.brand_color).to be_nil
    expect(group.profile_image_attachment.id).to eq(profile_id)

    sign_in admin
    group.update!(operation_suspended_at: Time.current)
    patch group_path(group), params: { group: { remove_profile_image: "1" } }
    expect(response).to redirect_to(root_path)
    expect(group.reload.profile_image_attachment.id).to eq(profile_id)
  end

  it "checks current group access for each variant and prevents other-parent and public URL bypasses" do
    upload_branding
    profile = group.profile_image_attachment
    cover = group.cover_image_attachment
    paths = [ group_image_path(group, profile, size: :card), group_image_path(group, profile, size: :detail),
      group_image_path(group, cover, size: :cover) ]
    paths.each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/webp")
      expect(response.headers["Cache-Control"]).to include("private", "no-store")
      expect(response.headers["Location"]).to be_nil
    end
    get group_image_path(group, profile, size: :original)
    expect(response).to have_http_status(:not_found)
    other = Group.create!(group_admin: admin, name: "Other group", lifecycle_status: :active)
    get group_image_path(other, profile, size: :card)
    expect(response).to have_http_status(:not_found)

    # 실제 세션을 전환해 관리자 권한이 남아 있지 않은지 확인한다.
    delete destroy_user_session_path
    expect(response).to redirect_to(new_user_session_path)

    post user_session_path, params: {
      user: { email: reader.email, password: "password123!" }
    }
    expect(response).to redirect_to(root_path)

    get account_settings_path
    expect(response.body).to include(%(value="#{reader.name}"))

    paths.each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
    membership = group.group_memberships.create!(user: reader, status: :active)
    get paths.first
    expect(response).to have_http_status(:ok)
    membership.destroy!
    get paths.first
    expect(response).to have_http_status(:not_found)

    ActiveStorage::Attachment.create!(record: reader, name: "avatar", blob: profile.blob)
    get user_avatar_image_path(reader, size: 128)
    expect(response).to have_http_status(:not_found)
    get "/rails/active_storage/blobs/redirect/#{profile.blob.signed_id}/image.webp"
    expect(response).to have_http_status(:not_found)

    sign_out reader
    get paths.first
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows profile thumbnails on accessible cards and uses an icon for private name-only search results" do
    upload_branding
    profile_path = group_image_path(group, group.profile_image_attachment, size: :card)
    get groups_path
    expect(Nokogiri::HTML(response.body).at_css("img[src='#{profile_path}']")).to be_present
    get edit_groups_membership_order_path
    order_image = Nokogiri::HTML(response.body).at_css("img[src='#{profile_path}']")
    expect(order_image["class"].split).to include("h-12", "w-12")
    source = admin.jjaeks.create!(content: "Branded share source")
    get new_jjaek_path(quoted_jjaek_id: source.id, share_to_group: 1)
    choice = Nokogiri::HTML(response.body).at_css("input[name='jjaek[group_id]'][value='#{group.id}']").ancestors("label").first
    expect(choice.at_css("img[src='#{profile_path}']")["class"].split).to include("h-12", "w-12")
    get group_path(group)
    expect(response.body).to include(group_image_path(group, group.profile_image_attachment, size: :detail),
      group_image_path(group, group.cover_image_attachment, size: :cover))
    get search_path(q: group.name, type: "groups")
    expect(response.body).to include(profile_path)
    expect(response.body).not_to include(group_image_path(group, group.cover_image_attachment, size: :cover))

    sign_in reader
    get search_path(q: group.name, type: "groups")
    expect(response.body).not_to include(profile_path)
    expect(Nokogiri::HTML(response.body).at_css("[data-icon='users-round']")).to be_present

    discoverable = Group.create!(group_admin: admin, name: "Discovered branding", lifecycle_status: :active)
    get discovery_path
    icon = Nokogiri::HTML(response.body).at_css("#discovery_group [data-icon='users-round']")
    expect(icon.parent["class"].split).to include("h-14", "w-14")
    upload_branding(discoverable)
    sign_in reader
    get discovery_path
    expect(response.body).to include(group_image_path(discoverable, discoverable.profile_image_attachment, size: :card))
    image = Nokogiri::HTML(response.body).at_css("#discovery_group img[src='#{group_image_path(discoverable, discoverable.profile_image_attachment, size: :card)}']")
    expect(image["class"].split).to include("h-14", "w-14")
    expect(response.body).not_to include(group_image_path(discoverable, discoverable.cover_image_attachment, size: :cover))
  end

  it "uses icons for inaccessible past groups and images for accessible past groups in the order editor" do
    upload_branding
    group.group_membership_events.create!(user: reader, actor: reader, event_type: :left)
    public_past = Group.create!(group_admin: admin, name: "Public past readers", lifecycle_status: :active)
    public_past.group_membership_events.create!(user: reader, actor: reader, event_type: :left)
    upload_branding(public_past)
    reader.group_list_hidings.create!(group: public_past)
    current = Group.create!(group_admin: admin, name: "Current icon readers", lifecycle_status: :active)
    current.group_memberships.create!(user: reader, status: :active)
    sign_in reader

    get edit_groups_membership_order_path
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    private_card = page.at_css("[data-past-group-id='#{group.id}']")
    expect(private_card.at_css("[data-icon='users-round']")).to be_present
    expect(private_card.css("img")).to be_empty
    expect(response.body).not_to include(group_image_path(group, group.profile_image_attachment, size: :card))
    public_card = page.at_css("[data-hidden-groups] [data-past-group-id='#{public_past.id}']")
    public_image = public_card.at_css("img[src='#{group_image_path(public_past, public_past.profile_image_attachment, size: :card)}']")
    expect(public_image["class"].split).to include("h-12", "w-12")
    expect(page.at_css("[data-group-membership-sort-target='item'] [data-icon='users-round']")).to be_present
  end

  it "colors group activity and detail feeds using each post's destination, including book posts and requotes" do
    group.update!(brand_color: "red")
    other = Group.create!(group_admin: admin, name: "Blue readers", lifecycle_status: :active, brand_color: "blue")
    post = admin.jjaeks.create!(group:, content: "Red group post")
    source = admin.jjaeks.create!(content: "Personal public source")
    requote = admin.jjaeks.create!(group: other, quoted_jjaek: source, content: "Blue group requote")
    book_post = create_jjaek_with_books(user: admin, group: other, content: "Blue book post",
      books: [ Book.create!(title: "Group branding book") ])
    sign_in admin

    get groups_path
    page = Nokogiri::HTML(response.body)
    [ [ post, group ], [ requote, other ], [ book_post, other ] ].each do |jjaek, destination|
      card = page.at_css("article#jjaek_#{jjaek.id}")
      stripe = card.at_css("[data-group-color]")
      expect(stripe["data-group-color"]).to eq(destination.brand_color)
      expect(stripe["style"]).to include(destination.brand_color_hex)
      expect(card.at_css("a[href='#{group_path(destination)}']")).to be_present
    end

    get group_path(other)
    page = Nokogiri::HTML(response.body)
    [ requote, book_post ].each do |jjaek|
      stripes = page.css("article#jjaek_#{jjaek.id} [data-group-color]")
      expect(stripes.size).to eq(1)
      expect(stripes.first["data-group-color"]).to eq("blue")
    end
    get group_path(group)
    expect(Nokogiri::HTML(response.body).at_css("article#jjaek_#{post.id} [data-group-color]")["data-group-color"]).to eq("red")

    [ root_path, user_path(admin), search_path(q: "Blue", type: "jjaeks"),
      search_path(q: other.name, type: "groups"), jjaek_path(requote) ].each do |path|
      get path
      expect(Nokogiri::HTML(response.body).css("[data-group-color]")).to be_empty
    end
  end

  it "colors both current and past group cards without changing past membership information" do
    group.update!(brand_color: "teal")
    group.group_memberships.create!(user: reader, status: :active)
    past = Group.create!(group_admin: admin, name: "Past violet readers", lifecycle_status: :active,
      group_type: :private_group, brand_color: "violet")
    past.group_membership_events.create!(user: reader, actor: reader, event_type: :left)
    sign_in reader

    get groups_path
    page = Nokogiri::HTML(response.body)
    current_card = page.at_css("[data-group-grid] a[href='#{group_path(group)}']").ancestors("article").first
    expect(current_card.at_css("[data-group-color]")["data-group-color"]).to eq("teal")
    past_card = page.at_css("[data-past-group-id='#{past.id}']")
    expect(past_card.at_css("[data-group-color]")["data-group-color"]).to eq("violet")
    expect(past_card.text).to include(I18n.t("groups.past_membership.statuses.left"))
    expect(past_card.at_css("a[href='#{group_path(past.id)}']")).to be_present
    expect(past_card.css("img, [data-group-members]")).to be_empty

    get edit_groups_membership_order_path
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css("[data-group-color]")).to be_empty
  end
end
