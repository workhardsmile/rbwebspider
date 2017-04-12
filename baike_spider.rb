# encoding: UTF-8
require 'json'
require 'thread'
require 'open-uri'
require 'rest-client'
require 'addressable/uri'
require 'nokogiri'

each_imgs = 500
worker_threads = 50
ignore_exist = true
root_dir = File.absolute_path(File.dirname(__FILE__))  #./result/*, ./data/asian_id_name_mapping.tsv
result_dir = "#{root_dir}/baike_result"
Dir.mkdir result_dir unless File.exist?(result_dir)
root_url = "http://baike.baidu.com"

def url_query_string(hash={})
  if hash.instance_of? String
    URI.encode hash
  else
    uri = Addressable::URI.new
  uri.query_values = hash
  uri.query
  end
end

def get_more_image_link(root_url,query_name)
  href_link = nil
  request_url = "#{root_url}/item/#{url_query_string(query_name)}"
  puts request_url
  mydoc = Nokogiri::HTML(RestClient.get(request_url).body) rescue nil
  return href_link if mydoc.nil?
  element = mydoc.xpath("//div[@class='album-list']//div[@class='header']//a[1]")[0] rescue nil
  href_link = "#{root_url}#{element.attribute("href")}" unless element.nil?
  puts href_link
  href_link
end

def get_all_image_links(href_link,root_url)
  image_links = []
  childdoc = Nokogiri::HTML(RestClient.get(href_link).body) rescue nil
  return image_links if childdoc.nil?
  a_elements = childdoc.xpath("//div[@id='album-list']//div[@class='pic-list']//a//img/..") rescue []
  a_elements.each do |a_element| 
    a_link = "#{root_url}#{a_element.attribute("href")}"
    mydoc = Nokogiri::HTML(RestClient.get(a_link).body) rescue nil
    #puts a_link
    next if mydoc.nil?
    original_image = mydoc.xpath("//a[@class='tool-button origin'][1]")[0]
    next if original_image.nil?
    image_link = "#{original_image.attribute("href")}".strip
    image_links = image_links << image_link unless image_links.include?(image_link)
  end
  image_links
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

threads = []
mutex = Mutex.new
$queue_names = Queue.new
$split = ARGV[0].nil? ? 1 : ARGV[0].to_i
$n = ARGV[1].nil? ? 1 : ARGV[1].to_i
puts "#################task: the #{$n} in #{$split} total"
lines=IO.readlines("#{root_dir}/data/asian_id_name_mapping.tsv")
split_length=lines.length/$split
lines=lines[split_length*($n-1)..(split_length*$n-1)]
lines.each{|line| $queue_names.push(line.gsub(/\r\n/,"").split("\t"))}
record_file = "#{root_dir}/data/baike_download_records_#{Time.now.strftime("%m%d%H%M%S")}.txt"
File.delete(record_file) if File.exist?(record_file)
(0..worker_threads).each do |i|
  threads<<Thread.new do
    loop do
      break if $queue_names.empty?
      queue_name = []
      mutex.synchronize do
        queue_name = $queue_names.pop
      end
      puts "#################Threds[#{i}] for #{queue_name[0]}-#{queue_name[1]}..."
      folder_path = "#{result_dir}/#{queue_name[0]}-#{queue_name[1]}"
      next if ignore_exist&&File.exist?(folder_path)
      #next if ignore_exist&&Dir.glob("#{folder_path}/*.jpg")!=[]
      images_link = get_more_image_link(root_url,queue_name[1])
      next if images_link.nil?
      image_links = get_all_image_links(images_link,root_url)
      next if image_links.length<=0
      Dir.mkdir folder_path unless File.exist?(folder_path)
      hash_imgs = []
      page_index = count = index = 0
      image_links.each do |img_url|
        next if img_url.nil?
        img_url = "#{root_url}#{img_url}" unless "#{img_url}".include?("http")
        count += 1
        file_path = "#{folder_path}/#{count}.jpg"
        flag = (queue_name.include?(img_url)||img_url=="") ? false : download_img(img_url, file_path)
        unless flag
        count -= 1
        next
        end
        queue_name = queue_name<<img_url  #file_path.gsub("#{root_dir}/")
        break if count>=each_imgs
      end
      #mutex.synchronize do
      File.open(record_file,"a"){|wfile| wfile.puts(queue_name.join(" | "))}
    end
  end
end

loop do
  threads.each{|t| t.join}
  sleep(1)
  threads = threads.delete(nil)
  break if threads.nil? || threads.length<=0
end