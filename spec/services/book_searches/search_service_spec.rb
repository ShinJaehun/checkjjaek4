require "rails_helper"

RSpec.describe BookSearches::SearchService do
  it "normalizes kakao book search results for the view" do
    allow(BookSearches::KakaoAdapter).to receive(:search).with(query: "미움받을 용기", page: 2, size: 10).and_return(
      {
        "meta" => { "total_count" => 1, "pageable_count" => 1, "is_end" => true },
        "documents" => [
          {
            "title" => "미움받을 용기",
            "authors" => [ "기시미 이치로", "고가 후미타케" ],
            "publisher" => "인플루엔셜",
            "thumbnail" => "https://search1.kakaocdn.net/thumb/R120x174.q85/?fname=http%3A%2F%2Fexample.com%2Fcover.jpg",
            "isbn" => "8996991341 9788996991342",
            "contents" => "소개",
            "url" => "https://example.com"
          }
        ]
      }
    )

    result = described_class.call(query: "미움받을 용기", page: 2)

    expect(result[:results].first[:authors_text]).to eq("기시미 이치로, 고가 후미타케")
    expect(result[:results].first[:thumbnail]).to eq("https://search1.kakaocdn.net/thumb/R120x174.q85/?fname=http%3A%2F%2Fexample.com%2Fcover.jpg")
    expect(result[:meta][:total_count]).to eq(1)
  end

  it "accepts partial fields and ignores malformed documents" do
    allow(BookSearches::KakaoAdapter).to receive(:search).and_return(
      "documents" => [nil, "bad", { "title" => "Partial title" }], "meta" => nil
    )
    result = described_class.call(query: "Partial", page: 1)
    expect(result[:results]).to eq([
      { title: "Partial title", authors_text: "", publisher: "", thumbnail: nil, isbn: "", contents_excerpt: "", url: nil }
    ])
  end

  it "treats an invalid provider response as an external search failure" do
    allow(BookSearches::KakaoAdapter).to receive(:search).and_return([])
    expect { described_class.call(query: "Book", page: 1) }.to raise_error(BookSearches::KakaoAdapter::Error)
  end

  it "drops unsafe book and thumbnail URLs" do
    allow(BookSearches::KakaoAdapter).to receive(:search).and_return(
      "documents" => [ { "title" => "책", "url" => "file:///etc/passwd", "thumbnail" => "http://localhost/cover" } ],
      "meta" => {}
    )

    result = described_class.call(query: "책", page: 1).fetch(:results).first

    expect(result[:url]).to be_nil
    expect(result[:thumbnail]).to be_nil
  end
end
