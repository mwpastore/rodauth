module Rodauth
  Remember = Feature.define(:remember) do
    depends :logout
    route 'remember'
    notice_flash "Your remember setting has been updated"
    view 'remember', 'Change Remember Setting'
    view 'confirm-password', 'Confirm Password', 'remember_confirm'
    additional_form_tags
    additional_form_tags 'remember_confirm'
    button 'Change Remember Setting'
    button 'Confirm Password', 'remember_confirm'
    after
    after 'load_memory'
    after 'remember_confirm'
    redirect
    redirect :remember_confirm
    require_account

    auth_value_method :remember_cookie_options, {}
    auth_value_method :extend_remember_deadline?, false
    auth_value_method :remember_period, {:days=>14}
    auth_value_method :remembered_session_key, :remembered
    auth_value_method :remember_deadline_interval, {:days=>14}
    auth_value_method :remember_id_column, :id
    auth_value_method :remember_key_column, :key
    auth_value_method :remember_deadline_column, :deadline
    auth_value_method :remember_table, :account_remember_keys
    auth_value_method :remember_cookie_key, '_remember'
    auth_value_method :remember_param, 'remember'
    auth_value_method :remember_confirm_param, 'confirm'

    auth_methods(
      :add_remember_key,
      :clear_remembered_session_key,
      :disable_remember_login,
      :forget_login,
      :generate_remember_key_value,
      :get_remember_key,
      :load_memory,
      :logged_in_via_remember_key?,
      :remember_key_value,
      :remember_login,
      :remove_remember_key
    )

    get_block do |r, auth|
      if auth._param(auth.remember_confirm_param)
        auth.remember_confirm_view
      else
        auth.remember_view
      end
    end

    post_block do |r, auth|
      if auth._param(auth.remember_confirm_param)
        if auth.password_match?(auth.param(auth.password_param))
          auth.transaction do
            auth.clear_remembered_session_key
            auth._after_remember_confirm
          end
          r.redirect auth.remember_confirm_redirect
        else
          @password_error = auth.invalid_password_message
          auth.remember_confirm_view
        end
      else
        auth.transaction do
          case auth.param(auth.remember_param)
          when 'remember'
            auth.remember_login
          when 'forget'
            auth.forget_login 
          when 'disable'
            auth.disable_remember_login 
          end
          auth._after_remember
        end
        auth.set_notice_flash auth.remember_notice_flash
        r.redirect auth.remember_redirect
      end
    end

    def _after_logout
      forget_login
      super
    end

    def _after_close_account
      remove_remember_key
      super if defined?(super)
    end

    attr_reader :remember_key_value

    def generate_remember_key_value
      @remember_key_value = random_key
    end

    def load_memory
      return if session[session_key]
      return unless cookie = request.cookies[remember_cookie_key]
      id, key = cookie.split('_', 2)
      return unless id && key

      id = id.to_i

      return unless actual = active_remember_key_dataset(id).
        get(remember_key_column)

      return unless timing_safe_eql?(key, actual)

      session[session_key] = id
      account = _account_from_session
      session.delete(session_key)

      unless account
        remove_remember_key(id)
        return 
      end

      update_session

      session[remembered_session_key] = true
      if extend_remember_deadline?
        active_remember_key_dataset(id).update(:deadline=>Sequel.date_add(:deadline, remember_period))
      end
      _after_load_memory
    end

    def remember_login
      get_remember_key
      opts = Hash[remember_cookie_options]
      opts[:value] = "#{account_id_value}_#{remember_key_value}"
      ::Rack::Utils.set_cookie_header!(response.headers, remember_cookie_key, opts)
    end

    def forget_login
      ::Rack::Utils.delete_cookie_header!(response.headers, remember_cookie_key, remember_cookie_options)
    end

    def remember_key_dataset(id_value=account_id_value)
      db[remember_table].
        where(remember_id_column=>id_value)
    end
    def active_remember_key_dataset(id_value=account_id_value)
      remember_key_dataset(id_value).where(Sequel.expr(remember_deadline_column) > Sequel::CURRENT_TIMESTAMP)
    end

    def get_remember_key
      unless @remember_key_value = active_remember_key_dataset.get(remember_key_column)
       generate_remember_key_value
       transaction do
         remove_remember_key
         add_remember_key
       end
      end
      nil
    end

    def disable_remember_login
      remove_remember_key
    end

    def add_remember_key
      hash = {remember_id_column=>account_id_value, remember_key_column=>remember_key_value}
      set_deadline_value(hash, remember_deadline_column, remember_deadline_interval)
      remember_key_dataset.insert(hash)
    end

    def remove_remember_key(id_value=account_id_value)
      remember_key_dataset(id_value).delete
    end

    def clear_remembered_session_key
      session.delete(remembered_session_key)
    end

    def logged_in_via_remember_key?
      !!session[remembered_session_key]
    end

    def use_date_arithmetic?
      extend_remember_deadline? || db.database_type == :mysql
    end
  end
end
