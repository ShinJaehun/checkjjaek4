require "rails_helper"

RSpec.describe JjaekPolicy, "Group Jjaek" do
  let(:group_admin) { User.create!(name: "Group admin", email: "group-jjaek-policy-group_admin@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:member) { User.create!(name: "Member", email: "group-jjaek-policy-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:pending_user) { User.create!(name: "Pending", email: "group-jjaek-policy-pending@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:non_member) { User.create!(name: "Non-member", email: "group-jjaek-policy-non-member@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "Group Book", authors_text: "Author") }

  it "allows signed-in non-members to read public group jjaeks and book jjaeks" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    general = group_admin.jjaeks.create!(group:, content: "Public group jjaek")
    book_jjaek = group_admin.jjaeks.create!(group:, book:, content: "Public group book jjaek")

    expect(described_class.new(non_member, general).show?).to be(true)
    expect(described_class.new(non_member, book_jjaek).show?).to be(true)
  end

  it "allows only active members to read approval group jjaeks" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    group.group_memberships.create!(user: member, status: :active)
    group.group_memberships.create!(user: pending_user, status: :pending)
    jjaek = group_admin.jjaeks.create!(group:, content: "Approval group jjaek")

    expect(described_class.new(member, jjaek).show?).to be(true)
    expect(described_class.new(pending_user, jjaek).show?).to be(false)
    expect(described_class.new(non_member, jjaek).show?).to be(false)
  end

  it "allows only active members to read private group jjaeks" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = group_admin.jjaeks.create!(group:, book:, content: "Private group book jjaek")

    expect(described_class.new(member, jjaek).show?).to be(true)
    expect(described_class.new(non_member, jjaek).show?).to be(false)
  end

  it "does not grant a global admin private group content access" do
    admin = User.create!(name: "Admin", email: "group-jjaek-admin@example.com", password: "password123!", password_confirmation: "password123!", global_admin: true)
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    jjaek = group_admin.jjaeks.create!(group:, content: "Private content")

    expect(described_class.new(admin, jjaek).show?).to be(false)
    expect(described_class::Scope.new(admin, Jjaek.all).resolve).not_to include(jjaek)
  end

  it "scopes group jjaeks by public or active membership access" do
    public_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    approval_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    private_group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Private", group_type: :private_group)
    public_jjaek = group_admin.jjaeks.create!(group: public_group, content: "Public")
    approval_jjaek = group_admin.jjaeks.create!(group: approval_group, content: "Approval")
    private_jjaek = group_admin.jjaeks.create!(group: private_group, content: "Private")
    approval_group.group_memberships.create!(user: non_member, status: :pending)
    private_group.group_memberships.create!(user: non_member, status: :active)

    resolved = described_class::Scope.new(non_member, Jjaek.all).resolve

    expect(resolved).to include(public_jjaek, private_jjaek)
    expect(resolved).not_to include(approval_jjaek)
  end

  it "hides pending and inactive public group jjaeks from nonmembers" do
    pending = Group.create!(group_admin: group_admin, name: "Pending", group_type: :public_group, application_purpose: "Read together")
    inactive = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Inactive", group_type: :public_group)
    inactive.group_memberships.create!(user: member, status: :active)
    pending_jjaek = group_admin.jjaeks.create!(group: pending, content: "Pending")
    inactive_jjaek = group_admin.jjaeks.create!(group: inactive, content: "Inactive")
    inactive.update!(
      lifecycle_status: :inactive,
      closure_reason: "Test closure",
      closed_at: Time.current
    )
    expect(described_class::Scope.new(non_member, Jjaek.all).resolve).not_to include(pending_jjaek, inactive_jjaek)
    expect(described_class::Scope.new(member, Jjaek.all).resolve).to include(inactive_jjaek)
    expect(described_class.new(member, inactive_jjaek).show?).to be(true)
    expect(described_class.new(group_admin, pending_jjaek).show?).to be(false)
  end

  it "allows only active members with the book in their shelf to create" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    group.group_memberships.create!(user: member, status: :active)
    group.group_memberships.create!(user: pending_user, status: :pending)
    member.bookshelf_entries.create!(book: book)

    expect(described_class.new(member, member.jjaeks.build(group:, content: "Group jjaek")).create?).to be(true)
    expect(described_class.new(member, member.jjaeks.build(group:, book:, content: "Group book jjaek")).create?).to be(true)
    expect(described_class.new(pending_user, pending_user.jjaeks.build(group:, content: "Pending")).create?).to be(false)
    expect(described_class.new(non_member, non_member.jjaeks.build(group:, content: "Non-member")).create?).to be(false)
    expect(described_class.new(group_admin, group_admin.jjaeks.build(group:, book:, content: "No shelf entry")).create?).to be(false)
  end

  it "allows an active author to update and destroy a group jjaek" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Group jjaek")
    policy = described_class.new(member, jjaek)

    expect(policy.requote?).to be(false)
    expect(policy.update?).to be(true)
    expect(policy.destroy?).to be(true)
  end

  it "allows an inactive or former author only to destroy their group jjaek" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Approval", group_type: :approval_group)
    membership = group.group_memberships.create!(user: member, status: :inactive)
    jjaek = member.jjaeks.create!(group:, content: "Old group jjaek")

    expect(described_class.new(member, jjaek).update?).to be(false)
    expect(described_class.new(member, jjaek).destroy?).to be(true)

    membership.destroy!

    expect(described_class.new(member, jjaek).update?).to be(false)
    expect(described_class.new(member, jjaek).destroy?).to be(true)
  end

  it "does not let another member or the group group_admin manage someone else's jjaek" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    group.group_memberships.create!(user: member, status: :active)
    group.group_memberships.create!(user: non_member, status: :active)
    jjaek = member.jjaeks.create!(group:, content: "Member jjaek")

    [ group_admin, non_member ].each do |viewer|
      expect(described_class.new(viewer, jjaek).update?).to be(false)
      expect(described_class.new(viewer, jjaek).destroy?).to be(false)
    end
  end

  it "keeps update and destroy for a regular jjaek" do
    jjaek = group_admin.jjaeks.create!(content: "Regular jjaek")
    policy = described_class.new(group_admin, jjaek)

    expect(policy.update?).to be(true)
    expect(policy.destroy?).to be(true)
  end

  it "does not allow updating, destroying, or requoting a deleted jjaek" do
    jjaek = group_admin.jjaeks.create!(content: "Deleted")
    jjaek.comments.create!(user: member, content: "Existing")
    jjaek.destroy_or_tombstone!
    policy = described_class.new(group_admin, jjaek)

    expect(policy.update?).to be(false)
    expect(policy.destroy?).to be(false)
    expect(policy.requote?).to be(false)
  end

  it "excludes group jjaeks and book jjaeks from FeedScope" do
    group = Group.create!(lifecycle_status: :active, group_admin: group_admin, name: "Public", group_type: :public_group)
    general = group_admin.jjaeks.create!(group:, content: "Group jjaek")
    book_jjaek = group_admin.jjaeks.create!(group:, book:, content: "Group book jjaek")
    non_member.active_follows.create!(followee: group_admin)
    BookFriendship.create!(requester: non_member, addressee: group_admin, status: :accepted)

    resolved = described_class::FeedScope.new(non_member, Jjaek.all).resolve

    expect(resolved).not_to include(general, book_jjaek)
  end
end
