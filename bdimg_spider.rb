# encoding: UTF-8
require 'json'
require 'thread'
require 'open-uri'
require 'rest-client'
require 'addressable/uri'

each_imgs = 200
worker_threads = 100
ignore_exist = true
root_dir = File.absolute_path(File.dirname(__FILE__))  #./result/*, ./data/asian_id_name_mapping.tsv
result_dir = "#{root_dir}/baidu_result"
Dir.mkdir result_dir unless File.exist?(result_dir)
url_api = "http://image.baidu.com/search/avatarjson?tn=resultjsonavatarnew&ct=201326592&ie=utf-8&ipn=rj&face=1"
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
record_file = "#{root_dir}/data/baidu_download_records_#{Time.now.strftime("%m%d%H%M%S")}.txt"
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
      next if ignore_exist&&File.exist?(folder_path) #&&Dir.glob("#{folder_path}/*.jpg").length>=each_imgs
      hash_imgs = []
      page_index = count = index = 0
      loop do
        count += 1
        index += 1
        file_path = "#{folder_path}/#{count}.jpg"
        if hash_imgs.length <= index
          page_index += 1
          request_url = "#{url_api}&rn=60&pn=#{60*(page_index-1)}&#{url_query_string({"word"=>queue_name[1]},true)}" rescue ""
          #puts request_url
          imgs = JSON.parse(RestClient.get(request_url).body)["imgs"] rescue []
          break if imgs.length <= 0
          Dir.mkdir folder_path unless File.exist?(folder_path)
          hash_imgs = hash_imgs + imgs
        end
        img_url = hash_imgs[index]["objURL"] rescue nil
        ignore_check = true #count<(each_imgs/2+1) ? true : false
        flag = (queue_name.include?(img_url)||img_url.nil?) ? false : download_img(img_url, file_path, ignore_check)
        unless flag
          count -= 1
          next
        end
        queue_name = queue_name<<img_url  #file_path.gsub("#{root_dir}/")
        break if count>=each_imgs || page_index>9999
      end
      #mutex.synchronize do
      if File.exist?(folder_path) && Dir.glob("#{folder_path}/*.jpg")==[]
        Dir.delete(folder_path)
      next
      end
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