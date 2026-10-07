require "rails_helper"

RSpec.describe Groups::ContentThreadQuery do
  let(:group_admin) { User.create!(name: "Group owner", email: "group-query-owner@example.com", password: "password123!") }
  let(:platform_admin) { User.create!(name: "Platform admin", email: "group-query-platform@example.com", password: "password123!", global_admin: true) }
  let(:author) { User.create!(name: "Author", email: "group-query-author@example.com", password: "password123!") }
  let(:group) { Group.create!(lifecycle_status: :active, group_admin:, name: "Query group", group_type: :private_group) }

  def search_threads(term)
    described_class.new(
      group:,
      jjaek_scope: Jjaek.all,
      comment_scope: Comment.all,
      content_section: "all",
      params: { content_q: term }
    ).call.records
  end

  it_behaves_like "group content search contract", :group_admin

  it "restricts even broad input relations to the authorized group" do
    other_group = Group.create!(lifecycle_status: :active, group_admin:, name: "Other search group", group_type: :public_group)
    other_root = author.jjaeks.create!(group: other_group, content: "OtherGroupOnly")
    other_root.comments.create!(user: author, content: "OtherGroupComment")

    expect(search_threads("OtherGroupOnly")).to be_empty
    expect(search_threads("OtherGroupComment")).to be_empty
  end

  it "excludes a platform hide after a restored group hide for both roots and comments" do
    root = author.jjaeks.create!(group:, content: "PlatformAfterGroupRoot")
    comment = root.comments.create!(user: author, content: "PlatformAfterGroupComment")

    Jjaeks::Hide.new(root, actor: group_admin, public_reason: "other").call!
    Comments::Hide.new(comment, actor: group_admin, public_reason: "other").call!
    Jjaeks::Restore.new(root, actor: group_admin, public_reason: "Resolved").call!
    Comments::Restore.new(comment, actor: group_admin, public_reason: "Resolved").call!
    Jjaeks::Hide.new(root, actor: platform_admin, public_reason: "other").call!
    Comments::Hide.new(comment, actor: platform_admin, public_reason: "other").call!

    expect(root.current_hide_action).to be_platform_authority
    expect(comment.current_hide_action).to be_platform_authority
    expect(search_threads("PlatformAfterGroupRoot")).to be_empty
    expect(search_threads("PlatformAfterGroupComment")).to be_empty
  end

  it "includes a group hide after a restored platform hide for both roots and comments" do
    root = author.jjaeks.create!(group:, content: "GroupAfterPlatformRoot")
    comment = root.comments.create!(user: author, content: "GroupAfterPlatformComment")

    Jjaeks::Hide.new(root, actor: platform_admin, public_reason: "other").call!
    Comments::Hide.new(comment, actor: platform_admin, public_reason: "other").call!
    Jjaeks::Restore.new(root, actor: platform_admin, public_reason: "Resolved").call!
    Comments::Restore.new(comment, actor: platform_admin, public_reason: "Resolved").call!
    Jjaeks::Hide.new(root, actor: group_admin, public_reason: "other").call!
    Comments::Hide.new(comment, actor: group_admin, public_reason: "other").call!

    expect(root.current_hide_action).to be_group_authority
    expect(comment.current_hide_action).to be_group_authority
    expect(search_threads("GroupAfterPlatformRoot").map(&:root)).to eq([ root ])
    expect(search_threads("GroupAfterPlatformComment").map(&:root)).to eq([ root ])
  end
end
