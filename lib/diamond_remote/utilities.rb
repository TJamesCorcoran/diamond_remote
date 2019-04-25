require 'mechanize'
require 'ostruct'
require 'csv'
require 'base64'
require 'open-uri'

module DiamondRemote
  
  # attr accessor stuff
  @@logger = method(:puts)   

  # works in a class, not a module
  #   cattr_accessor :logger
  # works in a module
  #
  def self.logger=(l) @@logger = l end
  def self.logger()  @@logger end
    

  private
  
  def self.get_agent()    @@agent   end
  def self.get_cookies()    @@agent.cookie_jar.jar.first[1].first[1].keys   end
  
  @@agent = Mechanize.new
  @@agent.user_agent = "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.2.13) Gecko/20101206 Ubuntu/10.04 (lucid) Firefox/3.6.13"
  #  @@agent.post_connect_hooks << MechanizeCleanupHook.new
  
  LOGIN_COOKIE_NAME             = '.ASPXAUTH'
  
  ROOT_URL                      = 'https://retailerservices.diamondcomics.com'
  LOGIN_URL                     = 'https://retailerservices.diamondcomics.com/Login/Login'
  LOGOUT_URL                    = 'https://retailerservices.diamondcomics.com/Login/Logout'
  ITEM_URL_BASE                 = 'https://retailerservices.diamondcomics.com/ShoppingList/AddItem/'
  DEFAULT_URL                   = 'https://retailerservices.diamondcomics.com/'
  INVOICES_URL                  = 'https://retailerservices.diamondcomics.com/MyAccount/Invoices/List'
  TRUALL_URL                    = 'https://retailerservices.diamondcomics.com/FileExport/main_dynamic_b/truall.csv'
  PREVIEWS_MASTER_URL           = 'https://retailerservices.diamondcomics.com/FileExport/Misc/MasterDataFile-ITEMS.txt'
  CURRENT_URL_MASTER            = 'https://retailerservices.diamondcomics.com/FileExport/Misc/MasterDataFile-ITEMS.txt'
  CURRENT_URL_PREVIEW           = 'https://retailerservices.diamondcomics.com/FileExport/MonthlyToolsTXT/previewsDB.txt'
  ARCHIVE_DOWNLOAD_URL_MASTER   = "https://retailerservices.diamondcomics.com/Downloads/Archives/monthlytools/previews_master_data_file/MasterDataFile-Items_%4i%02i.txt"
  ARCHIVE_DOWNLOAD_URL_PREVIEW  = "https://retailerservices.diamondcomics.com/Downloads/Archives/monthlytools/previews_product_copy/previewsDB_%4i%02i.TXT"
  
  REORDERS_URL                  = 'https://retailerservices.diamondcomics.com/Reorder'
  REORDERS_UPLOAD_URL           = 'https://retailerservices.diamondcomics.com/Reorder/UploadReorder'
  REORDERS_REVIEW_URL           = 'https://retailerservices.diamondcomics.com/Reorder/Reorder'
  REORDERS_CONFIRM_URL          = 'https://retailerservices.diamondcomics.com/Reorder/ConfirmOrder'
  REORDERS_DELETE_URL           = 'https://retailerservices.diamondcomics.com/Reorder/DeleteOrder'
  
  # used in a view
  INITIAL_BASE_URL              = 'https://retailerservices.diamondcomics.com/InitialOrder'
  INITIAL_URL                   = 'https://retailerservices.diamondcomics.com/InitialOrder/Upload'
  
  ITEM_CODE_ROOT_REGEXP         = /[A-Z]{3}[0-9]{2}/
  ITEM_CODE_REGEXP              = /^[A-Z]{3}[0-9]{6}$/
  
  SUCCESS_EXPRESSIONS           = [/Memphis thru Local/, /Memphis Backorder/, /Olive Branch thru Local/, /Memphis Stock/, /Olive Branch Stock/, /Olive Branch Backorder/, /Local Order Increase/, /Local Stock/, /Local Extras/, /Local Backorder/]
  FAILURE_EXPRESSIONS           = [/Qty Unable to Order/]

  def self.archive_download_dir_template() "#{config.download_dir}/lib/datafiles/%4i%02i/" end
  def self.archive_download_file_master()  "#{archive_download_dir_template}master.csv"  end
  def self.archive_download_file_preview() "#{archive_download_dir_template}previewsDB.txt" end
  

  
  # There seems to be a keep-alive issue with Diamond, not fixed via setting keep-alive to false
  def self.reset_agent
    @@agent = Mechanize.new
    #    @@agent.user_agent_alias = 'Linux Mozilla'
    #    @@agent.post_connect_hooks << MechanizeCleanupHook.new
  end
  
  # Login if needed; if a block is provided, automatically logs out
  # after the block returns and returns the result of the block
  def self.login
    verbose = false
    
    # See if we're already logged in
    # raise 'Already logged into Diamond' if @@agent.cookies.detect { |cookie| cookie.name == LOGIN_COOKIE_NAME }
    reset_agent
    
    login_page               = @@agent.get(LOGIN_URL)
    login_form               = login_page.forms.first
    login_form.UserName      = config.username
    login_form.EnteredCustNo = config.custnumber
    login_form.Password      = config.password
    logged_in_page           = @@agent.submit(login_form)
    
    raise 'Login to Diamond failed' unless logged_in_page.body.match(config.firm_name_at_diamond)
    puts "* logged in body = #{logged_in_page.body.inspect}"  if verbose
    puts "* logged in keys = #{@@agent.cookie_jar.jar.first[1].first[1].keys.inspect}" if verbose
    
    raise 'post login: missing cookies' unless @@agent.cookies.detect { |cookie| cookie.name == LOGIN_COOKIE_NAME }
    
    return yield if block_given?
  ensure
    logout if block_given?
  end
  
  def self.logout
    # Log the session out
    @@agent.get(LOGOUT_URL)
    # Delete the cookies so we realize we're logged out
    @@agent.cookie_jar.clear!
  end
  
  def self.url_for_itemcode(item_code)
    ITEM_URL_BASE + item_code
  end
  
  #==========
  # download data files from Diamond
  #==========
  
  def self.get_arbitrary(url, local_file)
    
    dir  = File.dirname(local_file)
    unless File.exist?(dir)
      puts "    * mkdir #{dir}"
      `mkdir -p #{dir}` 
    end
    
    
    login do
      #open(local_file, "w:UTF-8") { |f| 
      open(local_file, "w") { |f| 
        # Jan 2013:
        #     Diamond serves their data in ISO-8859-1 (similar to Latin-1? identical?)
        #     Ruby wants to store everything in UTF-8 (sliding-size Unicode)
        #           
        data = @@agent.get_file(url).force_encoding('ISO-8859-1').encode("UTF-8")
        #data = @@agent.get_file(url).force_encoding('ISO-8859-1')
        
        # data = @@agent.get_file(url)
        # ret = []
        # ii = 1
        # data.split("\n").each do |line|
        #   puts "#{ii} // #{line.encoding} // line = #{line}"
        #   line.force_encoding('ISO-8859-1').encode("UTF-8")
        #   ret << line
        # end
        # data = ret.join("\n")
        f << data
      }
    end
  end
  
  def self.get_solicit_datafile(url_template, local_file, yr, month)
    
    url = sprintf(url_template, yr, month)
    
    puts "    * FROM: #{url}"
    puts "    * TO:   #{local_file}"
    get_arbitrary(url, local_file)
  end

  def self.get_filename_master(yr, month)    sprintf(archive_download_file_master, yr, month)  end
  def self.get_filename_preview(yr, month)  sprintf(archive_download_file_preview, yr, month)  end
  
  #----------
  # truall funcs
  #
  # Background:
  #   Every week (day?) Diamond updates the master list of what is re-orderable.
  #   This file is known as 'truall'.
  #----------
  
  # download the file
  #
  def self.get_truall_raw(filename = "/tmp/truall_#{String.random_alphanumeric}.txt")
    ret =  nil
    login do
      open(filename, "w") do |f| 
        ret = @@agent.get(TRUALL_URL).body
        f << ret
      end
    end
    [filename, ret]
  end
  
  # parse the file
  # 
  # output:
  #  [ { :code => XX, :title => ....}, 
  #    { :code => XX, :title => ....}, 
  #     ...
  #    { :code => XX, :title => ....}]
  #
  def self.parse_truall(filename)
    
    
    options = { 
      :col_sep => ",",
      :headers => [:code, :title, :unkown, :price, :type, :date, :unknown, :unknown, :base_price, :vendor]
      #:headers => [:code, :title, :unkown, :price, :type, :date, :unknown, :unknown, :base_price, :vendor],
      #:header_converters => :symbol
    }
    
    ret = []
    
    # the easy way to do this is
    #
    #     truall = File.read(filename)    
    #     CSV.parse(truall, options) do |line|
    #           ...
    #      end
    #
    # ...but Diamnd has poorly formatted data ( unescaped quotes ).
    # We restructure the loop so that we can catch an explosion on one line.
    #
    # so see
    #   http://stackoverflow.com/questions/14534522/ruby-csv-parsing-string-with-escaped-quotes
    #
    #
    
    ii = 0
    File.foreach(filename) do |csv_line|
      ii += 1
      begin
        line = CSV.parse(csv_line, options).first
        
        line = line.to_hash
        line = line.map { |k, v| [k, v.strip] }.to_h
        
        # Remove the discount part of the code, if present
        line[:discount] = line[:code][9,line[:code].size-9] if line[:code] && line[:code].size > 9
        line[:code] = line[:code][0,9]
        
        ret << line
      rescue Exception => e
        puts "Error on line #{ii} : #{e.message}" 
      end
    end
    
    ret
  end
  
  #----------
  # previews-master funcs
  #
  # Background:
  #   Every month Diamond updates the master list of what is on previews world.
  #   This file is known as 'MasterDataFile-ITEMS.txt'.
  # https://retailerservices.diamondcomics.com/FileExport/Misc/MasterDataFile-ITEMS.txt
  #----------
  
  # download the file
  #
  def self.get_previews_raw(filename = "/tmp/previews_master_#{String.random_alphanumeric}.csv")
    ret = nil
    login do
      open(filename, "w") do |f|
        ret = @@agent.get(PREVIEWS_MASTER_URL).body
        f << ret
      end
    end
    [filename, ret]
  end

  # 
  # Category Code = Numeric. The Diamond category code, from Previews on Disk.
  # 1     Comics - Black & White/Color
  # 2     Magazines - Comics/Games/Sports
  # 3     Books - Illustrated Comic Graphic Novels/Trade Paperbacks
  # 4     Books - Science-Fiction/Horror/Novels
  # 5     Games
  # 6     Cards - Sports/Non-Sports
  # 7     Novelties - Comic Material
  # 8     Novelties - Non-Comic Material
  # 9     Apparel - T-shirts/Caps
  # 10    Toys and Models
  # 11    Supplies - Card
  # 12    Supplies - Comic
  # 13    Retailers Sales Tools
  # 14    Diamond Publications
  # 15    Posters/Prints/Portfolios/Calendars
  # 16    Video/Audio/Video Games
    
  def self.parse_previews_master(filename)
    
    options = { 
      #:col_sep => ",",
      :col_sep => "\t",
      #:headers => [:code, :stock_no, :unknown, :unknown, :title, :description, :var_description, :series_code, :issue_no, :issue_seq_no, :unknown, :max_issue, :buy_price, :publisher, :upc, :isbn, :ean, :cards_per_pack, :pack_per_box, :box_per_case, :discount_code, :unknown, :print_date, :foc_vendor, :ship_date, :sell_price, :type, :genre, :brand_code, :mature, :adult, :unknown, :unknown, :unknown, :unknown, :unknown, :note_price, :order_form_notes, :page, :writer, :artist, :cover_artist, :colorist, :alliance_sku, :foc_date, :offered_date, :number_of_pages],
      :headers => [:code, :stock_no, :unknown, :unknown, :title, :description, :var_description, :series_code, :issue_no, :issue_seq_no, :unknown, :max_issue, :buy_price, :publisher, :upc, :isbn, :ean, :cards_per_pack, :pack_per_box, :box_per_case, :discount_code, :unknown, :print_date, :foc_vendor, :ship_date, :sell_price, :type, :genre, :brand_code, :mature, :adult, :unknown, :unknown, :unknown, :unknown, :unknown, :note_price, :order_form_notes, :page, :writer, :artist, :cover_artist, :colorist, :alliance_sku, :foc_date, :offered_date, :number_of_pages]
      #:header_converters => :symbol
    }
    
    ret = []
    
    # the easy way to do this is
    #
    #     truall = File.read(filename)    
    #     CSV.parse(truall, options) do |line|
    #           ...
    #      end
    #
    # ...but Diamond has poorly formatted data ( unescaped quotes ).
    # We restructure the loop so that we can catch an explosion on one line.
    #
    # so see
    #   http://stackoverflow.com/questions/14534522/ruby-csv-parsing-string-with-escaped-quotes
    #
    #
    
    ii = 0
    File.foreach(filename) do |csv_line|
      ii += 1
      begin
        line = CSV.parse(csv_line, options).first

        puts line
        
        line = line.to_hash
        puts line

        line = line.map { |k, v| [k, v.strip] }.to_h
        puts line
        
        # Remove the discount part of the code, if present
        line[:discount] = line[:code][9,line[:code].size-9] if line[:code] && line[:code].size > 9
        line[:code] = line[:code][0,9]
        
        ret << line
      rescue Exception => e
        puts "Error on line #{ii} : #{e.message}" 
      end
    end
    
    ret
  end
  
  public
  
  # yr - 4 digit
  # mo - 2 digi
  def self.get_master(yr, month)
    get_solicit_datafile(ARCHIVE_DOWNLOAD_URL_MASTER, get_filename_master(yr, month), yr, month)
  end
  
  def self.get_preview(yr, month)
    get_solicit_datafile(ARCHIVE_DOWNLOAD_URL_PREVIEW, get_filename_preview(yr, month), yr, month)  
  end
  
  def self.get_both(yr, month)
    raise "year must be over 2000 !" unless yr.to_i >= 2000
    master_file = get_master(yr, month)
    previews_file = get_preview(yr, month)
    [ master_file, previews_file ]
  end
  
  def self.get_current
    yr = (Date.today >> 1).year
    mo = (Date.today >> 1).month
    
    master_file  = sprintf(archive_download_file_master, yr, mo)
    preview_file = sprintf(archive_download_file_preview, yr, mo)
    
    get_arbitrary(CURRENT_URL_MASTER,  master_file)
    get_arbitrary(CURRENT_URL_PREVIEW, preview_file)
    [ master_file, preview_file ]
  end
  
  # Get the current previews file
  def self.get_current_previews
    yr = (Date.today >> 1).year
    mo = (Date.today >> 1).month
    
    preview_file = sprintf(archive_download_file_preview, yr, mo)
    get_arbitrary(CURRENT_URL_PREVIEW, preview_file)
    return preview_file
  end

  # Get the current master file
  def self.get_current_master
    yr = (Date.today >> 1).year
    mo = (Date.today >> 1).month

    master_file  = sprintf(archive_download_file_master, yr, mo)
    get_arbitrary(CURRENT_URL_MASTER,  master_file)
    return master_file
  end

  # 1) download truall.txt from Diamond
  # 2) parse it
  # 3) return an array of hashes; one data hash per item that Diamond has in inventory
  #
  #def self.get_truall(filename = "/tmp/truall_#{String.random_alphanumeric}.txt")
  def self.get_truall(filename = "/tmp/truall_"+[*('a'..'z'),*('0'..'9')].shuffle[0,12].join+".txt")
    get_truall_raw(filename)
    parse_truall(filename)
  end

  # 1) download previews-master.txt from Diamond
  # 2) parse it
  # 3) return an array of hashes; one data hash per item that Diamond has in previews file
  #
  #def self.get_truall(filename = "/tmp/truall_#{String.random_alphanumeric}.txt")
  def self.get_previews(filename = "/tmp/preview_master_"+[*('a'..'z'),*('0'..'9')].shuffle[0,12].join+".csv")
    get_previews_raw(filename)
    parse_previews_master(filename)
  end

	# Download truall file and then convert it to odoo csv format
	def self.truall_to_odoo(filename = "/tmp/truall_"+[*('a'..'z'),*('0'..'9')].shuffle[0,12].join+".txt")
	  get_truall_raw(filename)
  	write_odoo_csv(filename)
	end


	# Write the truall file to a format that odoo can import directly  
  def self.write_odoo_csv(filename)

    parsed_truall = "/tmp/parsed_truall.csv"
    
    options = { 
      :col_sep => ",",
      :headers => [:code, :title, :unknown, :price, :type, :date, :unknown, :unknown, :base_price, :vendor, :upc, :unknown, :unknown, :unknown, :unknown, :unknown, :unknown, :unknown,]
    }
    ii = 0
    CSV.open(parsed_truall, "wb", :write_headers => true, :headers => ["id", "name", "barcode", "list_price", "standard_price", "type"]) do |csv_file|
      begin
        CSV.foreach(filename, options) do |line|
          ii += 1
          begin        
            # Remove the discount part of the code, if present
            line[:discount] = line[:code][9,line[:code].size-9] if line[:code] && line[:code].size > 9
            line[:code] = line[:code][0,9]

            # line[:upc] = nil if line[:upc].nil? || line[:upc] == 0
            line[:upc] = line[:upc].to_i.nonzero?

            row_array = [line[:code], line[:title], line[:upc], line[:price].to_i, line[:price].to_i, "Stockable Product"]

            csv_file << row_array
          rescue Exception => e
            puts "Error on line #{ii} : #{e.message}" 
          end
        end
      rescue Exception => q
        puts "Error on line #{ii} : #{q.message}"
      end
    end
  end

  ## 
  # Make the inventory files from the invoices for diamond in odoo parsable
  #
  def self.write_inv_adj_csv(invoices)
    
    options = {
      :col_sep => ",",
      :headers => [:units, :id, :dc_code, :description, :full_price, :my_price, :total, :category_code, :order_type, :processed_as_field, :order_number, :upc, :isbn, :ean, :po_number, :allocated_code, :publisher]
    }
    invoices.each { |invoice|
      ii = 0
      begin
        CSV.open(invoice+"_parsed_inv_file.csv", "wb", :write_headers => true, :headers => ["inventory_reference", "line_ids/product_qty", "line_ids/location_id/id", "line_ids/product_id/id", "line_ids/product_uom_id/id"]) do |inv_file|
          CSV.foreach(invoice, options) do |line|
            ii += 1
            begin
              #line[:name] = (ii > 1 ? nil : "First inventory import")
              
              inv_array = [nil, line[:units].to_i, "stock.stock_location_stock", line[:id], "product.product_uom_unit"]

              inv_file << inv_array unless ii < 2
            rescue Exception => e
              puts "Error on line #{ii} : #{e.message}"
            end
          end
        end
      rescue Exception => e
        puts "Error on line #{ii} : #{e.message}"
      end
    }
  end

  # Get each Invoice individually and download it.
  # download each as a csv, return as files
  #
  def self.invoices_download_each
    invoices = []
    login do
      
      #----- 
      # Get top-level page
      #
      invoice_page = @@agent.get(INVOICES_URL)
      invoice_links = invoice_page.links.select { |link| link.href.andand.match(/Export\?CustNo.*Type=D/) }
      invoice_links.each do |link|
        
        #-----
        # download one invoice
        #
        link_date = link.href[/Export\?CustNo=#{config.custnumber}&InvDate=([0-9\/]+)/, 1]
        invoice = link.click.body
        filename = "#{config.download_dir}#{link_date}.csv"
        invoices << filename
        puts "Writing  #{link_date}.csv to #{filename}"
        CSV.open(filename, "wb", :write_headers => true, :headers => ["Units Shipped", "id", "Discount Code", "Item Description", "Retail Price", "Unit Price", "Invoice Amount", "Category Code", "Order Type", "Processed Ass Field", "Order Number", "UPC", "ISBN", "EAN", "PO number", "Allocated Code"]) do |csv_file|
          qq = 0
          CSV.parse(invoice) do |line|
            qq += 1
            csv_file << line unless qq < 5
          end
        end
      end
    end
    invoices
  end
  
  #==========
  # invoices - WORKING 2012
  #==========
  
  # download, return as raw unparsed CSV
  #
  def self.invoices_download_all
    invoices = {}
    login do
      
      #----- 
      # Get top-level page
      #
      invoice_page = @@agent.get(INVOICES_URL)
      invoice_links = invoice_page.links.select { |link| link.href.andand.match(/Export\?CustNo.*Type=D/) }
      invoice_links.each do |link|
        
        #-----
        # download one file
        #
        link_date = link.href[/Export\?CustNo=#{config.custnumber}&InvDate=([0-9\/]+)/, 1]
        one = link.click.body
        
        invoices[link_date] = one
      end
    end
    invoices
  end

  def self.parse_invoices_for_odoo(invoices)

    options = {
      :col_sep => ",",
      :headers => [:units, :id, :dc_code, :description, :full_price, :my_price, :total, :category_code, :order_type, :processed_as_field, :order_number, :upc, :isbn, :ean, :po_number, :allocated_code, :publisher]
    }

    invoices.each { |invoice|
      ii = 0
      begin
        bad_fp = File.dirname(invoice)
        CSV.open(invoice+"_parsed_for_odoo.csv", "wb", :write_headers => true, :headers => ["id", "name", "default_code", "barcode", "list_price", "standard_price", "type", "quantity_on_hand", "available_in_pos", "image"]) do |csv_file|
          CSV.foreach(invoice, options) do |line|
            ii += 1
            begin
              #if !line[:upc].to_i.nonzero?
              #  line[:upc] = line[:isbn].to_i.nonzero? ? line[:isbn] : line[:ean]
              #end
              if line[:isbn].strip.empty?
                line[:isbn] = !line[:upc].strip.empty? ? line[:upc] : line[:ean]
              end
              if line[:isbn].to_s.length == 16
                line[:barcode] = line[:isbn].to_s.prepend("0")
              else
                line[:barcode] = line[:isbn]
              end
              ret = [line[:id], line[:description], line[:id], line[:barcode], line[:full_price].to_f, line[:my_price].to_f, "Stockable Product", line[:units], "True"]#, img]
              csv_file << ret unless ii < 2
            rescue Exception => e
              puts "Error on line #{ii} : #{e.message}"
            end
          end
        end
      rescue Exception => q
        puts "Error on invoice #{invoice} : #{q.message}"
      end
    }
  end

  #==========
  # release dates - WORKING 2012
  #==========
  
  
  # Find updated diamond ship dates / cancellation information
  #
  # input:
  #    array of item codes (objects or strings)
  #
  # output:
  #    hash { item_code => release date }
  #
  # testing in development:
  #    - ???
  #
  def self.get_diamond_release_dates(item_codes)
    hh = {}
    verbose = false
    errors = []
    
    login do
      # Get the page of invoices and find all the invoice links that
      # meet our criteria, then download and process each page
      item_codes.each do |item_code_input|
        item_code = case item_code_input
                    when String then   item_code_input
                    when ItemCode then item_code_input.code
                    else raise "unknown input type - use String or ItemCode"
                    end
        begin
          item_page = @@agent.get(url_for_itemcode(item_code))
          
          if item_page.body.match(/ERROR.*This item could not be found/)
            yield item_code, nil
            next
          end
          
          if item_page.body.match(/CANCELLED/)
            yield item_code, nil
            next
          end
          
          details = parse_item_table(item_page, :verbose => false)
          
          begin
            est_date = details["Est Ship Date"]
            if est_date.strip.upcase.match(/TBD/)
              est_date = Date.today + 365
            else
              est_date = Date.strptime(est_date, "%m/%d/%Y")
            end
          rescue Exception => e
            raise "DATE PROBLEM: #{est_date}"
          end
          
          hh[item_code] = est_date
          yield item_code, est_date if block_given?
        rescue Exception => e
          errors << (e.message + "\n")
        end
      end
    end
    raise errors.inspect if errors.any? 
    return hh
  end
  
  
  # Get the text version of the invoices and pull out cancellation
  # information
  #
  # Return a hash ...
  # 
  def self.get_cancellations
    cancellations = {}
    login do

      # Get the page of invoices and find all the invoice links that
      # meet our criteria
      invoice_page = @@agent.get(INVOICES_URL)
      invoice_links = invoice_page.links.select { |link| link.href.andand.match(/Type=T/) }

      # download and process each page
      #
      invoice_links.each do |link|
        link_date = link.href[/InvDate=([0-9\/]+)/, 1]
        # next if link_date.nil? || (options[:since] && Date.parse(link_date) <= options[:since])
        cancellations[link_date] = []
        invoice = link.click.body
        invoice.each_line do |line|
          next unless match = line.match(/^\s+[0-9]+\s+([0-9]+)-\s+([A-Z]{3,4}[0-9]{5,6})/)
          cancellations[link_date] << { :code => match[2], :quantity => match[1].to_i }
        end
      end
    end
    cancellations
  end
  
  #==========
  # reorder
  #==========
  
  
  
  # Parse the results of a single Diamond reorder results page
  #
  # input:
  #    page_index   - integer - what page of results am I on? 1? 15?
  #    confirm_page - the page object
  #
  # return:
  #   [ results,    # - an array of OpenStructs with fields [ item_code, description, quantity, list_price, order_type, confirmed ]
  #     next_url ]  # - URL for next block of results, or nil
  #   
  #
  def self.reorder_parse_page_results(page_index, confirm_page)
    verbose = false
    
    # find the URL for the next page.  
    #
    # This is tricky.  The prev/next buttons in the page are javascript and replace text inline.
    # We hack this by reading their code.
    #
    # 1) the page loads and sets javascript variables
    #     var cartPageIndex = 1;
    #     var cartNextKey = "";
    #     var cartPrevKey = "";
    #     var cartLastDir = "";
    #
    #  2) then, on each data load, these vars are overwritten.  e.g.
    #     cartPageIndex = 1;
    #     cartNextKey = '11317011088R000010DEC101075      ';
    #     cartPrevKey = '11317011088R000001JUN130486      ';
    #
    #  3) then the next and prev buttons are created to pt to urls constructed from this data.
    #      e.g. on the first load, 
    #
    # So we can construct URLs that get us the contents that SHOULD
    # load into the single diamond page...  and then we can load them
    # individually and parse them.
    #
    confirm_page.body.match(/cartNextKey *= *'([0-9A-Z]+) *'/)
    next_key = $1
    confirm_page.body.match(/cartPrevKey *= *'([0-9A-Z]+) *'/)
    prev_key = $1
    
    final = confirm_page.body.match(/btnNextCart.*disabled/)
    
    if final
      next_url = nil
    else
      next_url = ROOT_URL + '/Reorder/ReorderCartDisplay?pageNo=' + (page_index + 1).to_s + "&key=" + next_key + "&direction=" + 'F'
    end
    
    # parse the results
    #
    results = []

    table_rows = confirm_page.search("//div[@class='ReorderCart_ItemsContainer']/table[@class='DisplayGrid']/tr")

    open("/tmp/output.html", "w") { |f| f << confirm_page.body } # NOTFORCHECKIN

    ii = 0
    table_rows.each_with_index do |row, ii|

      puts "row #{ii}" if verbose
      puts "---------" if verbose
      tds = row.css("/td")
      puts "TD COUNT = #{tds.count}" if verbose
      next unless tds.size > 0

      tds.each_with_index do |td, ii|
        puts "TD[#{ii}] = #{td.text.strip}"  if verbose
        puts " ... #{td.text.strip.match(ITEM_CODE_REGEXP).to_bool}"         if ii == 0 && verbose
      end

      next unless tds[0].text.strip.match(ITEM_CODE_REGEXP)

      result = OpenStruct.new


      result.item_code   = tds[ 0].text.strip
      # 1: discount code
      result.description = tds[ 2].text.strip
      result.quantity    = tds[ 3].text.strip
      result.list_price  = tds[ 4].text.strip
      # 5: purchase price
      # 6: quant UNABLE to deliver
      result.order_type  = tds[ 7].text.strip
      # 8: buttons

      result.confirmed = SUCCESS_EXPRESSIONS.any? { |re| re.match(result.order_type) }
      raise "Unknown Diamond status #{result.order_type}" unless result.confirmed || FAILURE_EXPRESSIONS.any? { |re| re.match(result.order_type) }

      results << result
      
      ii += 1
      
    end
    
    return [results, next_url]
  end
  
  # Submit a reorder to Diamond using the designed-for-humans web interface
  # and return what items were successfully ordered; the reorder items should
  # be supplied as an array of items that respond to item_code and quantity.
  # Returns a list of items with item_code, description, list_price, quantity,
  # and confirmed (boolean indicating whether it was ordered); if given a block,
  # the block is called with a string status update and a percent complete; the
  # optional parameter :always_cancel can be set to true if we just want to
  # check availability
  #
  # testing:
  #
  #    reorder_items      = SuggestedOrder.last.suggested_order_items[0,50] ; reorder_items.size
  #    code_to_quant_hash = reorder_items.map { |soi| [soi.item_code.code, soi.quantity ]}.to_h
  #    DiamondRemote.submit_reorder!(code_to_quant_hash)
  #
  def self.submit_reorder!(code_to_quant_hash)
    
    raise "illegal input" unless code_to_quant_hash.is_a?(Hash)

    @@logger.call("* using Mechanize version: #{Mechanize::VERSION}")
    
    order_results = []
    
    login do
      
      #-----
      # step 1: GET upload page
      #
      @@logger.call("* 1: GET upload page")
      
      reorders_upload_page = @@agent.get(REORDERS_UPLOAD_URL)
      
      @@logger.call("* page title (upload): #{reorders_upload_page.title}")
      gold_title = "DCD Retailer Services - Reorder Upload"
      raise "invalid reorders upload page - expecting title '#{gold_title}'; got '#{reorders_upload_page.title}'" unless reorders_upload_page.title == gold_title
      
      reorders_upload_form = reorders_upload_page.forms.first
      
      # Mark the POSTEDFLAG as it would be if a browser were uploading
      #      reorders_upload_form.fields.select { |f| f.name == 'POSTEDFLAG' }.first.value = 'Y'
      
      # Set a PO number
      po_number = Time.now.strftime('%y%m%d%H%M')
      @@logger.call("* PO number: #{po_number}")
      reorders_upload_form.fields.select { |f| f.name == 'PONumber'}.first.value = po_number
      
      # we want to review the order
      reorders_upload_form.radiobuttons.select { |f| f.name == 'ReviewBeforePost'}[1].check
      
      # Specify the contents of the "file" we wish to upload
      upload_data = code_to_quant_hash.map { |code, quant| "#{code},#{quant}\n" }.join ; nil

      # @@logger.call("* Placing diamond reorder for these items:\n\n#{upload_data}")
      reorders_upload_form.file_uploads.select { |f| f.name == 'ReorderFile'}.first.file_data = upload_data
      reorders_upload_form.file_uploads.select { |f| f.name == 'ReorderFile'}.first.file_name = "#{Time.now.strftime('%y%m%d%H%M')}.txt"
      reorders_upload_form.file_uploads.select { |f| f.name == 'ReorderFile'}.first.mime_type = 'text/plain'
      
      #----------
      # step 2: POST upload page 
      #
      @@logger.call("* 2: POST upload page")
      confirm_page = @@agent.submit(reorders_upload_form, reorders_upload_form.buttons.first )
      
      @@logger.call("* title of review start page: #{confirm_page.title}")
      gold_title = "DCD Retailer Services - Reorder - Upload Complete"
      raise "reorder already in progress" if confirm_page.body.match(/ERROR: cannot import/)
      if confirm_page.body.match(/PageError/)
        error_div = confirm_page.search("//div[@class='PageError']")
        error_text = error_div.text.strip
        puts confirm_page.body.inspect
        raise "Page error: #{error_text}"
      end
      raise "invalid reorders confirm page - expecting title '#{gold_title}'; got '#{reorders_upload_page.title}'"       unless confirm_page.title == gold_title

      
      error =  confirm_page.body.match(/(ERROR:.*)/)
      if error
        orig_error_text = $1
        if  confirm_page.body.match(/ERROR: Errors detected in line\(s\): (.*)/)
          error_lines = $1
          error_lines.gsub!(/<\/div>.*/, "")
          lines = upload_data.split("\n")
          bad_items = error_lines.split(",").map { |ln| lines[ln.strip.to_i - 1] }.join("; ")
          raise "error on item codes #{bad_items}"
        else
          raise "error #{orig_error_text}"
        end
      end
      
      
      #----------
      # step 3: GET review page
      #
      @@logger.call("* 3: GET review page")
      confirm_page = @@agent.get(REORDERS_REVIEW_URL)
      gold_title = "DCD Retailer Services - Reorders"
      raise "invalid review start page - expecting title '#{gold_title}'; got #{confirm_page.title}'" unless confirm_page.title == gold_title
      
      page_index = 1
      while true
        @@logger.call("* subpage #{page_index}")
        
        new_results, next_url = reorder_parse_page_results(page_index, confirm_page)
        @@logger.call("  * new results: #{new_results.size} items; #{new_results.select(&:confirmed).size} confirmed")
        order_results += new_results
        @@logger.call("  * running total: #{order_results.size} items; #{order_results.select(&:confirmed).size} confirmed")
        @@logger.call("  * next_url: #{next_url}")        
        unless next_url
          @@logger.call("  LAST PAGE REACHED")        
          break 
        end
        
        # iterate to next page
        confirm_page = @@agent.get(next_url)
        
        page_index += 1
      end
      
      #----------
      # Commit the order (in PRODUCTION)
      # or cancel it     (in DEVEL)
      #

      if (Rails.env.production?)
        @@logger.call("Comitting order")
        post_confirm_page = @@agent.post(REORDERS_CONFIRM_URL)
      else
        @@logger.call("Cancelling order")
        post_confirm_page = @@agent.post(REORDERS_DELETE_URL)
      end
      
    end

    order_results

  end
  

  
  #==========
  # initial orders
  #==========
  
  # submit an initial order
  # 
  def self.submit_initial!(order_items_hash)
    
    @@logger.call("* using Mechanize version: #{Mechanize::VERSION}")
    
    success = false
    
    login do
      
      #----------
      # (1) Go to the upload-initial-order page
      #----------
      #
      upload_page = @@agent.get(INITIAL_URL)
      
      # make sure it's the right page
      #
      @@logger.call("* Initial Upload Page title: #{upload_page.title}")
      gold_title = "DCD Retailer Services - Upload Initial Order"
      raise "invalid reorders upload page - expecting title '#{gold_title}'; got #{upload_page.title}'"      if upload_page.title != gold_title
      
      # make sure that there are no errors
      #
      error_div = upload_page.search("//div[@class='NoDataError']")
      if error_div.any?
        initial_upload_page = @@agent.get(INITIAL_BASE_URL)
        error_str = initial_upload_page.search("//div[@class='NoDataError']").text.strip
        error_str = upload_page.search("//div[@class='NoDataError']").strip if error_str == ""
        error_str = "Diamond website says: " + error_str
        raise error_str
      end


      # Get the upload form
      #
      upload_form = upload_page.forms.first
      raise "expected 1 file upload" unless upload_form.file_uploads.size == 1
      upload_form_file = upload_form.file_uploads.first
      
      # Specify the contents of the "file" we wish to upload
      #
      order_items = order_items_hash.select { |code, quant| quant > 0 } 
      upload_data = order_items_hash.map { |code, quant| "#{code},#{quant}\n" }.sort.join ; nil
      
      line_item_count = order_items_hash.size
      piece_count = order_items_hash.values.sum
      
      @@logger.call("* LineItem count : #{line_item_count}")
      @@logger.call("* Piece count    : #{piece_count}")
      
      upload_form_file.file_data = upload_data
      upload_form_file.file_name = "#{config.custnumber}.txt"
      upload_form_file.mime_type = 'text/plain'
      
      #----------
      # (2) Submit the form
      #----------
      
      # @@logger.call("* form: #{upload_form.inspect}")
      submit_button = upload_form.buttons.first
      done_page = @@agent.submit(upload_form, submit_button )
      
      
      #----------
      # (3) Look at the intermediate page
      #----------
      
      raise "expected success in title" unless done_page.title.match(/DCD Retailer Services - Initial Order \(Editing\)/)
      
      
      #----------
      # (4) click the 'confirm' link
      #----------
      
      # This is a weird Diamond mess.
      #
      # It's not a real HTML form.  Each act of modification on the form merely updates
      # an in-memory Javascript datastructure of diffs.
      #
      # Then the final "submit" button click runs some code:
      #
      #    function ConfirmOrder() { 
      #        if (!confirm("Your order will be saved and confirmed. ...")) { 
      #            return false; 
      #        } 
      #        $.ajax({ 
      #            type: "POST", 
      #            url: "/InitialOrder/Edit/201302/Confirm/#{config.custnumber}", 
      #            contentType: "application/json; charset=utf-8", 
      #            data: JSON.stringify({ saveItems: _changedItems }), 
      #            success: function (result) { 
      #                if (result == "Success") { 
      #                    RedirectToConfirmationPage(); 
      #                } 
      #                else if (IsNotLoggedIn(result)) { 
      #                    RedirectToLogin(); 
      #                } 
      #                else { 
      #                    alert("An Error Occurred while attempting to confirm your order"); 
      #                } 
      #            } 
      #        }); 
      #        return true; 
      #    }
      #
      # which sends this over the wire:
      #
      #     [1 bytes missing in capture file]GET /1/urls/count.json?url=https://retailerservices.diamondcomics.com/InitialOrder/Confirmation/201302/11317 HTTP/1.1
      #     Host: urls.api.twitter.com
      #     Connection: keep-alive
      #     User-Agent: Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.17 (KHTML, like Gecko) Chrome/24.0.1312.70 Safari/537.17
      #     Accept: */*
      #     Accept-Encoding: gzip,deflate,sdch
      #     Accept-Language: en-US,en;q=0.8
      #     Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.3
      #     Cookie: guest_id=v1%3A135999092078142736; k=10.40.15.121.1361202775783993; auth_token_session=true; secure_session=true; twll=l%3D1361452855; remember_checked=0; __utma=43838368.999350110.1359998148.1361387172.1361452793.22; __utmc=43838368; __utmz=43838368.1361387172.21.10.utmcsr=slate.com|utmccn=(referral)|utmcmd=referral|utmcct=/blogs/future_tense/2013/02/20/google_s_new_contest_asks_consumers_to_compete_for_a_chance_to_buy_glass.html; __utmv=43838368.lang%3A%20en
      
      # So we need to 
      #   * do a post to that URL
      #   * set the content type
      #   * set the data
      #   * get the result
      
      # Note that on 21 Feb 2013 this still is not working.  Something
      # is slightly off in our attempt to mimic the Diamond AJAX.  I
      # tried running wireshark on it to spy on the packets, but it's
      # all over SSL, so we can't introspect.  Spent 30 min learning
      # how to get wireshark to decrypt SSL, but we don't just need
      # the server's public cert for that - we need it's PRIVATE key.
      # Derp - of course.  And that is one thing we can't get.

      initial_confirm_url_template  = "https://retailerservices.diamondcomics.com/InitialOrder/Edit/%4i%02i/Confirm/#{config.custnumber}"
      confirm_url = sprintf(initial_confirm_url_template, Date.today.year, Date.today.month)
      @@logger.call("* confirm url: #{confirm_url.inspect}")
      
      # how do I know this?  ran it in the console against the live page
      #
      params = "{\"saveItems\":[]}"  
      
      
      # http://stackoverflow.com/questions/1327495/ruby-mechanize-post-with-header
      #
      ajax_headers = { 'X-Requested-With' => 'XMLHttpRequest', 
        'Content-Type'     => 'application/json; charset=utf-8',  
        'Accept'           => 'application/json, text/javascript, */*'}

      if (Rails.env.production?)
        @@logger.call("Comitting order")
        post_confirm_page = @@agent.post(confirm_url,  params,  ajax_headers ) 
      else
        @@logger.call("Abandoning order")
        return true
      end
      
      if post_confirm_page.body.match(/Success/)      
        @@logger.call("* success! ")
      else
        @@logger.call("* failure: got #{post_confirm_page.body[0,100]} ")
        raise "expected success in body on confirm page"  
      end
      
    end
    
    return true
    
  end
  
  # input:
  #   item_code  - a string e.g. "SEP120001"
  #   local_name - a dir path, e.g. "/tmp/fred.jpg"
  #
  # return:
  #   local_name - on success
  #   nil        - on failure
  #
  def self.get_diamond_image(item_code, local_name) 
    verbose = false 
    login do 
      
      # Diamond has a small image embedded in the page, and there's an
      # href there to get the bigger image.
      #
      # Parse the page to grab the href, then grab the image directly
      #
      item_page = @@agent.get(url_for_itemcode(item_code))
      return nil if item_page.body.match(/could not be found/)
      begin
        image_path = item_page.search("//a[@class='ImagePopup MainImagePopup']").attribute("href").value
        return nil unless image_path
      rescue Exception => e
        return nil
      end
      img_url  = ROOT_URL + image_path
      
      open(local_name, "wb") { |f| f << @@agent.get_file(img_url) }
      
    end
    puts "* image saved to file #{local_name}" if verbose
    local_name
  end

  def self.get_diamond_image_uri(diamond_id)
    verbose = false
    login do
      item_page = @@agent.get(url_for_itemcode(item_code))
      return nil if item_page.body.match(/could not be found/)
      begin
        image_path = item_page.search("//a[@class='ImagePopup MainImagePopup']").attribute("href").value
        return nil unless image_path
      rescue Exception => e
        return nil
      end
      img_url  = ROOT_URL + image_path
    end
    return img_url
  end

  private

  #--------------------------------------------------
  # Our fetch-data-on-one-item funcs.
  #--------------------------------------------------
  
  #
  # parses the Shopping List Add Page
  # e.g. 
  #    https://retailerservices.diamondcomics.com/ShoppingList/AddItem/OCT110459
  # 
  # input:
  #     page - the page, of type Mechanize::Page
  #
  # output:
  #     hash of fields
  #
  def self.parse_item_table(page, options = {} )
    
    options.allowed_and_required( [:verbose], [])
    verbose = options[:verbose]
    
    hh = {}
    
    data_items = page.search("//div[@class='ItemDetails']//div[@class='LookupItemData_Item']")
    
    data_items.each do |di|
      kk = di.search("div[@class='LookupItemData_Label']").text.strip
      vv = di.search("div[@class='LookupItemData_Value']").text.strip
      puts "#{sprintf('%20s', kk)} -> #{sprintf('%20s', vv)}" if verbose 
      hh[kk] = vv
    end
    
    hh
  end
  
  # We want to iterate over multiple item codes in several places.
  # Abstract that into this func, and put the guts into a block
  #
  # in:
  #   * item-codes: a list
  #   * a block { |item_code, parsed_fields| ... }
  # 
  # out: 
  #   * none
  def self.perform_multiple(item_codes)
    login do
      item_codes.each do |item_code|
        code = item_code.is_a?(ItemCode) ? item_code.code : item_code
        begin
          item_page = @@agent.get(url_for_itemcode(code))
          hh = self.parse_item_table(item_page, :verbose => false)
          yield code, hh
        rescue Exception => e
          HiAdminMailer.bug(code, e) 
        end
      end
    end
  end
  
  # Given item codes, get an ISBNs
  # In:
  #    * array of item codes (either strings or ItemCode objects)
  #    * block { |item_code, isbn|  puts "#{item_code.inspect} -> #{isbn}" }
  # Out:
  #    * nil
  # Also:
  #    
  def self.get_GN_ISBNs(item_codes)
    perform_multiple(item_codes) { |item_code, hh|
      isbn = hh["ISBN-13/EAN"]
      yield item_code, isbn if block_given?
    }
  end
  
  def self.get_IC_UPCS(item_codes)
    perform_multiple(item_codes) { |item_code, hh|
      upc = hh["UPC"]
      yield item_code, upc if block_given?
    }
  end
  
  # low level: get_order_deadline_raw
  # hi level:  get_order_deadline
  #
  # WORKING 2012
  #
  # Get the order deadline from the main diamond page
  #
  # return:
  #    [ item_code_root, deadline_date ]
  # e.g.
  #
  #    ["MAY12", <24_May_2012>  ]
  #
  def self.get_order_deadline
    ret = nil
    
    login do
      
      main_page = @@agent.get(ROOT_URL)
      
      due_date_info_noko = main_page.search("//div[@id='duedatecontainer']/div")
      raise "no due_date_info" unless due_date_info_noko.any?
      
      due_date_info_str = due_date_info_noko.text.gsub(/\s+/," ").strip
      
      ret = due_date_info_str.match(/^(#{ITEM_CODE_ROOT_REGEXP}) *initial orders.*\((.*)\)/)
      item_code_root = $1
      due_date = $2
      test_date = due_date.split(" ")[2..-1].join(" ")
      # due_date = Date.strptime(due_date, "%m/%d/%Y") # Date.parse(due_date)
      due_date = Date.strptime(test_date, "%m/%d/%Y") # Date.parse(due_date)
      ret = [item_code_root, due_date]
    end
    
    return ret
  end

end

# MonkeyPatch rand_string in the mechanize WWW library to produce mime
# seperator strings that Diamond can understand, needed for reorders
class Mechanize::Form
  def rand_string(*args)
    chars = ('0'..'9').to_a
    string = '-------------------------'
    28.times { string << chars[rand(chars.size)] }
    string
  end
end

# Diamond has nulls (^@) after the account name in a form, which
# appears to blow up Nokogiri; remove these via a post connect hook
class MechanizeCleanupHook
  # we want to be able to turn this off before downloading an image
  @@run = true 
# NOTFORCHECKIN  cattr_accessor :run 
  
  def call(context, uri, response, response_body)
    # puts "run == #{run}"
    response_body.gsub!("\0", "") if response_body and @@run
  end
end

