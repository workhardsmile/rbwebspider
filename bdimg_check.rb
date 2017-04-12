# encoding: UTF-8
require 'json'
require 'thread'
require 'open-uri'
require 'rest-client'
require 'addressable/uri'

each_imgs = 200
worker_threads = 5
ignore_exist = true
root_dir = File.absolute_path(File.dirname(__FILE__))  #./result/*, ./data/asian_id_name_mapping.tsv
result_dir = "#{root_dir}/baidu_result"
Dir.mkdir result_dir unless File.exist?(result_dir)
url_api = "http://image.baidu.com/search/avatarjson?tn=resultjsonavatarnew&ct=201326592&ie=utf-8&ipn=rj&face=0"
#url_api = "https://image.baidu.com/search/acjson?tn=resultjson_com&ipn=rj&ct=201326592&ie=utf-8&face=1"

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

def download_img(img_url,file_path, ignore_check=true)
  temp = img_url.downcase rescue img_url
  return false unless (ignore_check || temp.include?("baike") || temp.include?("wiki"))
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
record_file = "#{root_dir}/data/baidu_download_records_#{$split}_#{$n}.txt"

if $flag == 0 || $flag == 1
  File.delete(record_file) if File.exist?(record_file)
  (0..worker_threads).each do |i|
    url_threads<<Thread.new do
      loop do
        break if $queue_names.empty?
        queue_name = $queue_names.pop
        puts "#################Threds[#{i}] for #{queue_name[0]}-#{queue_name[1]}..."
        hash_imgs = []
        page_index = index = 0
        loop do
          index += 1
          if hash_imgs.length <= index
            page_index += 1
            request_url = "#{url_api}&rn=60&pn=#{60*(page_index-1)}&#{url_query_string({"word"=>queue_name[1]},true)}" rescue ""
            puts request_url
            imgs = JSON.parse(RestClient.get(request_url).body)["imgs"] rescue []
          break if imgs.length <= 1
          hash_imgs = hash_imgs + imgs
          end
          img_url = hash_imgs[index]["objURL"] rescue nil
          puts img_url
          next if queue_name.include?(img_url) || img_url.nil?
          queue_name = queue_name<<img_url  #file_path.gsub("#{root_dir}/")
          break if index>=each_imgs*1.2 || page_index>9999
        end
        #mutex.synchronize do
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