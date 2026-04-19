module BookSearches
  class SearchService
    class << self
      def call(query:)
        raw = BookSearches::KakaoAdapter.search(query: query)

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
          thumbnail: item["thumbnail"].presence,
          isbn: item["isbn"].to_s,
          contents_excerpt: item["contents"].to_s,
          url: item["url"].to_s
        }
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
