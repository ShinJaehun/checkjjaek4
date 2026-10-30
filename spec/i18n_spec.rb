require "rails_helper"

RSpec.describe "User-facing translations" do
  %i[ko en].each do |locale|
    it "provides the validation messages used by the app in #{locale} without fallback" do
      %w[
        blank invalid taken confirmation too_short too_long inclusion required
        not_a_number not_an_integer greater_than greater_than_or_equal_to
      ].each do |error|
        message = I18n.t("errors.messages.#{error}", locale:, fallback: false, raise: true, count: 3, attribute: "Password")

        expect(message).to be_a(String)
      end
    end

    it "provides the user-specific validation messages in #{locale} without fallback" do
      %w[
        handle.invalid handle.blank handle.taken handle.reserved handle.immutable
        current_password.blank current_password.invalid
        password.blank password.too_short password.too_long
        password_confirmation.confirmation
        reset_password_token.invalid reset_password_token.expired
        avatar.invalid_format avatar.too_large
      ].each do |error|
        message = I18n.t("activerecord.errors.models.user.attributes.#{error}", locale:, fallback: false, raise: true, count: 6)

        expect(message).to be_a(String)
      end
    end

    it "provides the active authentication messages in #{locale} without fallback" do
      %w[
        devise.failure.already_authenticated
        devise.failure.unauthenticated
        devise.failure.invalid
        devise.failure.not_found_in_database
        devise.failure.withdrawn
        devise.sessions.signed_in
        devise.sessions.signed_out
        devise.sessions.already_signed_out
        devise.registrations.signed_up
        devise.registrations.updated
        devise.passwords.no_token
        devise.passwords.updated
        devise.passwords.updated_not_active
        devise.mailer.reset_password_instructions.subject
        auth.passwords.request_sent
        auth.passwords.rate_limited
        auth.alerts.login_rate_limited
        auth.alerts.suspended
        auth.alerts.suspended_fallback
        settings.notices.updated
        account_withdrawals.notices.completed
      ].each do |key|
        message = I18n.t(key, locale:, fallback: false, raise: true, authentication_keys: "Email", reason: "Reason")

        expect(message).to be_a(String)
      end
    end
  end

  it "keeps the club and moderation messages at their called English keys" do
    %w[
      groups.index.my_groups
      groups.index.empty_my_groups
      groups.index.empty_activity
      groups.jjaeks.title
      groups.jjaeks.book_search_context
      groups.members.history.lifecycle.admin_role_revoked
      groups.members.history.lifecycle.admin_role_granted
      admin.jjaeks.actions.hide
      admin.jjaeks.actions.restore
      admin.jjaeks.notices.hidden
      admin.jjaeks.alerts.hide_failed
      jjaeks.moderation.hidden_by_system_admin
      jjaeks.moderation.hidden_book_by_system_admin
    ].each do |key|
      expect(I18n.exists?(key, :en, fallback: false)).to be(true), "Missing en.#{key}"
    end
  end
end
