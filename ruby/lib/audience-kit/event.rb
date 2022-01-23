class Event
  attr_reader :data

  def self.find(id)
    Event.new API_CONNECTION.get("/v1/events/#{id}").body['event']
  end

  def initialize(data)
    @data = data
    puts "Event => #{data}"
  end
end