module Account
  class SettingsController < ApplicationController
    def show
      @user = current_user
    end

    def update
      @user = current_user

      if @user.update(settings_params)
        redirect_to account_settings_path, notice: t("settings.notices.updated")
      else
        render :show, status: :unprocessable_content
      end
    end

    private

    def settings_params
      params.require(:user).permit(
        :accepts_book_friend_requests,
        :accepts_group_invitations,
        :allows_new_followers
      )
    end
  end
end
