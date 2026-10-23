module Admin
  module PaginationHelper
    def admin_pagination_numbers(page)
      first_number = [ page.page - 2, 1 ].max
      last_number = [ page.page + 2, page.total_pages ].min
      numbers = [ 1, *(first_number..last_number), page.total_pages ].uniq.sort

      numbers.each_with_object([]) do |number, items|
        items << nil if items.any? && number > items.last + 1
        items << number
      end
    end

    def admin_pagination_link(label, number, page_param:)
      if number
        link_to label,
                url_for(request.query_parameters.merge(page_param.to_s => number)),
                class: "rounded-lg border border-stone-200 px-3 py-2 text-stone-700 hover:bg-stone-100"
      else
        tag.span label,
                 class: "rounded-lg border border-stone-100 px-3 py-2 text-stone-400",
                 aria: { disabled: true }
      end
    end
  end
end
