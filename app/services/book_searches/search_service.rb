module BookSearches
  class SearchService
    DEFAULT_SIZE = 10

    class << self
      def call(query:, page:, size: DEFAULT_SIZE)
        raw = BookSearches::KakaoAdapter.search(query: query, page: page, size: size)

        {
          results: Array(raw["documents"]).map { |item| normalize(item) },
          meta: normalize_meta(raw["meta"] || {})
        }
      end

      private

      def normalize(item)
        {
          title: item["title"].to_s,
          authors_text: Array(item["authors"]).join(", "),
          publisher: item["publisher"].to_s,
          thumbnail: valid_url(item["thumbnail"]),
          isbn: item["isbn"].to_s,
          contents_excerpt: item["contents"].to_s,
          url: valid_url(item["url"])
        }
      end

      def valid_url(value)
        value.to_s if Book.valid_http_url?(value)
      end

      def normalize_meta(meta)
        {
          total_count: meta["total_count"].to_i,
          pageable_count: meta["pageable_count"].to_i,
          is_end: meta["is_end"]
        }
      end
    end
  end
end
