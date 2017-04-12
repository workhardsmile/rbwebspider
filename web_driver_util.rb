# encoding: UTF-8
require 'addressable/uri'
#require "selenium-webdriver"
require 'open-uri'
module WebDriverUtil
  class << self
    def launch_browser(browser=:chrome)
      driver = Selenium::WebDriver.for browser
      driver.manage.timeouts.implicit_wait = 10
      driver
    end

    def url_query_string(hash={},is_url=false)
      if hash.instance_of? String
        URI.encode hash
      elsif is_url
        uri = Addressable::URI.new
      uri.query_values = hash
      uri.query
      else
        query_str = ""
        hash.reject{ |key,value| query_str="#{query_str}&#{key}=#{value}" }
      query_str[1,query_str.length-1]
      end
    end

    def download_img(img_url,file_path)
      begin
        puts img_url
        img_file = open(img_url) { |f| f.read }
        open(file_path, "wb") { |f| f.write(img_file) }
        return true
      rescue => err
        puts err
        return false
      end
    end
  end
end