require 'rubygems'
require 'mysql2'
require 'io/console'
require 'nokogiri'
require 'mechanize'
require 'csv'
require 'pp'


password = STDIN.noecho(&:gets).chomp
dbObj = Mysql2::Client.new(:host => "localhost", :username => "root", :password => password, :database => "FishBase")

categories = ["Characiformes","Cypriniformes","Cyprinodontiformes","Perciformes","Siluriformes","The Rest"]
countries = []
countryFiles = "Countries-Continents.csv"

load "open-uri.rb"

def fishBrowse(dbObj, pageLink, countryList)
    fishPage = Nokogiri::HTML(open(pageLink))
    sciName = ""
    sciName = fishPage.xpath("//h1[@class='profile_title']/em")
    # this code will catch the scientific name most of the time, but it might require looking through the data
    # to clean up some weird stragglers
    if sciName.text == ""
        sciName = fishPage.xpath("//p/em")
    end
    fullSci = ""
    if sciName.length == 1
        if fishPage.xpath("//h1/i").length() > 0
            fullSci = sciName[0].text + " " + fishPage.xpath("//h1/i")[0].text
        else
            fullSci = sciName[0].text
        end
    else
        fullSci = sciName[0].text + " " + sciName[1].text
    end
    puts fullSci
    dist = true
    distNode = fishPage.xpath("//h2[@class='profile_distribution']")[0]
    disText = ""
    # Check the distribution section and get all the text from it
    while dist
        if distNode.next_element.text == "Habitat" || distNode.next_element.text == "Maximum Standard Length" || distNode.next_element.text == "Sexual Dimorphism"
            dist = false
        else
            disText += distNode.next_element.text + " "
            distNode = distNode.next_element
        end
    end
    fishCountry = countryCheck(countryList,disText)
    tankNode = fishPage.xpath("//h2[@class='profile_mintanksize']")[0]
    tankSize = ""
    if tankNode != nil
        dimensions = tankNode.next_element.text.scan(/\d+ ∗ \d+ ∗ \d+/)
        if dimensions.length == 0
            dimensions = tankNode.next_element.text.scan(/\d+ ∗ \d+/)
        end
        puts dimensions
    end
    sleep(1)
end

# Takes the text from the distribution section and returns an array of all countries the fish is found in
def countryCheck(countries,disText)
    fishCountry = []
    countries.each do |country|
        if disText.include?(country)
            puts country
            fishCountry << country
        end
    end
end

agent = Mechanize.new

CSV.foreach(countryFiles, {:headers=>:first_row}) do |row|
    countries << row[1]
end

categories.each do |fish|
    puts fish
    agent.get("https://www.seriouslyfish.com/knowledge-base/")
    agent.page.link_with(:text => fish).click
    hasNext = true
    while hasNext
        agent.page.xpath("//h1[@class='profile_title']/a").each do |pageLink|
            fishBrowse(dbObj,pageLink["href"],countries)
        end
        if agent.page.link_with(:text => "Next") != nil
            agent.page.link_with(:text => "Next").click
        else
            hasNext = false
        end
    end

end
