class GroupsController < ApplicationController
  before_action :set_group, only: :show

  def index
    authorize Group
    @groups = policy_scope(Group).includes(:owner, :group_memberships).order(created_at: :desc)
    @invitations = current_user.group_memberships.invited.includes(group: :owner).order(created_at: :desc)
  end

  def show
    authorize @group
    @membership = @group.group_memberships.find_by(user: current_user)
    @pending_memberships = if @group.owner?(current_user)
      @group.group_memberships.pending.includes(:user).order(:created_at)
    else
      GroupMembership.none
    end
    @invite_candidates = if @group.private_group? && @group.owner?(current_user)
      User.where.not(id: @group.group_memberships.select(:user_id)).order(:name)
    else
      User.none
    end
    prepare_jjaek_context
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

  def prepare_jjaek_context
    group_policy = policy(@group)
    @can_read_group_jjaeks = group_policy.read_jjaeks?
    @jjaeks = if @can_read_group_jjaeks
      policy_scope(@group.jjaeks).includes(:user, :book, :group).recent
    else
      Jjaek.none
    end
    @jjaek = Jjaek.new(user: current_user, group: @group) if group_policy.create_jjaek?
  end
end
