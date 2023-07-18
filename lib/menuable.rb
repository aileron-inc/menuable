# frozen_string_literal: true

require_relative "menuable/version"
require "active_support/all"

module Menuable
  extend ActiveSupport::Concern

  class_methods do
    def resource(resource_name, **options, &block)
      resources(resource_name, single: true, **options, &block)
    end

    def resources(resource_name, single: false, **options, &block)
      namespace = name.to_s.deconstantize.constantize

      menu = Class.new(MenuDefinition)
      menu.options = options
      menu.single = single
      menu.resource_name = resource_name
      menu.model_name = ActiveModel::Name.new(nil, nil, "#{namespace}/#{resource_name.to_s.classify}")
      menu.instance_eval(&block) if block

      class_eval do
        class_attribute :menu, default: menu
      end
    end
  end

  class MenuDefinition
    class_attribute :options
    class_attribute :resource_name
    class_attribute :model_name
    class_attribute :single

    NOTHING = ->(_) { true }

    def self.single?
      single
    end

    def self.loyalty(&value)
      return (@loyalty || NOTHING) if value.nil?

      @loyalty = value
    end

    def self.actions(&value)
      return @actions if value.nil?

      @actions = value
    end
  end

  class MenuContext
    attr_reader :context

    def initialize(menus:, context:)
      @menus = menus
      @context = context
    end

    def each # rubocop:todo Metrics/MethodLength
      return enum_for(:each) unless block_given?

      @menus.each do |config|
        case config
        in divider:
          yield config
        in items:
          yield menu({ **config, items: items.filter_map { |item| menu(item) } })
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
    def initialize(namespace, path) # rubocop:todo Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
      extract_namespace = lambda do |name|
        if name
          namespaces = name.split("/")
          namespaces.pop
          namespaces
        else
          []
        end
      end

      @controllers = {}
      @menus = YAML.load_file(path).map do |config|
        config.deep_symbolize_keys!
        namespaces = extract_namespace.call(config[:name])
        controller = "#{namespace}/#{config[:name]&.pluralize}_controller".classify.safe_constantize
        @controllers[namespaces] ||= []
        @controllers[namespaces] << controller if controller

        config[:items]&.each do |item|
          item[:controller] = "#{namespace}/#{item[:name]&.pluralize}_controller".classify.safe_constantize
          item_namespaces = extract_namespace.call(item[:name])
          @controllers[item_namespaces] ||= []
          @controllers[item_namespaces] << item[:controller] if item[:controller]
        end

        { **config, controller:, namespaces: }
      end
    end

    def all
      @menus
    end

    def call(context)
      MenuContext.new(menus: @menus, context:)
    end

    def first(current_user:)
      @controllers.values.flatten.each do |controller|
        break controller.menu if controller.menu.loyalty.call(current_user)
      end
    end

    def routes(routing) # rubocop:todo Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
      controller_mappings = @controllers
      routing.instance_eval do # rubocop:todo Metrics/BlockLength
        controller_mappings.each do |namespaces, controllers| # rubocop:todo Metrics/BlockLength
          define =
            controllers.map do |controller|
              if controller.menu.single?
                lambda do |router|
                  router.resource controller.menu.resource_name do
                    router.instance_eval(&controller.menu.actions) if controller.menu.actions
                  end
                end
              else
                lambda do |router|
                  router.resources controller.menu.resource_name do
                    router.instance_eval(&controller.menu.actions) if controller.menu.actions
                  end
                end
              end
            end

          case namespaces.length
          when 3
            namespace namespaces[0] do
              namespace namespaces[1] do
                namespace namespaces[2] { define.each { _1.call(self) } }
              end
            end
          when 2
            namespace namespaces[0] do
              namespace(namespaces[1]) { define.each { _1.call(self) } }
            end
          when 1
            namespace(namespaces[0]) { define.each { _1.call(self) } }
          when 0
            define.each { _1.call(self) }
          end
        end
      end
    end
  end
end
