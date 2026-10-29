class FollowsController < ApplicationController
  include RelationshipManagement

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
    authorize @user, :unfollow?
    follow = current_user.active_follows.find_by(followee: @user)

    unless follow
      redirect_to redirect_target, alert: t("follows.alerts.not_found")
      return
    end

    follow.destroy!

    if params[:return_to] == "relationships"
      render_relationships_change(notice: t("follows.notices.destroyed"))
    else
      redirect_to redirect_target, notice: t("follows.notices.destroyed")
    end
  end

  private

  def set_user
    @user = User.find_by_public_param!(params[:user_id])
  end

  def redirect_target
    params[:return_to] == "relationships" ? relationships_return_path : user_path(@user)
  end
end
