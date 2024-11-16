# frozen_string_literal: true

module DiscourseEvents
  class Event < ActiveRecord::Base
    self.table_name = "discourse_events_events"
    self.ignored_columns += %i[uid source_id provider_id]

    # Associations
    has_many :event_connections,
             foreign_key: "event_id",
             class_name: "DiscourseEvents::EventConnection",
             dependent: :destroy

    has_many :connections, through: :event_connections, source: :connection
    has_many :topics, through: :event_connections

    has_many :event_sources,
             foreign_key: "event_id",
             class_name: "DiscourseEvents::EventSource",
             dependent: :destroy

    has_many :sources, through: :event_sources, source: :source

    has_many :series_events,
             primary_key: "series_id",
             foreign_key: "series_id",
             class_name: "DiscourseEvents::EventConnection"

    has_many :series_events_topics, through: :series_events, source: :topic

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :start_time, presence: true
    validates :status,
              inclusion: {
                in: %w[draft published cancelled],
                message: "%{value} is not a valid event status",
              }

    validate :end_time_after_start_time

    # Scopes
    scope :published, -> { where(status: "published") }
    scope :draft, -> { where(status: "draft") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :upcoming, -> { where("start_time >= ?", Time.zone.now) }
    scope :past, -> { where("end_time < ?", Time.zone.now) }

    # Callbacks
    before_save :set_default_status

    # Methods

    # Checks if the event is ongoing
    def ongoing?
      start_time <= Time.zone.now && (end_time.nil? || end_time >= Time.zone.now)
    end

    # Calculates event duration
    def duration
      return nil unless end_time
      end_time - start_time
    end

    # Formats the event's time range
    def formatted_time_range
      if end_time
        "#{start_time.strftime('%F %T')} - #{end_time.strftime('%F %T')}"
      else
        start_time.strftime('%F %T')
      end
    end

    private

    # Sets default status for new events
    def set_default_status
      self.status ||= "draft"
    end

    # Validates that end_time is after start_time
    def end_time_after_start_time
      return if end_time.nil? || start_time < end_time

      errors.add(:end_time, "must be after start time")
    end
  end
end

# == Schema Information
#
# Table name: discourse_events_events
#
#  id            :bigint           not null, primary key
#  start_time    :datetime         not null
#  end_time      :datetime
#  name          :string
#  description   :string
#  status        :string           default("published")
#  taxonomy      :string
#  url           :string
#  series_id     :string
#  occurrence_id :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Foreign Keys
#
#  fk_rails_...  (provider_id => discourse_events_providers.id)
#  fk_rails_...  (source_id => discourse_events_sources.id)
#
