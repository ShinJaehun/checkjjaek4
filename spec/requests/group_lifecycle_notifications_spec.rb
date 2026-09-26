require "rails_helper"

RSpec.describe "Group lifecycle notification scheduling", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "lifecycle-request-owner@example.com", password: "password123!") }
  let!(:platform_admin) { User.create!(name: "Platform admin", email: "lifecycle-request-platform@example.com", password: "password123!", global_admin: true) }
  let!(:suspended_admin) { User.create!(name: "Suspended admin", email: "lifecycle-request-suspended@example.com", password: "password123!", global_admin: true, suspended_at: Time.current) }
  let!(:withdrawn_admin) { User.create!(name: "Withdrawn admin", email: "lifecycle-request-withdrawn@example.com", password: "password123!", global_admin: true, withdrawn_at: Time.current) }

  it "schedules an opening request for only eligible global admins using its actual event" do
    sign_in group_admin
    expect(Notifications::GroupLifecycleNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to be_persisted
      expect(event).to be_opening_requested
      expect(event).to eq(event.group.lifecycle_events.sole)
      expect(recipient_ids).to contain_exactly(platform_admin.id)
    end

    post groups_path, params: { group: { name: "Applicants", group_type: "public_group", application_purpose: "Read together" } }
    expect(response).to redirect_to(group_path(Group.find_by!(name: "Applicants")))
  end

  it "schedules an opening approval for the group admin" do
    group = Group.create!(group_admin:, name: "Pending", group_type: :public_group, application_purpose: "Read")
    sign_in platform_admin
    expect(Notifications::GroupLifecycleNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(group.lifecycle_events.opening_approved.sole)
      expect(recipient_ids).to eq([ group_admin.id ])
    end

    patch approve_admin_group_path(group)
    expect(group.reload).to be_active
  end

  it "snapshots only active members when closing operations" do
    group = Group.create!(group_admin:, name: "Closing", group_type: :public_group, lifecycle_status: :active)
    active = User.create!(name: "Active", email: "lifecycle-request-active@example.com", password: "password123!")
    pending = User.create!(name: "Pending", email: "lifecycle-request-pending@example.com", password: "password123!")
    invited = User.create!(name: "Invited", email: "lifecycle-request-invited@example.com", password: "password123!")
    group.group_memberships.create!(user: active, status: :active)
    group.group_memberships.create!(user: pending, status: :pending)
    group.group_memberships.create!(user: invited, status: :invited)
    sign_in group_admin
    expect(Notifications::GroupLifecycleNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(group.lifecycle_events.operations_closed.sole)
      expect(recipient_ids).to contain_exactly(group_admin.id, active.id)
    end

    patch close_group_path(group), params: { group: { closure_reason: "Private closure reason" } }
    expect(group.reload).to be_inactive
  end

  it "schedules a reactivation request for only eligible global admins" do
    group = Group.create!(group_admin:, name: "Returning", group_type: :public_group, lifecycle_status: :active)
    group.update!(lifecycle_status: :inactive, closure_reason: "Previous closure", closed_at: Time.current)
    sign_in group_admin
    expect(Notifications::GroupLifecycleNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(group.lifecycle_events.reactivation_requested.sole)
      expect(recipient_ids).to contain_exactly(platform_admin.id)
    end

    patch request_reactivation_group_path(group)
    expect(group.reload).to be_pending_approval
  end

  it "snapshots active members for reactivation approval" do
    group = Group.create!(group_admin:, name: "Reopening", group_type: :public_group, lifecycle_status: :active)
    member = User.create!(name: "Member", email: "lifecycle-request-member@example.com", password: "password123!")
    pending = User.create!(name: "Pending", email: "lifecycle-request-other@example.com", password: "password123!")
    group.group_memberships.create!(user: member, status: :active)
    group.group_memberships.create!(user: pending, status: :pending)
    group.update!(lifecycle_status: :inactive, closure_reason: "Previous closure", closed_at: Time.current)
    group.update!(lifecycle_status: :pending_approval)
    sign_in platform_admin
    expect(Notifications::GroupLifecycleNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(group.lifecycle_events.reactivation_approved.sole)
      expect(recipient_ids).to contain_exactly(group_admin.id, member.id)
    end

    patch approve_admin_group_path(group)
    expect(group.reload).to be_active
  end

  it "schedules both real membership events for a recovery transfer" do
    group = Group.create!(group_admin:, name: "Transfer", group_type: :public_group, lifecycle_status: :active)
    new_admin = User.create!(name: "New admin", email: "lifecycle-request-new-admin@example.com", password: "password123!")
    group.group_memberships.create!(user: new_admin, status: :active)
    sign_in platform_admin
    scheduled = []
    allow(Notifications::GroupLifecycleNotifier).to receive(:schedule) { |event:, recipient_ids:| scheduled << [ event, recipient_ids ] }

    patch transfer_admin_group_path(group), params: { new_admin_id: new_admin.id }

    expect(scheduled.map { |event, ids| [ event.event_type, event.user_id, ids ] }).to contain_exactly(
      [ "admin_role_revoked", group_admin.id, [ group_admin.id ] ],
      [ "admin_role_granted", new_admin.id, [ new_admin.id ] ]
    )
    expect(scheduled.map(&:first)).to contain_exactly(*group.group_membership_events.where(event_type: %i[admin_role_revoked admin_role_granted]))
  end
end
