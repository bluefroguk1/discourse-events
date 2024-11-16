# frozen_string_literal: true
# name: discourse-events
# about: Allows you to manage events in Discourse
# version: 0.8.9
# authors: Angus McLeod
# contact_emails: angus@pavilion.tech
# url: https://github.com/paviliondev/discourse-events

enabled_site_setting :events_enabled

after_initialize do
  module ::DiscourseEvents
    PLUGIN_NAME = "discourse-events"

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseEvents
    end
  end

  # Add routes
  Discourse::Application.routes.append do
    mount ::DiscourseEvents::Engine, at: "/events"
  end

  # Reusable method to register topic custom fields
  def register_topic_custom_fields(fields)
    fields.each do |name, type|
      register_topic_custom_field_type(name, type)
    end
  end

  # Register topic custom fields
  register_topic_custom_fields(
    "event_start" => :integer,
    "event_end" => :integer,
    "event_all_day" => :boolean,
    "event_deadline" => :boolean,
    "event_rsvp" => :boolean,
    "event_going" => :json,
    "event_going_max" => :integer,
    "event_version" => :integer
  )

  # Add serializers for events
  add_to_serializer(:event, :custom_fields, false) do
    object.custom_fields.slice("start_date", "end_date", "title", "location")
  end

  add_to_serializer(:site, :event_timezones) { DiscourseEventsTimezoneDefaultSiteSetting.values }

  add_to_serializer(:topic_list_item, :event, include_condition: -> { object.has_event? }) do
    object.event
  end

  add_to_serializer(:topic_list_item, :event_going_total, include_condition: -> { object.has_event? }) do
    object.event_going ? object.event_going.length : 0
  end

  # Register admin assets
  register_asset "stylesheets/common/events.scss"
  register_asset "stylesheets/desktop/events.scss", :desktop
  register_asset "stylesheets/mobile/events.scss", :mobile

  # Include additional libraries
  %w[
    timezone_default_site_setting
    timezone_display_site_setting
    engine
    helper
    list
    event_creator
    event_revisor
    logger
    import_manager
    sync_manager
    syncer/discourse_events
    syncer/discourse_calendar
    publisher/event_data
  ].each do |lib|
    require_relative "lib/discourse_events/#{lib}.rb"
  end

  # Register user fields
  register_user_custom_field_type("calendar_first_day_week", :integer)
  add_to_serializer(:current_user, :calendar_first_day_week) do
    object.custom_fields["calendar_first_day_week"]
  end

  if defined?(register_editable_user_custom_field)
    register_editable_user_custom_field :calendar_first_day_week
  end

  # Custom category settings
  %w[
    events_enabled
    events_agenda_enabled
    events_calendar_enabled
    events_min_trust_to_create
    events_required
  ].each do |key|
    register_category_custom_field_type(key, key == "events_min_trust_to_create" ? :integer : :boolean)

    if CategoryList.respond_to?(:preloaded_category_custom_fields)
      CategoryList.preloaded_category_custom_fields << key
    end

    if Site.respond_to?(:preloaded_category_custom_fields)
      Site.preloaded_category_custom_fields << key
    end

    add_to_class(:category, key.to_sym) { self.custom_fields[key] }
    add_to_serializer(:basic_category, key.to_sym) { object.send(key) }
  end

  # Topic associations
  Topic.has_one :event_connection, class_name: "DiscourseEvents::EventConnection"
  Topic.has_one :event_record, through: :event_connection, source: :event, class_name: "DiscourseEvents::Event"

  # Event-related hooks
  on(:post_created) do |post, opts, user|
    DiscourseEvents::EventCreator.create(post, opts, user)
    DiscourseEvents::PublishManager.perform(post, "create") unless opts[:skip_event_publication]
  end

  on(:post_edited) { |post| DiscourseEvents::PublishManager.perform(post, "update") }

  # User destroyed hook to clean up RSVPs
  on(:user_destroyed) do |user|
    user_id = user.id
    topic_ids = TopicCustomField.where(name: "event_going").pluck(:topic_id)

    Topic.where(id: topic_ids).find_each do |topic|
      rsvp_array = topic.custom_fields["event_going"] || []
      rsvp_array.delete(user_id)
      topic.custom_fields["event_going"] = rsvp_array
      topic.save_custom_fields(true)
    end
  end
end
