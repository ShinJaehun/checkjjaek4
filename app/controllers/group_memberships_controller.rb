class GroupMembershipsController < ApplicationController
  before_action :set_group
  before_action :authorize_group_access, only: %i[update destroy]
  before_action :set_membership, only: %i[update destroy]

  def create
    @membership = @group.group_memberships.build(
      user: current_user,
      status: @group.public_group? ? :active : :pending
    )
    authorize @membership

    if @membership.save
      notice = @membership.active? ? t("group_memberships.notices.joined") : t("group_memberships.notices.requested")
      redirect_to @group, notice: notice
    else
      redirect_to @group, alert: @membership.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @membership, :approve?
    @membership.active!

    redirect_to @group, notice: t("group_memberships.notices.approved")
  end

  def destroy
    authorize @membership
    pending = @membership.pending?
    @membership.destroy!

    redirect_to groups_path,
                notice: t(pending ? "group_memberships.notices.cancelled" : "group_memberships.notices.left"),
                status: :see_other
  end

  private

  def set_group
    @group = policy_scope(Group).find(params[:group_id])
  end

  def set_membership
    @membership = @group.group_memberships.find(params[:id])
  end

  def authorize_group_access
    authorize @group, :show?
  end
end
