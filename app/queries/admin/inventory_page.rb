module Admin
  class InventoryPage
    PER_PAGE = 50
    attr_reader :records, :page, :total_count

    def initialize(scope, page:)
      @total_count = scope.except(:select, :order).count
      requested = Integer(page, exception: false).to_i
      requested = 1 if requested < 1
      @total_pages = [ (total_count.to_f / PER_PAGE).ceil, 1 ].max
      @page = [ requested, @total_pages ].min
      @records = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
    end

    def total_pages = @total_pages

    def previous_page
      page - 1 if page > 1
    end

    def next_page
      page + 1 if page < total_pages
    end

    def first_item = total_count.zero? ? 0 : (page - 1) * PER_PAGE + 1
    def last_item = [ page * PER_PAGE, total_count ].min
  end
end
