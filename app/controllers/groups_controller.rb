class GroupsController < ApplicationController
  before_action :set_group, only: :show

  def index
    authorize Group
    @groups = policy_scope(Group).includes(:owner, :group_memberships).order(created_at: :desc)
  end

  def show
    authorize @group
    @membership = @group.group_memberships.find_by(user: current_user)
    @pending_memberships = if @group.owner?(current_user)
      @group.group_memberships.pending.includes(:user).order(:created_at)
    else
      GroupMembership.none
    end
  end

  def new
    @group = current_user.owned_groups.build
    authorize @group
  end

  def create
    @group = current_user.owned_groups.build(group_params)
    authorize @group

    if @group.save
      redirect_to @group, notice: t("groups.notices.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def set_group
    @group = policy_scope(Group).find(params[:id])
  end

  def group_params
    params.fetch(:group, {}).permit(:name, :description, :group_type)
  end
end
