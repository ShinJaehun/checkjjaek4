require "json"
require "net/http"

module BookSearches
  class KakaoAdapter
    class Error < StandardError; end

    ENDPOINT = URI("https://dapi.kakao.com/v3/search/book")

    def self.search(query:, target: "title", sort: "accuracy", page: 1, size: 10)
      new.search(query:, target:, sort:, page:, size:)
    end

    def search(query:, target:, sort:, page:, size:)
      key = api_key
      raise Error, "missing_api_key" if key.blank?

      uri = ENDPOINT.dup
      uri.query = URI.encode_www_form(
        query: query,
        target: target,
        sort: sort,
        page: page,
        size: size
      )

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "KakaoAK #{key}"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      raise Error, "http_error" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError, SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout
      raise Error, "request_failed"
    end

    private

    def api_key
      ENV["KAKAO_REST_API_KEY"].presence ||
        Rails.application.credentials.dig(:kakao, :rest_api_key).presence
    end
  end
end
