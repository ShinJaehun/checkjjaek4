module Account
  class SettingsController < ApplicationController
    def show
      @user = current_user
    end

    def update
      @user = current_user
      attributes = settings_params

      if with_settings_lock { @user.update(attributes) }
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
      elsif with_settings_lock { @user.update_with_password(attributes) }
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
      if upload.present? && !upload.is_a?(ActionDispatch::Http::UploadedFile)
        @user.errors.add(:avatar, :invalid_format)
        return render_avatar_failure
      end
      @user.avatar = upload if upload.present?
      @user.errors.add(:avatar, :blank) if upload.blank?

      return render_avatar_failure if upload.blank? || !@user.valid?

      blob = @user.avatar.blob
      begin
        blob.save!
        blob.upload_without_unfurling(upload.open)
      rescue StandardError => error
        Rails.logger.error("Avatar upload failed: #{error.class}: #{error.message}")
        @avatar_errors = [ t("settings.avatar.upload_failed") ]
        return render_avatar_failure
      end

      saved = with_settings_lock { @user.save_validated_avatar(blob) }
      if saved
        redirect_to account_settings_path, notice: t("settings.avatar.updated")
      else
        render_avatar_failure
      end
    ensure
      blob.purge_later if !saved && blob&.persisted? && !blob.attachments.exists?
    end

    def destroy_avatar
      @user = current_user
      with_settings_lock { @user.avatar_attachment&.destroy! }
      redirect_to account_settings_path, notice: t("settings.avatar.removed"), status: :see_other
    end

    private

    def with_settings_lock
      current_user.with_lock do
        raise Pundit::NotAuthorizedError unless current_user.active_account? && !current_user.suspended?

        yield
      end
    end

    def password_params
      attributes = params.require(:user).permit(:current_password, :password, :password_confirmation)
      attributes[:password_confirmation] ||= ""
      attributes
    end

    def render_avatar_failure
      @avatar_errors ||= @user.errors.map { |error| helpers.user_validation_error_message(error) }
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
