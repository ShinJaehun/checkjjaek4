require "rails_helper"

RSpec.describe "Group content cleanup policy scopes" do
  let(:owner) { User.create!(name: "Owner", email: "cleanup-policy-owner@example.com", password: "password123!") }
  let(:reader) { User.create!(name: "Reader", email: "cleanup-policy-reader@example.com", password: "password123!") }

  it "authorizes restricted access only for actual former participants who cannot currently read" do
    group = Group.create!(group_admin: owner, name: "Private", group_type: :private_group, lifecycle_status: :active)
    post = reader.jjaeks.create!(group:, content: "Own unproven participation")
    comment = post.comments.create!(user: reader, content: "Own comment")
    group.group_membership_events.create!(user: reader, actor: reader, event_type: :requested_to_join)
    expect(GroupPolicy.new(reader, group).cleanup_content?).to be(false)
    expect(GroupPolicy.new(reader, group).hide_from_list?).to be(false)
    expect(JjaekPolicy::GroupCleanupScope.new(reader, Jjaek).resolve).to be_empty
    expect(CommentPolicy::GroupCleanupScope.new(reader, Comment).resolve).to be_empty

    group.group_membership_events.create!(user: reader, actor: reader, event_type: :left)
    policy = GroupPolicy.new(reader, group)
    expect(policy.cleanup_content?).to be(true)
    expect(policy.hide_from_list?).to be(true)
    expect(policy.read_jjaeks?).to be(false)
    expect(policy.show?).to be(false)
    expect(JjaekPolicy.new(reader, post).show?).to be(false)
    expect(CommentPolicy.new(reader, comment).update?).to be(false)
    expect(GroupPolicy.new(nil, group).cleanup_content?).to be(false)

    group.group_memberships.create!(user: reader, status: :active)
    expect(GroupPolicy.new(reader, group).cleanup_content?).to be(false)
    expect(GroupPolicy.new(reader, group).hide_from_list?).to be(false)
    expect(GroupPolicy::PastMembershipScope.new(reader, Group).resolve).to be_empty
  end

  it "matches GroupPolicy#read_jjaeks? across lifecycle, group type, membership, and admin roles" do
    admin = User.create!(name: "Reviewer", email: "cleanup-policy-admin@example.com", password: "password123!", global_admin: true)
    stranger = User.create!(name: "Stranger", email: "cleanup-policy-stranger@example.com", password: "password123!")
    groups = Group.group_types.keys.product(Group.lifecycle_statuses.keys).each_with_index.map do |(type, status), index|
      group = Group.create!(group_admin: owner, name: "#{type} #{status}", group_type: type, lifecycle_status: status,
                            application_purpose: "Read", closure_reason: "Finished", closed_at: (Time.current if status == "inactive"))
      group.group_memberships.create!(user: reader, status: %i[active pending invited][index % 3])
      group.update!(operation_suspended_at: Time.current) if index.even?
      group
    end

    [ owner, reader, stranger, admin, nil ].each do |actor|
      expected = groups.select { |group| GroupPolicy.new(actor, group).read_jjaeks? }.map(&:id)
      expect(GroupPolicy::ReadableContentScope.new(actor, Group).resolve.pluck(:id)).to match_array(expected)
    end
  end

  it "limits post cleanup to the author's undeleted posts in groups they cannot read" do
    unreadable = Group.create!(group_admin: owner, name: "Private", group_type: :private_group, lifecycle_status: :active)
    unreadable.group_membership_events.create!(user: reader, actor: reader, event_type: :left)
    readable = Group.create!(group_admin: owner, name: "Public", lifecycle_status: :active)
    own = reader.jjaeks.create!(group: unreadable, content: "Own")
    hidden = reader.jjaeks.create!(group: unreadable, content: "Hidden", hidden_at: Time.current)
    deleted = reader.jjaeks.create!(group: unreadable, content: "Deleted")
    deleted.comments.create!(user: owner, content: "Preserved")
    deleted.destroy_or_tombstone!
    owner.jjaeks.create!(group: unreadable, content: "Other author")
    reader.jjaeks.create!(group: readable, content: "Readable")
    reader.jjaeks.create!(content: "Personal")

    expect(JjaekPolicy::GroupCleanupScope.new(reader, Jjaek).resolve).to contain_exactly(own, hidden)
    expect(JjaekPolicy::GroupCleanupScope.new(nil, Jjaek).resolve).to be_empty
    expect(JjaekPolicy.new(reader, own).show?).to be(false)
    expect(JjaekPolicy.new(reader, own).update?).to be(false)
    expect(JjaekPolicy.new(reader, own).destroy?).to be(true)
    expect(JjaekPolicy.new(reader, hidden).show?).to be(false)
  end

  it "includes only own group comments and keeps cleanup available on a deleted parent" do
    group = Group.create!(group_admin: owner, name: "Private", group_type: :private_group, lifecycle_status: :active)
    group.group_membership_events.create!(user: reader, actor: reader, event_type: :left)
    parent = owner.jjaeks.create!(group:, content: "Parent")
    own = parent.comments.create!(user: reader, content: "Own comment")
    hidden = parent.comments.create!(user: reader, content: "Hidden", hidden_at: Time.current)
    parent.comments.create!(user: owner, content: "Other comment")
    personal = owner.jjaeks.create!(content: "Personal parent")
    personal.comments.create!(user: reader, content: "Personal comment")
    parent.destroy_or_tombstone!

    expect(CommentPolicy::GroupCleanupScope.new(reader, Comment).resolve).to contain_exactly(own, hidden)
    expect(CommentPolicy::GroupCleanupScope.new(nil, Comment).resolve).to be_empty
    expect(CommentPolicy.new(reader, own).destroy?).to be(true)
    expect(CommentPolicy.new(reader, own).update?).to be(false)
  end
end
