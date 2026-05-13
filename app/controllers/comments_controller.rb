class CommentsController < ApplicationController
  COMMENTS_CONTEXTS = %w[detail home profile book].freeze

  before_action :set_jjaek
  before_action :set_comments_context, only: %i[index create destroy]
  before_action :set_comment, only: %i[update destroy]

  def index
    @comments_panel_closed = inline_comments_context? && params[:panel_state] == "closed"
    prepare_comments_panel(comment: Comment.new(jjaek: @jjaek))

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to jjaek_path(@jjaek, anchor: helpers.comments_panel_dom_id(@jjaek)) }
    end
  end

  def create
    @comment = Comment.new(comment_params.merge(jjaek: @jjaek, user: current_user))
    authorize @comment

    if @comment.save
      Notification.notify_comment_created(@comment)
      @jjaek.reload
      prepare_comments_panel(comment: Comment.new(jjaek: @jjaek))

      respond_to do |format|
        format.turbo_stream { flash.now[:notice] = t("comments.notices.created") }
        format.html { redirect_to jjaek_path(@jjaek), notice: t("comments.notices.created") }
      end
    else
      prepare_comments_panel(comment: @comment)
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_content }
        format.html do
          prepare_visible_requote_counts_for([ @jjaek ])
          render "jjaeks/show", status: :unprocessable_content
        end
      end
    end
  end

  def update
    authorize @comment

    if @comment.update(comment_params)
      redirect_to jjaek_path(@jjaek), notice: t("comments.notices.updated")
    else
      @comments = @jjaek.comments.includes(:user).order(created_at: :asc)
      prepare_visible_requote_counts_for([ @jjaek ])
      render "jjaeks/show", status: :unprocessable_content
    end
  end

  def destroy
    authorize @comment
    @comment.destroy!

    @jjaek.reload
    prepare_comments_panel(comment: Comment.new(jjaek: @jjaek))

    respond_to do |format|
      format.turbo_stream { flash.now[:notice] = t("comments.notices.destroyed") }
      format.html { redirect_to jjaek_path(@jjaek), notice: t("comments.notices.destroyed") }
    end
  end

  private

  def set_jjaek
    @jjaek = Jjaek.find(params[:jjaek_id])
    authorize @jjaek, :show?
  end

  def set_comment
    @comment = @jjaek.comments.find(params[:id])
  end

  def set_comments_context
    requested_context = params[:comments_context].presence || default_comments_context

    unless COMMENTS_CONTEXTS.include?(requested_context)
      set_detail_comments_context
      return
    end

    case requested_context
    when "profile"
      set_profile_comments_context
    when "book"
      set_book_comments_context
    else
      @comments_context = requested_context.to_sym
    end
  end

  def prepare_comments_panel(comment:)
    @comments = @jjaek.comments.includes(:user).order(created_at: :asc)
    @comment = comment
  end

  def default_comments_context
    action_name == "index" ? "home" : "detail"
  end

  def set_detail_comments_context
    @comments_context = :detail
    @comments_profile_user = nil
    @comments_book = nil
  end

  def set_profile_comments_context
    @comments_profile_user = User.find_by(id: params[:profile_user_id])
    return set_detail_comments_context if @comments_profile_user.blank?

    @comments_context = :profile
    @comments_book = nil
  end

  def set_book_comments_context
    @comments_book = Book.find_by(id: params[:book_id])
    return set_detail_comments_context if @comments_book.blank?
    return set_detail_comments_context unless @jjaek.book_id == @comments_book.id

    @comments_context = :book
    @comments_profile_user = nil
  end

  def inline_comments_context?
    %i[home profile book].include?(@comments_context)
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
