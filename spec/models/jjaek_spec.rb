require "rails_helper"

RSpec.describe Jjaek, type: :model do
  let(:user) { User.create!(name: "Reader", email: "reader-jjaek@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:other_user) { User.create!(name: "Other", email: "other-jjaek@example.com", password: "password123!", password_confirmation: "password123!") }
  let(:book) { Book.create!(title: "북짹", authors_text: "저자") }

  it "allows a jjaek without a book" do
    jjaek = described_class.new(user:, content: "책 없이 남기는 짹")

    expect(jjaek).to be_valid
    jjaek.save!
    expect(jjaek.content_edited_at).to be_nil
  end

  it "tracks moderation hiding separately from author deletion" do
    jjaek = user.jjaeks.create!(content: "Moderated")
    action = ModerationAction.create!(target: jjaek, actor: other_user, action_type: :hide, public_reason: "inappropriate_content", moderation_authority: "platform")
    jjaek.update!(hidden_at: Time.current)

    expect(jjaek).to be_hidden
    expect(jjaek).not_to be_deleted
    expect(jjaek.current_hide_action).to eq(action)
    expect(described_class.visible).not_to include(jjaek)
  end

  it "finds the same unrestored current hide with or without a preloaded association" do
    jjaek = user.jjaeks.create!(content: "Repeated moderation")
    hide_a = ModerationAction.create!(target: jjaek, actor: other_user, action_type: :hide, public_reason: "other", moderation_authority: "platform")
    ModerationAction.create!(target: jjaek, actor: other_user, action_type: :restore, public_reason: "Restore A", moderation_authority: "platform", reversal_of: hide_a)
    hide_b = ModerationAction.create!(target: jjaek, actor: other_user, action_type: :hide, public_reason: "spam_advertising", moderation_authority: "platform")

    expect(jjaek.current_hide_action).to eq(hide_b)

    jjaek.moderation_actions.load
    expect(jjaek.current_hide_action).to eq(hide_b)
  end

  it "records only successful content edits" do
    jjaek = user.jjaeks.create!(content: "A")

    jjaek.update!(visibility: :private_jjaek)
    expect(jjaek.content_edited_at).to be_nil

    jjaek.update!(content: "B")
    edited_at = jjaek.content_edited_at
    expect(edited_at).to be_present

    expect(jjaek.update(content: "")).to be(false)
    expect(jjaek.reload.content_edited_at).to eq(edited_at)
  end

  it "hard deletes a jjaek without persisted comments" do
    jjaek = user.jjaeks.create!(content: "No comments")

    expect { jjaek.destroy_or_tombstone! }.to change(described_class, :count).by(-1)
  end

  it "tombstones a jjaek with comments and preserves its context and edited timestamp" do
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Readers", group_type: :public_group)
    jjaek = user.jjaeks.create!(group:, book:, content: "A")
    jjaek.update!(content: "B")
    edited_at = jjaek.content_edited_at
    comment = jjaek.comments.create!(user: other_user, content: "대화")

    expect { jjaek.destroy_or_tombstone! }.not_to change(described_class, :count)

    jjaek.reload
    expect(jjaek).to be_deleted
    expect(jjaek.content).to eq("")
    expect(jjaek.content_edited_at).to eq(edited_at)
    expect(jjaek.comments).to contain_exactly(comment)
    expect(jjaek.user).to eq(user)
    expect(jjaek.book).to eq(book)
    expect(jjaek.group).to eq(group)
  end

  it "allows a profile-context jjaek with a target user" do
    jjaek = described_class.new(user:, target_user: other_user, content: "프로필 문맥 짹")

    expect(jjaek).to be_valid
  end

  it "does not allow requoting a private jjaek" do
    original = other_user.jjaeks.create!(book:, content: "원문", visibility: :private_jjaek)
    requote = described_class.new(user:, book:, content: "인용", quoted_jjaek: original)

    expect(requote).not_to be_valid
  end

  it "does not allow broader visibility than the original jjaek" do
    original = other_user.jjaeks.create!(book:, content: "원문", visibility: :book_friends)
    requote = described_class.new(user:, book:, content: "인용", quoted_jjaek: original, visibility: :public_jjaek)

    expect(requote).not_to be_valid
    expect(requote.errors.of_kind?(:visibility, :cannot_exceed_quoted_visibility)).to be(true)
  end

  it "does not allow requoting another requote" do
    original = other_user.jjaeks.create!(book:, content: "원문")
    first_requote = user.jjaeks.create!(book:, content: "첫 인용", quoted_jjaek: original)
    nested_requote = described_class.new(user:, book:, content: "중첩 인용", quoted_jjaek: first_requote)

    expect(nested_requote).not_to be_valid
  end

  it "does not allow the same user to requote the same original twice" do
    original = other_user.jjaeks.create!(book:, content: "원문")
    user.jjaeks.create!(book:, content: "첫 인용", quoted_jjaek: original)
    duplicate_requote = described_class.new(user:, book:, content: "두 번째 인용", quoted_jjaek: original)

    expect(duplicate_requote).not_to be_valid
    expect(duplicate_requote.errors.of_kind?(:quoted_jjaek_id, :taken)).to be(true)
  end

  it "checks group requote uniqueness by destination" do
    original = other_user.jjaeks.create!(content: "개인 원문")
    first_group = Group.create!(lifecycle_status: :active, group_admin: user, name: "First readers", group_type: :public_group)
    second_group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Second readers", group_type: :public_group)
    described_class.insert_all!([ { user_id: user.id, group_id: first_group.id, quoted_jjaek_id: original.id, content: "기존 동아리 공유" } ])

    duplicate = described_class.new(user:, group: first_group, quoted_jjaek: original, content: "중복 공유")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:quoted_jjaek_id, :taken)).to be(true)

    other_destination = described_class.new(user:, group: second_group, quoted_jjaek: original, content: "다른 목적지")
    expect(other_destination).to be_valid
    expect(other_destination.errors.of_kind?(:quoted_jjaek_id, :taken)).to be(false)

    personal_destination = described_class.new(user:, quoted_jjaek: original, content: "개인 목적지")
    expect(personal_destination).to be_valid
  end

  it "enforces personal and group requote uniqueness separately in PostgreSQL" do
    original = other_user.jjaeks.create!(content: "개인 원문")
    first_group = Group.create!(lifecycle_status: :active, group_admin: user, name: "First destination", group_type: :public_group)
    second_group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Second destination", group_type: :public_group)
    user.jjaeks.create!(content: "개인 다시짹", quoted_jjaek: original)

    [ first_group, second_group ].each do |group|
      described_class.insert_all!([ { user_id: user.id, group_id: group.id, quoted_jjaek_id: original.id, content: "동아리 공유" } ])
    end

    expect {
      described_class.transaction(requires_new: true) do
        described_class.insert_all!([ { user_id: user.id, quoted_jjaek_id: original.id, content: "중복 개인 다시짹" } ])
      end
    }.to raise_error(ActiveRecord::RecordNotUnique)

    expect {
      described_class.transaction(requires_new: true) do
        described_class.insert_all!([ { user_id: user.id, group_id: first_group.id, quoted_jjaek_id: original.id, content: "중복 동아리 공유" } ])
      end
    }.to raise_error(ActiveRecord::RecordNotUnique)

    user.jjaeks.create!(group: first_group, content: "일반 동아리 짹 하나")
    user.jjaeks.create!(group: first_group, content: "일반 동아리 짹 둘")
    expect(described_class.where(user:, group: first_group, quoted_jjaek_id: nil).count).to eq(2)
  end

  it "allows different users to requote the same original" do
    original = other_user.jjaeks.create!(book:, content: "원문")
    user.jjaeks.create!(book:, content: "첫 인용", quoted_jjaek: original)
    another_user = User.create!(name: "Another", email: "another-jjaek@example.com", password: "password123!", password_confirmation: "password123!")
    other_requote = described_class.new(user: another_user, book:, content: "다른 사용자 인용", quoted_jjaek: original)

    expect(other_requote).to be_valid
  end

  it "allows regular jjaeks and book jjaeks from the same user" do
    general_jjaek = described_class.new(user:, content: "일반 짹")
    book_jjaek = described_class.new(user:, book:, content: "책짹")

    expect(general_jjaek).to be_valid
    expect(book_jjaek).to be_valid
  end

  it "allows a group jjaek with or without a book" do
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Readers", group_type: :public_group)

    expect(described_class.new(user:, group:, content: "그룹 짹")).to be_valid
    expect(described_class.new(user:, group:, book:, content: "그룹 책짹")).to be_valid
  end

  it "does not mix group context with profile context" do
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Readers", group_type: :public_group)

    expect(described_class.new(user:, group:, target_user: other_user, content: "그룹 프로필 짹")).not_to be_valid
  end

  it "allows public personal originals, including book jjaeks, in group requotes without copying the book" do
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Readers", group_type: :public_group)
    general_original = other_user.jjaeks.create!(content: "전체 공개 짹")
    book_original = other_user.jjaeks.create!(book:, content: "전체 공개 책짹")

    [ general_original, book_original ].each do |original|
      group_requote = described_class.new(user:, group:, quoted_jjaek: original, content: "내 의견")

      expect(group_requote).to be_valid
      expect(group_requote.book_id).to be_nil
    end

    blank_opinion = described_class.new(user:, group:, quoted_jjaek: general_original, content: "")
    expect(blank_opinion).not_to be_valid
    expect(blank_opinion.errors.of_kind?(:content, :blank)).to be(true)
  end

  it "rejects book-friends and private personal originals in group requotes" do
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Readers", group_type: :public_group)

    %i[book_friends private_jjaek].each do |visibility|
      original = other_user.jjaeks.create!(content: "제한된 원문", visibility:)
      group_requote = described_class.new(user:, group:, quoted_jjaek: original, content: "내 의견")

      expect(group_requote).not_to be_valid
      expect(group_requote.errors.of_kind?(:quoted_jjaek, :invalid)).to be(true)
    end
  end

  it "allows same-group originals of every group type but rejects cross-group and nested requotes" do
    groups = %i[public_group approval_group private_group].map do |group_type|
      Group.create!(lifecycle_status: :active, group_admin: user, name: group_type.to_s, group_type:)
    end

    groups.each do |group|
      original = user.jjaeks.create!(group:, content: "동아리 원문")
      group_requote = described_class.new(user:, group:, quoted_jjaek: original, content: "내 의견")

      expect(group_requote).to be_valid
      expect(described_class.new(user:, group: groups.find { |item| item != group }, quoted_jjaek: original, content: "다른 동아리")).not_to be_valid

      group_requote.save!
      expect(described_class.new(user:, group:, quoted_jjaek: group_requote, content: "중첩 인용")).not_to be_valid
    end

    book_original = user.jjaeks.create!(group: groups.first, book:, content: "동아리 책짹 원문")
    book_requote = described_class.new(user:, group: groups.first, quoted_jjaek: book_original, content: "책 의견")
    expect(book_requote).to be_valid
    expect(book_requote.book_id).to be_nil
  end

  it "allows public group jjaeks and book jjaeks to be personal requote sources" do
    group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Readers", group_type: :public_group)
    group_jjaek = described_class.create!(user: other_user, group:, content: "그룹 원문")
    group_book_jjaek = described_class.create!(user: other_user, group:, book:, content: "그룹 책짹 원문")

    expect(described_class.new(user:, quoted_jjaek: group_jjaek, content: "다시짹")).to be_valid
    expect(described_class.new(user:, quoted_jjaek: group_book_jjaek, content: "책 다시짹")).to be_valid
  end

  it "does not allow approval or private group jjaeks to be requote sources" do
    %i[approval_group private_group].each do |group_type|
      group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: group_type.to_s, group_type:)
      group_jjaek = described_class.create!(user: other_user, group:, content: "그룹 원문")

      expect(described_class.new(user:, quoted_jjaek: group_jjaek, content: "다시짹")).not_to be_valid
    end
  end

  it "keeps an existing public group requote valid after the source group becomes inactive" do
    group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Lifecycle Readers", group_type: :public_group)
    group_jjaek = described_class.create!(user: other_user, group:, content: "그룹 원문")
    requote = described_class.create!(user:, quoted_jjaek: group_jjaek, content: "다시짹")

    group.update!(lifecycle_status: :inactive, closure_reason: "Closed", closed_at: Time.current)

    expect(requote.reload).to be_valid
    expect(requote.update(content: "수정된 다시짹")).to be(true)
  end

  it "keeps requotes private and marked when the original is destroyed" do
    original = other_user.jjaeks.create!(book:, content: "원문")
    requote = user.jjaeks.create!(book:, content: "인용", quoted_jjaek: original)

    expect { original.destroy! }.to change(described_class, :count).by(-1)

    requote.reload
    expect(requote).to be_private_jjaek
    expect(requote).to be_quoted_source_deleted
    expect(requote.quoted_jjaek_id).to be_nil
    expect(requote.quoted_source_author_name).to eq(other_user.name)
    expect(requote.quoted_source_kind).to eq("book")
  end

  it "marks requotes as deleted source when the original is tombstoned" do
    original = other_user.jjaeks.create!(book:, content: "원문")
    requote = user.jjaeks.create!(book:, content: "인용", quoted_jjaek: original)
    original.comments.create!(user:, content: "댓글")

    original.destroy_or_tombstone!

    expect(original.reload).to be_deleted
    expect(requote.reload).to be_quoted_source_deleted
    expect(requote.quoted_jjaek_id).to be_nil
  end

  it "keeps personal requotes private and group shares public after a hard delete" do
    group = Group.create!(lifecycle_status: :active, group_admin: user, name: "Readers", group_type: :public_group)
    original = other_user.jjaeks.create!(book:, content: "원문")
    personal_requote = user.jjaeks.create!(content: "개인 의견", quoted_jjaek: original)
    group_share = user.jjaeks.create!(group:, content: "동아리 의견", quoted_jjaek: original)
    comment = group_share.comments.create!(user: other_user, content: "별도 토론")
    like = group_share.likes.create!(user: other_user)
    action = ModerationAction.create!(target: group_share, actor: other_user, action_type: :hide,
                                      public_reason: "other", moderation_authority: "platform")

    original.destroy!

    expect(personal_requote.reload).to be_private_jjaek
    expect(personal_requote.quoted_source_author_name).to eq(other_user.name)
    expect(group_share.reload).to be_public_jjaek
    expect(group_share).to be_quoted_source_deleted
    expect(group_share.quoted_jjaek_id).to be_nil
    expect(group_share.quoted_source_author_name).to be_nil
    expect(group_share.quoted_source_kind).to be_nil
    expect(group_share.content).to eq("동아리 의견")
    expect(group_share.group).to eq(group)
    expect(group_share.comments).to contain_exactly(comment)
    expect(group_share.likes).to contain_exactly(like)
    expect(ModerationAction.find(action.id)).to eq(action)
    expect(group_share.update(content: "이어서 쓴 의견")).to be(true)
    expect(group_share.reload).to be_quoted_source_deleted
    expect(group_share).to be_public_jjaek
  end

  it "keeps a same-group quote and its discussion after the source is tombstoned" do
    group = Group.create!(lifecycle_status: :active, group_admin: other_user, name: "Readers", group_type: :private_group)
    group.group_memberships.create!(user:, status: :active)
    original = other_user.jjaeks.create!(group:, book:, content: "동아리 원문")
    quote = user.jjaeks.create!(group:, content: "독립 의견", quoted_jjaek: original)
    comment = quote.comments.create!(user: other_user, content: "독립 댓글")
    like = quote.likes.create!(user: other_user)
    original.comments.create!(user:, content: "원문 댓글")

    original.destroy_or_tombstone!

    expect(original.reload).to be_deleted
    expect(quote.reload).to be_quoted_source_deleted
    expect(quote.quoted_jjaek_id).to be_nil
    expect(quote.quoted_source_author_name).to be_nil
    expect(quote.quoted_source_kind).to be_nil
    expect(quote).to be_public_jjaek
    expect(quote.group).to eq(group)
    expect(quote.content).to eq("독립 의견")
    expect(quote.comments).to contain_exactly(comment)
    expect(quote.likes).to contain_exactly(like)
  end

  it "counts only persisted comments when the association target includes a form object" do
    jjaek = user.jjaeks.create!(content: "댓글 집계")
    jjaek.comments.create!(user: other_user, content: "저장된 댓글")
    jjaek.comments.build(user:, content: "폼용 댓글")

    expect(jjaek.comments_count).to eq(1)
  end

  it "counts only persisted likes when the association target includes an unsaved like" do
    jjaek = user.jjaeks.create!(content: "좋아요 집계")
    jjaek.likes.create!(user: other_user)
    jjaek.likes.build(user:)

    expect(jjaek.likes_count).to eq(1)
  end
end
