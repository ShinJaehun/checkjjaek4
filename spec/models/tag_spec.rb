require "rails_helper"

RSpec.describe Tag, type: :model do
  it "extracts the same valid tokens used for links and canonicalizes names" do
    content = "#어린왕자 #독서_토론 #2026독서 #1984 #Reading #reading #독서 토론 #독서-토론 #독서.토론 #"

    expect(described_class.extract_names(content)).to eq(%w[어린왕자 독서_토론 2026독서 1984 reading 독서])
    expect(described_class.extract_names("#한글 #한글")).to eq([ "한글" ])
    expect(described_class.canonical_name("READING")).to eq("reading")
    expect(described_class.canonical_name("독서-토론")).to be_nil
  end
end
