require "rails_helper"

RSpec.describe "Requote pagination", type: :request do
  let(:author) { User.create!(name: "Source author", email: "paged-source@example.com", password: "password123!") }
  let(:group_admin) { User.create!(name: "Club admin", email: "paged-group-admin@example.com", password: "password123!") }
  let(:group) { Group.create!(name: "Approval page club", group_admin:, group_type: :approval_group, lifecycle_status: :active) }
  let(:source) { author.jjaeks.create!(content: "PAGE_SOURCE", visibility: :public_jjaek) }
  let(:time) { Time.zone.parse("2026-10-19 12:00:00") }
  let(:cards) do
    Array.new(11) do |index|
      writer = User.create!(name: "Page writer #{index}", email: "requote-page-#{index}@example.com", password: "password123!")
      group.group_memberships.create!(user: writer, status: :active)
      readable = writer.jjaeks.create!(quoted_jjaek: source, content: "READABLE_PAGE_#{index}", created_at: time)
      restricted = writer.jjaeks.create!(group:, quoted_jjaek: source, content: "RESTRICTED_PAGE_#{index}", created_at: time)
      [ [ readable, false ], [ restricted, true ] ]
    end.flatten(1).reverse
  end

  def displayed_cards
    Nokogiri::HTML(response.body).css("article[id^='jjaek_'], article[data-restricted-requote]").map do |card|
      if card.key?("data-restricted-requote")
        [ card.at_css("img")["alt"], true ]
      else
        [ card["id"].delete_prefix("jjaek_").to_i, false ]
      end
    end
  end

  def expected_cards(records)
    records.map { |record, restricted| [ restricted ? record.user.name : record.id, restricted ] }
  end

  it "paginates readable and restricted cards together in HTML and the existing Turbo panel" do
    expected = expected_cards(cards)
    sign_in author
    [ {}, { "Accept" => "text/vnd.turbo-stream.html" } ].each do |headers|
      get jjaek_requotes_path(source), headers: headers
      expect(response).to have_http_status(:ok)
      expect(displayed_cards).to eq(expected.first(20))
      page = Nokogiri::HTML(response.body)
      link = page.at_css("nav a[href*='page=2']")
      expect(link).to be_present
      expect(link["data-turbo-stream"]).to eq(headers.empty? ? nil : "true")

      get link["href"], headers: headers
      expect(displayed_cards).to eq(expected.last(2))
      expect(response.body).not_to include("RESTRICTED_PAGE_")
      expect(Nokogiri::HTML(response.body).at_css("[aria-current='page']").text).to eq("2")
      if headers.any?
        expect(Nokogiri::HTML(response.body).css("turbo-stream").map { |node| node["target"] }).to eq([ "requotes_panel_jjaek_#{source.id}" ])
      end
    end
  end

  it "normalizes invalid and nonpositive pages and clamps pages beyond the last" do
    expected = expected_cards(cards)
    sign_in author
    [ nil, "wrong", "1.5", "0x2", "0", "-1", [ "2" ] ].each do |page|
      get jjaek_requotes_path(source), params: { page: }
      expect(response).to have_http_status(:ok)
      expect(displayed_cards).to eq(expected.first(20))
    end
    get jjaek_requotes_path(source), params: { page: "999999999999999999999" }
    expect(displayed_cards).to eq(expected.last(2))
  end

  it "does not expose restricted cards when another reader requests a later page" do
    cards
    reader = User.create!(name: "Reader", email: "paged-other-reader@example.com", password: "password123!")
    sign_in reader
    get jjaek_requotes_path(source), params: { page: 2 }

    expect(displayed_cards).to eq(expected_cards(cards.reject(&:last)))
    expect(response.body).not_to include("RESTRICTED_PAGE_", group.name)
    source.update!(visibility: :private_jjaek)
    get jjaek_requotes_path(source), params: { page: 2 }
    expect(response).to redirect_to(root_path)
    expect(response.body).not_to include("PAGE_SOURCE", "READABLE_PAGE_")
  end

  it "loads only the selected page's full cards rather than all requotes" do
    cards
    sign_in author
    loaded = 0
    subscriber = lambda do |*args|
      payload = args.last
      loaded += payload[:record_count] if payload[:class_name] == "Jjaek"
    end
    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      get jjaek_requotes_path(source)
    end

    expect(displayed_cards.size).to eq(20)
    # Include Jjaek instances loaded for source and card rendering.
    expect(loaded).to be <= 25
  end

  it "keeps an empty list successful even for an out-of-range page" do
    sign_in author
    get jjaek_requotes_path(source), params: { page: 99 }

    expect(response).to have_http_status(:ok)
    expect(displayed_cards).to be_empty
    expect(response.body).to include(I18n.t("requotes.index.empty"))
    expect(Nokogiri::HTML(response.body).at_css("nav[aria-label='#{I18n.t('pagination.pages')}']")).to be_nil
  end
end
