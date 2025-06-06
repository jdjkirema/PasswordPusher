# frozen_string_literal: true

class Url < ApplicationRecord
  has_many :views, -> { order(created_at: :asc) }, dependent: :destroy
  has_encrypted :payload, :note, :passphrase

  belongs_to :user, optional: true

  def to_param
    url_token.to_s
  end

  def days_old
    (Time.zone.now.to_datetime - created_at.to_datetime).to_i
  end

  def days_remaining
    [(expire_after_days - days_old), 0].max
  end

  def views_remaining
    [(expire_after_views - view_count), 0].max
  end

  def view_count
    views.where(kind: 0).size
  end

  def successful_views
    views.where(successful: true, kind: 0).order(:created_at)
  end

  def failed_views
    views.where(successful: false, kind: 0).order(:created_at)
  end

  # Expire this password, delete the password and save the record
  def expire
    self.expired = true
    self.payload = nil
    self.passphrase = nil
    self.expired_on = Time.zone.now
    save
  end

  # Override to_json so that we can add in <days_remaining>, <views_remaining>
  # and show the clear password
  def to_json(*args)
    # def to_json(owner: false, payload: false)
    attr_hash = attributes

    owner = false
    payload = false

    owner = args.first[:owner] if args.first.key?(:owner)
    payload = args.first[:payload] if args.first.key?(:payload)

    attr_hash["days_remaining"] = days_remaining
    attr_hash["views_remaining"] = views_remaining

    # Remove unnecessary fields
    attr_hash.delete("payload_ciphertext")
    attr_hash.delete("note_ciphertext")
    attr_hash.delete("passphrase_ciphertext")
    attr_hash.delete("user_id")
    attr_hash.delete("id")

    attr_hash.delete("passphrase")
    attr_hash.delete("name") unless owner
    attr_hash.delete("note") unless owner
    attr_hash.delete("payload") unless payload

    Oj.dump attr_hash
  end

  ##
  # validate!
  #
  # Run basic validations on the password.  Expire the password
  # if it's limits have been reached (time or views)
  #
  def validate!
    return if expired

    # Range checking
    self.expire_after_days ||= Settings.url.expire_after_days_default
    self.expire_after_views ||= Settings.url.expire_after_views_default

    unless expire_after_days.between?(Settings.url.expire_after_days_min, Settings.url.expire_after_days_max)
      self.expire_after_days = Settings.url.expire_after_days_default
    end

    unless expire_after_views.between?(Settings.url.expire_after_views_min, Settings.url.expire_after_views_max)
      self.expire_after_views = Settings.url.expire_after_views_default
    end

    return if new_record?

    expire if !days_remaining.positive? || !views_remaining.positive?
  end
end
