class FollowsController < ApplicationController
  before_action :set_user

  def create
    authorize @user, :follow?

    follow = current_user.active_follows.find_or_initialize_by(followee: @user)

    if follow.persisted? || follow.save
      redirect_to redirect_target, notice: t("follows.notices.created")
    else
      redirect_to redirect_target, alert: follow.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @user, :follow?
    follow = current_user.active_follows.find_by(followee: @user)

    unless follow
      redirect_to redirect_target, alert: t("follows.alerts.not_found")
      return
    end

    follow.destroy!

    if params[:return_to] == "relationships"
      @following_users = current_user.followees.order(:name)
      flash.now[:notice] = t("follows.notices.destroyed")

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to redirect_target, notice: t("follows.notices.destroyed") }
      end
    else
      redirect_to redirect_target, notice: t("follows.notices.destroyed")
    end
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def redirect_target
    params[:return_to] == "relationships" ? relationships_path : user_path(@user)
  end
end
