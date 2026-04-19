require "rails_helper"

RSpec.describe "Authentication", type: :request do
  describe "POST /users" do
    it "creates a user and redirects to the home feed" do
      expect {
        post user_registration_path, params: {
          user: {
            name: "New Reader",
            email: "new-reader@example.com",
            password: "password123!",
            password_confirmation: "password123!"
          }
        }
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /users/sign_in" do
    it "signs in and redirects to the home feed" do
      user = User.create!(
        name: "Signed In Reader",
        email: "signed-in@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      )

      post user_session_path, params: {
        user: {
          email: user.email,
          password: "password123!"
        }
      }

      expect(response).to redirect_to(root_path)
    end
  end

  describe "DELETE /users/sign_out" do
    it "signs out and redirects to the sign-in page" do
      user = User.create!(
        name: "Signed Out Reader",
        email: "signed-out@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      )
      sign_in user

      delete destroy_user_session_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
