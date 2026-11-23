# frozen_string_literal: true

class JrcCulture::ShellController < ApplicationController
  include JrcCulture::NativeSession

  def show
    render layout: false
  end
end
