class LegalController < ApplicationController
  PRIVACY_EFFECTIVE_ON = Date.new(2026, 10, 31)

  skip_before_action :authenticate_user!

  def privacy
    @document = "privacy"
    @effective_date = PRIVACY_EFFECTIVE_ON
    render :show
  end

  def terms
    @document = "terms"
    @effective_date = Date.iso8601(User::TERMS_VERSION)
    render :show
  end
end
