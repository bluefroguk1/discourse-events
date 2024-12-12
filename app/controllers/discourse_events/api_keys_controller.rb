# frozen_string_literal: true
class DiscourseEvents::ApiKeysController < ApplicationController
  APPLICATION_NAME = "discourse-events"

  requires_plugin DiscourseEvents::PLUGIN_NAME

  before_action :ensure_logged_in

  def index
    key =
      UserApiKey.create! attributes.reverse_merge(
                           scopes: [
                             UserApiKeyScope.new(
                               name: "#{APPLICATION_NAME}:#{DiscourseEvents::USER_API_KEY_SCOPE}",
                             ),
                           ],
                           client_id: SecureRandom.uuid,
                         )

    render json: [{ key: key.key, client_id: key.client_id }]
  end

  private

  def attributes
    { application_name: APPLICATION_NAME, user_id: current_user.id, revoked_at: nil }
  end
end
