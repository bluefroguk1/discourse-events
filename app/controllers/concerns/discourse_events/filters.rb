# frozen_string_literal: true
module DiscourseEvents
  module Filters
    def valid_filters
    end

    def save_filters
      @errors ||= []
      saved_ids = []
      filters_to_upsert = []

      ActiveRecord::Base.transaction do
        valid_filters.each do |f|
          params = f.slice(:query_column, :query_operator, :query_value)

          if f[:id] === "new"
            filters_to_upsert << {
              model_id: @model.id,
              model_type: @model.class.name,
              **params,
              created_at: Time.now,
              updated_at: Time.now,
            }
          else
            filter = @model.filters.find(f[:id].to_i)
            if filter.query_column != params[:query_column] || filter.query_operator != params[:query_operator] || filter.query_value != params[:query_value]
              filters_to_upsert << {
                id: filter.id,
                **params,
                updated_at: Time.now,
              }
            end
            saved_ids << filter.id
          end
        end

        DiscourseEvents::Filter.upsert_all(filters_to_upsert, unique_by: :id) if filters_to_upsert.any?

        @model.filters.where.not(id: saved_ids).destroy_all
      end
    end
  end
end
