require "rails_helper"

RSpec.describe BookSearches::SearchService do
  it "normalizes kakao book search results for the view" do
    allow(BookSearches::KakaoAdapter).to receive(:search).and_return(
      {
        "meta" => { "total_count" => 1, "pageable_count" => 1, "is_end" => true },
        "documents" => [
          {
            "title" => "미움받을 용기",
            "authors" => [ "기시미 이치로", "고가 후미타케" ],
            "publisher" => "인플루엔셜",
            "thumbnail" => "",
            "isbn" => "8996991341 9788996991342",
            "contents" => "소개",
            "url" => "https://example.com"
          }
        ]
      }
    )

    result = described_class.call(query: "미움받을 용기")

    expect(result[:results].first[:authors_text]).to eq("기시미 이치로, 고가 후미타케")
    expect(result[:results].first[:thumbnail]).to be_nil
    expect(result[:meta][:total_count]).to eq(1)
  end
end
