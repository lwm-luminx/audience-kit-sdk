class Venue
  attr_reader :data

  def self.find(id)
    Venue.new API_CONNECTION.get("/v1/venues/#{id}").body['venue']
  end

  def initialize(data)
    @data = data
    puts "Venue => #{data}"
  end
end