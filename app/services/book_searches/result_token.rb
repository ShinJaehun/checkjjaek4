module BookSearches
  class ResultToken
    EXPIRES_IN = 30.minutes

    def self.issue(result, user:)
      attributes = {
        title: result[:title],
        authors_text: result[:authors_text],
        publisher: result[:publisher],
        thumbnail: result[:thumbnail],
        isbn: result[:isbn],
        description: result[:contents_excerpt],
        external_url: result[:url]
      }

      verifier.generate(attributes, expires_in: EXPIRES_IN, purpose: purpose_for(user))
    end

    def self.verify(token, user:)
      return if token.blank?

      attributes = verifier.verified(token, purpose: purpose_for(user))
      attributes.symbolize_keys if attributes.is_a?(Hash)
    end

    def self.verifier
      Rails.application.message_verifier("book_search_result")
    end
    private_class_method :verifier

    def self.purpose_for(user)
      "book_search_result:user:#{user.id}"
    end
    private_class_method :purpose_for
  end
end
