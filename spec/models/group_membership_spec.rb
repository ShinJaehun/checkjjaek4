require "rails_helper"

RSpec.describe GroupMembership, type: :model do
  let(:group_admin) { User.create!(name: "Group admin", email: "membership-group_admin@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:member) { User.create!(name: "Member", email: "membership-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Readers", group_type: :approval_group) }

  it "uses only pre-membership and active lifecycle states" do
    expect(described_class.statuses.keys).to contain_exactly("pending", "active", "invited")
  end

  describe "personal display order" do
    let!(:memberships) do
      3.times.map do |index|
        club = Group.create!(group_admin:, name: "Ordered club #{index}", lifecycle_status: :active,
                             created_at: Time.zone.parse("2026-10-20 12:00:00") + index.days)
        club.group_memberships.create!(user: member, status: :active)
      end
    end

    def displayed_memberships(user)
      groups = GroupPolicy::MembershipScope.new(user, Group).resolve
      described_class.displayed_for(user:, groups:)
    end

    def reorder_memberships(user, ids)
      groups = GroupPolicy::MembershipScope.new(user, Group).resolve
      described_class.reorder_for!(user:, groups:, ordered_ids: ids)
    end

    it "uses newest group creation first for existing memberships without positions" do
      expect(memberships.map(&:position)).to eq([ nil, nil, nil ])
      expect(displayed_memberships(member).pluck(:id)).to eq(memberships.reverse.map(&:id))

      memberships.first.group.update!(created_at: memberships.last.group.created_at)
      expect(displayed_memberships(member).pluck(:id)).to eq([ memberships.last.id, memberships.first.id, memberships.second.id ])
    end

    it "saves a complete order without altering groups, membership status, or another user's order" do
      owner_memberships = group_admin.group_memberships.order(:id).to_a
      reorder_memberships(group_admin, owner_memberships.map(&:id))
      owner_positions = owner_memberships.map { |membership| membership.reload.position }
      group_attributes = memberships.map { |membership| membership.group.reload.attributes }
      ids = [ memberships.second.id, memberships.first.id, memberships.last.id ]

      reorder_memberships(member, ids.map(&:to_s))

      expect(displayed_memberships(member).pluck(:id)).to eq(ids)
      expect(displayed_memberships(member).pluck(:position)).to eq([ 1, 2, 3 ])
      expect(displayed_memberships(group_admin).pluck(:id)).to eq(owner_memberships.map(&:id))
      expect(owner_memberships.map { |membership| membership.reload.position }).to eq(owner_positions)
      expect(memberships.map { |membership| membership.group.reload.attributes }).to eq(group_attributes)
      expect(memberships.map { |membership| membership.reload.status }).to eq(%w[active active active])
    end

    %i[pending invited].each do |status|
      it "appends a newly activated #{status} membership behind the saved order" do
        ids = memberships.map(&:id)
        reorder_memberships(member, ids)
        older_group = Group.create!(group_admin:, name: "Older club", lifecycle_status: :active, created_at: 1.year.ago)
        joining = older_group.group_memberships.create!(user: member, status:)
        expect(displayed_memberships(member).pluck(:id)).to eq(ids)

        joining.update!(status: :active)

        expect(joining.position).to be_nil
        expect(displayed_memberships(member).pluck(:id)).to eq(ids + [ joining.id ])
      end
    end

    it "keeps remaining positions after leaving and puts a new membership for the same group last" do
      ids = memberships.map(&:id)
      reorder_memberships(member, ids)
      club = memberships.second.group
      memberships.second.destroy!

      expect(displayed_memberships(member).pluck(:id)).to eq([ ids.first, ids.last ])
      expect(displayed_memberships(member).pluck(:position)).to eq([ 1, 3 ])
      rejoining = club.group_memberships.create!(user: member, status: :active)
      expect(rejoining.id).not_to eq(ids.second)
      expect(displayed_memberships(member).pluck(:id)).to eq([ ids.first, ids.last, rejoining.id ])
    end

    it "allows nil positions but rejects zero, negative, and noninteger positions" do
      membership = memberships.first
      [ 0, -1, "invalid" ].each do |position|
        membership.position = position
        expect(membership).not_to be_valid
        expect(membership.errors[:position]).to be_present
      end
      membership.position = nil
      expect(membership).to be_valid
    end

    it "rolls back all positions when saving one membership fails" do
      allow_any_instance_of(described_class).to receive(:update!).and_call_original
      allow_any_instance_of(described_class).to receive(:update!).with(position: 2)
        .and_raise(ActiveRecord::RecordInvalid.new(memberships.second))

      expect {
        reorder_memberships(member, memberships.map(&:id))
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(memberships.map { |membership| membership.reload.position }).to eq([ nil, nil, nil ])
    end

    it "rechecks the current active membership set under the lock" do
      ids = memberships.map(&:id)
      allow(member).to receive(:with_lock).and_wrap_original do |method, *arguments, &block|
        memberships.last.destroy!
        method.call(*arguments, &block)
      end

      expect { reorder_memberships(member, ids) }.to raise_error(described_class::InvalidOrder)
      expect(memberships.first(2).map { |membership| membership.reload.position }).to eq([ nil, nil ])
    end

    it "rolls back if a new membership appears while positions are being written" do
      joining_group = Group.create!(group_admin:, name: "Concurrent join", lifecycle_status: :active)
      inserted = false
      allow_any_instance_of(described_class).to receive(:update!).and_wrap_original do |method, *arguments|
        result = method.call(*arguments)
        unless inserted
          inserted = true
          joining_group.group_memberships.create!(user: member, status: :active)
        end
        result
      end

      expect { reorder_memberships(member, memberships.map(&:id)) }.to raise_error(described_class::InvalidOrder)
      expect(memberships.map { |membership| membership.reload.position }).to eq([ nil, nil, nil ])
    end
  end

  it "does not allow duplicate memberships" do
    described_class.create!(group: group, user: member, status: :pending)
    duplicate = described_class.new(group: group, user: member, status: :active)

    expect(duplicate).not_to be_valid
  end

  it "does not allow a banned user to obtain membership" do
    GroupMemberBan.create!(group:, user: member)

    expect(described_class.new(group:, user: member, status: :active)).not_to be_valid
  end

  it "requires the group_admin membership to be active" do
    membership = group.group_memberships.find_by!(user: group_admin)

    expect(membership.update(status: :pending)).to be(false)
  end

  it "does not allow an active membership to return to pending" do
    membership = described_class.create!(group: group, user: member, status: :active)

    expect(membership.update(status: :pending)).to be(false)
  end

  it "supports an invitation becoming active" do
    membership = described_class.create!(group: group, user: member, status: :invited)

    expect(membership).to be_invited
    expect(membership.update(status: :active)).to be(true)
  end

  it "does not allow an invitation to become pending" do
    membership = described_class.create!(group: group, user: member, status: :invited)

    expect(membership.update(status: :pending)).to be(false)
  end

  it "keeps activity moderation separate from membership lifecycle" do
    membership = described_class.create!(group: group, user: member, status: :active)

    expect(membership).to be_moderation_status_normal
    membership.update!(moderation_status: :activity_suspended)
    expect(membership).to be_active

    expect(membership).to be_activity_suspended
  end

  it "does not allow the group_admin membership to be destroyed" do
    membership = group.group_memberships.find_by!(user: group_admin)

    expect {
      membership.destroy
    }.not_to change(described_class, :count)

    expect(membership).not_to be_destroyed
  end

  it "allows an inactive group's historical admin membership to be destroyed" do
    membership = group.group_memberships.find_by!(user: group_admin)
    group.update!(lifecycle_status: :inactive, closure_reason: "Finished", closed_at: Time.current)

    expect {
      membership.destroy!
    }.to change(described_class, :count).by(-1)
    expect(group.reload.group_admin).to eq(group_admin)
  end
end
