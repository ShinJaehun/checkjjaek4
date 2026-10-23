require "rails_helper"

RSpec.describe "Admin inventory pagination", type: :request do
  let!(:admin) { User.create!(name: "Admin", email: "pagination-admin@example.com", password: "password123!", global_admin: true) }
  let!(:reader) { User.create!(name: "Reader", email: "pagination-reader@example.com", password: "password123!") }
  let(:created_at) { 1.day.ago.change(usec: 0) }
  let(:record_count) { 101 }

  def document
    Nokogiri::HTML(response.body)
  end

  def row_ids
    document.css(row_selector).map { |row| row[row_id_attribute] }
  end

  def pagination_link(label)
    document.css("a").find { |link| link.text.strip == I18n.t("pagination.#{label}") }
  end

  def pagination_navigation
    document.at_css("nav[aria-label='#{I18n.t('pagination.navigation')}']")
  end

  def displayed_page_numbers
    pagination_navigation.css("a, strong, span").map { |item| item.text.strip }
      .select { |text| text.match?(/\A(?:\d+|…)\z/) }
  end

  def link_params(link)
    Rack::Utils.parse_nested_query(URI.parse(link["href"]).query)
  end

  shared_examples "a configurable admin inventory" do
    before { sign_in admin }

    it "shows 30, 50 or 100 items, keeps conditions, and clamps to the last page" do
      expected_ids = ordered_row_ids

      [ 30, 50, 100 ].each do |size|
        get inventory_path, params: filters.merge(per_page: size, page_parameter => 1)

        expect(response).to have_http_status(:ok)
        expect(row_ids).to eq(expected_ids.first(size))
        options = document.css("select[name='per_page'] option")
        expect(options.map { |option| option["value"] }).to eq(%w[30 50 100])
        expect(options.find { |option| option["selected"] }["value"]).to eq(size.to_s)
        expect(document.text).to include(I18n.t("pagination.range", first: 1, last: size, total: 101))
        expect(pagination_link(:previous)).to be_nil
        expect(pagination_navigation.css("[aria-disabled='true']").map(&:text)).to match_array(
          [ I18n.t("pagination.first"), I18n.t("pagination.previous") ]
        )

        next_link = pagination_link(:next)
        expect(link_params(next_link)).to include(
          filters.stringify_keys.merge("per_page" => size.to_s, page_parameter.to_s => "2")
        )
        get next_link["href"]
        expect(row_ids).to eq(expected_ids.slice(size, size))
        expect(link_params(pagination_link(:previous))).to include(
          filters.stringify_keys.merge("per_page" => size.to_s, page_parameter.to_s => "1")
        )

        get inventory_path, params: filters.merge(per_page: size, page_parameter => 999)
        last_offset = (100 / size) * size
        expect(row_ids).to eq(expected_ids.drop(last_offset))
        expect(pagination_link(:next)).to be_nil
        expect(pagination_navigation.css("[aria-disabled='true']").map(&:text)).to match_array(
          [ I18n.t("pagination.next"), I18n.t("pagination.last") ]
        )
        expect(document.text).to include(
          I18n.t("pagination.range", first: last_offset + 1, last: 101, total: 101)
        )
      end
    end

    it "follows number, last and first links while highlighting the current page without a link" do
      expected_ids = ordered_row_ids
      get inventory_path, params: filters.merge(per_page: 30, page_parameter => 2)

      expect(displayed_page_numbers).to eq(%w[1 2 3 4])
      current = pagination_navigation.at_css("[aria-current='page']")
      expect(current.name).to eq("strong")
      expect(current.text.strip).to eq("2")
      expect(current["href"]).to be_nil
      expect(pagination_navigation.css("a").map { |link| link.text.strip }).not_to include("2")

      third_page_link = pagination_navigation.css("a").find { |link| link.text.strip == "3" }
      expect(link_params(third_page_link)).to include(
        filters.stringify_keys.merge("per_page" => "30", page_parameter.to_s => "3")
      )
      get third_page_link["href"]
      expect(row_ids).to eq(expected_ids.slice(60, 30))
      expect(pagination_navigation.at_css("[aria-current='page']").text.strip).to eq("3")

      last_link = pagination_link(:last)
      expect(link_params(last_link)).to include(
        filters.stringify_keys.merge("per_page" => "30", page_parameter.to_s => "4")
      )
      get last_link["href"]
      expect(row_ids).to eq(expected_ids.drop(90))
      expect(pagination_navigation.at_css("[aria-current='page']").text.strip).to eq("4")

      first_link = pagination_link(:first)
      expect(link_params(first_link)).to include(
        filters.stringify_keys.merge("per_page" => "30", page_parameter.to_s => "1")
      )
      get first_link["href"]
      expect(row_ids).to eq(expected_ids.first(30))
      expect(pagination_navigation.at_css("[aria-current='page']").text.strip).to eq("1")
    end

    context "with many pages" do
      let(:record_count) { 301 }

      it "shows the first, last and surrounding two pages with gaps" do
        expected_ids = ordered_row_ids
        {
          1 => %w[1 2 3 … 11],
          2 => %w[1 2 3 4 … 11],
          6 => %w[1 … 4 5 6 7 8 … 11],
          10 => %w[1 … 8 9 10 11],
          11 => %w[1 … 9 10 11]
        }.each do |page_number, expected_numbers|
          get inventory_path, params: filters.merge(per_page: 30, page_parameter => page_number)

          expect(displayed_page_numbers).to eq(expected_numbers)
          expect(row_ids).to eq(expected_ids.slice((page_number - 1) * 30, 30))
          expect(pagination_navigation.at_css("[aria-current='page']").text.strip).to eq(page_number.to_s)
          pagination_navigation.css("a").each do |link|
            expect(link_params(link)).to include(filters.stringify_keys.merge("per_page" => "30"))
          end
        end
      end
    end

    context "with one page" do
      let(:record_count) { 21 }

      it "keeps the range but hides all page numbers and navigation controls" do
        expected_ids = ordered_row_ids
        get inventory_path, params: filters.merge(per_page: 30, page_parameter => 999)

        expect(row_ids).to eq(expected_ids)
        expect(pagination_navigation.css("a, strong, [aria-disabled]")).to be_empty
        expect(pagination_navigation.text).to include(
          I18n.t("pagination.range", first: 1, last: 21, total: 21)
        )
      end
    end

    it "defaults missing and invalid sizes to 30 and invalid pages to the first page" do
      expected_ids = ordered_row_ids

      [ nil, "", "0", "-1", "31", "101", "invalid", "50.0", "50junk", [ "30" ], { value: "30" } ].each do |size|
        get inventory_path, params: filters.merge(per_page: size, page_parameter => "invalid").compact

        expect(response).to have_http_status(:ok)
        expect(row_ids).to eq(expected_ids.first(30))
        expect(document.at_css("select[name='per_page'] option[selected]")["value"]).to eq("30")
      end

      get inventory_path, params: filters.merge(per_page: 30, page_parameter => -1)
      expect(row_ids).to eq(expected_ids.first(30))
    end

    it "submits size changes with the current filters and without the content page position" do
      expected_ids = ordered_row_ids
      get inventory_path, params: filters.merge(per_page: 30, page_parameter => 2)

      select = document.at_css("select[name='per_page']")
      expect(select["data-action"]).to eq("change->page-size#submit")
      form = select.ancestors("form").first
      expect(form.at_css("input[name='#{page_parameter}']")).to be_nil
      expect(form.css("[name='per_page']").size).to eq(1)
      submitted_params = form.css("input[name], select[name]").to_h do |field|
        value = if field.name == "select"
          (field.at_css("option[selected]") || field.at_css("option"))["value"]
        else
          field["value"]
        end
        [ field["name"], value ]
      end
      submitted_params["per_page"] = "100"
      expect(submitted_params).to include(filters.stringify_keys)

      get form["action"], params: submitted_params
      expect(row_ids).to eq(expected_ids.first(100))
      expect(pagination_link(:previous)).to be_nil
    end

    it "keeps empty filtered results on the first page" do
      ordered_row_ids
      search_parameter = filters.key?(:content_q) ? :content_q : :q
      get inventory_path, params: filters.merge(search_parameter => "NO_MATCH_FOR_PAGE_SIZE", per_page: 30, page_parameter => 999)

      expect(response).to have_http_status(:ok)
      expect(row_ids).to be_empty
      expect(pagination_link(:previous)).to be_nil
      expect(pagination_link(:next)).to be_nil
      expect(pagination_navigation.css("a, strong, [aria-disabled]")).to be_empty
      expect(document.text).to include(I18n.t("pagination.range", first: 0, last: 0, total: 0))
    end

    it "keeps authentication and global admin authorization for custom sizes" do
      sign_out admin
      get inventory_path, params: { per_page: 100 }
      expect(response).to redirect_to(new_user_session_path)

      sign_in reader
      get inventory_path, params: { per_page: 30 }
      expect(response).to redirect_to(root_path)
    end
  end

  context "user list" do
    let(:inventory_path) { admin_users_path }
    let(:page_parameter) { :page }
    let(:row_selector) { "#admin_user_inventory_table tbody tr" }
    let(:row_id_attribute) { "id" }
    let(:filters) { { q: "Page size user", status: "active", role: "regular", sort: "oldest" } }
    let(:ordered_row_ids) do
      record_count.times.map do |index|
        user = User.create!(name: "Page size user #{index}", email: "page-size-#{index}@example.com", password: "password123!", created_at:)
        "user_#{user.id}"
      end
    end

    include_examples "a configurable admin inventory"
  end

  context "Group list" do
    let(:inventory_path) { admin_groups_path }
    let(:page_parameter) { :page }
    let(:row_selector) { "#admin_group_inventory_table tbody tr" }
    let(:row_id_attribute) { "id" }
    let(:filters) do
      { q: "Page size club", group_type: "private_group", status: "active", operation_status: "normal", sort: "recent" }
    end
    let(:ordered_row_ids) do
      record_count.times.map do |index|
        group = Group.create!(name: "Page size club #{index}", group_admin: reader, group_type: :private_group, lifecycle_status: :active, created_at:)
        "group_#{group.id}"
      end.reverse
    end

    include_examples "a configurable admin inventory"
  end

  context "user content table" do
    let(:inventory_path) { content_admin_user_path(reader) }
    let(:page_parameter) { :all_page }
    let(:row_selector) { "#admin_user_content_timeline tbody tr" }
    let(:row_id_attribute) { "id" }
    let(:filters) { { q: "PAGE_SIZE", content: "all", location: "personal", sort: "recent" } }
    let(:ordered_row_ids) do
      source = admin.jjaeks.create!(content: "Comment source")
      posts = ((record_count + 1) / 2).times.map { |index| reader.jjaeks.create!(content: "PAGE_SIZE_POST_#{index}", visibility: :private_jjaek, created_at:) }
      comments = (record_count / 2).times.map { |index| source.comments.create!(user: reader, content: "PAGE_SIZE_COMMENT_#{index}", created_at:) }
      Jjaeks::Hide.new(posts.last, actor: admin, public_reason: "other").call!
      Comments::Hide.new(comments.last, actor: admin, public_reason: "other").call!
      posts.reverse.map { |post| "timeline_jjaek_#{post.id}" } + comments.reverse.map { |comment| "timeline_comment_#{comment.id}" }
    end

    include_examples "a configurable admin inventory"
  end

  context "Group content threads" do
    let(:group) { Group.create!(name: "Private content club", group_admin: reader, group_type: :private_group, lifecycle_status: :active) }
    let(:inventory_path) { content_admin_group_path(group) }
    let(:page_parameter) { :all_page }
    let(:row_selector) { "#admin_group_content_timeline tbody[data-thread-id]" }
    let(:row_id_attribute) { "data-thread-id" }
    let(:filters) do
      {
        content_q: "PAGE_SIZE", content: "general", content_status: "active", content_sort: "recent",
        q: "club", group_type: "private_group", status: "active", sort: "oldest", page: "3"
      }
    end
    let(:roots) do
      record_count.times.map do |index|
        root = reader.jjaeks.create!(group:, content: "PAGE_SIZE_ROOT_#{index}", created_at:)
        2.times { |comment_index| root.comments.create!(user: reader, content: "PAGE_SIZE_COMMENT_#{index}_#{comment_index}", created_at:) }
        root
      end
    end
    let(:ordered_row_ids) do
      Jjaeks::Hide.new(roots.last, actor: admin, public_reason: "other").call!
      root_with_hidden_comment = roots[70] || roots.first
      Comments::Hide.new(root_with_hidden_comment.comments.last, actor: admin, public_reason: "other").call!
      group.update!(lifecycle_status: :inactive, closure_reason: "Reading completed", closed_at: Time.current)
      roots.reverse.map { |root| root.id.to_s }
    end

    include_examples "a configurable admin inventory"

    it "keeps all comments with their root across page boundaries, including hidden content" do
      ordered_row_ids
      sign_in admin

      [ 1, 2, 4 ].each do |page_number|
        get inventory_path, params: filters.merge(per_page: 30, all_page: page_number)

        expected_roots = roots.reverse.slice((page_number - 1) * 30, 30)
        expect(row_ids).to eq(expected_roots.map { |root| root.id.to_s })
        expected_roots.each do |root|
          thread = document.at_css("tbody[data-thread-id='#{root.id}']")
          expected_comments = root.comments.order(created_at: :desc, id: :desc)
          expect(thread.css("tr").map { |row| row["id"] }).to eq(
            expected_comments.map { |comment| "group_timeline_comment_#{comment.id}" } + [ "group_timeline_jjaek_#{root.id}" ]
          )
        end

        hidden_row_id = page_number == 1 ? "jjaek_#{roots.last.id}" : "comment_#{roots[70].comments.last.id}"
        if page_number <= 2
          status = document.at_css("#group_timeline_#{hidden_row_id} [data-field='status']")
          expect(status.text.strip).to eq(I18n.t("content_statuses.hidden"))
        end
      end
    end
  end
end
