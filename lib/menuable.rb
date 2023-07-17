# frozen_string_literal: true

require_relative "menuable/version"
require "active_support/all"

module Menuable
  extend ActiveSupport::Concern

  class_methods do
    def menu(resource_name, &block)
      namespace = self.name.to_s.deconstantize.constantize

      menu = Class.new(MenuDefinition)
      menu.namespace =
        self.name.split("::").try do |token|
          token.shift
          token.pop
          token.first&.underscore
        end
      menu.resource_name = resource_name
      menu.model_name = ActiveModel::Name.new(nil, nil, "#{namespace}/#{resource_name.to_s.classify}")
      menu.instance_eval(&block) if block

      self.class_eval do
        class_attribute :menu, default: menu
      end
    end
  end

  class MenuDefinition
    class_attribute :namespace
    class_attribute :resource_name
    class_attribute :model_name
    class_attribute :name

    NOTHING = ->(_) { true }

    def self.loyalty(&value)
      return (@loyalty || NOTHING) if value.nil?

      @loyalty = value
    end

    def self.member_actions(values = nil)
      return Array(@member_actions) if values.nil?

      @member_actions = values
    end
  end

  class MenuContext
    attr_reader :context

    def initialize(menus:, context:)
      @menus = menus
      @context = context
    end

    def each
      @menus.each do |config|
        case config
        in divider:
          yield config
        in group:
          items = config[:items].filter_map { |item| menu(item) }
          yield menu({ **config, items: })
        else
          menu(config).try { yield _1 }
        end
      end
    end

    private

    def menu(config)
      return unless approved?(config)
      return { **config, active: active?(config) } if config[:controller].nil?

      { **config, active: active?(config), path: path(config) }
    end

    def path(config)
      path = context.url_for(config[:controller].menu) if config[:controller]
      path || config[:path] || "/"
    end

    def active?(menu)
      case menu
      in items:
        items.any? do |item|
          path = path(item)
          path = path[0..-2] if path.end_with?("/")
          context.request.path.start_with?(path)
        end
      else
        path = path(menu)
        path = path[0..-2] if path.end_with?("/")
        context.request.path.start_with?(path)
      end
    end

    def approved?(config)
      if config[:loyalty]
        context.public_send(:"#{config[:loyalty]}?")
      elsif config[:controller]
        config[:controller].menu.loyalty.call(context.current_user)
      else
        true
      end
    end
  end

  class Menu
    def initialize(namespace, path)
      @controllers = []
      @menus = YAML.load_file(path).map do |config|
        config.deep_symbolize_keys!
        controller = "#{namespace}/#{config[:name]}_controller".classify.safe_constantize
        @controllers << controller if controller
        config[:items]&.each do |item|
          item[:controller] = "#{namespace}/#{item[:name]}_controller".classify.safe_constantize
          @controllers << item[:controller] if item[:controller]
        end
        { **config, controller: }
      end
    end

    def all
      @menus
    end

    def call(context)
      MenuContext.new(menus: @menus, context:)
    end

    def first(current_user:)
      @controllers.each do |controller|
        break controller.menu if controller.menu.loyalty.call(current_user)
      end
    end

    def routes(routing)
      controllers = @controllers
      routing.instance_eval do
        controllers.each do |controller|
          if controller.menu.namespace
            namespace controller.menu.namespace do
              resources controller.menu.resource_name do
                controller.menu.member_actions.each do |action_name|
                  get action_name, on: :member
                end
              end
            end
          else
            resources controller.menu.resource_name do
              controller.menu.member_actions.each do |action_name|
                get action_name, on: :member
              end
            end
          end
        end
      end
    end
  end
end
