module DiamondRemote

  def self.config
    @@config ||= DiamondRemote.new
  end

  def self.configure
    yield config if block_given?
  end

  class DiamondRemote 
    [:typical_diamond_delay, :username, :password, :custnumber, :firm_name_at_diamond, :download_dir ].each do |attr|
      attr_accessor attr
    end
  end
end



