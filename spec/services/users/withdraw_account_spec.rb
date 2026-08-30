require "rails_helper"

RSpec.describe Users::WithdrawAccount do
  let(:password) { "password123!" }
  let(:user) { User.create!(name: "Leaving", email: "leaving@example.com", password: password, password_confirmation: password) }
  let(:other) { User.create!(name: "Other", email: "withdrawal-other@example.com", password: password, password_confirmation: password) }

  it "anonymizes the user, preserves social content, and removes relationships and reading operations data" do
    original_email = user.email
    book = Book.create!(title: "Withdrawal book", authors_text: "Author")
    jjaek = user.jjaeks.create!(book: book, content: "Preserved Jjaek")
    comment = user.comments.create!(jjaek: other.jjaeks.create!(content: "Conversation"), content: "Preserved comment")
    profile_context = other.jjaeks.create!(target_user: user, content: "Preserved profile context", visibility: :public_jjaek)
    user.active_follows.create!(followee: other)
    other.active_follows.create!(followee: user)
    user.requested_book_friendships.create!(addressee: other)
    third = User.create!(name: "Third", email: "withdrawal-third@example.com", password: password, password_confirmation: password)
    third.requested_book_friendships.create!(addressee: user, status: :accepted)
    user.likes.create!(jjaek: comment.jjaek)
    Notification.create!(recipient: user, actor: other, action: :comment_created, notifiable: comment)
    Notification.create!(recipient: other, actor: user, action: :profile_jjaek_created, notifiable: jjaek)
    entry = user.bookshelf_entries.create!(book: book, bookshelf: user.default_bookshelf, position: 1)
    user.book_activities.create!(book: book, bookshelf_entry: entry, action: :added_to_shelf)
    group = Group.create!(lifecycle_status: :active, group_admin: other, name: "Joined", group_type: :public_group)
    group.group_memberships.create!(user: user, status: :active)

    described_class.new(user, current_password: password).call!

    expect(user.reload).to be_withdrawn
    expect(user.name).to eq("탈퇴한 사용자")
    expect(user.email).to match(/\Awithdrawn-#{user.id}-.*@users\.invalid\z/)
    expect(user.email).not_to eq(original_email)
    expect(user.default_avatar_index).to be_nil
    expect(jjaek.reload.user).to eq(user)
    expect(comment.reload.user).to eq(user)
    expect(profile_context.reload.target_user).to eq(user)
    expect(Follow.where("follower_id = :id OR followee_id = :id", id: user.id)).to be_empty
    expect(BookFriendship.where("requester_id = :id OR addressee_id = :id", id: user.id)).to be_empty
    expect(user.likes).to be_empty
    expect(Notification.where("recipient_id = :id OR actor_id = :id", id: user.id)).to be_empty
    expect(user.group_memberships).to be_empty
    expect(user.bookshelves).to be_empty
    expect(user.bookshelf_entries).to be_empty
    expect(user.book_activities).to be_empty
    expect(Book.exists?(book.id)).to be(true)
  end

  it "rejects an incorrect password, a second withdrawal, and a global admin without partial mutation" do
    expect { described_class.new(user, current_password: "wrong").call! }.to raise_error(described_class::InvalidPassword)
    expect(user.reload).not_to be_withdrawn

    described_class.new(user, current_password: password).call!
    expect { described_class.new(user, current_password: password).call! }.to raise_error(described_class::AlreadyWithdrawn)

    admin = User.create!(name: "Admin", email: "withdrawal-admin@example.com", password: password, password_confirmation: password, global_admin: true)
    expect { described_class.new(admin, current_password: password).call! }.to raise_error(described_class::GlobalAdmin)
    expect(admin.reload).not_to be_withdrawn
  end

  it "rejects withdrawal for a suspended user" do
    user.update!(suspended_at: Time.current)

    expect { described_class.new(user, current_password: password).call! }.to raise_error(described_class::Suspended)
    expect(user.reload).not_to be_withdrawn
  end

  it "blocks an active group admin and succeeds after admin transfer" do
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Managed", group_type: :public_group)
    group.group_memberships.create!(user: other, status: :active)
    jjaek = user.jjaeks.create!(group: group, content: "Group history")

    expect { described_class.new(user, current_password: password).call! }.to raise_error(described_class::ActiveGroupAdmin)
    expect(user.reload).not_to be_withdrawn

    group.transfer_admin_to!(other, by: user)
    described_class.new(user, current_password: password).call!

    expect(group.reload.group_admin).to eq(other)
    expect(group.group_memberships.find_by(user: user)).to be_nil
    expect(group.group_memberships.find_by!(user: other)).to be_active
    expect(jjaek.reload.user).to eq(user)
  end

  it "preserves an inactive group, lifecycle history, and historical admin attribution" do
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Closed", group_type: :public_group)
    group.update!(lifecycle_status: :inactive, closure_reason: "Finished", closed_at: Time.current)
    event = group.lifecycle_events.create!(actor: user, event_type: :operations_closed, detail: "Finished")
    jjaek = user.jjaeks.create!(group: group, content: "Preserved group content")
    comment = other.comments.create!(jjaek: jjaek, content: "Preserved group comment")

    described_class.new(user, current_password: password).call!

    expect(group.reload).to be_inactive
    expect(group.group_admin).to eq(user.reload)
    expect(group.group_memberships.find_by(user: user)).to be_nil
    expect(group.lifecycle_events).to contain_exactly(event)
    expect(jjaek.reload.user).to eq(user)
    expect(comment.reload.jjaek).to eq(jjaek)
  end

  it "removes only a safe initial pending application" do
    empty_group = Group.create!(group_admin: user, name: "Empty pending", group_type: :public_group, application_purpose: "Apply")
    empty_group.lifecycle_events.create!(actor: user, event_type: :opening_requested, detail: "Apply")
    described_class.new(user, current_password: password).call!
    expect(Group.exists?(empty_group.id)).to be(false)
  end

  it "rolls back an initial pending application with unexpected content or membership" do
    content_user = User.create!(name: "Content group_admin", email: "withdrawal-content@example.com", password: password, password_confirmation: password)
    content_group = Group.create!(group_admin: content_user, name: "Pending content", group_type: :public_group, application_purpose: "Apply")
    content_jjaek = content_user.jjaeks.create!(group: content_group, content: "Unexpected")

    expect { described_class.new(content_user, current_password: password).call! }.to raise_error(described_class::PendingGroupHasContent)
    expect(content_user.reload).not_to be_withdrawn
    expect(content_group.reload).to be_persisted
    expect(content_jjaek.reload).to be_persisted

    membership_user = User.create!(name: "Membership group_admin", email: "withdrawal-membership-group_admin@example.com", password: password, password_confirmation: password)
    extra_member = User.create!(name: "Extra", email: "withdrawal-extra-member@example.com", password: password, password_confirmation: password)
    membership_group = Group.create!(group_admin: membership_user, name: "Pending membership", group_type: :public_group, application_purpose: "Apply")
    membership_group.group_memberships.create!(user: extra_member, status: :active)

    expect { described_class.new(membership_user, current_password: password).call! }.to raise_error(described_class::PendingGroupHasContent)
    expect(membership_user.reload).not_to be_withdrawn
    expect(membership_group.reload).to be_persisted
  end

  it "cancels a reactivation request while preserving its group, content, history, and historical admin" do
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Reactivation", group_type: :public_group)
    jjaek = user.jjaeks.create!(group: group, content: "Past operations")
    comment = other.comments.create!(jjaek: jjaek, content: "Past discussion")
    group.update!(lifecycle_status: :inactive, closure_reason: "Season ended", closed_at: Time.current)
    close_event = group.lifecycle_events.create!(actor: user, event_type: :operations_closed, detail: "Season ended")
    group.update!(lifecycle_status: :pending_approval)
    request_event = group.lifecycle_events.create!(actor: user, event_type: :reactivation_requested)

    described_class.new(user, current_password: password).call!

    expect(group.reload).to be_inactive
    expect(group.group_admin).to eq(user.reload)
    expect(group.group_memberships.find_by(user: user)).to be_nil
    expect(group.jjaeks).to contain_exactly(jjaek)
    expect(comment.reload.jjaek).to eq(jjaek)
    expect(group.lifecycle_events).to contain_exactly(close_event, request_event)
    expect(group.closed_at).to be_present
    expect(group.closure_reason).to eq("Season ended")
  end

  it "preserves a content-free reactivation request as an inactive historical group" do
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Empty reactivation", group_type: :public_group)
    group.update!(lifecycle_status: :inactive, closure_reason: "Paused", closed_at: Time.current)
    history = group.lifecycle_events.create!(actor: user, event_type: :operations_closed, detail: "Paused")
    group.update!(lifecycle_status: :pending_approval)
    request_event = group.lifecycle_events.create!(actor: user, event_type: :reactivation_requested)

    described_class.new(user, current_password: password).call!

    expect(group.reload).to be_inactive
    expect(group.group_memberships.find_by(user: user)).to be_nil
    expect(group.lifecycle_events).to contain_exactly(history, request_event)
  end
end
