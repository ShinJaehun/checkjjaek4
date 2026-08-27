require "rails_helper"

RSpec.describe "Admin user inventory", type: :request do
  let!(:admin) { User.create!(name: "Global Admin", email: "global-admin@example.com", password: "password123!", global_admin: true) }
  let!(:reader) { User.create!(name: "Alpha Reader", email: "alpha@example.com", password: "password123!", created_at: 3.days.ago) }
  let!(:withdrawn) { User.create!(name: "Withdrawn Reader", email: "withdrawn@example.com", password: "password123!") }

  before { withdrawn.update_columns(withdrawn_at: 1.day.ago) }

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

  it "combines name or email search with account and admin filters" do
    sign_in admin
    get admin_users_path, params: { q: "alpha@", status: "active", global_admin: "no" }
    expect(listed_ids).to eq([ reader.id ])

    get admin_users_path, params: { q: "Withdrawn", status: "withdrawn" }
    expect(listed_ids).to eq([ withdrawn.id ])

    get admin_users_path, params: { global_admin: "yes" }
    expect(listed_ids).to eq([ admin.id ])
  end

  it "filters by an inclusive joining period and supports whitelisted sorting" do
    sign_in admin
    get admin_users_path, params: { from: 4.days.ago.to_date.iso8601, to: 2.days.ago.to_date.iso8601 }
    expect(listed_ids).to eq([ reader.id ])

    get admin_users_path, params: { sort: "name" }
    expect(listed_ids.first).to eq(reader.id)
    get admin_users_path, params: { sort: "oldest" }
    expect(listed_ids.first).to eq(reader.id)
    get admin_users_path, params: { sort: "recent" }
    expect(listed_ids.first).to eq(withdrawn.id)
  end

  it "paginates without losing filters and handles invalid values safely" do
    49.times { |index| User.create!(name: "Paged #{index}", email: "paged-#{index}@example.com", password: "password123!") }
    sign_in admin

    get admin_users_path, params: { q: "example.com", page: 2, sort: "unknown", status: "unknown" }
    expect(response).to have_http_status(:ok)
    expect(listed_ids.size).to eq(2)
    expect(response.body).to include("q=example.com", "page=1")

    get admin_users_path, params: { page: "invalid", from: "invalid" }
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
