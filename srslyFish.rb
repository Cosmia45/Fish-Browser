require 'rubygems'
require 'mysql2'
require 'io/console'
require 'nokogiri'
require 'mechanize'
require 'csv'


password = STDIN.noecho(&:gets).chomp
dbObj = Mysql2::Client.new(:host => "localhost", :username => "root", :password => password, :database => "FishBase")

load "open-uri.rb"

def fishBrowse(dbObj, pageLink)
    fishPage = Nokogiri::HTML(open(pageLink))
end

categories = ["Characiformes","Cypriniformes","Cyprinodontiformes","Perciformes","Siluriformes","The Rest"]

agent = Mechanize.new

categories.each do |fish|
    puts fish
    agent.get("https://www.seriouslyfish.com/knowledge-base/")
    agent.page.link_with(:text => fish).click
    hasNext = true
    while hasNext
        agent.page.xpath("//h1[@class='profile_title']/a").each do |pageLink|
            fishBrowse(dbObj,pageLink["href"])
        end
        if agent.page.link_with(:text => "Next") != nil
            agent.page.link_with(:text => "Next").click
        else
            hasNext = false
        end
    end

end
