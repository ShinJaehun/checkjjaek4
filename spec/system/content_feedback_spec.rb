require "rails_helper"

RSpec.describe "Content error accessibility", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Reader", email: "content-feedback@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Feedback book") }
  let(:source) { user.jjaeks.create!(content: "Existing post") }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 720 ]
    login_as user, scope: :user
  end
  after { Warden.test_reset! }

  it "updates only the edited field as blank and length errors are corrected" do
    source.comments.create!(user:, content: "Existing comment")
    forms = [
      [ book_path(book), "#jjaek-publish-form", "jjaek[content]", I18n.t("jjaeks.actions.publish_short") ],
      [ jjaek_path(source), %(form[action="#{jjaek_comments_path(source)}"]), "comment[content]", I18n.t("comments.actions.submit") ]
    ]

    forms.each do |path, selector, name, submit|
      visit path
      if name == "jjaek[content]"
        find("button[aria-controls='book-jjaek-form'][aria-expanded='false']").click
        within("#jjaek-composer") { click_button submit }
      else
        within(selector) { click_button submit }
      end

      expect(page).to have_css("#{selector} [data-content-error-type='blank']")

      within(selector) do
        input = find("textarea")
        errors_id = find('[data-content-length-target="errors"]')["id"]
        counter_id = find('[data-content-length-target="counter"]')["id"]
        expect(input["aria-invalid"]).to eq("true")
        expect(input["aria-describedby"].split).to eq([ counter_id, errors_id ])

        fill_in name, with: " "
        expect(page).to have_css('textarea[aria-invalid="true"]')
        fill_in name, with: "한" * 201
        expect(page).to have_css('textarea[aria-invalid="true"]')
        expect(page).to have_css('[data-content-length-target="warning"]', text: I18n.t("content_form.too_long", count: 200))
        expect(page).to have_no_css('[data-content-error-type="blank"]')
        expect(input.evaluate_script("this.validity.customError")).to be(true)

        fill_in name, with: "Corrected"
        expect(page).to have_css('textarea[aria-invalid="false"]')
        expect(input["aria-describedby"].split).to eq([ counter_id ])
        expect(page).to have_no_css('[data-content-length-target="errors"]')
        expect(input.evaluate_script("this.validity.customError")).to be(false)
      end

      edited_id = find("#{selector} textarea")["id"]
      other_inputs = page.all("textarea", visible: :all).reject { |input| input["id"] == edited_id }
      expect(other_inputs).not_to be_empty if name == "comment[content]"
      expect(other_inputs.map { |input| input["aria-invalid"] }).to all(eq("false"))
    end
  end
end
