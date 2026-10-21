require "rails_helper"

RSpec.describe "Joined group carousel", type: :system do
  include Warden::Test::Helpers

  let(:user) { User.create!(name: "Carousel reader", email: "group-carousel@example.com", password: "password123!") }

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 900 ]
    page.driver.browser.manage.window.resize_to(390, 900)
    login_as user, scope: :user
  end

  after { Warden.test_reset! }

  it "navigates thirteen groups six at a time with buttons and keyboard at every screen width" do
    groups = 13.times.map do |index|
      Group.create!(lifecycle_status: :active, group_admin: user, name: "Carousel club #{index}", group_type: :private_group)
    end
    expected_pages = groups.reverse.each_slice(6).map { |page_groups| page_groups.map(&:name) }
    visit groups_path

    carousel = find("[data-controller='group-carousel']")
    viewport = carousel.find("[data-group-carousel-target='viewport']")
    position = "[data-group-carousel-target='position']"
    expect(carousel).to have_css(position, exact_text: "1 / 3")
    expect(carousel).to have_css("[data-group-grid] article", count: 6)
    expect(carousel.all("article h3 a").map(&:text)).to eq(expected_pages.first)
    expect(carousel.all("article h3 a", visible: :all).map { |link| link.text(:all) }).to eq(groups.reverse.map(&:name))
    expect(carousel).to have_button(I18n.t("groups.index.carousel.previous"), disabled: true)
    expect(carousel).to have_button(I18n.t("groups.index.carousel.next"), disabled: false)
    expect(viewport.find("[data-group-grid]").evaluate_script("getComputedStyle(this).gridTemplateColumns.split(' ').length")).to eq(1)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)

    carousel.click_button I18n.t("groups.index.carousel.next")
    expect(carousel).to have_css(position, exact_text: "2 / 3")
    expect(carousel.all("article h3 a").map(&:text)).to eq(expected_pages[1])
    carousel.click_button I18n.t("groups.index.carousel.previous")
    expect(carousel).to have_css(position, exact_text: "1 / 3")
    expect(carousel.all("article h3 a").map(&:text)).to eq(expected_pages.first)
    viewport.send_keys(:end)
    expect(carousel).to have_css(position, exact_text: "3 / 3")
    expect(carousel).to have_css("article", count: 1)
    expect(carousel.all("article h3 a").map(&:text)).to eq(expected_pages.last)
    expect(carousel).to have_button(I18n.t("groups.index.carousel.next"), disabled: true)
    viewport.send_keys(:home)
    expect(carousel).to have_css(position, exact_text: "1 / 3")
    viewport.send_keys(:arrow_right)
    expect(carousel).to have_css(position, exact_text: "2 / 3")
    viewport.send_keys(:arrow_left)
    expect(carousel).to have_css(position, exact_text: "1 / 3")

    [ [ 900, 2 ], [ 1280, 3 ] ].each do |width, columns|
      page.current_window.resize_to(width, 900)
      expect(viewport.find("[data-group-grid]").evaluate_script("getComputedStyle(this).gridTemplateColumns.split(' ').length")).to eq(columns)
      expect(carousel).to have_css(position, exact_text: "1 / 3")
      expect(carousel.all("article h3 a").map(&:text)).to eq(expected_pages.first)
    end
    expect(viewport.evaluate_script("new Set(Array.from(this.querySelectorAll('[data-group-carousel-target=page]:not([hidden]) article')).map(card => card.getBoundingClientRect().height)).size")).to eq(1)
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
    carousel.click_button I18n.t("groups.index.carousel.next")
    expect(carousel).to have_css(position, exact_text: "2 / 3")
    expect(carousel.all("article h3 a").map(&:text)).to eq(expected_pages[1])
    carousel.click_button I18n.t("groups.index.carousel.next")
    expect(carousel).to have_css(position, exact_text: "3 / 3")
    expect(carousel.all("article h3 a").map(&:text)).to eq(expected_pages.last)
    viewport.click_link groups.first.name
    expect(page).to have_current_path(group_path(groups.first))
  end

  it "shows the seventh group and its pending request link only on the second page and returns" do
    groups = 7.times.map do |index|
      Group.create!(lifecycle_status: :active, group_admin: user, name: "Seven clubs #{index}", group_type: :approval_group)
    end
    applicant = User.create!(name: "Applicant", email: "carousel-system-applicant@example.com", password: "password123!")
    groups.first.group_memberships.create!(user: applicant, status: :pending)
    visit groups_path

    carousel = find("[data-controller='group-carousel']")
    expect(carousel).to have_css("article", count: 6)
    expect(carousel).not_to have_link(groups.first.name)
    expect(carousel).not_to have_link("가입 승인 대기 1건")
    expect(carousel).to have_css("[data-group-carousel-target='position']", exact_text: "1 / 2")
    expect(carousel).to have_button(I18n.t("groups.index.carousel.previous"), disabled: true)
    expect(carousel).to have_button(I18n.t("groups.index.carousel.next"), disabled: false)

    carousel.click_button I18n.t("groups.index.carousel.next")
    expect(carousel).to have_css("article", count: 1)
    expect(carousel).to have_link(groups.first.name, href: group_path(groups.first))
    expect(carousel).to have_link("가입 승인 대기 1건", href: group_members_path(groups.first))
    expect(carousel).to have_css("[data-group-carousel-target='position']", exact_text: "2 / 2")
    expect(carousel).to have_button(I18n.t("groups.index.carousel.previous"), disabled: false)
    expect(carousel).to have_button(I18n.t("groups.index.carousel.next"), disabled: true)

    carousel.click_button I18n.t("groups.index.carousel.previous")
    expect(carousel).to have_css("article", count: 6)
    expect(carousel.all("article h3 a").map(&:text)).to eq(groups.reverse.first(6).map(&:name))
    expect(carousel).not_to have_link("가입 승인 대기 1건")
    expect(carousel).to have_css("[data-group-carousel-target='position']", exact_text: "1 / 2")
  end
end
