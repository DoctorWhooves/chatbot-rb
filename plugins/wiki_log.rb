require 'httparty'
class WikiLog
  include Chatbot::Plugin
  match /^updatelogs$/, :method => :update_logs_command
  match /^logs$/, :method => :logs_command
  match /^updated$/, :method => :updated_command
  match /.*/, :method => :on_message, :use_prefix => false

  listen_to :join, :on_join
  listen_to :part, :on_part
  listen_to :kick, :on_kick
  listen_to :ban, :on_ban
  listen_to :quitting, :on_bot_quit

  CATEGORY_TS = "%Y %m %d"
  attr_accessor :log_thread, :buffer, :buffer_mutex
  def initialize(bot)
    super(bot)
    @buffer = ''
    @buffer_mutex = Mutex.new
    @log_thread = make_thread
    @last_log = nil
    unless @client.config.key? :wikilog
      @client.config[:wikilog] = {
          :log_interval => 3600,
          :title => '',
          :type => :daily,
          :fifo_threshold => 5000,
          :category => 'Chat logs'
      }
      @client.save_config
    end
    @options = @client.config[:wikilog]
  end

  def make_thread
    thr = Thread.new(@options) {
      sleep @options[:log_interval]
      update
    }
    @client.threads << thr
    thr
  end

  def update
    update_logs
    @log_thread = make_thread
  end

  def update_logs
    @last_log = Time.now.utc
    title = Time.now.utc.strftime @options[:title]
    text = @buffer.dup.gsub('<', '&lt;').gsub('>', '&gt;') # Ideally, this is inside a buffer lock somewhere...
    @buffer = ''
    page_content = @client.api.get(title)
    if @options[:type].eql? :fifo
      if page_content.scan(/\n/).size >= @options[:fifo_threshold]
        text = "<pre class=\"ChatLog\">#{text}\n</pre>\n[[Category:#{@options[:category]}]]"
      else
        text = page_content.gsub('</pre>', text + '</pre>')
      end
    else # Daily or overwrite
      if page_content.nil? or @options[:type].eql? :overwrite
        text = "<pre class=\"ChatLog\">#{text}</pre>\n[[Category:#{@options[:category]}|#{Time.now.utc.strftime CATEGORY_TS}]]"
      else
        text = page_content.gsub('</pre>', text + '</pre>')
      end
    end
    @client.api.edit title, text, :bot => 1, :minor => 1, :summary => 'Updating chat logs'
  end

  def update_logs_command(captures, user)
    if user.is? :mod
      @buffer_mutex.synchronize do
        lines = @buffer.scan(/\n/).size
        update
        @client.send_msg "#{user.name}: [[Project:Chat/Logs|Logs]] updated (added ~#{lines} to log page)."
      end
    end
  end

  def logs_command(captures, user)
    @client.send_msg "#{user.name}: Logs can be seen [[Project:Chat/Logs|here]]."
  end

  def updated_command(captures, user)
    if @last_log.nil?
      @client.send_msg "#{user.name}: I haven't updated the logs since I joined here. There are currently ~#{@buffer.scan(/\n/).size} lines in the log buffer."
    else
      @client.send_msg "#{user.name}: I last updated the logs #{Time.now.utc.to_i - @last_log.to_i} seconds ago. There are currently ~#{@buffer.scan(/\n/).size} lines in the log buffer."
    end
  end

  def on_bot_quit(*a)
    @log_thread.kill
    update_logs
  end

  def on_ban(data)
    @buffer_mutex.synchronize do
      @buffer << "\n" + Util::ts + " -!- #{data['attrs']['kickedUserName']} was banned from Special:Chat by #{data['attrs']['moderatorName']}"
    end
  end

  def on_kick(data)
    @buffer_mutex.synchronize do
      @buffer << "\n" + Util::ts + " -!- #{data['attrs']['kickedUserName']} was kicked from Special:Chat by #{data['attrs']['moderatorName']}"
    end
  end

  def on_part(data)
    @buffer_mutex.synchronize do
      @buffer << "\n" + Util::ts + " -!- #{data['attrs']['name']} has left Special:Chat"
    end
  end

  def on_join(data)
    @buffer_mutex.synchronize do
      @buffer << "\n" + Util::ts + " -!- #{data['attrs']['name']} has joined Special:Chat"
    end
  end

  def on_message(captures, user)
    @buffer_mutex.synchronize do
      if /^\/me/.match captures[0]
        @buffer << "\n" + Util::ts + " * #{user.log_name} #{captures[0].gsub(/\/me /, '')}"
      else
        @buffer << "\n" + Util::ts + " <#{user.log_name}> #{captures[0]}"
      end
    end
  end

  def get_page_contents(title)

  end
end