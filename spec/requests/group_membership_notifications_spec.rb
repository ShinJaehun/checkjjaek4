require "rails_helper"

RSpec.describe "Group membership notification scheduling", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "membership-notification-admin@example.com", password: "password123!") }
  let!(:applicant) { User.create!(name: "Applicant", email: "membership-notification-applicant@example.com", password: "password123!") }
  let!(:group) { Group.create!(name: "Approval club", group_admin:, lifecycle_status: :active, group_type: :approval_group) }

  it "passes the actual request event and the current group admin ID" do
    sign_in applicant
    expect(Notifications::GroupMembershipNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(group.group_membership_events.requested_to_join.sole)
      expect(event).to have_attributes(actor: applicant, user: applicant, group:)
      expect(recipient_ids).to eq([ group_admin.id ])
    end

    post group_group_memberships_path(group)

    expect(group.group_memberships.find_by!(user: applicant)).to be_pending
    expect(response).to redirect_to(group_path(group))
  end

  it "passes the actual approval event and applicant ID" do
    membership = group.group_memberships.create!(user: applicant, status: :pending)
    sign_in group_admin
    expect(Notifications::GroupMembershipNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(group.group_membership_events.approved.sole)
      expect(event).to have_attributes(actor: group_admin, user: applicant, group:)
      expect(recipient_ids).to eq([ applicant.id ])
    end

    patch group_group_membership_path(group, membership)

    expect(membership.reload).to be_active
    expect(response).to redirect_to(group_members_path(group))
  end

  it "retains the rejection event after deleting the pending membership" do
    membership = group.group_memberships.create!(user: applicant, status: :pending)
    sign_in group_admin
    expect(Notifications::GroupMembershipNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(group.group_membership_events.request_rejected.sole)
      expect(event).to have_attributes(actor: group_admin, user: applicant, group:)
      expect(recipient_ids).to eq([ applicant.id ])
    end

    delete reject_group_group_membership_path(group, membership)

    expect(GroupMembership.exists?(membership.id)).to be(false)
    expect(group.group_membership_events.request_rejected.sole.user).to eq(applicant)
    expect(response).to redirect_to(group_members_path(group))
  end

  it "does not schedule delivery if request audit creation rolls back" do
    sign_in applicant
    allow(GroupMembershipEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(GroupMembershipEvent.new))
    expect(Notifications::GroupMembershipNotifier).not_to receive(:schedule)

    post group_group_memberships_path(group)

    expect(response).to have_http_status(422)
    expect(group.group_memberships.where(user: applicant)).to be_empty
    expect(group.group_membership_events.where(user: applicant)).to be_empty
  end
end
