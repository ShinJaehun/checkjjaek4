require "rails_helper"

RSpec.describe Admin::ContentHelper, type: :helper do
  it "normalizes only Group presentation labels and colors each content kind" do
    expect(helper.admin_content_kind_key(:general, context: :group)).to eq("group_general")
    expect(helper.admin_content_kind_key(:book, context: :group)).to eq("group_book")
    expect(helper.admin_content_kind_key(:comments, context: :group)).to eq("comments")
    expect(helper.admin_content_kind_label(:general, context: :group)).to eq("동아리짹")
    expect(helper.admin_content_kind_label(:book, context: :group)).to eq("동아리 책짹")

    {
      general: "bg-sky-100", book: "bg-emerald-100", requote: "bg-violet-100",
      group_general: "bg-sky-100", group_book: "bg-emerald-100", comments: "bg-amber-100"
    }.each do |kind, color|
      expect(helper.admin_content_kind_badge_classes(kind)).to include(color)
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
