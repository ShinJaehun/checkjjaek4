class JjaeksController < ApplicationController
  before_action :set_jjaek, only: %i[show edit update destroy]
  before_action :build_new_jjaek, only: %i[new create]

  def new
  end

  def show
    prepare_comments
  end

  def edit
  end

  def create
    authorize target_user, :write_jjaek? if target_user.present?

    @jjaek.assign_attributes(jjaek_params)

    if @jjaek.save
      redirect_to create_success_path, notice: t("jjaeks.notices.created")
    else
      render_failed_create
    end
  end

  def update
    if @jjaek.update(jjaek_params.except(:book_id, :quoted_jjaek_id, :target_user_id))
      redirect_to jjaek_path(@jjaek), notice: t("jjaeks.notices.updated")
    else
      render :edit, status: :unprocessable_content
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
    @book = find_jjaek_book
    @quoted_jjaek = find_quoted_jjaek
    @jjaek_visibility_options = jjaek_visibility_options_for(@quoted_jjaek)
    @jjaek = Jjaek.new(
      user: current_user,
      book: @book,
      quoted_jjaek: @quoted_jjaek,
      target_user:,
      visibility: default_jjaek_visibility_for(@quoted_jjaek)
    )
    authorize @jjaek
  end

  def render_failed_create
    return render_book_create_failure if @book.present?
    return render :new, status: :unprocessable_content if @quoted_jjaek.present?
    return render_profile_create_failure if render_profile_create_failure?

    render_home_create_failure
  end

  def target_user
    return if jjaek_target_user_id.blank?

    @target_user ||= User.find(jjaek_target_user_id)
  end

  def prepare_user_context(user)
    @user = user
    authorize @user, :show?
    profile_policy = policy(@user)

    @book_friendship = current_user == @user ? nil : current_user.book_friendship_with(@user)
    prepare_profile_bookshelf(profile_policy)
    prepare_profile_jjaeks(profile_policy)
    @profile_jjaek = @jjaek
    @profile_jjaek_visibility_options = profile_jjaek_visibility_options_for(@user)
  end

  def prepare_comments
    @comment = Comment.new(jjaek: @jjaek)
    @comments = @jjaek.comments.includes(:user).order(created_at: :asc)
  end

  def create_success_path
    target_user.present? ? root_path : jjaek_path(@jjaek)
  end

  def find_jjaek_book
    Book.find(jjaek_book_id) if jjaek_book_id.present?
  end

  def find_quoted_jjaek
    return unless jjaek_quoted_id.present?

    policy_scope(Jjaek).find(jjaek_quoted_id)
  end

  def render_book_create_failure
    @bookshelf_entry = current_user.bookshelf_entries.find_by(book: @book) ||
      BookshelfEntry.new(user: current_user, book: @book)
    authorize @bookshelf_entry
    @sticker_definitions = StickerDefinition.alphabetical
    @jjaeks = policy_scope(@book.jjaeks.includes(:user, :book, :target_user, :likes, :comments, quoted_jjaek: [ :user, :book ])).recent
    render "books/show", status: :unprocessable_content
  end

  def render_profile_create_failure?
    target_user.present? && Pundit.policy!(current_user, target_user).write_jjaek?
  end

  def render_profile_create_failure
    prepare_user_context(target_user)
    render "users/show", status: :unprocessable_content
  end

  def render_home_create_failure
    @feed_jjaeks = policy_scope(Jjaek, policy_scope_class: JjaekPolicy::FeedScope)
      .includes(:user, :book, :target_user, :likes, :comments, :quoted_jjaek)
      .recent
    render "homes/show", status: :unprocessable_content
  end

  def prepare_profile_bookshelf(profile_policy)
    @show_bookshelf = profile_policy.show_profile_bookshelf?
    @show_profile_bookshelf_status = profile_policy.show_profile_bookshelf_status?
    @bookshelf_entries =
      if @show_bookshelf
        policy_scope(@user.bookshelf_entries, policy_scope_class: BookshelfEntryPolicy::ProfileScope).recent_first
      end
  end

  def prepare_profile_jjaeks(profile_policy)
    @show_jjaeks = profile_policy.show_profile_jjaeks?
    @jjaeks =
      if @show_jjaeks
        resolve_profile_jjaeks(profile_policy.profile_access_level)
      else
        Jjaek.none
      end
  end

  def profile_jjaek_visibility_options_for(user)
    options = %w[public_jjaek book_friends]
    options << "private_jjaek" if current_user == user
    options
  end

  def resolve_profile_jjaeks(access_level)
    scope = policy_scope(@user.jjaeks).includes(:user, :book, :target_user, :likes, :comments, quoted_jjaek: [ :user, :book ])

    case access_level
    when :none, :following
      # stranger와 follow는 public_jjaek만
      scope.where(visibility: Jjaek.visibilities[:public_jjaek]).recent
    else
      scope.recent
    end
  end

  def jjaek_book_id
    params.dig(:jjaek, :book_id) || params[:book_id]
  end

  def jjaek_quoted_id
    params.dig(:jjaek, :quoted_jjaek_id) || params[:quoted_jjaek_id]
  end

  def jjaek_target_user_id
    params.dig(:jjaek, :target_user_id)
  end

  def jjaek_params
    params.require(:jjaek).permit(:book_id, :content, :visibility, :quoted_jjaek_id, :target_user_id)
  end

  def jjaek_visibility_options_for(quoted_jjaek)
    return Jjaek.visibilities.keys unless quoted_jjaek&.book_friends?

    %w[book_friends private_jjaek]
  end

  def default_jjaek_visibility_for(quoted_jjaek)
    return :book_friends if quoted_jjaek&.book_friends?

    :public_jjaek
  end
end
