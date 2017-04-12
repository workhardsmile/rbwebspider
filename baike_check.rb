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

url_threads = []
download_threads = []
#mutex = Mutex.new
$queue_names = Queue.new
$queue_urls = Queue.new
$split = ARGV[0].nil? ? 1 : ARGV[0].to_i
$n = ARGV[1].nil? ? 1 : ARGV[1].to_i
$flag = ARGV[2].nil? ? 1 : ARGV[2].to_i
puts "#################task: the #{$n} in #{$split} total: #{$split},#{$n},#{$flag}"
lines=IO.readlines("#{root_dir}/data/asian_id_name_mapping.tsv")
split_length=lines.length/$split
lines=lines[split_length*($n-1)..(split_length*$n-1)]
lines.each{|line| $queue_names.push(line.gsub(/\r\n/,"").split("\t"))}
record_file = "#{root_dir}/data/baike_download_records_#{$split}_#{$n}.txt"

if $flag == 0 || $flag == 1
  File.delete(record_file) if File.exist?(record_file)
  (0..worker_threads).each do |i|
    url_threads<<Thread.new do
      loop do
        break if $queue_names.empty?
        queue_name = $queue_names.pop
        puts "#################Threds[#{i}] for #{queue_name[0]}-#{queue_name[1]}..."
        images_link = get_more_image_link(root_url,queue_name[1])
        next if images_link.nil?
        image_links = get_all_image_links(images_link,root_url)
        next if image_links.length<=0
        hash_imgs = []
        page_index = count = 0
        image_links.each do |img_url|
          next if img_url.nil?
          img_url = "#{root_url}#{img_url}" unless "#{img_url}".include?("http")
          next if queue_name.include?(img_url)||img_url==""
          queue_name = queue_name<<img_url  #file_path.gsub("#{root_dir}/")
        end
        #mutex.synchronize do
        puts queue_name
        if (queue_name||[]).length > 2
          File.open(record_file,"a"){|wfile| wfile.puts(queue_name.join("|"))}
          $queue_urls.push(queue_name)
          puts queue_name
        end
      end
    end
  end
  url_threads.each{|t| t.join}
end

if $flag == 0 || $flag == 2
  if $queue_urls.empty?
    lines = IO.readlines(record_file) rescue []
    lines.each{|line| $queue_urls.push(line.split("|"))}
  end
  (1..(worker_threads/2)).each do |i|
    download_threads<<Thread.new do
      loop do
        if $queue_urls.empty? && $split>0
          lines = IO.readlines(record_file) rescue []
          lines.each{|line| $queue_urls.push(line.split("|"))}
          mutex.synchronize { $split -= 1 }
        elsif $queue_urls.empty?
        break
        end
        queue_url = $queue_urls.pop
        folder_path = "#{result_dir}/#{queue_url[0]}-#{queue_url[1]}"
        total_length = "#{`ls -l #{folder_path}|wc -l`}".to_i rescue 0  # Dir.glob("#{folder_path}/*.jpg").length
        next if ignore_exist&&File.exist?(folder_path)&&total_length>=each_imgs
        puts "#################Download Threds[#{i}] for #{queue_url[0]}-#{queue_url[1]}..."
        Dir.mkdir folder_path unless File.exist?(folder_path)
        ((total_length+2)..(queue_url.length-1)).each do |j|
          total_length += 1
          file_path = "#{folder_path}/#{total_length}.jpg"
          flag = download_img(queue_url[j], file_path)
          unless flag
          total_length -= 1
          next
          end
          puts queue_url[j]
          break if total_length>=each_imgs
        end
      end
    end
  end
  download_threads.each{|t| t.join}
end