#!/usr/local/env ruby
# coding: utf-8


# DB
@db = "off_bot.sqlite3"
@db_1st_execute = "PRAGMA journal_mode = MEMORY;"

# use HTTPS
@mastodon_server = "mstdn-workers.com"

require 'net/https'
require 'uri'
require 'json'
require 'sqlite3'
require 'date'
require 'cgi'

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
  if body.gsub(/\<.*?\>/,"") =~ /([0-9]+)年([0-9]+)月([0-9]+)日\[.*?\]\s*([0-9]+)\:([0-9]+)/
    datetime = Time.mktime($1,$2,$3,$4,$5)
  elsif body.gsub(/\<.*?\>/,"") =~ /([0-9]+)年([0-9]+)月([0-9]+)日\[.*?\]\s*終日/
    datetime = Time.mktime($1,$2,$3,23,59,59)
  elsif body.gsub(/\<.*?\>/,"") =~ /([0-9]+)年([0-9]+)月([0-9]+)日\[.*?\]\s*未定/
    datetime = Time.mktime($1,$2,$3,23,59,59)
  elsif body =~ /\<a +href\=\"http\:\/\/www\.google\.com\/calendar\/event\?[^"]*\&amp\;dates\=([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z/
    datetime = Time.mktime($1,$2,$3,$4.to_i+9,$5,$6)
  end
  if body =~ /\<a +href\=\"http\:\/\/www\.google\.com\/calendar\/event\?[^"]*\&amp\;location\=([A-Za-z0-9\%\+\-\.\\\_]+)/
    location_tmp = $1
    begin
      location = CGI.unescape(location_tmp).force_encoding("UTF-8")
    rescue => e
    end
  end
  return [nil,nil,nil,nil] if not body.gsub(/\<.*?\>/,"") =~ /mstdn\-workers|社畜丼/
  return [title,location,datetime,"http://twipla.jp/events/" + eventid]
end

def write_ok(db,id)
  d = (db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url,off_url from off where id = ?;",id))[0]
  msg = "オフ会情報\n\n"
  msg += "ユーザ:" + d[3] + "(" + d[4] + ") によってオフ会情報 #" + id.to_s + " が登録されました\n\n"
  msg += "「" + d[1] + "」\n\n" if !d[1].nil?
  msg += "場所:" + d[2] + "\n\n" if !d[2].nil?
  t = Time.at(d[0])
  if t.hour == 23 and t.min == 59 and t.sec == 59
    msg += "日付:" + t.strftime("%Y年%m月%d日") + "\n\n"
  else
    msg += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n\n"
  end
  msg += "\n"
  msg += "詳細:" + d[5]
  msg += "\n\n" + d[6] if !d[6].nil?
  write_mstdn({'status' => msg, 'visibility' => 'public'})
end

def generate_data(d)
  msg = "#" + d[7].to_s + " "
  msg += "「" + d[1] + "」\n" if !d[1].nil?
  msg += "場所:" + d[2] + "\n" if !d[2].nil?
  t = Time.at(d[0])
  #msg += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n"
  if t.hour == 23 and t.min == 59 and t.sec == 59
    msg += "日付:" + t.strftime("%Y年%m月%d日") + "\n\n"
  else
    msg += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n\n"
  end
  msg += "\n"
  #msg += "詳細:" + d[5] + "\n\n"
  return msg
end

def generate_data_full(d)
  msg = "#" + d[7].to_s + " "
  msg += "「" + d[1] + "」\n" if !d[1].nil?
  msg += "場所:" + d[2] + "\n" if !d[2].nil?
  t = Time.at(d[0])
  #msg += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n"
  if t.hour == 23 and t.min == 59 and t.sec == 59
    msg += "日付:" + t.strftime("%Y年%m月%d日") + "\n\n"
  else
    msg += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n\n"
  end
  msg += "\n"
  msg += "詳細:" + d[5]
  msg += "\n\n" + d[6] if !d[6].nil?
  msg += "\n\n"
  return msg
end

def show_execute(db,opt,row)
  msg = "オフ会情報\n\n"
  msg_hidden = "(" + Time.now.strftime("%Y年%m月%d日 %H時%M分") + "現在の情報です)\n\n"
  opt = "" if opt.nil?
  opt,other = opt.split(/[ \n]+/,2)
  opt = "" if opt.nil?
  opt.downcase!
  if opt == "all"
    msg_hidden += "登録されている情報の最新２０件までのIDリストです\n\n"
    db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url,off_url,id from off order by off_datetime desc limit 20;") do |row|
      t = Time.at(row[0])
      msg_hidden += "#" + row[7].to_s + ":"
      if t.hour == 23 and t.min == 59 and t.sec == 59
        msg_hidden += "日付:" + t.strftime("%Y年%m月%d日") + "\n\n"
      else
        msg_hidden += "日時:" + t.strftime("%Y年%m月%d日 %H時%M分～") + "\n\n"
      end
    end
  elsif opt =~ /^\#([0-9]+)$/
    id = $1
    d = db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url,off_url,id from off where id = ?;",id)
    if d.size < 1
      msg += "#"+id+" は登録がありません"
      msg_hidden = ""
    else
      d.each{ |row|
        msg_hidden += generate_data_full(row)
      }
    end
  else
    msg_hidden += "現時点以降のリストです\n\n"
    d = db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url,off_url,id from off where off_datetime > ? order by off_datetime;",Time.now.to_i)
    if d.size < 1
      msg += "登録がありません"
      msg_hidden = ""
    else
      d.each{ |row|
        msg_hidden += generate_data(row)
      }
    end
  end
  if msg_hidden.length > 400
    msg_hidden = msg_hidden[0,400] + "...多すぎます"
    msg_hidden += "\n\nhttp://offbot.mstdn-workers.net/view.html も参照ください"
  end
  if msg_hidden.length > 0
    write_mstdn({'status' => msg_hidden,'spoiler_text' => msg, 'visibility' => 'public'})
  else
    write_mstdn({'status' => msg, 'visibility' => 'public'})
  end
end

def val_to_int(intstr)
  return nil if intstr.nil?
  return intstr.to_s.gsub(/０/,'0').gsub(/１/,'1').gsub(/２/,'2').gsub(/３/,'3').gsub(/４/,'4').gsub(/５/,'5').gsub(/６/,'6').gsub(/７/,'7').gsub(/８/,'8').gsub(/９/,'9').to_i
end

def add_execute(db,opt,json,row)
    off_datetime = nil
    off_title = nil
    off_location = nil
    account_id = json['status']['account']['id']
    account_name = json['status']['account']['username']
    account_display_name = json['status']['account']['display_name']
    message_content = row[1]
    message_url = json['status']['url']
    message_id = json['status']['id']
    # off_datetimeっぽいものを探す
    year = Time.now.year
    month = nil
    day = nil
    hour = nil
    min = nil
    if opt =~ /([0-9０１２３４５６７８９]+)[\:：]([0-9０１２３４５６７８９]+)/
      # 時間？
      hour = $1
      min = $2
    elsif opt =~ /([0-9０１２３４５６７８９]+)時([0-9０１２３４５６７８９]+)/
      # 時間？
      hour = $1
      min = $2
    elsif opt =~ /([0-9０１２３４５６７８９]+)時/
      # 時間？
      hour = $1
    end
    hour = val_to_int(hour)
    min = val_to_int(min)
    if opt =~ /([0-9０１２３４５６７８９]+)[\/／\-－年]([0-9０１２３４５６７８９]+)[\/／\-－月]([0-9０１２３４５６７８９]+)/
      # 年月日?
      year = $1
      month = $2
      day = $3
    elsif opt =~ /([0-9０１２３４５６７８９]+)[\/／\-－月]([0-9０１２３４５６７８９]+)/
      # 月日？
      month = $1
      day = $2
      month = val_to_int(month)
      day = val_to_int(day)
      if Date.new(year,month,day) < Date.now
        year += 1
      end
    end
    year = val_to_int(year)
    month = val_to_int(month)
    day = val_to_int(day)
    # return if month.nil? or day.nil?
    begin
      if month.nil? or day.nil?
      else
        if hour.nil? or min.nil?
          off_datetime = Time.local(year,month,day,23,59,59)
        else
          off_datetime = Time.local(year,month,day,hour,min)
        end
      end
    rescue
      return
    end
    opt =~ /場所[\:：\s](.*)/
    off_location = $1
    opt =~ /「(.*?)」/
    off_title = $1
    if off_datetime.nil?
      # もしかして: twipla?
      if json['status']['content'] =~ /http\:\/\/twipla\.jp\/events\/([0-9]+)/
        off_title,off_location,off_datetime,off_url = getTwipla($1)
      end
    end
    puts off_title,off_location,off_datetime,off_url
    return if off_datetime.nil? or off_location.nil? or off_title.nil?
      db.execute("insert into off values(NULL,?,?, ?,?,?,?, ?,?,?, ?, ?);",
                 Time.now.to_i,Time.now.to_i,
                 off_datetime.to_i,off_title,off_location,nil,
                 account_id,account_name,account_display_name,
                 message_url,message_id)
      id = db.last_insert_row_id
      db.execute("insert into off_update values(?,?,?, ?,?,?, ?,?);",
                 id,message_id,Time.now.to_i,
                 account_id,account_name,account_display_name,
                 message_content,message_url)
      write_ok(db,id)
end

def del_execute(db,opt,json,row)
  opt =~ /^\#([0-9]+)$/
  id = $1
  return if id.nil?
  account_id = json['status']['account']['id']
  # check
  check = db.execute("select account_id,message_url from off where id = ?;",id.to_i)
  if check.size < 1
    write_mstdn({'status' => "指定されたオフ会情報が見つかりません id= # " + id, 'visibility' => 'public'})
    return
  end
  addid = check[0][0]
  msgurl = check[0][1]
  if addid > 0 and account_id.to_i != addid
    write_mstdn({'status' => "登録ユーザが違うため消せません id= # " + id, 'visibility' => 'public'})
  else
    db.execute("delete from off where id = ?;",id.to_i)
    write_mstdn({'status' => "オフ会情報 # " + id + " を削除しました\n" + "削除されたオフ情報:" + msgurl, 'visibility' => 'public'})
  end
end

def reload_execute(db,opt,json,row)
  opt =~ /^\#([0-9]+)$/
  id = $1
  return if id.nil?
  account_id = json['status']['account']['id']
  # check
  check = db.execute("select account_id,message_url,message_id,off_url from off where id = ?;",id.to_i)
  if check.size < 1
    write_mstdn({'status' => "指定されたオフ会情報が見つかりません id= # " + id, 'visibility' => 'public'})
    return
  end
  addid = check[0][0]
  msgurl = check[0][1]
  off_url = check[0][3]
  # twipla only
  #datas = db.execute("select off_url,message_content from off_update where id = ? and message_id = ?;",id.to_i,check[0][2].to_i)
  #if datas.size < 1
  #  write_mstdn({'status' => "オフ会情報の更新に失敗（内部エラー:" + __LINE__ + ")", 'visibility' => 'public'})
  #  return
  #end
  #json = JSON.parse(datas[0][0])
  #return if json.nil? or json['status'].nil? or json['status']['content'].nil?
  off_datetime = nil
  off_title = nil
  off_location = nil
  #if json['status']['content'] =~ /http\:\/\/twipla\.jp\/events\/([0-9]+)/
  if off_url =~ /http\:\/\/twipla\.jp\/events\/([0-9]+)/
    off_title,off_location,off_datetime = getTwipla($1)
  else
    write_mstdn({'status' => "更新出来るオフ会情報はtwiplaのものだけです id= # " + id + "は更新出来ません", 'visibility' => 'public'})
    return
  end
  if off_datetime != nil
    puts off_title,off_location,off_datetime
    db.execute("update off set off_datetime = ?,off_title = ?,off_location = ? where id = ?;",
               off_datetime.to_i,off_title,off_location,
               id
              );
    d = (db.execute("select off_datetime,off_title,off_location,account_display_name,account_name,message_url,off_url,id from off where id = ?;",id))[0]
    text = generate_data(d)
    write_mstdn({'status' => "オフ会情報 # " + id + " をアップデートしました\n" + "更新されたオフ情報:" + msgurl + "\n\n" + text, 'visibility' => 'public'})
  else
    write_mstdn({'status' => "オフ会情報 # " + id + " のアップデートに失敗しました（タイトルがないよ）\n", 'visibility' => 'public'})
  end
end


def help_execute
  msg = "@off_botの使い方 1/3\n\n"
  msg_hidden = "’@off_bot show’ オフ会の一覧を表示します(現時点以降のモノ一覧です)\n\n"
  msg_hidden += "’@off_bot show all’ オフ会の一覧を表示します(登録されているモノ全てです)\n\n"
  msg_hidden += "’@off_bot show #id ’ #id のオフ会詳細を表示します\n\n"
  msg_hidden += "※ #id 内部で勝手に割り振ってるオフ会の番号です\n"
  msg_hidden += "http://offbot.mstdn-workers.net/も参照ください\n"
  write_mstdn({'status' => msg_hidden,'spoiler_text' => msg, 'visibility' => 'public'})

  msg = "@off_botの使い方 2/3\n\n"
  msg_hidden = "’@off_bot twiplaっぽいアドレス’  twiplaのイベントを追加します\n\n"
  msg_hidden += "’@off_bot reload #id’ #id のオフ会情報を再読み込みします(twiplaのみ)\n\n"
  msg_hidden += "’@off_bot add 日時 「オフ会タイトル」 場所：～’  それっぽいオフ会情報を追加します\n"
  msg_hidden += "例えば、’add 2017/1/1 10:00～「オフ」　場所：上野駅’　など\n\n"
  msg_hidden += "’@off_bot del #id’ #id のオフ会情報を削除します\n"
  msg_hidden += "※ 削除は登録したユーザーのみが可能です\n\n"
  write_mstdn({'status' => msg_hidden,'spoiler_text' => msg, 'visibility' => 'public'})

  msg = "@off_botの使い方 3/3\n\n"
  msg_hidden = "’@off_bot’ 簡易ヘルプを表示します\n\n"
  msg_hidden += "’@off_bot help’ ヘルプを表示します\n\n"
  msg_hidden += "これら以外のコマンドは基本的に無視します\n\n"
  msg_hidden += "20秒に1回読み込むのでタイムラグがあります。\n"
  write_mstdn({'status' => msg_hidden,'spoiler_text' => msg, 'visibility' => 'public'})
end

def help_short_execute
  msg = "@off_botの使い方(簡易版)\n\n"
  msg_hidden = "’@off_bot show’ オフ会の一覧を表示します\n\n"
  msg_hidden += "’@off_bot twiplaっぽいアドレス’  twiplaのイベントを追加します\n\n"
  msg_hidden += "’@off_bot help’ 詳細版ヘルプを表示します（長いので注意）\n\n"
  msg_hidden += "http://offbot.mstdn-workers.net/ も参照ください\n"
  msg_hidden += "\n"
  msg_hidden += "コマンドは20秒に1回読み込むのでタイムラグがあります。\n"
  write_mstdn({'status' => msg_hidden,'spoiler_text' => msg, 'visibility' => 'public'})
end

def default_execute(db,arg,json,row)
    off_datetime = nil
    off_title = nil
    off_location = nil
    off_url = nil
    account_id = json['status']['account']['id']
    account_name = json['status']['account']['username']
    account_display_name = json['status']['account']['display_name']
    message_content = row[1]
    message_url = json['status']['url']
    message_id = json['status']['id']
    if json['status']['content'] =~ /http\:\/\/twipla\.jp\/events\/([0-9]+)/
      off_title,off_location,off_datetime,off_url = getTwipla($1)
    else
      # 途中 :P
      # off_datetimeっぽいものを探す
      year = Time.now.year
      month = nil
      day = nil
      hour = 18
      min = 0
      if arg =~ /\s([0-9０１２３４５６７８９]+[\/／\-－])([0-9０１２３４５６７８９]+[\/／\-－])([0-9０１２３４５６７８９]+)/
        # 年月日?
      elsif arg =~ /\s([0-9０１２３４５６７８９]+[\/／\-－])([0-9０１２３４５６７８９]+)/
        # 月日？
      end
    end
    if off_datetime != nil
      puts off_title,off_location,off_datetime,off_url
      force_update = false
      id = nil
      if off_url != nil then
        check = db.execute("select id,account_id from off where off_url = ?",off_url)
        if check.size > 0
          # もしあっても、権限的に更新出来なければ新規登録にする
          id = check[0][0]
          force_update = true if check[0][1] < 0
        end
      end
      if force_update
        puts "force_update:" + id.to_s
        db.execute("update off set last_update=?, off_datetime=?,off_title=?,off_location=?,off_url=?, account_id=?,account_name=?,account_display_name=?, message_url=?, message_id=? where id = ?",
                   Time.now.to_i,
                   off_datetime.to_i,off_title,off_location,off_url,
                   account_id,account_name,account_display_name,
                   message_url,message_id,
                   id
                  )
      else
        db.execute("insert into off values(NULL,?,?, ?,?,?,?, ?,?,?, ?, ?);",
                   Time.now.to_i,Time.now.to_i,
                   off_datetime.to_i,off_title,off_location,off_url,
                   account_id,account_name,account_display_name,
                   message_url,message_id)
        id = db.last_insert_row_id
      end
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
    cmd,opt = arg.split(/[ \n　]+/,2)
    cmd = "" if cmd.nil?
    opt = "" if opt.nil?
    cmd.downcase!
    begin
      if cmd == "show"
        show_execute(db,opt,row)
      elsif cmd == "add"
        add_execute(db,opt,json,row)
      elsif cmd == "del" or cmd == "delete"
        del_execute(db,opt,json,row)
      elsif cmd == "reload"
        reload_execute(db,opt,json,row)
      elsif cmd == "help"
        help_execute()
      elsif arg == ""
        help_short_execute()
      else
        default_execute(db,arg,json,row)
      end
    rescue => e
      p e # debug message
      p e.backtrace
    end
  end
  # 全部処理が終わったはずなので全部消す
  db.execute("delete from read_data;");
end

def generate_write_off_ltl(db)
  db.execute("select json from read_data_ltl;") do |row|
    begin
      json = JSON.parse(row[0])
      off_datetime = nil
      off_title = nil
      off_location = nil
      off_url = nil
      account_id = json['account']['id']
      account_name = json['account']['username']
      account_display_name = json['account']['display_name']
      message_content = row[0]
      message_url = json['url']
      message_id = json['id']
      next if !(json['content'] =~ /http\:\/\/twipla\.jp\/events\/([0-9]+)/)
      off_title,off_location,off_datetime,off_url = getTwipla($1)
      if off_datetime != nil
        puts "LTL-add",off_title,off_location,off_datetime,off_url
        # 登録済みか？
        check = db.execute("select id from off where off_url = ?;",off_url)
        if check.size > 0 then
          # puts "...skip... exist ID:" + check[0][0].to_s
          # silent-mode update
          db.execute("update off set off_datetime = ?,off_title = ?,off_location = ? where id = ?;",
            off_datetime.to_i,off_title,off_location,
            check[0][0]
          );
          puts "...silent-mode reloaded... exist ID:" + check[0][0].to_s
          next
        end
        # 未登録URL
        # account_id,message_idをマイナスにして登録
        db.execute("insert into off values(NULL,?,?, ?,?,?,?, ?,?,?, ?, ?);",
                   Time.now.to_i,Time.now.to_i,
                   off_datetime.to_i,off_title,off_location,off_url,
                   -account_id,account_name,account_display_name,
                   message_url,-message_id)
        id = db.last_insert_row_id
        db.execute("insert into off_update values(?,?,?, ?,?,?, ?,?);",
                   id,-message_id,Time.now.to_i,
                   -account_id,account_name,account_display_name,
                   message_content,message_url)
      end
    rescue => e
      p e # debug message
      p e.backtrace
    end
  end
  # 全部処理が終わったはずなので全部消す
  db.execute("delete from read_data_ltl;");
end

def doit
  SQLite3::Database.new(@db) do |db|
    db.execute(@db_1st_execute)
    db.transaction do
      generate_write_off(db)
      #raise Exception # debug
    end
    db.transaction do
      generate_write_off_ltl(db)
      #raise Exception # debug
    end
  end
end


doit

