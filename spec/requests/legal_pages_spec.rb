require "rails_helper"

RSpec.describe "Legal pages", type: :request do
  it "shows the privacy policy and terms to visitors without sign-in" do
    get privacy_policy_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("legal.privacy.title"), User::TERMS_VERSION)

    get terms_of_service_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("legal.terms.title"), User::TERMS_VERSION)
  end

  it "keeps policy and contact links in the shared footer on public and sign-in pages" do
    [ terms_of_service_path, new_user_session_path ].each do |path|
      get path

      footer = Nokogiri::HTML(response.body).at_css("footer nav")
      expect(footer.at_css(%(a[href="#{privacy_policy_path}"]))).to be_present
      expect(footer.at_css(%(a[href="#{terms_of_service_path}"]))).to be_present
      expect(footer.at_css('a[href="mailto:support@jjaek.kr"]')).to be_present
    end
  end
end
