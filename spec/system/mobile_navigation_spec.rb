require "rails_helper"

RSpec.describe "Responsive navigation", type: :system do
  include Warden::Test::Helpers

  let(:reader) { User.create!(name: "Mobile reader", email: "mobile-nav-reader@example.com", password: "password123!") }

  after { Warden.test_reset! }

  it "keeps the notification badge visible and opens the remaining links at 390px" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 800 ]
    page.driver.browser.manage.window.resize_to(390, 800)
    actor = User.create!(name: "Actor", email: "mobile-nav-actor@example.com", password: "password123!")
    jjaek = actor.jjaeks.create!(content: "A notification source")
    Notification.create!(recipient: reader, actor:, action: :profile_jjaek_created, notifiable: jjaek)
    login_as reader, scope: :user

    visit root_path

    expect(page).to have_css("header #notification-badge-container #notification-badge", text: "1", visible: true)
    expect(page).to have_css("header #notification-badge-container", count: 1, visible: :all)
    expect(page).to have_css("header turbo-cable-stream-source", count: 1, visible: :all)
    expect(find("header a[href='#{notifications_path}']")["data-turbo-prefetch"]).to eq("false")
    expect(page).to have_no_css("#mobile-navigation-links", visible: true)
    expect(page.evaluate_script(<<~JS)).to be(true)
      (() => {
        const header = document.querySelector('header')
        const brand = header.querySelector('a[href="#{root_path}"]')
        const notification = header.querySelector('a[href="#{notifications_path}"]')
        const button = header.querySelector('button[data-mobile-navigation-target="button"]')
        return header.scrollWidth <= window.innerWidth &&
          Math.abs(
            (brand.getBoundingClientRect().top + brand.getBoundingClientRect().height / 2) -
            (notification.getBoundingClientRect().top + notification.getBoundingClientRect().height / 2)
          ) < 2 &&
          Math.abs(
            (brand.getBoundingClientRect().top + brand.getBoundingClientRect().height / 2) -
            (button.getBoundingClientRect().top + button.getBoundingClientRect().height / 2)
          ) < 2
        })()
    JS

    click_button I18n.t("navigation.menu")
    expect(find("header button[data-mobile-navigation-target='button']")["aria-expanded"]).to eq("true")
    expect(page).to have_css("#mobile-navigation-links a[href='#{discovery_path}']", visible: true)
    expect(page).to have_css("#mobile-navigation-account a[href='#{user_path(reader)}']", visible: true)
    expect(page).to have_button(I18n.t("auth.actions.sign_out"), visible: true)
    expect(page.evaluate_script("document.querySelector('header').scrollWidth <= window.innerWidth")).to be(true)

    click_button I18n.t("navigation.menu")
    expect(page).to have_no_css("#mobile-navigation-links", visible: true)
    expect(page).to have_css("header #notification-badge-container #notification-badge", visible: true)
  end

  it "hides navigation and provides auth links on sign-in and sign-up pages" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 800 ]
    page.driver.browser.manage.window.resize_to(390, 800)

    visit new_user_session_path

    expect(page).to have_no_css("header", visible: :all)
    expect(page).to have_css("a[href='#{new_user_registration_path}']", visible: true)

    visit new_user_registration_path

    expect(page).to have_no_css("header", visible: :all)
    expect(page).to have_css("a[href='#{new_user_session_path}']", visible: true)

    page.driver.browser.manage.window.resize_to(1280, 900)
    visit new_user_session_path

    expect(page).to have_no_css("header", visible: :all)
    expect(page).to have_css("a[href='#{new_user_registration_path}']", visible: true)

    visit new_user_registration_path

    expect(page).to have_no_css("header", visible: :all)
    expect(page).to have_css("a[href='#{new_user_session_path}']", visible: true)
  end

  it "keeps the desktop links and global admin links visible without opening a menu" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]
    page.driver.browser.manage.window.resize_to(1280, 900)
    admin = User.create!(name: "Global admin", email: "mobile-nav-admin@example.com", password: "password123!", global_admin: true)
    login_as admin, scope: :user

    visit root_path

    expect(page).to have_no_css("header button[data-mobile-navigation-target='button']", visible: true)
    expect(page).to have_css("#mobile-navigation-links a[href='#{admin_users_path}']", visible: true)
    expect(page).to have_css("#mobile-navigation-links a[href='#{admin_groups_path}']", visible: true)
    expect(page).to have_css("header a[href='#{notifications_path}']", visible: true)
    expect(page).to have_css("#mobile-navigation-account a[href='#{user_path(admin)}']", visible: true)
    expect(page).to have_button(I18n.t("auth.actions.sign_out"), visible: true)
    expect(page.evaluate_script("document.querySelector('header').scrollWidth <= window.innerWidth")).to be(true)
  end
end
