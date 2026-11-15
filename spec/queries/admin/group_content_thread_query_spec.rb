require "rails_helper"

RSpec.describe Admin::GroupContentThreadQuery do
  def search_threads(term)
    described_class.new(
      jjaek_scope: group.jjaeks,
      comment_scope: Comment.joins(:jjaek).where(jjaeks: { group_id: group.id }),
      content_section: "all",
      params: { content_q: term }
    ).call.records
  end

  it_behaves_like "group content search contract", :admin

  it "counts and paginates searched active threads using all comments for latest activity" do
    other_author = User.create!(
      name: "Other author",
      email: "thread-other-author@example.com",
      password: "password123!"
    )

    group_admin = other_author
    group = Group.create!(
      name: "Pagination test group",
      group_admin:,
      group_type: :private_group,
      lifecycle_status: :active
    )

    base_time = 1.day.ago.change(usec: 0)
    roots = 101.times.map do |index|
      {
        user_id: other_author.id, group_id: group.id, content: (index % 5 == 0 ? "" : "PAGE_SIZE_ROOT_#{index}"),
        created_at: base_time, updated_at: base_time,
        deleted_at: (base_time + 10.minutes if index % 5 == 0),
        hidden_at: (base_time + 10.minutes if index % 3 == 0)
      }
    end
    root_ids = Jjaek.insert_all!(roots, returning: %w[id]).rows.flatten
    comment_rows = root_ids.each_with_index.flat_map do |id, index|
      [
        { jjaek_id: id, user_id: other_author.id, content: "PAGE_SIZE_COMMENT_#{index}",
          created_at: base_time + 1.minute, updated_at: base_time, hidden_at: nil },
        { jjaek_id: id, user_id: other_author.id, content: "Later unrelated hidden comment",
          created_at: base_time + (index % 7 + 2).minutes, updated_at: base_time, hidden_at: base_time + 10.minutes }
      ]
    end
    comment_ids = Comment.insert_all!(comment_rows, returning: %w[id]).rows.flatten
    recent_ids = root_ids.each_with_index.sort_by { |id, index| [ index % 7, id ] }.map(&:first).reverse
    other_group = Group.create!(name: "Other pagination group", group_admin:, lifecycle_status: :active)
    foreign_root = other_author.jjaeks.create!(group: other_group, content: "PAGE_SIZE_FOREIGN")
    foreign_root.comments.create!(user: other_author, content: "PAGE_SIZE_FOREIGN_COMMENT", created_at: Time.current)

    ActiveRecord::Base.transaction(requires_new: true) do
      # Fail promptly if the old pathological plan is reintroduced. This limits
      # each SQL statement, not fixture size, assertions or application behavior.
      ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = '5s'")
      %w[recent oldest].each do |sort|
        ordered_ids = sort == "recent" ? recent_ids : recent_ids.reverse
        [ 30, 50, 100 ].each do |size|
          [ 1, 999 ].each do |page_number|
            result = described_class.new(
              jjaek_scope: group.jjaeks,
              comment_scope: Comment.joins(:jjaek).where(jjaeks: { group_id: group.id }),
              content_section: "group", per_page: size,
              params: { content_q: "PAGE_SIZE", content_status: "active", content_sort: sort, all_page: page_number }
            ).call
            expected_page = page_number == 1 ? 1 : (101.to_f / size).ceil
            expect(result.total_count).to eq(101)
            expect(result.page).to eq(expected_page)
            expect(result.records.map { |thread| thread.root.id }).to eq(ordered_ids.slice((expected_page - 1) * size, size))
            result.records.each do |thread|
              index = root_ids.index(thread.root.id)
              expect(thread.comments.map(&:id)).to eq([ comment_ids[index * 2 + 1], comment_ids[index * 2] ])
            end
          end
        end
      end
    end
  end
end
