require "rails_helper"

RSpec.describe "Responsive navigation", type: :system do
  include Warden::Test::Helpers

  let(:reader) { User.create!(name: "A mobile reader with a deliberately long name", email: "mobile-nav-reader@example.com", password: "password123!") }

  after { Warden.test_reset! }

  it "keeps the mobile header controls on one row and signs out through the menu" do
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
    search_button = "header button[aria-controls='global-book-search-dialog']"
    expect(page).to have_css("#{search_button}[aria-haspopup='dialog'][aria-label='#{I18n.t("book_search.nav")}'] svg", visible: true)
    profile_link = "header a[href='#{user_path(reader)}']"
    expect(page).to have_css("#{profile_link} img", visible: true)
    expect(find(profile_link)["aria-label"]).to eq(reader.name)
    expect(page).to have_no_css("#{profile_link} span", visible: true)
    expect(page).to have_no_css("#mobile-navigation-links", visible: true)
    expect(page).to have_no_button(I18n.t("auth.actions.sign_out"))
    header_row_fits = <<~JS
      (() => {
        const header = document.querySelector('header')
        const brand = header.querySelector('a[href="#{root_path}"]')
        const search = header.querySelector('button[aria-controls="global-book-search-dialog"][aria-label]')
        const notification = header.querySelector('a[href="#{notifications_path}"]')
        const profile = header.querySelector('a[href="#{user_path(reader)}"]')
        const button = header.querySelector('button[data-mobile-navigation-target="button"]')
        const boxes = [brand, search, notification, profile, button].map((element) => element.getBoundingClientRect())
        const centerY = (box) => box.top + box.height / 2
        return header.scrollWidth <= window.innerWidth &&
          boxes.every((box) => Math.abs(centerY(box) - centerY(boxes[0])) < 2) &&
          boxes.slice(1).every((box) => box.width >= 44 && box.height >= 44) &&
          boxes.slice(1).every((box, index) => boxes[index].right <= box.left)
        })()
    JS
    expect(page.evaluate_script(header_row_fits)).to be(true)
    browser = page.driver.browser
    begin
      browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 800, deviceScaleFactor: 1, mobile: false)
      expect(page.evaluate_script("window.innerWidth")).to eq(320)
      expect(page.evaluate_script(header_row_fits)).to be(true)
    ensure
      browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end

    menu_button = find("header button[data-mobile-navigation-target='button']")
    expect(menu_button["aria-controls"].split).to eq(%w[mobile-navigation-links mobile-navigation-account])
    menu_button.click
    expect(menu_button["aria-expanded"]).to eq("true")
    expect(page).to have_css("#mobile-navigation-links a[href='#{discovery_path}']", visible: true)
    expect(page).to have_css(search_button, count: 1, visible: true)
    expect(page).to have_no_css("#mobile-navigation-links button[aria-controls='global-book-search-dialog']", visible: true)
    expect(page).to have_css(profile_link, count: 1, visible: :all)
    expect(page).to have_no_css("#mobile-navigation-links a[href='#{user_path(reader)}'], #mobile-navigation-account a[href='#{user_path(reader)}']", visible: :all)
    within("#mobile-navigation-account") { expect(page).to have_button(I18n.t("auth.actions.sign_out"), visible: true) }
    expect(page.evaluate_script("document.querySelector('header').scrollWidth <= window.innerWidth")).to be(true)

    menu_button.click
    expect(menu_button["aria-expanded"]).to eq("false")
    expect(page).to have_no_css("#mobile-navigation-links", visible: true)
    expect(page).to have_css("header #notification-badge-container #notification-badge", visible: true)
    find(profile_link).click
    expect(page).to have_current_path(user_path(reader))

    find_button(I18n.t("navigation.menu"), enable_aria_label: true).click
    within("#mobile-navigation-account") { click_button I18n.t("auth.actions.sign_out") }
    expect(page).to have_current_path(new_user_session_path)
  end

  it "hides navigation and keeps invited sign-up linked back to sign-in" do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 800 ]
    page.driver.browser.manage.window.resize_to(390, 800)
    admin = User.create!(name: "Invitation admin", email: "mobile-nav-inviter@example.com", password: "password123!", global_admin: true)
    invitation = RegistrationInvitation.new(email: "mobile-nav-invitee@example.com", invited_by: admin)
    token = invitation.issue_token!
    invitation.save!

    visit new_user_session_path

    expect(page).to have_no_css("header", visible: :all)
    expect(page).to have_text(I18n.t("registration_invitations.sign_in_notice"))

    visit new_user_registration_path(invitation_token: token)

    expect(page).to have_no_css("header", visible: :all)
    expect(page).to have_css("a[href='#{new_user_session_path}']", visible: true)

    visit privacy_policy_path
    within("body > header[data-controller='mobile-navigation']") do
      expect(page).to have_no_button(I18n.t("book_search.nav"), enable_aria_label: true)
      expect(page).to have_no_css("a[href='#{notifications_path}']")
      click_button I18n.t("navigation.menu")
      expect(page).to have_css("#mobile-navigation-links a[href='#{new_user_session_path}']", visible: true)
    end

    page.driver.browser.manage.window.resize_to(1280, 900)
    visit new_user_session_path

    expect(page).to have_no_css("header", visible: :all)
    expect(page).to have_text(I18n.t("registration_invitations.sign_in_notice"))

    visit new_user_registration_path(invitation_token: token)

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
    expect(page).to have_css("#mobile-navigation-links button[aria-controls='global-book-search-dialog']", text: I18n.t("book_search.nav"), visible: true)
    expect(page).to have_css("header a[href='#{notifications_path}']", visible: true)
    expect(page).to have_css("header a[href='#{user_path(admin)}']", text: admin.name, visible: true)
    expect(page).to have_css("header a[href='#{user_path(admin)}'] img", visible: true)
    expect(page).to have_button(I18n.t("auth.actions.sign_out"), visible: true)
    expect(page.evaluate_script("document.querySelector('header').scrollWidth <= window.innerWidth")).to be(true)
  end
end
