require "rails_helper"

RSpec.describe "Requote menu", type: :system do
  include Warden::Test::Helpers

  before { driven_by :selenium, using: :headless_chrome }
  after { Warden.test_reset! }

  it "keeps the group feed menu clickable beyond the card and inside a narrow viewport" do
    reader = User.create!(name: "Menu reader", email: "group-menu-reader@example.com", password: "password123!")
    author = User.create!(name: "Menu author", email: "group-menu-author@example.com", password: "password123!")
    group = Group.create!(group_admin: author, name: "Menu readers", group_type: :private_group, lifecycle_status: :active)
    group.group_memberships.create!(user: reader, status: :active)
    source = author.jjaeks.create!(group:, content: "Group menu source", created_at: 3.minutes.ago)
    next_card = author.jjaeks.create!(group:, quoted_jjaek: source, content: "Existing group requote", created_at: 4.minutes.ago)
    2.times { |index| author.jjaeks.create!(group:, content: "Newer group post #{index}") }
    login_as reader, scope: :user

    browser = page.driver.browser
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 550, deviceScaleFactor: 1, mobile: false)
    visit group_path(group)

    card = find("#jjaek_#{source.id}")
    menu = "#jjaek_#{source.id} details[data-controller='requote-menu']"
    trigger = find("#{menu} summary", text: I18n.t("jjaeks.meta.requotes", count: 1))
    view_label = I18n.t("requotes.actions.view_count", count: 1)
    page.execute_script("arguments[0].scrollIntoView({ block: 'center', behavior: 'instant' })", trigger)
    trigger.click
    expect(page).to have_css("#{menu}[open] a", count: 2)
    expect(menu_geometry(menu, next_card)).to eq(
      "insideViewport" => true, "linksReachable" => true, "overlapsNextCard" => true, "opensAbove" => false
    )

    card.click
    expect(page).to have_no_css("#{menu}[open]")
    page.execute_script(<<~JS, trigger)
      const bottom = arguments[0].getBoundingClientRect().bottom
      window.scrollBy(0, bottom - document.documentElement.clientHeight + 20)
    JS
    trigger.send_keys(:enter)
    expect(page).to have_css("#{menu}[open] a", count: 2)
    expect(menu_geometry(menu, next_card)).to eq(
      "insideViewport" => true, "linksReachable" => true, "overlapsNextCard" => false, "opensAbove" => true
    )

    view_link = find_link(view_label, href: jjaek_requotes_path(source))
    trigger.send_keys(:tab)
    expect(page.evaluate_script("document.activeElement === arguments[0]", view_link)).to be(true)
    view_link.send_keys(:escape)
    expect(page).to have_no_css("#{menu}[open]")
    expect(page.evaluate_script("document.activeElement === arguments[0]", trigger)).to be(true)
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  def menu_geometry(menu, next_card)
    page.evaluate_async_script(<<~JS, menu, "#jjaek_#{next_card.id}")
      const [menuSelector, nextCardSelector, done] = arguments
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const menu = document.querySelector(menuSelector)
        const panel = menu.querySelector("[data-requote-menu-target='panel']")
        const rect = panel.getBoundingClientRect()
        const trigger = menu.querySelector("summary").getBoundingClientRect()
        const nextCard = document.querySelector(nextCardSelector).getBoundingClientRect()
        const insideViewport = rect.left >= 0 && rect.right <= document.documentElement.clientWidth &&
          rect.top >= 0 && rect.bottom <= document.documentElement.clientHeight
        const linksReachable = Array.from(panel.querySelectorAll("a")).every(link => {
          const item = link.getBoundingClientRect()
          return link.contains(document.elementFromPoint(item.left + item.width / 2, item.top + item.height / 2))
        })
        const overlapsNextCard = rect.bottom > nextCard.top && rect.top < nextCard.bottom
        done({ insideViewport, linksReachable, overlapsNextCard, opensAbove: rect.bottom < trigger.top })
      }))
    JS
  end
end
