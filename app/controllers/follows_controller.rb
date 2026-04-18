class FollowsController < ApplicationController
  before_action :set_user

  def create
    authorize @user, :follow?
    current_user.active_follows.find_or_create_by!(followee: @user)

    redirect_to user_path(@user), notice: t("follows.notices.created")
  end

  def destroy
    authorize @user, :follow?
    current_user.active_follows.find_by!(followee: @user).destroy!

    redirect_to user_path(@user), notice: t("follows.notices.destroyed")
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end
end
