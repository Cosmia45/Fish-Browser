require 'rubygems'
require 'mysql2'
require 'io/console'
require 'nokogiri'
require 'csv'


password = STDIN.noecho(&:gets).chomp
dbObj = Mysql2::Client.new(:host => "localhost", :username => "root", :password => password, :database => "FishBase")

load "open-uri.rb"

countryFiles = "Countries-Continents.csv"

idCount = 0

CSV.foreach(countryFiles, {:headers=>:first_row}) do |row|
    statement = dbObj.prepare("select regionID from regions where regionName = ?")
    bloop = statement.execute(row[0])
    continent = bloop.first["regionID"]
    statement2 = dbObj.prepare("insert ignore into countries (countryID, regionID, countryName) values (?,?,?)")
    statement2.execute(idCount,continent,row[1])
    idCount += 1
end