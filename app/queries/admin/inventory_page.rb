module Admin
  class InventoryPage
    PER_PAGE = 30
    PER_PAGE_OPTIONS = [ 30, 50, 100 ].freeze
    attr_reader :records, :page, :per_page, :total_count

    def self.normalize_per_page(value)
      PER_PAGE_OPTIONS.find { |size| size.to_s == value.to_s } || PER_PAGE
    end

    def initialize(scope, page:, per_page: nil)
      @per_page = self.class.normalize_per_page(per_page)
      @total_count = scope.except(:select, :order).count
      requested = Integer(page, exception: false).to_i
      requested = 1 if requested < 1
      @total_pages = [ (total_count.to_f / @per_page).ceil, 1 ].max
      @page = [ requested, @total_pages ].min
      @records = scope.limit(@per_page).offset((@page - 1) * @per_page)
    end

    def total_pages = @total_pages

    def previous_page
      page - 1 if page > 1
    end

    def next_page
      page + 1 if page < total_pages
    end

    def first_item = total_count.zero? ? 0 : (page - 1) * per_page + 1
    def last_item = [ page * per_page, total_count ].min
  end
end
