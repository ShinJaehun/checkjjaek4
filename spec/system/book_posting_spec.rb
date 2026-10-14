require "rails_helper"

RSpec.describe "Book posting location", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Posting reader", email: "posting-system@example.com", password: "password123!") }
  let(:admin) { User.create!(name: "Posting admin", email: "posting-system-admin@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "게시 위치 선택 책", authors_text: "저자") }
  let!(:entry) { user.bookshelf_entries.create!(book: book, status: :reading) }
  let!(:group) { Group.create!(name: "책을 읽는 동아리", group_admin: admin, group_type: :private_group, lifecycle_status: :active) }
  let!(:membership) { group.group_memberships.create!(user: user, status: :active) }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    login_as user, scope: :user
  end

  after { Warden.test_reset! }

  it "keeps the draft and visibility through location changes and posts to the selected club" do
    visit book_path(book)
    expect(page).to have_select(I18n.t("jjaeks.form.posting_location"), selected: I18n.t("jjaeks.actions.publish_book"))
    fill_in I18n.t("jjaeks.form.book_jjaek_content"), with: "게시 위치를 바꿔도 남아 있는 본문"
    select I18n.t("jjaeks.visibility.private_jjaek"), from: I18n.t("jjaeks.form.visibility")

    select I18n.t("jjaeks.actions.publish_group_book"), from: I18n.t("jjaeks.form.posting_location")
    expect(page).to have_no_select(I18n.t("jjaeks.form.visibility"))
    expect(page).to have_button(I18n.t("jjaeks.actions.publish_group_book"), disabled: true)
    select group.name, from: I18n.t("jjaeks.form.posting_group")
    expect(page).to have_text(I18n.t("books.show.group_destination", name: group.name))
    expect(page).to have_field(I18n.t("jjaeks.form.book_jjaek_content"), with: "게시 위치를 바꿔도 남아 있는 본문")

    select I18n.t("jjaeks.actions.publish_book"), from: I18n.t("jjaeks.form.posting_location")
    expect(page).to have_select(I18n.t("jjaeks.form.visibility"), selected: I18n.t("jjaeks.visibility.private_jjaek"))
    expect(page).to have_no_select(I18n.t("jjaeks.form.posting_group"))
    expect(page).to have_button(I18n.t("jjaeks.actions.publish_book"))

    select I18n.t("jjaeks.actions.publish_group_book"), from: I18n.t("jjaeks.form.posting_location")
    expect(page).to have_select(I18n.t("jjaeks.form.posting_group"), selected: group.name)
    click_button I18n.t("jjaeks.actions.publish_group_book")

    expect(page).to have_current_path(group_path(group))
    expect(group.jjaeks.last).to have_attributes(book: book, user: user, quoted_jjaek_id: nil, content: "게시 위치를 바꿔도 남아 있는 본문")
    expect(entry.reload.status).to eq("reading")
    expect(entry.book_activities).to be_empty
  end

  it "defaults to the entering club and can publish the same draft as a personal book post" do
    visit book_path(book, group_id: group.id)
    expect(page).to have_select(I18n.t("jjaeks.form.posting_location"), selected: I18n.t("jjaeks.actions.publish_group_book"))
    expect(page).to have_select(I18n.t("jjaeks.form.posting_group"), selected: group.name)
    expect(page).to have_no_select(I18n.t("jjaeks.form.visibility"))
    fill_in I18n.t("jjaeks.form.book_jjaek_content"), with: "동아리에서 시작한 개인 책짹"

    select I18n.t("jjaeks.actions.publish_book"), from: I18n.t("jjaeks.form.posting_location")
    select I18n.t("jjaeks.visibility.book_friends"), from: I18n.t("jjaeks.form.visibility")
    expect(page).to have_field(I18n.t("jjaeks.form.book_jjaek_content"), with: "동아리에서 시작한 개인 책짹")
    click_button I18n.t("jjaeks.actions.publish_book")

    expect(page).to have_current_path(%r{\A/jjaeks/\d+\z}, ignore_query: true)
    post = user.jjaeks.order(:id).last
    expect(page).to have_current_path(
      jjaek_path(post, return_to: book_path(book, group_id: group.id))
    )
    expect(post).to have_attributes(book: book, group_id: nil, visibility: "book_friends", content: "동아리에서 시작한 개인 책짹")
    expect(group.jjaeks).to be_empty
  end

  it "hides club selection when none is writable and still publishes a personal book post" do
    membership.update!(moderation_status: :activity_suspended)
    visit book_path(book)

    expect(page).to have_no_select(I18n.t("jjaeks.form.posting_location"))
    expect(page).to have_no_select(I18n.t("jjaeks.form.posting_group"))
    expect(page).to have_no_text(I18n.t("jjaeks.form.no_postable_groups"))
    expect(page).to have_css("h2", text: I18n.t("jjaeks.actions.publish_book"), exact_text: true)
    expect(page).to have_button(I18n.t("jjaeks.actions.publish_book"), disabled: false)
    fill_in I18n.t("jjaeks.form.book_jjaek_content"), with: "동아리 선택 없이 작성한 책짹"
    select I18n.t("jjaeks.visibility.private_jjaek"), from: I18n.t("jjaeks.form.visibility")
    click_button I18n.t("jjaeks.actions.publish_book")

    expect(page).to have_current_path(%r{\A/jjaeks/\d+\z}, ignore_query: true)
    post = user.jjaeks.order(:id).last
    expect(page).to have_current_path(
      jjaek_path(post, return_to: book_path(book))
    )
    expect(post).to have_attributes(book: book, group_id: nil, visibility: "private_jjaek", content: "동아리 선택 없이 작성한 책짹")
  end
end
