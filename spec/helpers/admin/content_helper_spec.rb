require "rails_helper"

RSpec.describe Admin::ContentHelper, type: :helper do
  it "uses posting context for post labels and keeps comments distinct" do
    expect(helper.admin_content_kind_key(:general, context: :group)).to eq("group_general")
    expect(helper.admin_content_kind_key(:book, context: :group)).to eq("group_general")
    expect(helper.admin_content_kind_key(:comments, context: :group)).to eq("comments")
    expect(helper.admin_content_kind_label(:general, context: :group)).to eq("동아리짹")
    expect(helper.admin_content_kind_label(:book, context: :group)).to eq("동아리짹")
    expect(helper.admin_content_kind_label(:recommendation)).to eq("짹")
    expect(helper.admin_content_kind_label(:requote)).to eq("다시짹")
    expect(helper.admin_content_kind_label(:requote, context: :group)).to eq("다시짹")

    {
      general: "bg-sky-100", book: "bg-sky-100", requote: "bg-violet-100",
      group_general: "bg-emerald-100", group_book: "bg-emerald-100", comments: "bg-amber-100"
    }.each do |kind, color|
      expect(helper.admin_content_kind_badge_classes(kind)).to include(color)
    end
  end

  it "classifies records exclusively with comments and requotes taking priority over location" do
    [
      [Jjaek.new, "general", "짹", "bg-sky-100"],
      [Jjaek.new(group_id: 1), "group_general", "동아리짹", "bg-emerald-100"],
      [Jjaek.new(quoted_jjaek_id: 2), "requote", "다시짹", "bg-violet-100"],
      [Jjaek.new(group_id: 1, quoted_jjaek_id: 2), "requote", "다시짹", "bg-violet-100"],
      [Jjaek.new(quoted_source_deleted_at: Time.current), "requote", "다시짹", "bg-violet-100"],
      [Jjaek.new(group_id: 1, quoted_source_deleted_at: Time.current), "requote", "다시짹", "bg-violet-100"],
      [Comment.new, "comments", "댓글", "bg-amber-100"]
    ].each do |record, kind, label, color|
      badge = helper.admin_content_badge(record)
      expect(badge.fetch(:kind)).to eq(kind)
      expect(badge.fetch(:label)).to eq(label)
      expect(badge.fetch(:classes)).to include(color)
    end
  end

  it "keeps hidden and deleted status badges distinct" do
    expect(helper.admin_content_status_label(:hidden)).to eq("숨김")
    expect(helper.admin_content_status_badge_classes(:hidden)).to include("bg-red-100")
    expect(helper.admin_content_status_label(:deleted)).to eq("삭제됨")
    expect(helper.admin_content_status_badge_classes(:deleted)).to include("bg-stone-200")
  end

  it "shows a deleted Jjaek as deleted without exposing its body" do
    record = double(content: "deleted body", deleted?: true, hidden?: true)

    expect(helper.admin_content_status(record, record_type: "Jjaek")).to eq(:deleted)
    expect(helper.admin_content_body(record, record_type: "Jjaek")).to eq("-")
  end

  it "keeps hidden Comment text available in the admin inventory" do
    record = double(content: "hidden comment", hidden?: true)

    expect(helper.admin_content_status(record, record_type: "Comment")).to eq(:hidden)
    expect(helper.admin_content_body(record, record_type: "Comment")).to eq("hidden comment")
  end
end
