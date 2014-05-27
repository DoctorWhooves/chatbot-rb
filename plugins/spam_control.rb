class SpamControl
  include Chatbot::Plugin
 
  SpamInfo = Struct.new(:last_message_text, :last_message_time, :threshold)
  def initialize(bot)
    super(bot)
    @users = {}
    @mut = Mutex.new
  end
 
  match /.*/, :method => :on_message, :use_prefix => false
  def on_message(captures, user)
    return if user.is? :mod or user.name.eql? @client.config['username']
    unless @users.key? user.name
      return @users[user.name] = SpamInfo.new(captures[0], Time.now.utc, is_spammy?(captures[0]) ? 1 : 0)
    end
    @mut.synchronize do
      info = @users[user.name].dup
      info.threshold += 1 if Time.now.utc.to_f - info.last_message_time.to_f < 1.0 # Time since last message < 1 second
      info.threshold += 1 if captures[0].eql?(info.last_message_text) and Time.now.utc.to_f - info.last_message_time.to_f < 3.0 # Same message as last time and time since last message < 3 seconds
      info.threshold += 1 if is_spammy?(captures[0]) # Text seems 'spammy'
      if info.threshold >= @client.config[:spam_threshold] # User is over threshold
        @client.kick user.name
        @users.delete(user.name)
      elsif Time.now.utc.to_f - info.last_message_time.to_f > 10 # User is not over threshold and hasn't spoken for 10 seconds
        @users.delete(user.name)
      else # User is not over threshold, but last message was < 10 seconds ago
        @users[user.name] = SpamInfo.new(captures[0], Time.now.utc, info.threshold)
      end
    end
  end
 
  ##
  # Check if text is 'spammy' - i.e. has the same character repeated some obscene amount of times, or has a lot of gibb-
  # erish looking stuff.
  def is_spammy?(text)
    [
        /(.)\1{19,}/,
        /[[:punct:]]{10,}/,
        /[asdfghjkl;]{10,}/i,
        /[zxcvbnm,\.]{10,}/i
    ].collect {|pattern| pattern.match(text)}.select {|result| !result.nil?}.size > 0
  end
end
