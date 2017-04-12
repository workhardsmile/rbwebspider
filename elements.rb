require "selenium-webdriver"
include Selenium::WebDriver::Error
module Elements
  class ElementBase
    def initialize(type,value,name="#{self.class}")
      @@type=type
      @@value=value
      @@name=name
    end

    def element
      begin
        @@element = $driver.find_element(@@type.to_sym,@@value)
      rescue NoSuchElementError
      return false
      end
    end

    def elements
      $driver.find_elements(@@type.to_sym,@@value)
    end

    def exist?
      @@element = element
    # if @@element
    # @@element.displayed?
    # else
    # return false
    # end
    end

    def click(how=:normal)
      case how
      when :normal
        if exist?
          puts "Execute - click #{self.class} - success."
          $driver.execute_script("arguments[0].scrollIntoView(true);", @@element) rescue false
          element.click
        else
          puts "Execute - click #{self.class} - failed. can't find element by #{@@type} and #{@@value}"
        end
      when :js
        begin
          $driver.execute_script("arguments[0].click()", element)
        rescue Exception => e
          puts "Execute - click #{self.class} via JavaScript - failed, get error message #{e}"
        end
        puts "Execute - click #{self.class} via JavaScript - success."
      end
    end

    def enabled?
      if exist?
        if @@element.enabled? && "#{get_property("disabled")}"!="true"
          puts "Execute - get if #{self.class} enabled? - success. it is enabled"
        return true
        else
          puts "Execute - get if #{self.class} enabled? - failed. it is NOT enabled"
        return false
        end
      else
        puts "Execute - get if #{self.class} enabled? - failed. can't find element by #{@@type} and #{@@value}"
      end
    end

    def wait_element_present(timeout=30)
      # $driver.manage.timeouts.implicit_wait = 0 #set timeout to default
      !timeout.to_i.times do |t|
        break if (exist? rescue false)
        sleep 1
        if t+1 == timeout
          puts "Execute - wait #{self.class} to present - failed. the element with the property #{@@type} and value #{@@value} was not found in #{timeout} seconds"
        end
      end
      puts "Execute - wait #{self.class} to present - success. it shows in #{timeout} seconds"
    end

    def get_property(string_property)
      if exist?
        result = @@element.attribute(string_property)
        puts "Execute - get #{string_property} of #{self.class} - success. get [#{result}] from page."
      result.nil? ? result : result.strip
      else
        puts "Execute ERROR - get #{string_property} of #{self.class} - failed. can't find element by #{@@type} and #{@@value}"
      false
      end
    end
  end
  
  class ImageByIndexBox < ElementBase
    def initialize(index=1)
      ElementBase.new("xpath","//div[@id='wrapper']//div[@class='imgpage']/ul/li[#{index}]//img[1]")
    end
  end
end