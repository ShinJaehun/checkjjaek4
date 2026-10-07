require "rails_helper"

RSpec.describe Admin::GroupContentThreadQuery do
  def search_threads(term)
    described_class.new(
      jjaek_scope: group.jjaeks,
      comment_scope: Comment.joins(:jjaek).where(jjaeks: { group_id: group.id }),
      content_section: "all",
      params: { content_q: term }
    ).call.records
  end

  it_behaves_like "group content search contract", :admin
end
