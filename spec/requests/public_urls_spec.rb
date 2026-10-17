require "rails_helper"

RSpec.describe "Public user URLs", type: :request do
  let(:viewer) { User.create!(name: "Viewer", email: "url-viewer@example.com", password: "password123!") }
  let(:reader) { User.create!(name: "Reader", email: "url-reader@example.com", password: "password123!", handle: "reader_one") }

  it "resolves handles and numeric IDs for profiles without changing authentication" do
    get user_path(reader)
    expect(response).to redirect_to(new_user_session_path)

    sign_in viewer
    get user_path(reader)
    expect(response).to have_http_status(:ok)
    get "/users/#{reader.id}"
    expect(response).to have_http_status(:ok)
  end

  it "resolves nested library and relationship mutations through the handle" do
    sign_in viewer

    get user_library_path(reader)
    expect(response).to redirect_to(user_path(reader))

    post user_follow_path(reader)
    expect(response).to redirect_to(user_path(reader))
    expect(viewer.reload.follows?(reader)).to be(true)

    post user_book_friendship_path(reader)
    expect(response).to redirect_to(user_path(reader))
    expect(BookFriendship.between(viewer, reader)).to be_present

    sign_in reader
    get user_library_path(reader)
    expect(response).to have_http_status(:ok)
  end

  it "keeps admin user lookup available when links use a handle" do
    admin = User.create!(name: "Admin", email: "url-admin@example.com", password: "password123!", global_admin: true)
    sign_in admin

    get admin_user_path(reader)
    expect(response).to have_http_status(:ok)
    get "/admin/users/#{reader.id}"
    expect(response).to have_http_status(:ok)
  end
end
