require "rails_helper"

RSpec.describe Group, type: :model do
  let(:group_admin) { User.create!(name: "Group admin", email: "group-group_admin@example.com", password: "password123!", password_confirmation: "password123!") }

  it "is pending approval by default" do
    group = described_class.create!(group_admin: group_admin, name: "Readers", group_type: :public_group, application_purpose: "Read together")

    expect(group).to be_pending_approval
  end

  it "allows only the lifecycle transitions used for approval, closing, and reactivation" do
    group = described_class.create!(group_admin: group_admin, name: "Readers", group_type: :public_group, application_purpose: "Read together")

    expect(group.update(lifecycle_status: :active)).to be(true)
    expect(
      group.update(
        lifecycle_status: :inactive,
        closure_reason: "Reading activities finished",
        closed_at: Time.current
      )
    ).to be(true)
    expect(group.update(lifecycle_status: :pending_approval)).to be(true)
    expect(group.update(lifecycle_status: :inactive)).to be(false)
  end

  it "allows regular attributes to be updated without a lifecycle transition" do
    group = described_class.create!(group_admin: group_admin, name: "Readers", group_type: :public_group, application_purpose: "Read together")

    expect(group.update(name: "Updated readers")).to be(true)
  end

  it "requires a name" do
    group = described_class.new(group_admin: group_admin, name: "", group_type: :public_group)

    expect(group).not_to be_valid
  end

  it "requires a purpose for a new pending application" do
    group = described_class.new(group_admin: group_admin, name: "Readers", group_type: :public_group)

    expect(group).not_to be_valid
    expect(group.errors[:application_purpose]).to be_present
  end

  it "does not let an existing purpose be removed" do
    group = described_class.create!(group_admin: group_admin, name: "Readers", group_type: :public_group, application_purpose: "Read together")

    expect(group.update(application_purpose: "")).to be(false)
  end

  it "limits application and closure reasons to 500 characters" do
    group = described_class.new(group_admin: group_admin, name: "Readers", group_type: :public_group, application_purpose: "a" * 501)

    expect(group).not_to be_valid

    group.assign_attributes(lifecycle_status: :active, application_purpose: nil, closure_reason: "a" * 501)
    expect(group).not_to be_valid
  end

  it "allows legacy active groups without a purpose to use lifecycle transitions" do
    group = described_class.create!(group_admin: group_admin, name: "Legacy", group_type: :public_group, lifecycle_status: :active)

    expect(group.update(lifecycle_status: :inactive, closure_reason: "Finished", closed_at: Time.current)).to be(true)
    expect(group.update(lifecycle_status: :pending_approval)).to be(true)
    expect(group.update(lifecycle_status: :active)).to be(true)
  end

  describe "#cancel_reactivation_for_withdrawal!" do
    it "cancels only a reactivation request without allowing the transition generally" do
      group = described_class.create!(
        group_admin: group_admin,
        name: "Reactivation",
        group_type: :public_group,
        lifecycle_status: :active
      )
      closed_at = Time.current

      group.update!(
        lifecycle_status: :inactive,
        closure_reason: "Finished",
        closed_at: closed_at
      )
      group.update!(lifecycle_status: :pending_approval)

      expect(group.update(lifecycle_status: :inactive)).to be(false)
      expect(group.reload).to be_pending_approval

      group.cancel_reactivation_for_withdrawal!

      expect(group.reload).to be_inactive
      expect(group.closure_reason).to eq("Finished")
      expect(group.closed_at).to be_within(1.second).of(closed_at)
    end

    it "rejects an initial pending application" do
      group = described_class.create!(
        group_admin: group_admin,
        name: "Initial application",
        group_type: :public_group,
        application_purpose: "Read together"
      )

      expect {
        group.cancel_reactivation_for_withdrawal!
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(group.reload).to be_pending_approval
      expect(group.closed_at).to be_nil
    end
  end


  it "creates an active membership for its group_admin" do
    group = described_class.create!(group_admin: group_admin, name: "Readers", group_type: :public_group, lifecycle_status: :active)

    expect(group.group_memberships.find_by(user: group_admin)).to be_active
  end

  it "includes only active memberships in members" do
    pending_user = User.create!(name: "Pending", email: "pending-group-member@example.com", password: "password123!", password_confirmation: "password123!")
    active_user = User.create!(name: "Active", email: "active-group-member@example.com", password: "password123!", password_confirmation: "password123!")
    group = described_class.create!(group_admin: group_admin, name: "Readers", group_type: :approval_group, lifecycle_status: :active)
    group.group_memberships.create!(user: pending_user, status: :pending)
    group.group_memberships.create!(user: active_user, status: :active)

    expect(group.members).to include(group_admin, active_user)
    expect(group.members).not_to include(pending_user)
  end

  it "includes only active memberships in a user's joined groups" do
    user = User.create!(name: "Reader", email: "joined-groups-reader@example.com", password: "password123!", password_confirmation: "password123!")
    pending_group = described_class.create!(group_admin: group_admin, name: "Pending", group_type: :approval_group, lifecycle_status: :active)
    active_group = described_class.create!(group_admin: group_admin, name: "Active", group_type: :public_group, lifecycle_status: :active)
    pending_group.group_memberships.create!(user: user, status: :pending)
    active_group.group_memberships.create!(user: user, status: :active)

    expect(user.joined_groups).to include(active_group)
    expect(user.joined_groups).not_to include(pending_group)
  end

  describe "#transfer_admin_to!" do
    let(:group) { described_class.create!(group_admin: group_admin, name: "Readers", group_type: :public_group, lifecycle_status: :active) }
    let(:new_admin) { User.create!(name: "New admin", email: "new-group-admin@example.com", password: "password123!", password_confirmation: "password123!") }

    it "transfers to an active member while keeping both memberships active" do
      group.group_memberships.create!(user: new_admin, status: :active)

      expect {
        group.transfer_admin_to!(new_admin, by: group_admin)
      }.to change(GroupMembershipEvent, :count).by(2)

      expect(group.reload.group_admin).to eq(new_admin)
      expect(group.group_memberships.find_by!(user: group_admin)).to be_active
      expect(group.group_memberships.find_by!(user: new_admin)).to be_active
      expect(group.group_membership_events.admin_role_revoked.sole).to have_attributes(user: group_admin, actor: group_admin)
      expect(group.group_membership_events.admin_role_granted.sole).to have_attributes(user: new_admin, actor: group_admin)
    end

    it "rolls back the admin change when an audit event fails" do
      group.group_memberships.create!(user: new_admin, status: :active)
      membership_events = group.group_membership_events
      allow(group).to receive(:group_membership_events).and_return(membership_events)
      allow(membership_events).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(GroupMembershipEvent.new))
      event_count = GroupMembershipEvent.count

      expect { group.transfer_admin_to!(new_admin, by: group_admin) }.to raise_error(ActiveRecord::RecordInvalid)

      expect(group.reload.group_admin).to eq(group_admin)
      expect(GroupMembershipEvent.count).to eq(event_count)
    end

    it "allows a global admin to perform the transfer" do
      global_admin = User.create!(name: "Global admin", email: "global-admin-transfer@example.com", password: "password123!", global_admin: true)
      group.group_memberships.create!(user: new_admin, status: :active)

      group.transfer_admin_to!(new_admin, by: global_admin)

      expect(group.reload.group_admin).to eq(new_admin)
    end

    it "rejects an activity-suspended member until activity is restored" do
      membership = group.group_memberships.create!(user: new_admin, status: :active)
      GroupMemberships::SuspendActivity.new(membership, actor: group_admin, public_reason: "Review").call!

      expect { group.transfer_admin_to!(new_admin, by: group_admin) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(group.reload.group_admin).to eq(group_admin)

      GroupMemberships::RestoreActivity.new(membership, actor: group_admin, public_reason: "Resolved").call!
      group.transfer_admin_to!(new_admin, by: group_admin)
      expect(group.reload.group_admin).to eq(new_admin)
    end

    it "rejects non-active members, nonmembers, and self transfer without changing admin" do
      nonmember = new_admin
      pending = User.create!(name: "Pending", email: "transfer-pending@example.com", password: "password123!", password_confirmation: "password123!")
      invited = User.create!(name: "Invited", email: "transfer-invited@example.com", password: "password123!", password_confirmation: "password123!")
      group.group_memberships.create!(user: pending, status: :pending)
      group.group_memberships.create!(user: invited, status: :invited)

      [ nonmember, pending, invited, group_admin ].each do |target|
        expect { group.transfer_admin_to!(target, by: group_admin) }.to raise_error(ActiveRecord::RecordInvalid)
        expect(group.reload.group_admin).to eq(group_admin)
      end
    end

    it "rejects a stale former admin" do
      next_admin = new_admin
      third_member = User.create!(name: "Third", email: "transfer-third@example.com", password: "password123!", password_confirmation: "password123!")
      group.group_memberships.create!(user: next_admin, status: :active)
      group.group_memberships.create!(user: third_member, status: :active)
      group.transfer_admin_to!(next_admin, by: group_admin)

      expect { group.transfer_admin_to!(third_member, by: group_admin) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(group.reload.group_admin).to eq(next_admin)
    end

    it "rejects transfer while pending approval" do
      pending_group = described_class.create!(group_admin: group_admin, name: "Pending", group_type: :public_group, application_purpose: "Read together")
      pending_group.group_memberships.create!(user: new_admin, status: :active)

      expect { pending_group.transfer_admin_to!(new_admin, by: group_admin) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(pending_group.reload.group_admin).to eq(group_admin)
    end
  end
end
