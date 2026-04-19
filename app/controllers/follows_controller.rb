class FollowsController < ApplicationController
  before_action :set_user

  def create
    authorize @user, :follow?

    follow = current_user.active_follows.find_or_initialize_by(followee: @user)

    if follow.persisted? || follow.save
      redirect_to user_path(@user), notice: t("follows.notices.created")
    else
      redirect_to user_path(@user), alert: follow.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @user, :follow?
    follow = current_user.active_follows.find_by(followee: @user)

    unless follow
      redirect_to user_path(@user), alert: t("follows.alerts.not_found")
      return
    end

    follow.destroy!

    redirect_to user_path(@user), notice: t("follows.notices.destroyed")
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end
end
