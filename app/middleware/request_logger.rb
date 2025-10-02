# frozen_string_literal: true
# app/middleware/request_logger.rb
#
# Detailed request logging for debugging and analytics

class RequestLogger
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    start_time = Time.current

    status, headers, response = @app.call(env)

    duration = ((Time.current - start_time) * 1000).round(2)

    # Log API requests only
    if request.path.start_with?("/api/")
      log_request(request, status, duration)
    end

    [status, headers, response]
  rescue => e
    log_error(request, e)
    raise
  end

  private

  def log_request(request, status, duration)
    Rails.logger.info({
      type: "api_request",
      method: request.method,
      path: request.path,
      status: status,
      duration_ms: duration,
      ip: request.remote_ip,
      user_agent: request.user_agent,
      params: safe_params(request),
      timestamp: Time.current.iso8601
    }.to_json)
  end

  def log_error(request, exception)
    Rails.logger.error({
      type: "api_error",
      method: request.method,
      path: request.path,
      error: exception.class.name,
      message: exception.message,
      backtrace: exception.backtrace&.first(5),
      ip: request.remote_ip,
      timestamp: Time.current.iso8601
    }.to_json)
  end

  def safe_params(request)
    request.params.except(:controller, :action, :format).to_unsafe_h
  rescue
    {}
  end
end