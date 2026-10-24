class RegistrationInvitation < ApplicationRecord
  VALIDITY_PERIOD = 7.days

  belongs_to :invited_by, class_name: "User"
  belongs_to :user, optional: true

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, format: { with: Devise.email_regexp }
  validates :token_digest, :expires_at, presence: true
  validate :email_is_available, on: :create
  validate :email_has_no_other_pending_invitation, on: :create

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_by_token(token)
    return if token.blank?

    find_by(token_digest: digest(token))
  end

  def active?
    consumed_at.nil? && canceled_at.nil? && expires_at.future?
  end

  def status
    return :used if consumed_at?
    return :canceled if canceled_at?
    return :expired if expires_at <= Time.current

    :pending
  end

  # The plain token exists only in the caller and the outgoing mail.
  def issue_token!
    token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest(token)
    self.expires_at = VALIDITY_PERIOD.from_now
    token
  end

  def resend_token!
    raise ActiveRecord::RecordInvalid, self if consumed_at? || canceled_at?
    if User.exists?(email: email)
      errors.add(:email, :taken)
      raise ActiveRecord::RecordInvalid, self
    end

    token = issue_token!
    save!
    token
  end

  def cancel!
    raise ActiveRecord::RecordInvalid, self if consumed_at? || canceled_at?

    update!(canceled_at: Time.current)
  end

  private

  def email_is_available
    errors.add(:email, :taken) if User.exists?(email: email)
  end

  def email_has_no_other_pending_invitation
    return if consumed_at? || canceled_at?

    errors.add(:email, :taken) if self.class.where(email:, consumed_at: nil, canceled_at: nil).exists?
  end
end
