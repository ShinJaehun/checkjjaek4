class JjaeksController < ApplicationController
  include CommentModerationHistory
  include GroupShowContext
  include HomeFeedContext
  include ProfileContext

  before_action :set_jjaek, only: :show
  before_action :set_editable_jjaek, only: %i[edit update]
  before_action :set_destroy_jjaek, only: :destroy
  before_action :build_new_jjaek, only: %i[new create]
  rate_limit to: 30, within: 5.minutes, by: -> { current_user.id },
             with: :jjaek_rate_limit_exceeded, only: :create

  def new
    raise ActiveRecord::RecordNotFound if params[:share_to_group].present? && !@share_to_group

    if @group.present?
      raise ActiveRecord::RecordNotFound unless @quoted_jjaek&.group_id == @group.id
    elsif @share_to_group
      authorize @quoted_jjaek, :share_to_group?
    end
  end

  def show
    @current_hide_action = @jjaek.current_hide_action if @jjaek.hidden?
    if policy(@jjaek).view_admin_inventory?
      @moderation_actions = @jjaek.moderation_actions
        .where(action_type: %i[hide restore])
        .includes(:actor)
        .order(created_at: :asc, id: :asc)
    end
    if policy(@jjaek).view_group_moderation_history?
      @group_moderation_actions = @jjaek.moderation_actions
        .where(action_type: %i[hide restore], moderation_authority: "group")
        .includes(:actor)
        .order(created_at: :asc, id: :asc)
    end
    if policy(@jjaek).view_deleted_tombstone? && !policy(@jjaek).view_admin_inventory?
      prepare_comments
      return render :hidden
    end
    if policy(@jjaek).view_hidden_placeholder?
      prepare_comments
      return render :hidden
    end
   if @jjaek.hidden? && !policy(@jjaek).view_admin_inventory?
     prepare_comments
     return render :hidden
   end

    prepare_comments
    prepare_current_reading_states_for([ @jjaek ])
    prepare_visible_requote_counts_for([ @jjaek ])
  end

  def edit
  end

  def create
    authorize target_user, :write_jjaek? if @group.blank? && target_user.present?
    raise Pundit::NotAuthorizedError if params[:share_to_group].present? && @group.blank?
    if @group.present? && request.path_parameters[:group_id].blank? && @quoted_jjaek.blank? &&
        params[:book_post_destination] != "group"
      raise Pundit::NotAuthorizedError
    end
    if @group.present? && @quoted_jjaek.present?
      nested_group_route = request.path_parameters[:group_id].present?
      valid_source = nested_group_route ? @quoted_jjaek.group_id == @group.id : @quoted_jjaek.group_id.nil?
      raise Pundit::NotAuthorizedError unless valid_source
    end

    attributes = jjaek_params
    attributes = attributes.except(:book_id, :visibility, :target_user_id) if @group.present? && @quoted_jjaek.present?
    @jjaek.assign_attributes(attributes)

    saved = begin
      if @group
        @group.with_lock do
          if group_requote_already_exists?
            @jjaek.errors.add(:quoted_jjaek_id, :taken)
            false
          else
            authorize @jjaek
            @jjaek.save
          end
        end
      else
        authorize @jjaek
        @jjaek.save
      end
    rescue ActiveRecord::RecordNotUnique
      raise unless @jjaek.quoted_jjaek_id.present?

      @jjaek.errors.add(:quoted_jjaek_id, :taken)
      false
    end

    if saved
      notify_jjaek_created
      redirect_to create_success_path, notice: t("jjaeks.notices.created")
    else
      render_failed_create
    end
  end

  def update
    updated = if @jjaek.group
      @jjaek.group.with_lock do
        authorize @jjaek
        @jjaek.update(update_jjaek_params)
      end
    else
      @jjaek.update(update_jjaek_params)
    end

    if updated
      redirect_to jjaek_path(@jjaek, post_return_params), notice: t("jjaeks.notices.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    group = @jjaek.group
    @jjaek.destroy_or_tombstone!
    destination = view_context.jjaek_detail_return_params(@jjaek)[:return_to]
    redirect_to destination || destroy_success_path(group), notice: t("jjaeks.notices.destroyed"), status: :see_other
  end

  private

  def jjaek_rate_limit_exceeded
    message = t("jjaeks.alerts.rate_limited")
    respond_to do |format|
      format.turbo_stream { render_content_rate_limit_flash(message) }
      format.html do
        @jjaek.assign_attributes(jjaek_params)
        flash.now[:alert] = message
        render_failed_create(status: :too_many_requests)
      end
    end
  end

  def set_jjaek
    @jjaek = Jjaek.find(params[:id])

    if @jjaek.group_id.present? && !policy(@jjaek).show?
      raise ActiveRecord::RecordNotFound
    end
    authorize @jjaek
  end

  def set_editable_jjaek
    @jjaek = Jjaek.find_by(id: params[:id])

    unless @jjaek
      redirect_to root_path, alert: t("jjaeks.alerts.not_found_or_inaccessible")
      return
    end

    if @jjaek.group_id.present? && !policy(@jjaek).show?
      raise ActiveRecord::RecordNotFound
    end
    authorize @jjaek
  end

  def set_destroy_jjaek
    @jjaek = Jjaek.find_by(id: params[:id])
    unless @jjaek
      redirect_to root_path, alert: t("jjaeks.alerts.not_found_or_inaccessible"), status: :see_other
      return
    end

    authorize @jjaek, :destroy?
  end

  def build_new_jjaek
    validate_book_post_destination!
    @group = find_jjaek_group
    @quoted_jjaek = find_quoted_jjaek
    return if performed?

    @share_to_group = @quoted_jjaek.present? && @quoted_jjaek.group_id.blank? &&
      (params[:share_to_group].present? || @group.present?)
    @available_share_groups = policy(@quoted_jjaek).group_share_destinations if @share_to_group
    @book = find_jjaek_book unless (@group.present? && @quoted_jjaek.present?) || @share_to_group
    @jjaek_visibility_options = jjaek_visibility_options_for(@quoted_jjaek)
    @jjaek = Jjaek.new(
      user: current_user,
      book: @book,
      group: @group,
      quoted_jjaek: @quoted_jjaek,
      target_user: @group.present? ? nil : target_user,
      visibility: default_jjaek_visibility_for(@quoted_jjaek)
    )
    authorize @jjaek if action_name == "new" && !@share_to_group
  end

  def render_failed_create(status: :unprocessable_content)
    if @group.present? && @quoted_jjaek.present?
      @available_share_groups = policy(@quoted_jjaek).group_share_destinations if @share_to_group
      return render :new, status:
    end
    return render_group_book_create_failure(status:) if @group.present? && @book.present?
    return render_group_create_failure(status:) if @group.present?
    return render_book_create_failure(status:) if @book.present?
    return render(:new, status:) if @quoted_jjaek.present?
    return render_profile_create_failure(status:) if render_profile_create_failure?

    render_home_create_failure(status:)
  end

  def target_user
    return if jjaek_target_user_id.blank?

    @target_user ||= User.find(jjaek_target_user_id)
  end

  def prepare_user_context(user)
    @user = user
    authorize @user, :show?
    prepare_profile_context
    @profile_jjaek = @jjaek
    @profile_jjaek_visibility_options = profile_jjaek_visibility_options_for(@user)
  end

  def prepare_comments
    @comment = Comment.new(jjaek: @jjaek)
    @comments = @jjaek.comments.includes(:user).order(created_at: :asc)
    prepare_comment_moderation_histories(@comments)
  end

  def post_return_params
    view_context.jjaek_detail_return_params(@jjaek)
  end

  def create_success_path
    return group_path(@group) if @group.present?

    target_user.present? ? root_path : jjaek_path(@jjaek, post_return_params)
  end

  def find_jjaek_group
    path_group_id = request.path_parameters[:group_id]
    form_group_id = params.dig(:jjaek, :group_id)
    quoting = params[:quoted_jjaek_id].present? ||
      params.dig(:jjaek, :quoted_jjaek_id).present?
    if quoting && path_group_id.present? && form_group_id.present? &&
        path_group_id.to_s != form_group_id.to_s
      raise Pundit::NotAuthorizedError
    end

    group_id = path_group_id || (form_group_id if action_name == "create")
    return if group_id.blank?
    raise Pundit::NotAuthorizedError unless group_id.to_s.match?(/\A[1-9]\d*\z/)

    if params[:book_post_destination] == "group"
      policy_scope(Group, policy_scope_class: GroupPolicy::CreateJjaekScope).find(group_id)
    else
      policy_scope(Group).find(group_id)
    end
  end

  def validate_book_post_destination!
    return unless params.key?(:book_post_destination)

    destination = params[:book_post_destination]
    valid_book_post = action_name == "create" && params.dig(:jjaek, :book_id).present? &&
      params[:quoted_jjaek_id].blank? && params.dig(:jjaek, :quoted_jjaek_id).blank? &&
      params[:share_to_group].blank? && jjaek_target_user_id.blank?
    raise Pundit::NotAuthorizedError unless valid_book_post && destination.in?(%w[personal group])

    path_group_id = request.path_parameters[:group_id]
    form_group_id = params.dig(:jjaek, :group_id)
    if destination == "personal"
      raise Pundit::NotAuthorizedError if path_group_id.present? || form_group_id.present?
    else
      raise Pundit::NotAuthorizedError if form_group_id.blank?
      if path_group_id.present? && path_group_id.to_s != form_group_id.to_s
        raise Pundit::NotAuthorizedError
      end
    end
  end

  def find_jjaek_book
    Book.find(jjaek_book_id) if jjaek_book_id.present?
  end

  def find_quoted_jjaek
    return unless jjaek_quoted_id.present?

    quoted_jjaek = policy_scope(Jjaek).find_by(id: jjaek_quoted_id)
    return quoted_jjaek if quoted_jjaek

    redirect_to root_path, alert: t("jjaeks.alerts.requote_source_unavailable")
    nil
  end

  def render_book_create_failure(status:)
    @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book) ||
      BookshelfEntry.new(user: current_user, book: @book)
    authorize @bookshelf_entry
    @sticker_definitions = StickerDefinition.alphabetical
    prepare_book_show_read_context
    render "books/show", status:
  end

  def render_group_book_create_failure(status:)
    @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book)
    @sticker_definitions = StickerDefinition.alphabetical
    prepare_book_show_read_context
    render "books/show", status:
  end

  def render_group_create_failure(status:)
    prepare_group_show_context
    render "groups/show", status:
  end

  def render_profile_create_failure?
    target_user.present? && Pundit.policy!(current_user, target_user).write_jjaek?
  end

  def render_profile_create_failure(status:)
    prepare_user_context(target_user)
    render "users/show", status:
  end

  def render_home_create_failure(status:)
    prepare_home_feed
    render "homes/show", status:
  end

  def profile_jjaek_visibility_options_for(user)
    options = %w[public_jjaek book_friends]
    options << "private_jjaek" if current_user == user
    options
  end

  def jjaek_book_id
    params.dig(:jjaek, :book_id) || params[:book_id]
  end

  def jjaek_quoted_id
    form_id = params.dig(:jjaek, :quoted_jjaek_id)
    url_id = params[:quoted_jjaek_id]
    if url_id.present? && params[:jjaek]&.key?(:quoted_jjaek_id) && form_id.to_s != url_id.to_s
      raise Pundit::NotAuthorizedError
    end

    quoted_id = form_id || url_id
    raise Pundit::NotAuthorizedError if quoted_id.present? && !quoted_id.to_s.match?(/\A[1-9]\d*\z/)

    quoted_id
  end

  def jjaek_target_user_id
    params.dig(:jjaek, :target_user_id)
  end

  def jjaek_params
    params.require(:jjaek).permit(:book_id, :content, :visibility, :quoted_jjaek_id, :target_user_id)
  end

  def group_requote_already_exists?
    @jjaek.quoted_jjaek_id.present? &&
      Jjaek.exists?(user_id: current_user.id, quoted_jjaek_id: @jjaek.quoted_jjaek_id, group_id: @group.id)
  end

  def update_jjaek_params
    return jjaek_params.slice(:content) if @jjaek.group_id.present?

    jjaek_params.except(:book_id, :group_id, :quoted_jjaek_id, :target_user_id)
  end

  def destroy_success_path(group)
    return root_path if group.blank?
    return group_path(group) if policy(group).show?

    groups_path
  end

  def jjaek_visibility_options_for(quoted_jjaek)
    return Jjaek.visibilities.keys unless quoted_jjaek&.book_friends?

    %w[book_friends private_jjaek]
  end

  def default_jjaek_visibility_for(quoted_jjaek)
    return :book_friends if quoted_jjaek&.book_friends?

    :public_jjaek
  end

  def notify_jjaek_created
    Notification.notify_profile_jjaek_created(@jjaek)
    Notification.notify_requote_created(@jjaek) if @jjaek.requote?
  end
end
