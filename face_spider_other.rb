# encoding: UTF-8

# Usage:
#1.  download images while get URLs, total 100 threads:    
#        ruby face_spider_other.rb    
#2.  split to n, firstly get URLs, then download images:
#        ruby face_spider_other.rb  2 1 1, ruby face_spider.rb  2 2 1  # $1=2: split to 2 parts, $2=1,2: the 1rd or the 2nd part, $3=1: total 100*2 threads for get URLs  
#        ruby face_spider_other.rb  2 1 2, ruby face_spider.rb  2 2 2  # $1=2: split to 2 parts, $2=1,2: the 1rd or the 2nd part, $3=2: total 100*2 threads for download images
require 'json'
require 'thread'
require 'open-uri'
require 'rest-client'
require 'addressable/uri'

each_imgs = 200       # total download number per people
worker_threads = 100   # total worker threads per process
ignore_exist = true    # true: skip completed, false: re-download all
root_dir = File.absolute_path(File.dirname(__FILE__))  #./result/*, ./data/asian_id_name_mapping.tsv
result_dir = "#{root_dir}/face_other_result"
Dir.mkdir result_dir unless File.exist?(result_dir)
url_api = "http://image.baidu.com/search/acjson?tn=resultjson_com&ipn=rj&ct=201326592&is=&fp=result&queryWord+=&cl=2&lm=&ie=utf-8&oe=utf-8&adpicid=&st=-1&z=&ic=0&s=&se=&tab=&width=&height=&istype=2&qc=&nc=1"
#url_api = "http://image.baidu.com/search/avatarjson?tn=resultjsonavatarnew&ct=201326592&ie=utf-8&ipn=rj&face=0"

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

def download_img(img_url,file_path, ignore_check=true, header=nil)
  temp = img_url.downcase rescue img_url
  return false unless (ignore_check || temp.include?("baike") || temp.include?("wiki"))
  begin
    img_file = open(img_url, header) { |f| f.read }
    open(file_path, "wb") { |f| f.write(img_file) }
    return true
  rescue => err
    puts err
  return false
  end
end

def get_queue_by_lines(lines,split_str="\t",max_length=1,except_lines=[])
  temp_queue = Queue.new
  lines.each do |line|
    names = "#{line}".gsub(/(\r)|(\n)/,"").split(split_str).delete_if{|a| a.nil?||a.strip==""}
    next if names.nil? || names.length<max_length
    if except_lines.include?(names[0])
      puts "##########重复：#{names[0]}"
      next
    end
    temp_queue.push(names)
  end
  puts "Total Queues(<#{max_length}): #{temp_queue.length} from #{lines.length}"
  temp_queue
end

$split = ARGV[0].nil? ? 1 : ARGV[0].to_i
$n = ARGV[1].nil? ? 1 : ARGV[1].to_i
$flag = ARGV[2].nil? ? 1 : ARGV[2].to_i
puts "#################Strat Task: the #{$n} in #{$split} total: #{$split},#{$n},#{$flag}"
$queue_names = Queue.new
$queue_urls = Queue.new
$mutex = Mutex.new
url_threads = download_threads = lines = []
header = {"User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.95 Safari/537.36"}
config_file = "#{root_dir}/data/wiki.txt"
record_file = "#{root_dir}/data/face_other_download_records_#{$split}_#{$n}.txt"
download_log = "#{record_file}.log"

if $flag == 0 || $flag == 1
  File.delete(record_file) if File.exist?(record_file)
  max_length = (each_imgs*1.25).to_i
  except_file = "#{root_dir}/data/asian_id_name_mapping.tsv"
  except_lines=IO.readlines(except_file).map{|line| line.gsub(/(\r)|(\n)/,"").split("\t").delete_if{|a| a.nil?||a.strip==""}[1] rescue ""} unless except_file.nil?
  # except_lines=[]
  if $queue_names.empty?
    lines=IO.readlines(config_file)
    split_length=lines.length/$split
    length_temp= ($split==$n) ? (lines.length-1) : (split_length*$n-1)
    lines=lines[split_length*($n-1)..length_temp]
    $queue_names = get_queue_by_lines(lines,"\t",1,except_lines)
  end
  (1..worker_threads).each do |i|
    url_threads<<Thread.new do
      loop do
        break if $queue_names.empty?
        queue_name = $queue_names.pop
        th_no = lines.length-$queue_names.length
        puts "#################URLs[#{th_no}] threds[#{i}] for #{queue_name[0]} start..."
        hash_imgs = []
        page_index = index = 0
        face = 1
        loop do
          if hash_imgs.length <= index
            request_url = "#{url_api}&face=#{face}&rn=60&pn=#{60*page_index}&#{url_query_string({"word"=>queue_name[0],"step_word"=>queue_name[0]},true)}" rescue ""
            imgs = JSON.parse(RestClient.get(request_url,header).body)["data"] rescue []
            if imgs.length <= 1 && face==1
              page_index = face = 0
              next
            end
            break if imgs.length <= 1
            hash_imgs = hash_imgs + imgs
            page_index += 1
          end
          img_url = hash_imgs[index]["replaceUrl"][0]["ObjURL"] rescue nil
          index += 1
          next if queue_name.include?(img_url) || img_url.nil?
          queue_name = queue_name << img_url
          break if (queue_name.length-1)>=max_length || page_index>9999
        end
        if (queue_name||[]).length > 1
          $mutex.synchronize{ File.open(record_file,"a"){|wfile| wfile.puts(queue_name.join("|"))} }
          $queue_urls.push(queue_name)
          puts "#################URLs[#{th_no}] threds[#{i}] for #{queue_name[0]} end with #{queue_name.length-1}"
        end
      end
    end
  end
  url_threads.each{|t| t.join}
end

if $flag == 0 || $flag == 2
  download_lines = File.exist?(download_log) ? IO.readlines(download_log) : []
  if $queue_urls.empty?
    lines = IO.readlines(record_file) rescue []
    $queue_urls = get_queue_by_lines(lines,"|",3)
  end
  (1..(worker_threads/2)).each do |i|
    download_threads<<Thread.new do
      loop do
        break if $queue_urls.empty?
        queue_url = $queue_urls.pop
        th_no = lines.length-$queue_urls.length
        folder_path = "#{result_dir}/#{queue_url[0]}"
        total_length = Dir.glob("#{folder_path}/*.jpg").length  rescue 0 #"#{`ls -l #{folder_path}|wc -l`}".to_i
        puts "#################Dwonloads[#{th_no}] threds[#{i}] for #{queue_url[0]} start with #{total_length}"
        next if ignore_exist&&File.exist?(folder_path)&&(total_length>=each_imgs||total_length>=queue_url.length*0.95)
        puts `rm -fr #{folder_path}` rescue false
        Dir.mkdir folder_path unless File.exist?(folder_path)
        download_urls = []
        total_length = 0
        ((total_length*1.1+1).to_i..(queue_url.length-1)).each do |j|
          total_length += 1
          file_path = "#{folder_path}/#{total_length}.jpg"
          flag = (download_lines+download_urls).include?(queue_url[j])? false: download_img(queue_url[j], file_path, true, header)
          unless flag
          total_length -= 1
          next
          end
          download_urls = download_urls << queue_url[j]
          break if total_length>=each_imgs
        end
        $mutex.synchronize{ File.open(download_log,"a"){|wfile| wfile.puts(download_urls.join("\n"))} } if download_urls.length>0
        puts "#################Dwonloads[#{th_no}] threds[#{i}] for #{queue_url[0]} end with #{total_length}"
      end
    end
  end
  download_threads.each{|t| t.join}
end
