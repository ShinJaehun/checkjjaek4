require "rails_helper"

RSpec.describe UsersHelper, type: :helper do
  it "keeps bookshelf tab color mapping keys aligned with Bookshelf color keys" do
    expect(described_class::BOOKSHELF_TAB_CLASSES_BY_COLOR_KEY.keys).to match_array(Bookshelf::COLOR_KEYS)
  end
end
