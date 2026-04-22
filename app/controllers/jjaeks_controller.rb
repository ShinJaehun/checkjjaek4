class JjaeksController < ApplicationController
  before_action :set_jjaek, only: %i[show edit update destroy]
  before_action :build_new_jjaek, only: %i[new create]

  def new
  end

  def show
    @comment = @jjaek.comments.build
    @comments = @jjaek.comments.includes(:user).order(created_at: :asc)
  end

  def edit
  end

  def create
    @jjaek.assign_attributes(jjaek_params)

    if @jjaek.save
      redirect_to jjaek_path(@jjaek), notice: t("jjaeks.notices.created")
    else
      render_failed_create
    end
  end

  def update
    if @jjaek.update(jjaek_params.except(:book_id, :quoted_jjaek_id))
      redirect_to jjaek_path(@jjaek), notice: t("jjaeks.notices.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @jjaek.destroy!
    redirect_to root_path, notice: t("jjaeks.notices.destroyed"), status: :see_other
  end

  private

  def set_jjaek
    @jjaek = Jjaek.find(params[:id])
    authorize @jjaek
  end

  def build_new_jjaek
    @book = Book.find(jjaek_book_id) if jjaek_book_id.present?
    @quoted_jjaek =
      if jjaek_quoted_id.present?
        policy_scope(Jjaek).find(jjaek_quoted_id)
      end
    @jjaek = current_user.jjaeks.build(book: @book, quoted_jjaek: @quoted_jjaek)
    authorize @jjaek
  end

  def render_failed_create
    if @book.present?
      @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book) ||
        current_user.bookshelf_entries.build(book: @book)
      authorize @bookshelf_entry
      @sticker_definitions = StickerDefinition.alphabetical
      @jjaeks = policy_scope(@book.jjaeks.includes(:user, :likes, :comments, :quoted_jjaek)).recent
      render "books/show", status: :unprocessable_entity
    elsif context_user.present? && Pundit.policy!(current_user, context_user).write_jjaek?
      prepare_user_context(context_user)
      render "users/show", status: :unprocessable_entity
    else
      @feed_jjaeks = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::FeedScope)
        .includes(:user, :book, :likes, :comments, :quoted_jjaek)
        .recent
      render "homes/show", status: :unprocessable_entity
    end
  end

  def context_user
    return if params[:context_user_id].blank?

    @context_user ||= User.find_by(id: params[:context_user_id])
  end

  def prepare_user_context(user)
    @user = user
    authorize @user, :show?
    @jjaeks = policy_scope(@user.jjaeks.includes(:user, :book, :likes, :comments, :quoted_jjaek)).recent
    @book_friendship = current_user == @user ? nil : current_user.book_friendship_with(@user)
    @show_bookshelf = policy(@user).show_bookshelf?
    @bookshelf_entries = policy_scope(@user.bookshelf_entries).recent_first if @show_bookshelf
    @profile_jjaek = @jjaek
    @profile_jjaek_visibility_options = profile_jjaek_visibility_options_for(@user)
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
    params.dig(:jjaek, :quoted_jjaek_id) || params[:quoted_jjaek_id]
  end

  def jjaek_params
    params.require(:jjaek).permit(:book_id, :content, :visibility, :quoted_jjaek_id)
  end
end
