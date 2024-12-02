# frozen_string_literal: true

module DiscourseEvents
  class EventController < AdminController
    PAGE_LIMIT = 30

    def index
      order = params[:order]
      raise Discourse::InvalidParameters.new(:order) if order && %w[start_time name].exclude?(order)
      order ||= "start_time"

      direction = ActiveRecord::Type::Boolean.new.cast(params[:asc]) ? "ASC" : "DESC"
      page = params[:page].to_i
      offset = page * PAGE_LIMIT
      limit = PAGE_LIMIT

      events = Event.order(order => direction).offset(offset).limit(limit)

      combined_sql = (<<~SQL)
        SELECT
          COUNT(CASE WHEN cardinality(topic_ids) > 0 THEN 1 END) AS with_topics_count,
          COUNT(CASE WHEN cardinality(topic_ids) = 0 THEN 1 END) AS without_topics_count
        FROM (#{Event.list_sql}) AS events
      SQL

      combined_query = ActiveRecord::Base.connection.execute(combined_sql).first

      providers = Rails.cache.fetch("providers_list", expires_in: 12.hours) do
        Provider.all.to_a
      end

      render_json_dump(
        page: page,
        filter: filter,
        order: order,
        with_topics_count: combined_query["with_topics_count"],
        without_topics_count: combined_query["without_topics_count"],
        events: serialize_data(events, EventSerializer, root: false),
        providers: serialize_data(providers, ProviderSerializer, root: false),
      )
    end

    def all
      events = Event.all
      render json: { event_ids: events.map(&:id) }.as_json
    end

    def destroy
      event_ids = params[:event_ids]
      target = params[:target]

      result = EventDestroyer.perform(user: current_user, event_ids: event_ids, target: target)

      if result[:destroyed_event_ids].present? || result[:destroyed_topics_event_ids].present?
        render json: success_json.merge(result)
      else
        render json: failed_json
      end
    end

    protected

    def filter
      @filter ||=
        begin
          result = params[:filter]
          if result && %w[unconnected connected].exclude?(result)
            raise Discourse::InvalidParameters.new(:filter)
          end
          result
        end
    end

    def filter_sql
      @filter_sql ||=
        begin
          if filter
            "WHERE et.topic_id IS #{filter === "unconnected" ? "NULL" : "NOT NULL"}"
          else
            ""
          end
        end
    end

    def events_sql(order: nil, direction: nil, offset: nil, limit: nil)
      sql = (<<~SQL)
        SELECT * FROM (#{Event.list_sql(filter_sql: filter_sql)}) AS events
      SQL

      sql << (<<~SQL) if !order.nil? && !direction.nil?
          ORDER BY #{order} #{direction}
        SQL

      sql << (<<~SQL) if !offset.nil? && !limit.nil?
          OFFSET #{offset}
          LIMIT #{limit}
        SQL

      sql
    end
  end
end
