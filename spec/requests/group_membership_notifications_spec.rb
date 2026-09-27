require "rails_helper"

RSpec.describe "Group membership notification scheduling", type: :request do
  let!(:group_admin) { User.create!(name: "Group admin", email: "membership-notification-admin@example.com", password: "password123!") }
  let!(:applicant) { User.create!(name: "Applicant", email: "membership-notification-applicant@example.com", password: "password123!") }
  let!(:group) { Group.create!(name: "Approval club", group_admin:, lifecycle_status: :active, group_type: :approval_group) }
  let(:private_group) { Group.create!(name: "Private club", group_admin:, lifecycle_status: :active, group_type: :private_group) }

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

  it "passes the invitation event and invitee ID" do
    sign_in group_admin
    expect(Notifications::GroupMembershipNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(private_group.group_membership_events.invited.sole)
      expect(event).to have_attributes(actor: group_admin, user: applicant, group: private_group)
      expect(recipient_ids).to eq([ applicant.id ])
    end

    post invite_group_group_memberships_path(private_group), params: { user_id: applicant.id }

    expect(private_group.group_memberships.find_by!(user: applicant)).to be_invited
    expect(response).to redirect_to(group_members_path(private_group))
  end

  it "passes the acceptance event and event-time admin ID" do
    invitation = private_group.group_memberships.create!(user: applicant, status: :invited)
    sign_in applicant
    expect(Notifications::GroupMembershipNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(private_group.group_membership_events.invitation_accepted.sole)
      expect(event).to have_attributes(actor: applicant, user: applicant, group: private_group)
      expect(recipient_ids).to eq([ group_admin.id ])
    end

    patch accept_group_group_membership_path(private_group, invitation)

    expect(invitation.reload).to be_active
    expect(response).to redirect_to(group_path(private_group))
  end

  it "delivers acceptance to the event-time admin after the admin changes" do
    invitation = private_group.group_memberships.create!(user: applicant, status: :invited)
    delivery_callbacks = []
    allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&callback| delivery_callbacks << callback }
    sign_in applicant

    patch accept_group_group_membership_path(private_group, invitation)

    expect(response).to redirect_to(group_path(private_group))
    event = private_group.group_membership_events.invitation_accepted.sole
    private_group.update!(group_admin: applicant)
    expect(delivery_callbacks.length).to eq(1)
    delivery_callbacks.fetch(0).call

    expect(Notification.find_by!(notifiable: event)).to have_attributes(
      recipient: group_admin, actor: applicant, action: "group_membership_invitation_accepted"
    )
  end

  it "passes the decline event and event-time admin ID after deleting the invitation" do
    invitation = private_group.group_memberships.create!(user: applicant, status: :invited)
    sign_in applicant
    expect(Notifications::GroupMembershipNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(private_group.group_membership_events.invitation_declined.sole)
      expect(event).to have_attributes(actor: applicant, user: applicant, group: private_group)
      expect(recipient_ids).to eq([ group_admin.id ])
      expect(GroupMembership.exists?(invitation.id)).to be(false)
    end

    delete decline_group_group_membership_path(private_group, invitation)

    expect(private_group.group_membership_events.invitation_declined.sole.user).to eq(applicant)
    expect(response).to redirect_to(groups_path)
  end

  it "passes the revocation event and invitee ID after deleting the invitation" do
    invitation = private_group.group_memberships.create!(user: applicant, status: :invited)
    sign_in group_admin
    expect(Notifications::GroupMembershipNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(private_group.group_membership_events.invitation_revoked.sole)
      expect(event).to have_attributes(actor: group_admin, user: applicant, group: private_group)
      expect(recipient_ids).to eq([ applicant.id ])
      expect(GroupMembership.exists?(invitation.id)).to be(false)
    end

    delete revoke_group_group_membership_path(private_group, invitation)

    expect(private_group.group_membership_events.invitation_revoked.sole.user).to eq(applicant)
    expect(response).to redirect_to(group_members_path(private_group))
  end

  it "keeps a successful revocation when notification delivery fails" do
    invitation = private_group.group_memberships.create!(user: applicant, status: :invited)
    delivery_callbacks = []
    allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&callback| delivery_callbacks << callback }
    sign_in group_admin
    allow(Notification).to receive(:notify_once).and_raise(StandardError, "delivery failed")
    allow(Rails.logger).to receive(:error)

    delete revoke_group_group_membership_path(private_group, invitation)

    expect(response).to redirect_to(group_members_path(private_group))
    expect(GroupMembership.exists?(invitation.id)).to be(false)
    event = private_group.group_membership_events.invitation_revoked.sole
    expect(event.user).to eq(applicant)
    expect(delivery_callbacks.length).to eq(1)
    delivery_callbacks.fetch(0).call
    expect(Notification.where(notifiable: event)).to be_empty
  end

  it "passes a cancelled request event and the event-time admin ID after deleting the membership" do
    membership = group.group_memberships.create!(user: applicant, status: :pending)
    sign_in applicant
    expect(Notifications::GroupMembershipNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(group.group_membership_events.join_request_cancelled.sole)
      expect(event).to have_attributes(actor: applicant, user: applicant, group:)
      expect(recipient_ids).to eq([ group_admin.id ])
      expect(GroupMembership.exists?(membership.id)).to be(false)
    end

    delete group_group_membership_path(group, membership)

    expect(response).to redirect_to(groups_path)
  end

  it "keeps the event-time recipient when the group admin changes before delivery" do
    membership = group.group_memberships.create!(user: applicant, status: :pending)
    callbacks = []
    allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&callback| callbacks << callback }
    sign_in applicant

    delete group_group_membership_path(group, membership)

    event = group.group_membership_events.join_request_cancelled.sole
    group.group_memberships.create!(user: applicant, status: :active)
    group.update!(group_admin: applicant)
    expect(callbacks.length).to eq(1)
    callbacks.fetch(0).call
    expect(Notification.find_by!(notifiable: event).recipient).to eq(group_admin)
  end

  it "passes a removal event and the removed user's ID while preserving the marker" do
    membership = group.group_memberships.create!(user: applicant, status: :active)
    sign_in group_admin
    expect(Notifications::GroupMembershipNotifier).to receive(:schedule) do |event:, recipient_ids:|
      expect(event).to eq(group.group_membership_events.removed.sole)
      expect(event).to have_attributes(actor: group_admin, user: applicant, group:)
      expect(recipient_ids).to eq([ applicant.id ])
      expect(GroupMembership.exists?(membership.id)).to be(false)
      expect(GroupMembershipRemoval.exists?(group:, user: applicant)).to be(true)
    end

    delete remove_group_group_membership_path(group, membership)

    expect(response).to redirect_to(group_members_path(group))
  end

  it "does not schedule a notification for public joining or voluntary leaving" do
    public_group = Group.create!(name: "Public club", group_admin:, lifecycle_status: :active, group_type: :public_group)
    sign_in applicant
    expect(Notifications::GroupMembershipNotifier).not_to receive(:schedule)

    post group_group_memberships_path(public_group)
    membership = public_group.group_memberships.find_by!(user: applicant)
    delete group_group_membership_path(public_group, membership)

    expect(public_group.group_membership_events.joined.where(user: applicant)).to exist
    expect(public_group.group_membership_events.left.where(user: applicant)).to exist
  end
end
