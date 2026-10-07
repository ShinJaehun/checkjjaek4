# A Group query can use this contract when its production implementation is added.
# The Admin query runs the same examples now through its own query spec.
RSpec.shared_examples "group content search contract" do |search_context|
  let(:group_admin) { User.create!(name: "Group owner", email: "search-contract-owner@example.com", password: "password123!") }
  let(:platform_admin) { User.create!(name: "Platform operator", email: "search-contract-platform@example.com", password: "password123!", global_admin: true) }
  let(:named_author) { User.create!(name: "RootNameNeedle", email: "root-email-needle@example.com", password: "password123!") }
  let(:comment_author) { User.create!(name: "CommentNameNeedle", email: "comment-email-needle@example.com", password: "password123!") }
  let(:other_author) { User.create!(name: "Other writer", email: "search-contract-other@example.com", password: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Search contract group", group_type: :private_group) }

  before do
    @visible_root = named_author.jjaeks.create!(group:, content: "VisibleRootNeedle")
    @visible_comment = @visible_root.comments.create!(user: comment_author, content: "VisibleCommentNeedle")

    @group_hidden_root = other_author.jjaeks.create!(group:, content: "GroupHiddenRootNeedle")
    Jjaeks::Hide.new(@group_hidden_root, actor: group_admin, public_reason: "other").call!
    @group_hidden_comment = @visible_root.comments.create!(user: other_author, content: "GroupHiddenCommentNeedle")
    Comments::Hide.new(@group_hidden_comment, actor: group_admin, public_reason: "other").call!

    @platform_hidden_root = other_author.jjaeks.create!(group:, content: "PlatformHiddenRootNeedle")
    Jjaeks::Hide.new(@platform_hidden_root, actor: platform_admin, public_reason: "other").call!
    @platform_hidden_comment = @visible_root.comments.create!(user: other_author, content: "PlatformHiddenCommentNeedle")
    Comments::Hide.new(@platform_hidden_comment, actor: platform_admin, public_reason: "other").call!

    @deleted_root = other_author.jjaeks.create!(group:, content: "DeletedRootNeedle")
    @deleted_root.comments.create!(user: other_author, content: "Preserved comment")
    @deleted_root.destroy_or_tombstone!
  end

  it "finds root and comment authors by name, then includes their complete thread" do
    expect(search_threads("RootNameNeedle").map(&:root)).to eq([ @visible_root ])
    expect(search_threads("CommentNameNeedle").map(&:root)).to eq([ @visible_root ])
    expect(search_threads("CommentNameNeedle").sole.comments.map(&:id)).to include(
      @visible_comment.id, @group_hidden_comment.id, @platform_hidden_comment.id
    )
  end

  it "finds visible root and comment bodies" do
    expect(search_threads("VisibleRootNeedle").map(&:root)).to eq([ @visible_root ])
    expect(search_threads("VisibleCommentNeedle").map(&:root)).to eq([ @visible_root ])
  end

  it "finds group-hidden root and comment bodies" do
    expect(search_threads("GroupHiddenRootNeedle").map(&:root)).to eq([ @group_hidden_root ])
    expect(search_threads("GroupHiddenCommentNeedle").map(&:root)).to eq([ @visible_root ])
  end

  it "applies the context's platform-hidden body search boundary to roots and comments" do
    expected_root = search_context == :admin ? [ @platform_hidden_root ] : []
    expected_comment_thread = search_context == :admin ? [ @visible_root ] : []

    expect(search_threads("PlatformHiddenRootNeedle").map(&:root)).to eq(expected_root)
    expect(search_threads("PlatformHiddenCommentNeedle").map(&:root)).to eq(expected_comment_thread)
  end

  it "applies the context's author email search boundary to roots and comments" do
    expected = search_context == :admin ? [ @visible_root ] : []

    expect(search_threads("root-email-needle@example.com").map(&:root)).to eq(expected)
    expect(search_threads("comment-email-needle@example.com").map(&:root)).to eq(expected)
  end

  if search_context == :group_admin
    it "does not search a deleted root even when its old body remains in the database" do
      @deleted_root.update_columns(content: "DeletedRootNeedle")

      expect(search_threads("DeletedRootNeedle")).to be_empty
    end
  end
end
