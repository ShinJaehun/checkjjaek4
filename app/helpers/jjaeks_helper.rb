module JjaeksHelper
  def jjaek_option_icon(key)
    paths = {
      "personal" => "M4 3h7a3 3 0 0 1 3 3v15a5 5 0 0 0-5-2H4V3Zm10 3h6v13h-1a5 5 0 0 0-5 2",
      "group" => "M8 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm-6 9v-2a6 6 0 0 1 12 0v2M16 4a4 4 0 0 1 0 8m1 3a5 5 0 0 1 5 5",
      "public_jjaek" => "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM3 12h18M12 3a18 18 0 0 1 0 18 18 18 0 0 1 0-18Z",
      "book_friends" => "M8 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm-6 9v-2a6 6 0 0 1 12 0v2m2-10 2 2 4-5",
      "private_jjaek" => "M6 10h12v11H6V10Zm2 0V6a4 4 0 0 1 8 0v4m-4 4v3"
    }
    tag.svg(viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": 1.7,
            "stroke-linecap": "round", "stroke-linejoin": "round", class: "h-5 w-5 shrink-0", aria: { hidden: true }) do
      tag.path(d: paths.fetch(key.to_s))
    end
  end

  def book_post_group_options(groups)
    groups.map do |group|
      [ group.name, group.id, { "data-destination-message" => t("books.show.group_destination", name: group.name) } ]
    end
  end

  def jjaek_option_card_classes
    "flex cursor-pointer items-center gap-3 rounded-2xl border border-stone-200 bg-white p-4 text-sm font-medium text-stone-600 has-[:checked]:border-amber-600 has-[:checked]:bg-amber-50 has-[:checked]:text-amber-950 has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-amber-500"
  end

  def current_reading_state_for(jjaek)
    return if jjaek.deleted?

    @current_reading_states.to_h[[ jjaek.user_id, jjaek.book_id ]]
  end

  def jjaek_hide_reason_options
    Jjaek::MODERATION_HIDE_REASONS.map do |reason|
      [ jjaek_hide_reason_label(reason), reason ]
    end
  end

  def jjaek_hide_reason_label(reason)
    t("jjaeks.moderation.reasons.#{reason}")
  end

  def jjaek_hidden_title(jjaek)
    action = jjaek.current_hide_action
    if action&.group_authority?
      key = jjaek.book.present? ? "hidden_book_by_group_admin" : "hidden_by_group_admin"
      return t("jjaeks.moderation.#{key}")
    end

    key = jjaek.book.present? ? "hidden_book_by_system_admin" : "hidden_by_system_admin"
    t("jjaeks.moderation.#{key}")
  end

  def moderation_action_reason_label(action)
    return jjaek_hide_reason_label(action.public_reason) if action.action_type_hide?

    action.public_reason
  end

  def moderation_authority_label(action)
    t("admin.jjaeks.moderation.authorities.#{action.moderation_authority}")
  end

  def jjaek_context_label(jjaek, hide_book_details: false)
    translation_key = jjaek_context_translation_key(jjaek)
    return if translation_key.blank?

    if hide_book_details && translation_key == "jjaeks.contexts.group_book_html"
      translation_key = "jjaeks.contexts.group_book_without_title_html"
    end

    t(translation_key, **jjaek_context_translation_options(jjaek))
  end

  def validated_jjaek_return_path(candidate, include_search_origin: true)
    return unless candidate.is_a?(String) && candidate.start_with?("/")
    return if candidate.start_with?("//") || candidate.match?(/[\\[:cntrl:]]/)

    uri = URI.parse(candidate)
    return if uri.host || uri.scheme

    route = Rails.application.routes.recognize_path(uri.path, method: :get)
    query = ActionController::Parameters.new(Rack::Utils.parse_nested_query(uri.query))
    path, filter_keys = jjaek_return_destination(route, query)
    return unless path

    filters = query.permit(*filter_keys).to_h
    if path == book_search_path && include_search_origin
      origin = validated_jjaek_return_path(query[:search_origin], include_search_origin: false)
      filters["search_origin"] = origin if origin
    end
    filters.present? ? "#{path}?#{filters.to_query}" : path
  rescue URI::InvalidURIError, ActionController::RoutingError, ActiveRecord::RecordNotFound, Rack::QueryParser::ParameterTypeError, Rack::QueryParser::InvalidParameterError, Rack::QueryParser::ParamsTooDeepError
    nil
  end

  def jjaek_navigation_params
    @jjaek_navigation_params ||= begin
      path = validated_jjaek_return_path(params[:return_to]) || validated_jjaek_return_path(request.fullpath)
      default_path = @quoted_jjaek.present? ? jjaek_path(@quoted_jjaek) : jjaek_default_return_path(@jjaek)
      path ||= validated_jjaek_return_path(default_path)
      path ? { return_to: path } : {}
    end
  end

  def jjaek_back_path(default_path: root_path)
    path = validated_jjaek_return_path(params[:return_to])
    path = nil if path && URI.parse(path).path == request.path
    path || validated_jjaek_return_path(default_path) || root_path
  end

  def jjaek_detail_return_params(jjaek = @jjaek)
    path = validated_jjaek_return_path(params[:return_to])
    path = nil if path && URI.parse(path).path == jjaek_path(jjaek)
    path ? { return_to: path } : {}
  end

  def book_navigation_params
    path = validated_jjaek_return_path(request.fullpath)
    path ? { return_to: path } : {}
  end

  def jjaek_default_return_path(jjaek)
    if jjaek&.group.present?
      group_path(jjaek.group)
    elsif jjaek&.book.present?
      book_path(jjaek.book)
    elsif jjaek&.target_user.present?
      user_path(jjaek.target_user)
    else
      root_path
    end
  end

  def current_user_like_for(jjaek)
    jjaek.likes.find { |like| like.user_id == current_user.id }
  end

  def show_like_summary_action?(jjaek)
    current_like = current_user_like_for(jjaek)

    jjaek.likes_count.positive? ||
      (current_like && policy(current_like).destroy?) ||
      policy(Like.new(jjaek: jjaek, user: current_user)).create?
  end

  def show_requote_book_link?(jjaek)
    jjaek.book.present? && jjaek.quoted_jjaek.present?
  end

  def visible_requote_count_for(jjaek)
    return 0 if jjaek.requote?

    @visible_requote_counts_by_jjaek_id.to_h.fetch(jjaek.id, 0)
  end

  def jjaek_edited?(jjaek)
    jjaek.content_edited_at.present?
  end

  def comments_panel_dom_id(jjaek, context: :detail, profile_user: nil, book: nil)
    case context.to_sym
    when :detail
      dom_id(jjaek, :comments_panel)
    when :home
      dom_id(jjaek, :comments_panel_home)
    when :profile
      raise ArgumentError, "profile_user is required for profile comments panel context" if profile_user.blank?

      "comments_panel_profile_#{profile_user.id}_jjaek_#{jjaek.id}"
    when :book
      raise ArgumentError, "book is required for book comments panel context" if book.blank?

      "comments_panel_book_#{book.id}_jjaek_#{jjaek.id}"
    when :book_friend
      raise ArgumentError, "book is required for book friend comments panel context" if book.blank?

      "comments_panel_book_friend_#{book.id}_jjaek_#{jjaek.id}"
    when :group
      return dom_id(jjaek, :comments_panel) if jjaek.group_id.blank?

      dom_id(jjaek, :comments_panel_group)
    else
      raise ArgumentError, "Unsupported comments panel context: #{context}"
    end
  end

  def requotes_panel_dom_id(jjaek, context: :detail)
    case context.to_sym
    when :detail
      dom_id(jjaek, :requotes_panel)
    else
      raise ArgumentError, "Unsupported requotes panel context: #{context}"
    end
  end

  private

  def jjaek_return_destination(route, query)
    case [ route[:controller], route[:action] ]
    when [ "homes", "show" ]
      [ root_path, [] ]
    when [ "discoveries", "show" ]
      [ discovery_path, [] ] if policy(:discovery).show?
    when [ "notifications", "index" ]
      [ notifications_path, [] ] if policy(Notification).index?
    when [ "book_searches", "show" ]
      return unless policy(:book_search).show?
      if query[:group_id].present?
        return unless query[:group_id].is_a?(String)
        return unless policy(Group.find(query[:group_id])).create_jjaek?
      end
      [ book_search_path, %i[query page group_id] ]
    when [ "users/libraries", "show" ]
      user = User.find_by_public_param!(route[:user_id])
      return unless policy(user).show? && policy(user).show_library?
      if query[:bookshelf_id].present?
        return unless query[:bookshelf_id].is_a?(String)
        return unless policy_scope(user.bookshelves).exists?(id: query[:bookshelf_id])
      end
      [ user_library_path(user), %i[bookshelf_id sort] ]
    when [ "users", "show" ]
      user = User.find_by_public_param!(route[:id])
      [ user_path(user), [] ] if policy(user).show?
    when [ "books", "show" ]
      book = Book.find(route[:id])
      return unless policy(book).show?
      if query[:group_id].present?
        return unless query[:group_id].is_a?(String)
        group = Group.find(query[:group_id])
        return unless policy(group).create_jjaek?
      end
      [ book_path(book), [ :group_id ] ]
    when [ "groups", "index" ]
      [ groups_path, [] ] if policy(Group).index?
    when [ "groups", "show" ], [ "groups/contents", "index" ]
      group = Group.find(route[:id])
      if route[:controller] == "groups/contents"
        [ content_group_path(group), GroupContentReturnContext::FILTER_KEYS ] if policy(group).view_content_inventory?
      elsif policy(group).show?
        [ group_path(group), [] ]
      end
    when [ "admin/users", "content" ]
      user = User.find_by_public_param!(route[:id])
      keys = [ *%i[content q location status sort all_page per_page], { inventory: %i[q status role sort page per_page] } ]
      [ content_admin_user_path(user), keys ] if policy(user).view_admin_inventory?
    when [ "admin/groups", "content" ]
      group = Group.find(route[:id])
      keys = [ *GroupContentReturnContext::FILTER_KEYS, :q, :group_type, :status, :operation_status, :sort, :page, :per_page,
               { inventory: %i[q group_type status operation_status sort page per_page] } ]
      [ content_admin_group_path(group), keys ] if policy(group).view_admin_details?
    when [ "requotes", "index" ]
      source = Jjaek.find(route[:jjaek_id])
      [ jjaek_requotes_path(source), [] ] if !source.deleted? && policy(source).view_requotes?
    when [ "jjaeks", "show" ]
      jjaek = Jjaek.find(route[:id])
      [ jjaek_path(jjaek), [] ] if !jjaek.deleted? && policy(jjaek).show?
    end
  end

  def jjaek_context_translation_key(jjaek)
    if jjaek.group_id.present? && jjaek.requote?
      return "jjaeks.contexts.group_requote_unavailable_html" unless policy(jjaek).view_quoted_source?

      jjaek.quoted_jjaek.group_id.blank? ? "jjaeks.contexts.group_share_html" : "jjaeks.contexts.group_quote_html"
    elsif jjaek.group_id.present? && jjaek.book_id.present?
      "jjaeks.contexts.group_book_html"
    elsif jjaek.group_id.present?
      "jjaeks.contexts.group_general_html"
    elsif jjaek.quoted_source_deleted?
      "jjaeks.contexts.deleted_requote_html"
    elsif jjaek.quoted_jjaek.present? && !policy(jjaek).view_quoted_source?
      "jjaeks.contexts.deleted_requote_html"
    elsif jjaek.quoted_jjaek&.group_id.present?
      "jjaeks.contexts.group_requote_html"
    elsif jjaek.quoted_jjaek.present? && policy(jjaek).view_quoted_source?
      "jjaeks.contexts.requote_html"
    elsif jjaek.book.present?
      "jjaeks.contexts.book_html"
    elsif profile_context_label?(jjaek)
      "jjaeks.contexts.profile_html"
    else
      "jjaeks.contexts.general_html"
    end
  end

  def jjaek_context_translation_options(jjaek)
    options = { author_name: jjaek_context_user_link(jjaek.user) }

    if jjaek.group_id.present?
      options[:group_name] = jjaek_context_group_link(jjaek.group)
      options[:book_title] = jjaek_context_book_link(jjaek.book) if jjaek.book.present?
      if jjaek.quoted_jjaek.present? && policy(jjaek).view_quoted_source?
        options[:quoted_user_name] = jjaek_context_user_link(jjaek.quoted_jjaek.user, avatar: true)
        options[:quoted_context_label] = jjaek.quoted_jjaek.book.present? ? t("jjaeks.contexts.quoted_book") : t("jjaeks.contexts.quoted_general")
      end
    elsif jjaek.quoted_jjaek.present? && policy(jjaek).view_quoted_source?
      options[:quoted_user_name] = jjaek_context_user_link(jjaek.quoted_jjaek.user, avatar: true)
      options[:quoted_context_label] = jjaek.quoted_jjaek.book.present? ? t("jjaeks.contexts.quoted_book") : t("jjaeks.contexts.quoted_general")
      if jjaek.quoted_jjaek.group_id.present?
        group = jjaek.quoted_jjaek.group
        options[:group_name] = jjaek_context_group_link(group)
      end
    elsif jjaek.book.present?
      options[:book_title] = jjaek_context_book_link(jjaek.book)
    elsif profile_context_label?(jjaek)
      options[:target_user_name] = jjaek_context_user_link(jjaek.target_user, avatar: true)
    end

    options
  end

  def jjaek_context_group_link(group)
    safe_join([
      tag.span(t("jjaeks.contexts.group_badge"), class: "inline-block rounded border border-stone-200 bg-stone-50 px-1.5 py-0.5 align-middle text-[10px] font-normal leading-none text-stone-500"),
      " ",
      link_to(group.name, group_path(group), class: "font-semibold text-stone-900 hover:text-stone-700")
    ])
  end

  def profile_context_label?(jjaek)
    jjaek.target_user.present? && jjaek.target_user != jjaek.user
  end

  def jjaek_context_user_link(user, avatar: false)
    return link_to(user.name, user_path(user), class: "font-semibold text-stone-900 hover:text-stone-700") unless avatar

    link_to user_path(user), class: "inline-flex items-center gap-1 align-middle font-semibold text-stone-900 hover:text-stone-700" do
      safe_join([
        user_avatar_image(user, size: 128, alt: user.name, class: "h-5 w-5 rounded-full object-cover"),
        tag.span(user.name)
      ])
    end
  end

  def jjaek_context_book_link(book)
    link_to(book.title, book_path(book, book_navigation_params), class: "font-semibold text-stone-900 hover:text-stone-700")
  end
end
