require "rails_helper"

RSpec.describe "Account withdrawals", type: :request do
  let(:password) { "password123!" }
  let!(:user) { User.create!(name: "Reader", email: "withdrawal-request@example.com", password: password, password_confirmation: password) }

  it "requires sign in for the confirmation page" do
    get account_withdrawal_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "requires the current password without mutating the account" do
    sign_in user

    delete account_withdrawal_path, params: { account_withdrawal: { current_password: "wrong" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("현재 비밀번호가 올바르지 않습니다.")
    expect(user.reload).not_to be_withdrawn
  end

  it "signs out, blocks the original credentials, and renders preserved content anonymously" do
    original_email = user.email
    jjaek = user.jjaeks.create!(content: "Preserved writing")
    comment = user.comments.create!(jjaek: jjaek, content: "Preserved reply")
    viewer = User.create!(name: "Viewer", email: "withdrawal-viewer@example.com", password: password, password_confirmation: password)
    sign_in user

    delete account_withdrawal_path, params: { account_withdrawal: { current_password: password } }

    expect(response).to redirect_to(root_path)
    get account_withdrawal_path
    expect(response).to redirect_to(new_user_session_path)

    post user_session_path, params: { user: { email: original_email, password: password } }
    expect(response).not_to redirect_to(root_path)

    sign_in viewer
    get jjaek_path(jjaek)
    expect(response.body).to include("탈퇴한 사용자", "Preserved writing", "Preserved reply")
    expect(response.body).to include("withdrawn_user")
    expect(jjaek.reload.user).to eq(user.reload)
    expect(comment.reload.user).to eq(user)
  end

  it "creates a new user id when registering again with the released identity fields" do
    original_id = user.id
    original_name = user.name
    original_email = user.email
    jjaek = user.jjaeks.create!(content: "Historical writing")
    sign_in user

    delete account_withdrawal_path, params: { account_withdrawal: { current_password: password } }

    withdrawn_user = User.find(original_id)
    expect(withdrawn_user).to be_withdrawn
    expect(withdrawn_user.withdrawn_at).to be_present
    expect(withdrawn_user.email).not_to eq(original_email)
    expect(jjaek.reload.user_id).to eq(original_id)

    expect {
      post user_registration_path, params: {
        user: {
          name: original_name,
          email: original_email,
          password: password,
          password_confirmation: password
        }
      }
    }.to change(User, :count).by(1)

    new_user = User.find_by!(email: original_email)
    expect(response).to redirect_to(root_path)
    expect(new_user.id).not_to eq(original_id)
    expect(new_user.name).to eq(original_name)
    expect(new_user).not_to be_withdrawn
    expect(new_user.default_avatar_index).to be_present
    expect(withdrawn_user.reload).to be_withdrawn
    expect(withdrawn_user.default_avatar_index).to be_nil
    expect(jjaek.reload.user_id).to eq(original_id)
    expect(jjaek.user).to eq(withdrawn_user)
  end

  it "redirects the Devise registration delete path without hard deleting anything" do
    jjaek = user.jjaeks.create!(content: "Must remain")
    comment = user.comments.create!(jjaek: jjaek, content: "Must also remain")
    sign_in user

    expect {
      delete user_registration_path
    }.not_to change(User, :count)

    expect(response).to redirect_to(account_withdrawal_path)
    expect(Jjaek.exists?(jjaek.id)).to be(true)
    expect(Comment.exists?(comment.id)).to be(true)
    expect(user.reload).not_to be_withdrawn
  end

  it "blocks new interactions with a withdrawn user" do
    Users::WithdrawAccount.new(user, current_password: password).call!
    actor = User.create!(name: "Actor", email: "withdrawal-actor@example.com", password: password, password_confirmation: password)
    private_group = Group.create!(lifecycle_status: :active, group_admin: actor, name: "Private", group_type: :private_group)
    sign_in actor

    expect { post user_follow_path(user) }.not_to change(Follow, :count)
    expect { post user_book_friendship_path(user) }.not_to change(BookFriendship, :count)
    expect {
      post invite_group_group_memberships_path(private_group), params: { user_id: user.id }
    }.not_to change(GroupMembership, :count)
    expect {
      post jjaeks_path, params: { jjaek: { target_user_id: user.id, content: "Blocked", visibility: :book_friends } }
    }.not_to change(Jjaek, :count)
  end

  it "treats an AlreadyWithdrawn race as completed and signs out" do
    sign_in user
    allow_any_instance_of(Users::WithdrawAccount).to receive(:call!).and_raise(Users::WithdrawAccount::AlreadyWithdrawn)

    delete account_withdrawal_path, params: { account_withdrawal: { current_password: password } }

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq(I18n.t("account_withdrawals.notices.completed"))
    get account_withdrawal_path
    expect(response).to redirect_to(new_user_session_path)
  end
end
