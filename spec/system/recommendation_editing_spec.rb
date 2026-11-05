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
      expect(page).to have_no_field("recommendation-query")
      expect(page).to have_no_button(I18n.t("recommendations.remove_book", title: book.title), enable_aria_label: true)
      expect(page).to have_button(I18n.t("recommendations.edit_books"))
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
      click_button I18n.t("recommendations.edit_books")
      expect(page).to have_no_field("jjaek[content]")
      fill_in "recommendation-query", with: book.title
      click_button I18n.t("book_search.form.submit")
    end
    expect(page).to have_current_path(book_search_path, ignore_query: true)
    within("#recommendation-window") do
      expect(page).to have_field("recommendation-query", with: book.title)
      click_button I18n.t("recommendations.finish_selection")
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

  it "resets between creation and editing and saves selection changes only after both steps" do
    other_book = Book.create!(title: "Another editing book")
    visit root_path
    find("main a[data-recommendation-open]", match: :first).click
    within("#recommendation-window") do
      expect(page).to have_field("recommendation-query")
      expect(page).to have_button(I18n.t("recommendations.finish_selection"), disabled: true)
      fill_in "recommendation-query", with: "editing"
      click_button I18n.t("book_search.form.submit")
    end
    within("main article", text: other_book.title) { click_button I18n.t("recommendations.add") }
    within("#recommendation-window") do
      click_button I18n.t("recommendations.finish_selection")
      fill_in "jjaek[content]", with: "Unsaved new recommendation"
      select I18n.t("jjaeks.visibility.private_jjaek"), from: "jjaek[visibility]"
      click_button I18n.t("recommendations.edit_books")
      expect(page).to have_button(I18n.t("recommendations.remove_book", title: other_book.title), enable_aria_label: true)
      click_button I18n.t("recommendations.finish_selection")
      expect(page).to have_field("jjaek[content]", with: "Unsaved new recommendation")
      expect(page).to have_select("jjaek[visibility]", selected: I18n.t("jjaeks.visibility.private_jjaek"))
    end

    find("main a[data-back-link]").click
    expect(page).to have_current_path(root_path)
    open_edit
    within("#recommendation-window") do
      expect(page).to have_select("jjaek[visibility]", selected: I18n.t("jjaeks.visibility.public_jjaek"))
      fill_in "jjaek[content]", with: "Saved after selecting books"
      select I18n.t("jjaeks.visibility.private_jjaek"), from: "jjaek[visibility]"
      click_button I18n.t("recommendations.edit_books")
      fill_in "recommendation-query", with: "editing"
      click_button I18n.t("book_search.form.submit")
    end
    within("main article", text: other_book.title) { click_button I18n.t("recommendations.add") }
    within("#recommendation-window") do
      expect(page).to have_button(I18n.t("recommendations.remove_book", title: other_book.title), enable_aria_label: true)
      click_button I18n.t("recommendations.remove_book", title: book.title), enable_aria_label: true
      expect(page).to have_no_button(I18n.t("recommendations.remove_book", title: book.title), enable_aria_label: true)
      click_button I18n.t("recommendations.finish_selection")
      expect(page).to have_text(other_book.title)
      expect(page).to have_text(I18n.t("recommendations.summary_count", count: 1))
      expect(page).to have_no_field("recommendation-query")
      expect(page).to have_field("jjaek[content]", with: "Saved after selecting books")
      expect(page).to have_select("jjaek[visibility]", selected: I18n.t("jjaeks.visibility.private_jjaek"))
    end
    expect(recommendation.reload.recommended_books).to eq([ book ])
    expect(recommendation.content).to eq("Original recommendation")
    expect(recommendation).to be_public_jjaek

    within("#recommendation-window") { click_button I18n.t("recommendations.save_edit") }
    expect(page).to have_current_path(jjaek_path(recommendation, return_to: root_path))
    expect(page).to have_no_css("#recommendation-window", visible: true)
    expect(recommendation.reload.recommended_books).to eq([ other_book ])
    expect(recommendation.content).to eq("Saved after selecting books")
    expect(recommendation).to be_private_jjaek
    expect(user.jjaeks.count).to eq(1)
  end
end
