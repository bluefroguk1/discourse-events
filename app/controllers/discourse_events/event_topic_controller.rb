# frozen_string_literal: true

module DiscourseEvents
  class EventTopicController < AdminController
    before_action :find_event_and_topic, only: [:connect]

    def connect
      topic_opts = {}

      user = Rails.cache.fetch("user_#{params[:username] || current_user.username}", expires_in: 12.hours) do
        params[:username] ? User.find_by!(username: params[:username]) : current_user
      end

      category_id = params[:category_id]
      category = nil
      if category_id
        category = Rails.cache.fetch("category_#{category_id}", expires_in: 12.hours) do
          Category.find_by!(id: category_id)
        end
        topic_opts[:category] = category_id
      end

      client = params[:client]
      raise Discourse::InvalidParameters.new(:client) if Source.available_clients.exclude?(client)

      if !@topic && client == "discourse_events"
        raise Discourse::InvalidParameters.new(:category_id) unless category&.events_enabled
      end

      syncer = SyncManager.new_client(client, user)
      connected_topic = nil

      if @topic
        event_topic = EventTopic.upsert({ event_id: @event.id, topic_id: @topic.id }, unique_by: :index_discourse_events_event_topics_on_event_id_and_topic_id)
        connected_topic = syncer.connect_topic(@topic, @event)
      else
        connected_topic = syncer.create_topic(@event, topic_opts)
      end

      if connected_topic.present?
        render json: success_json
      else
        render json: failed_json
      end
    end

    def update
      event_topic = @event.event_topics.first

      syncer = SyncManager.new_client(event_topic.client, event_topic.topic.first_post.user)
      updated_topic = syncer.update_topic(event_topic.topic, @event)

      if updated_topic.present?
        render json: success_json
      else
        render json: failed_json
      end
    end

    protected

    def find_event_and_topic
      event_id = params[:event_id]
      topic_id = params[:topic_id]

      @event = Event.find_by!(id: event_id)
      @topic = Topic.find_by(id: topic_id) if topic_id

      raise Discourse::InvalidParameters.new(:topic_id) if action_name.to_sym == :update && @topic.nil?
    end
  end
end
