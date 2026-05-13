class DemoController < ApplicationController
  def home
    I18n.locale = :en
  end

  def spanish
    I18n.locale = :es
  end

  def plural
    @count = (params[:count] || 3).to_i
  end
end
