require "rails_helper"

RSpec.describe "Admin user inventory", type: :request do
  let!(:admin) { User.create!(name: "Global Admin", email: "global-admin@example.com", password: "password123!", global_admin: true) }
  let!(:reader) { User.create!(name: "Alpha Reader", email: "alpha@example.com", password: "password123!", created_at: 3.days.ago) }
  let!(:withdrawn) { User.create!(name: "Withdrawn Reader", email: "withdrawn@example.com", password: "password123!") }

  before do
    withdrawn.update_columns(
      email: "withdrawn-#{withdrawn.id}-replacement@users.invalid",
      withdrawn_at: 1.day.ago
    )
  end

  def listed_ids
    Nokogiri::HTML(response.body).css("tbody tr").filter_map { |row| row["id"]&.delete_prefix("user_")&.to_i }
  end

  it "allows only a global admin to access the list and details" do
    get admin_users_path
    expect(response).to redirect_to(new_user_session_path)

    Group.create!(group_admin: reader, name: "Managed by reader", group_type: :public_group, application_purpose: "Read")
    sign_in reader
    get admin_users_path
    expect(response).to redirect_to(root_path)
    get admin_user_path(admin)
    expect(response).to redirect_to(root_path)

    sign_in admin
    get admin_users_path
    expect(response).to have_http_status(:ok)
    get admin_user_path(reader)
    expect(response).to have_http_status(:ok)
  end

  it "combines name or email search with account and role filters" do
    sign_in admin
    get admin_users_path, params: { q: "alpha@", status: "active", role: "regular" }
    expect(listed_ids).to eq([ reader.id ])

    get admin_users_path, params: { q: "Withdrawn", status: "withdrawn" }
    expect(listed_ids).to eq([ withdrawn.id ])

    get admin_users_path, params: { role: "global_admin" }
    expect(listed_ids).to eq([ admin.id ])
  end

  it "filters non-exclusive global admin and group admin roles and regular users" do
    Group.create!(group_admin: admin, name: "Admin club", group_type: :public_group, application_purpose: "Read")
    Group.create!(group_admin: reader, name: "Reader club", group_type: :public_group, application_purpose: "Read")
    sign_in admin

    get admin_users_path, params: { role: "global_admin" }
    expect(listed_ids).to contain_exactly(admin.id)
    expect(Nokogiri::HTML(response.body).at_css("#user_#{admin.id}").text).to include("Global admin")

    get admin_users_path, params: { role: "group_admin" }
    expect(listed_ids).to contain_exactly(admin.id, reader.id)
    expect(Nokogiri::HTML(response.body).at_css("#user_#{admin.id}").text).to include("Global admin", "동아리 관리자")

    get admin_users_path, params: { role: "regular" }
    expect(listed_ids).to contain_exactly(withdrawn.id)
    expect(Nokogiri::HTML(response.body).at_css("#user_#{withdrawn.id}").text).to include("일반 사용자")
  end

  it "hides the withdrawn replacement email while retaining lifecycle details" do
    sign_in admin
    get admin_users_path, params: { status: "withdrawn" }

    row = Nokogiri::HTML(response.body).at_css("#user_#{withdrawn.id}")
    expect(row.text).to include("본인 탈퇴", I18n.l(withdrawn.withdrawn_at, format: :short))
    expect(row.at_css('[data-field="email"]').text.strip).to eq("-")
    expect(row.text).not_to include(withdrawn.email)

    get admin_user_path(withdrawn)
    detail = Nokogiri::HTML(response.body)
    email_label = detail.css("dt").find { |node| node.text.strip == I18n.t("admin.users.fields.email") }
    expect(response.body).to include("본인 탈퇴", I18n.l(withdrawn.withdrawn_at, format: :short))
    expect(email_label.next_element.text.strip).to eq("-")
    expect(response.body).not_to include(withdrawn.email)

    get admin_users_path, params: { q: reader.email }
    expect(Nokogiri::HTML(response.body).at_css("#user_#{reader.id} [data-field='email']").text.strip).to eq(reader.email)
  end

  it "supports whitelisted sorting and falls back safely" do
    sign_in admin
    get admin_users_path, params: { sort: "name" }
    expect(listed_ids.first).to eq(reader.id)
    get admin_users_path, params: { sort: "oldest" }
    expect(listed_ids.first).to eq(reader.id)
    get admin_users_path, params: { sort: "recent" }
    expect(listed_ids.first).to eq(withdrawn.id)
    get admin_users_path, params: { sort: "invalid" }
    expect(listed_ids.first).to eq(withdrawn.id)
  end

  it "paginates without losing filters and handles invalid values safely" do
    49.times { |index| User.create!(name: "Paged #{index}", email: "paged-#{index}@example.com", password: "password123!") }
    sign_in admin

    get admin_users_path, params: { q: "example.com", page: 2, sort: "unknown", status: "unknown" }
    expect(response).to have_http_status(:ok)
    expect(listed_ids.size).to eq(1)
    expect(response.body).to include("q=example.com", "page=1")

    get admin_users_path, params: { page: "invalid", from: "ignored", to: "ignored", role: "invalid" }
    expect(response).to have_http_status(:ok)
    expect(listed_ids.size).to eq(50)

    get admin_users_path, params: { page: 999 }
    expect(response).to have_http_status(:ok)
    expect(listed_ids.size).to eq(2)
  end

  it "shows allowed operational summaries without exposing authentication secrets" do
    group = Group.create!(group_admin: reader, name: "Reader club", group_type: :public_group, application_purpose: "Read")
    sign_in admin
    get admin_user_path(reader)

    expect(response.body).to include(reader.email, group.name, "Jjaek", "Comment")
    expect(response.body).not_to include(reader.encrypted_password, "reset_password_token")
  end
end
