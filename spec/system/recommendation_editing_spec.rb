require "rails_helper"

RSpec.describe "Recommendation editing window", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Edit reader", email: "recommendation-edit-system@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Editing search book") }
  let!(:recommendation) do
    record = user.jjaeks.new(content: "Original recommendation", recommendation: true)
    record.jjaek_recommendations.build(book: book, position: 0)
    record.save!
    record
  end

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    login_as user, scope: :user
    allow(BookSearches::SearchService).to receive(:call).and_return(results: [], meta: { is_end: true })
  end

  after { Warden.test_reset! }

  def open_edit
    within("#jjaek_#{recommendation.id}") { click_link I18n.t("jjaeks.actions.edit") }
    expect(page).to have_css("#recommendation-window [data-mode='edit']")
    within("#recommendation-window") do
      expect(page).to have_text(I18n.t("recommendations.edit_title"))
      expect(page).to have_field("jjaek[content]", with: "Original recommendation")
      expect(page).to have_button(I18n.t("recommendations.save_edit"))
    end
  end

  it "opens in place, discards before searching, and preserves inputs until cancellation after searching" do
    visit root_path
    open_edit
    expect(page).to have_current_path(root_path)
    within("#recommendation-window") do
      fill_in "jjaek[content]", with: "Discard this draft"
      click_button I18n.t("book_search.actions.close")
    end
    expect(page).to have_no_css("#recommendation-window", visible: true)
    expect(page).to have_current_path(root_path)

    open_edit
    within("#recommendation-window") do
      fill_in "jjaek[content]", with: "Keep while searching"
      select I18n.t("jjaeks.visibility.private_jjaek"), from: "jjaek[visibility]"
      fill_in "recommendation-query", with: book.title
      click_button I18n.t("book_search.form.submit")
    end
    expect(page).to have_current_path(book_search_path, ignore_query: true)
    within("#recommendation-window") do
      expect(page).to have_field("jjaek[content]", with: "Keep while searching")
      expect(page).to have_select("jjaek[visibility]", selected: I18n.t("jjaeks.visibility.private_jjaek"))
    end
    find("main a[data-back-link]").click
    expect(page).to have_current_path(root_path)
    expect(page).to have_no_css("#recommendation-window", visible: true)
    expect(recommendation.reload.content).to eq("Original recommendation")

    open_edit
    find("header a[href='#{groups_path}']", match: :first).click
    expect(page).to have_current_path(groups_path)
    expect(page).to have_no_css("#recommendation-window", visible: true)
    expect(recommendation.reload.recommended_books).to eq([ book ])
  end
end
