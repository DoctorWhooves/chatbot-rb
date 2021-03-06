module Chatbot
  # Much of this logic is a watered-down/modified from Cinch's plugin system
  # Thanks to them <3
  module Plugin
    attr_reader :client

    def initialize(client)
      @client = client
    end

    module ClassMethods
      attr_reader :matchers, :listeners
      Matcher = Struct.new(:pattern, :use_prefix, :method, :prefix)
      Listener = Struct.new(:event, :method)

      def match(pattern, options = {})
        options = {
            :use_prefix => true,
            :method => :execute,
            :prefix => '!'
        }.merge(options)
        matcher = Matcher.new(pattern, *options.values_at(:use_prefix, :method, :prefix))
        @matchers << matcher
        matcher
      end

      def listen_to(event, method)
        listener = Listener.new(event, method)
        @listeners << listener
        listener
      end

      def self.extended(by)
        by.instance_exec do
          @matchers = []
          @listeners = []
        end
      end
    end

    def register
      self.class.matchers.each do |matcher|
        @client.handlers[:message] << Proc.new do |message, user|
          begin
            if matcher.use_prefix
              next unless message[0] == matcher.prefix
              message = message[1..-1]
            end
            # Ignore users, *except* when it's a catch-all regex (otherwise, disk_log / wiki_log won't ever log them!)
            next if user.ignored? and not matcher.pattern.eql? /.*/
            match = matcher.pattern.match(message)
            next if match.nil?
            method = method(matcher.method)
            method.call(match, user)
          rescue => err
            $logger.fatal err
          end
        end
      end

      self.class.listeners.each do |listener|
        @client.handlers[listener.event] << Proc.new do |data|
          method = method(listener.method)
          method.call(data)
        end
      end
    end

    def self.included(by)
      by.extend ClassMethods
    end
  end


end
