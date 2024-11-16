# frozen_string_literal: true

module DiscourseEvents
  class EventController < AdminController
    PAGE_LIMIT = 30

    before_action :ensure_logged_in, only: [:destroy]

    # GET /events
    def index
      page = params.fetch(:page, 0).to_i
      order = params.fetch(:order, "start_time")
      direction = ActiveRecord::Type::Boolean.new.cast(params[:asc]) ? "ASC" : "DESC"

      events = fetch_paginated_events(page, order, direction)

      render_json_dump(
        page: page,
        events: serialize_data(events, EventSerializer, root: false)
      )
    rescue StandardError => e
      render_json_error("An error occurred while fetching events: #{e.message}")
    end

    # DELETE /events
    def destroy
      event_ids = Array(params[:event_ids])
      target = params[:target]

      if event_ids.blank? || !%w[events_only events_and_topics topics_only].include?(target)
        render json: failed_json.merge(error: "Invalid parameters")
        return
      end

      result = destroy_events_and_topics(event_ids, target)

      if result[:destroyed_event_ids].present? || result[:destroyed_topics_event_ids].present?
        render json: success_json.merge(result)
      else
        render json: failed_json
      end
    rescue StandardError => e
      render_json_error("An error occurred while deleting events: #{e.message}")
    end

    private

    # Fetch paginated events with sorting
    def fetch_paginated_events(page, order, direction)
      offset = page * PAGE_LIMIT

      Event
        .includes(:sources, event_connections: [:topic])
        .order("#{sanitize_sql(order)} #{sanitize_sql(direction)}")
        .offset(offset)
        .limit(PAGE_LIMIT)
    end

    # Perform destruction of events and associated topics
    def destroy_events_and_topics(event_ids, target)
      result = { destroyed_event_ids: [], destroyed_topics_event_ids: [] }

      ActiveRecord::Base.transaction do
        events = Event.where(id: event_ids)

        if target.in?(%w[events_and_topics topics_only])
          result[:destroyed_topics_event_ids] += destroy_related_topics(events)
        end

        if target.in?(%w[events_and_topics events_only])
          destroyed_events = events.destroy_all
          result[:destroyed_event_ids] += destroyed_events.map(&:id)
        end
      end

      result
    end

    # Destroy topics associated with the given events
    def destroy_related_topics(events)
      destroyed_event_ids = []

      events.includes(:event_connections).each do |event|
        event.event_connections.each do |connection|
          PostDestroyer.new(current_user, connection.topic.first_post).destroy
        end
        destroyed_event_ids << event.id
      end

      destroyed_event_ids
    end

    # Sanitize SQL to prevent injection
    def sanitize_sql(value)
      ActiveRecord::Base.connection.quote_string(value)
    end
  end
end
