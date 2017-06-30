#!/usr/local/env ruby
# coding: utf-8


# DB
@db = "off_bot.sqlite3"

# use HTTPS
@mastodon_server = "mstdn-workers.com"

require 'net/https'
require 'uri'
require 'json'
require 'sqlite3'
require 'date'

@token = nil

File.open("off_bot.token","r"){|f|
  @token = f.gets.chomp
}

def write_mstdn(form_data)
  uri = URI.parse("https://" + @mastodon_server + "/api/v1/statuses");
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE # :P
  req = Net::HTTP::Post.new(uri.path)
  req['Authorization'] = "Bearer " + @token
  req.set_form_data(form_data)
  res = http.request(req)
  # とりあえず結果は無視する
end

def getTwipla(eventid)
  uri = URI.parse("http://twipla.jp/events/" + eventid);
  http = Net::HTTP.new(uri.host, uri.port)
  req = Net::HTTP::Get.new(uri.path)
  res = http.request(req)
  # 頑張ってパースするよ！
  body = res.body.force_encoding("UTF-8")
  datetime = nil
  title = nil
  location = nil
  body =~ /\<meta +property\=\'og\:title\' +content\=\'([^']+)/
  title = $1
  body.gsub(/\<.*?\>/,"") =~ /([0-9]+)年([0-9]+)月([0-9]+)日\[.*?\]\s*([0-9]+)\:([0-9]+)/
  datetime = Time.mktime($1,$2,$3,$4,$5)
  return [title,location,datetime]
end

def write_ok(db,id)
  d = (db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url from off where id = ?;",id))[0]
  msg = "オフ会情報\n\n"
  msg += "ユーザ:" + d[3] + "(" + d[4] + ") によってオフ会情報が登録されました\n\n"
  msg += "「" + d[1] + "」\n\n" if !d[1].nil?
  msg += "場所:" + d[2] + "\n\n" if !d[2].nil?
  t = Time.at(d[0])
  msg += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n\n"
  msg += "\n"
  msg += "詳細:" + d[5]
  write_mstdn({'status' => msg, 'visibility' => 'public'})
end

def generate_data(d)
  msg = "#" + d[6].to_s + "\n"
  msg += "「" + d[1] + "」\n" if !d[1].nil?
  msg += "場所:" + d[2] + "\n" if !d[2].nil?
  t = Time.at(d[0])
  msg += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n"
  msg += "\n"
  msg += "詳細:" + d[5] + "\n"
  return msg
end

def show_execute(db,opt,row)
  msg = "オフ会情報\n\n"
  msg_hidden = "(" + Time.now.strftime("%Y年%m月%d日 %H時%M分") + "現在の情報です)\n\n"
  opt = "" if opt.nil?
  opt,other = opt.split(/ +/,2)
  if opt == "all"
    msg_hidden += "登録されている情報の最新２０件までのIDリストです\n\n"
    db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url,id from off order by off_datetime desc limit 20;") do |row|
      t = Time.at(row[0])
      msg_hidden += "#" + row[6].to_s + ":"
      msg_hidden += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n"
    end
  elsif opt[0] =~ /^\#([0-9]+)$/
    id = $1
    d = db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url,id from off where id = ?;",id)
    if d.size < 1
      msg_hidden += "登録がありません"
    else
      d.each{ |row|
        msg_hidden += generate_data(row)
      }
    end
  else
    msg_hidden += "現時点以降のリストです\n\n"
    d = db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url,id from off where off_datetime > ?;",Time.now.to_i)
    if d.size < 1
      msg_hidden += "登録がありません"
    else
      d.each{ |row|
        msg_hidden += generate_data(row)
      }
    end
  end
  write_mstdn({'status' => msg_hidden,'spoiler_text' => msg, 'visibility' => 'public'})
end

def default_execute(db,arg,json,row)
    off_datetime = nil
    off_title = nil
    off_location = nil
    account_id = json['account']['id']
    account_name = json['account']['username']
    account_display_name = json['account']['display_name']
    message_content = row[1]
    message_url = json['url']
    message_id = json['id']
    if json['content'] =~ /http\:\/\/twipla\.jp\/events\/([0-9]+)/
      off_title,off_location,off_datetime = getTwipla($1)
      if not (off_title =~ /mstdn\-workers|社畜丼/)
        off_title,off_location,off_datetime = [nil,nil,nil]
      end
    else
      # 途中 :P
      # off_datetimeっぽいものを探す
      year = Time.now.year
      month = nil
      day = nil
      hour = 18
      min = 0
      if arg =~ /\s([0-9０１２３４５６７８９]+[\/／])([0-9０１２３４５６７８９]+[\/／])([0-9０１２３４５６７８９]+)/
        # 年月日?
      elsif arg =~ /\s([0-9０１２３４５６７８９]+[\/／])([0-9０１２３４５６７８９]+)/
        # 月日？
      end
    end
    puts off_title,off_location,off_datetime
    if off_datetime != nil
      db.execute("insert into off values(NULL,?,?, ?,?,?, ?,?,?, ?, ?);",
                 Time.now.to_i,Time.now.to_i,
                 off_datetime.to_i,off_title,off_location,
                 account_id,account_name,account_display_name,
                 message_url,message_id)
      id = db.last_insert_row_id
      db.execute("insert into off_update values(?,?,?, ?,?,?, ?,?);",
                 id,message_id,Time.now.to_i,
                 account_id,account_name,account_display_name,
                 message_content,message_url)
      write_ok(db,id)
    end
end


def generate_write_off(db)
  db.execute("select arg,json from read_data;") do |row|
    arg = row[0]
    json = JSON.parse(row[1])
    cmd,opt = arg.split(/ +/,2)
    if cmd == "show"
      show_execute(db,opt,row)
    else
      default_execute(db,arg,json,row)
    end
  end
  # 全部処理が終わったはずなので全部消す
  db.execute("delete from read_data;");
end

def doit
  db = SQLite3::Database.new(@db)
  begin
    db.transaction do
      generate_write_off(db)
      #raise Exception # debug
    end
  ensure
    db.close
  end
end


doit

