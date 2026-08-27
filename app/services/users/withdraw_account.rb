module Users
  class WithdrawAccount
    class Error < StandardError; end
    class InvalidPassword < Error; end
    class AlreadyWithdrawn < Error; end
    class GlobalAdmin < Error; end
    class ActiveGroupAdmin < Error
      attr_reader :group_names

      def initialize(group_names)
        @group_names = group_names
        super()
      end
    end
    class PendingGroupHasContent < Error; end

    def initialize(user, current_password:)
      @user = user
      @current_password = current_password
    end

    def call!
      User.transaction do
        user.with_lock do
          validate_withdrawal!
          cancel_pending_groups!
          anonymize!
          clean_group_memberships!
          clean_social_data!
          clean_personal_reading_data!
        end
      end

      user
    end

    private

    attr_reader :user, :current_password

    def validate_withdrawal!
      raise AlreadyWithdrawn if user.withdrawn?
      raise InvalidPassword unless user.valid_password?(current_password)
      raise GlobalAdmin if user.global_admin?

      @administered_groups = user.administered_groups.lock.to_a
      active_groups = administered_groups.select(&:active?).map(&:name)
      raise ActiveGroupAdmin.new(active_groups) if active_groups.any?
    end

    def cancel_pending_groups!
      administered_groups.select(&:pending_approval?).each do |group|
        if group.closed_at.present?
          group.cancel_reactivation_for_withdrawal!
        else
          begin
            group.cancel_pending_application_for_withdrawal!
          rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed
            raise PendingGroupHasContent
          end
        end
      end
    end

    def anonymize!
      replacement_password = SecureRandom.hex(32)
      user.update!(
        name: User::WITHDRAWN_NAME,
        email: "withdrawn-#{user.id}-#{SecureRandom.hex(8)}@users.invalid",
        password: replacement_password,
        password_confirmation: replacement_password,
        default_avatar_index: nil,
        withdrawn_at: Time.current,
        reset_password_token: nil,
        reset_password_sent_at: nil,
        remember_created_at: nil
      )
    end

    def clean_group_memberships!
      historical_membership_ids = administered_groups.select(&:inactive?).filter_map do |group|
        membership = group.group_memberships.find_by(user: user)
        membership&.update!(status: :inactive) if membership&.active?
        membership&.id
      end

      user.group_memberships.where.not(id: historical_membership_ids).find_each(&:destroy!)
    end

    def clean_social_data!
      user.received_notifications.destroy_all
      user.sent_notifications.destroy_all
      user.active_follows.destroy_all
      user.passive_follows.destroy_all
      user.requested_book_friendships.destroy_all
      user.received_book_friendships.destroy_all
      user.likes.destroy_all
    end

    def clean_personal_reading_data!
      user.book_activities.destroy_all
      user.bookshelf_entries.destroy_all
      user.bookshelves.delete_all
    end

    def administered_groups
      @administered_groups || []
    end
  end
end
