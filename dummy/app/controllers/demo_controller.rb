class DemoController < ApplicationController
  around_action :switch_locale

  def show
  end

  private

  def switch_locale(&action)
    I18n.with_locale(params[:locale] || I18n.default_locale, &action)
  end
end
