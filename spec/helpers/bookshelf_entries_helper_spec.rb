require "rails_helper"

RSpec.describe BookshelfEntriesHelper, type: :helper do
  it "renders a status icon and translated label and omits an unset status" do
    BookshelfEntry.statuses.each_key do |status|
      badge = Nokogiri::HTML.fragment(helper.reading_status_badge(status)).at_css("[data-reading-status]")
      expect(badge.text).to eq(I18n.t("bookshelf_entries.statuses.#{status}"))
      expect(badge.at_css("svg")["aria-hidden"]).to eq("true")
      expect(badge["class"]).to eq(helper.reading_badge_classes(:status))
    end
    expect(helper.reading_status_badge(nil)).to be_nil
    expect(helper.reading_status_badge("")).to be_nil
  end

  it "shares status and sticker content between selection controls and read-only badges" do
    sticker = StickerDefinition.new(key: "recommended_to_me", name: "Legacy name")
    status_badge = Nokogiri::HTML.fragment(helper.reading_status_badge("reading")).at_css("span")
    sticker_badge = Nokogiri::HTML.fragment(helper.reading_sticker_badge(sticker)).at_css("span")

    expect(status_badge.inner_html).to eq(Nokogiri::HTML.fragment(helper.reading_status_content("reading")).to_html)
    expect(sticker_badge.inner_html).to eq(Nokogiri::HTML.fragment(helper.reading_sticker_content(sticker)).to_html)
    expect(sticker_badge["class"]).to eq(helper.reading_badge_classes(:sticker))
    expect(helper.reading_badge_classes(:status, selectable: true)).to include("has-[:checked]", "has-[:focus-visible]")
    expect(helper.reading_badge_classes(:sticker, selectable: true)).to include("has-[:checked]", "has-[:focus-visible]")
  end

  it "renders icon-only stickers with the same icon, title, accessible name, and colors" do
    sticker = StickerDefinition.new(key: "recommended_to_me", name: "Legacy name")
    normal = Nokogiri::HTML.fragment(helper.reading_sticker_badge(sticker)).at_css("[data-reading-sticker]")
    icon = Nokogiri::HTML.fragment(helper.reading_sticker_badge(sticker, icon_only: true)).at_css("[data-reading-sticker]")

    expect(icon.text).to be_empty
    expect(icon["title"]).to eq(helper.reading_sticker_label(sticker))
    expect(icon["aria-label"]).to eq(normal.text)
    expect(icon["role"]).to eq("img")
    expect(icon["class"]).to eq(helper.reading_badge_classes(:sticker, icon_only: true))
    expect(icon["class"].split & normal["class"].split).to include("border-amber-200", "bg-amber-50", "text-amber-900")
    expect(icon.at_css("path")["d"]).to eq(normal.at_css("path")["d"])
  end

  it "uses distinct icons and translated labels for receiving and giving recommendations" do
    received = StickerDefinition.new(key: "recommended_to_me", name: "Old received label")
    giving = StickerDefinition.new(key: "want_to_recommend", name: "Old giving label")
    received_icon = Nokogiri::HTML.fragment(helper.reading_sticker_badge(received)).at_css("path")["d"]
    giving_icon = Nokogiri::HTML.fragment(helper.reading_sticker_badge(giving)).at_css("path")["d"]

    expect(received_icon).not_to eq(giving_icon)
    %i[ko en].each do |locale|
      I18n.with_locale(locale) do
        [ received, giving ].each do |sticker|
          expect(helper.reading_sticker_label(sticker)).to eq(I18n.t("reading_experience.stickers.#{sticker.key}"))
        end
      end
    end
  end

  it "escapes custom sticker names and renders without querying the database" do
    sticker = StickerDefinition.new(key: "custom", name: '<img src=x onerror="alert(1)">')
    queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }
    html = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      html = helper.reading_sticker_badge(sticker)
      helper.reading_status_badge("reading")
      helper.reading_sticker_badge(sticker, icon_only: true)
    end
    badge = Nokogiri::HTML.fragment(html)

    expect(badge.text).to eq(sticker.name)
    expect(badge.css("img")).to be_empty
    expect(queries).to be_empty
  end
end
