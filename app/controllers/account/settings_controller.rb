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

    def update_password
      @user = current_user
      attributes = password_params

      if attributes[:password].blank?
        @user.errors.add(:password, :blank)
      elsif @user.update_with_password(attributes)
        sign_out @user
        return redirect_to new_user_session_path, notice: t("devise.passwords.updated"), status: :see_other
      end

      @password_errors = @user.errors.full_messages
      @user = current_user.reload
      render :show, formats: :html, status: :unprocessable_content
    end

    def update_avatar
      @user = current_user
      upload = params.dig(:user, :avatar)
      @user.avatar = upload if upload.present?
      @user.errors.add(:avatar, :blank) if upload.blank?

      if upload.present? && @user.valid?
        blob = @user.avatar.blob
        begin
          blob.save!
          blob.upload_without_unfurling(upload.open)
        rescue StandardError => error
          blob.purge_later if blob.persisted?
          Rails.logger.error("Avatar upload failed: #{error.class}: #{error.message}")
          @avatar_errors = [ t("settings.avatar.upload_failed") ]
          return render_avatar_failure
        end

        @user.avatar = blob
        if @user.save
          return redirect_to account_settings_path, notice: t("settings.avatar.updated")
        end
        blob.purge_later
      end

      render_avatar_failure
    end

    def destroy_avatar
      @user = current_user
      @user.avatar.purge_later if @user.avatar.attached?
      redirect_to account_settings_path, notice: t("settings.avatar.removed")
    end

    private

    def password_params
      attributes = params.require(:user).permit(:current_password, :password, :password_confirmation)
      attributes[:password_confirmation] ||= ""
      attributes
    end

    def render_avatar_failure
      @avatar_errors ||= @user.errors.full_messages
      @user = current_user.reload
      render :show, status: :unprocessable_content
    end

    def settings_params
      params.require(:user).permit(
        :name,
        :handle,
        :accepts_book_friend_requests,
        :accepts_group_invitations,
        :allows_new_followers
      )
    end
  end
end
