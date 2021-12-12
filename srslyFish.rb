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

def fishBrowse(dbObj, pageLink, countryList, id)
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
    # skip all this code if we've done this fish before
    check = dbObj.query("select * from Fish where sName = '#{sciName}'")
    if check.count != 0
        return
    end
    commonName = fishPage.xpath("//h1[@class='profile_commonname']").text
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
    tankSize = nil
    if tankNode != nil
        dimensions = tankNode.next_element.text.scan(/\d+ ∗ \d+ ∗ \d+/)
        if dimensions.length == 0
            dimensions = tankNode.next_element.text.scan(/\d+ ∗ \d+/)
        end
        if dimensions.length != 0
            tankSize = getTankSize(dimensions)
        end
    end
    # get their water parameters if available
    conditions = fishPage.xpath("//h2[@class='profile_phrange']")[0]
    temp = nil
    pH = nil
    hardness = nil
    if conditions != nil
        cond = true
        while cond
            if conditions.next_element.text == "Diet" || conditions.next_element.text == "Maximum Standard Length"
                cond = false
            else 
                conditions = conditions.next_element 
                if conditions.text.include?("Temperature: ")
                    temp = conditions.text.delete("Temperature: ")
                elsif conditions.text.include?("pH: ")
                    pH = conditions.text.delete("pH: ")
                elsif conditions.text.include?("Hardness: ")
                    hardness = conditions.text.delete("Hardness: ")
                end
            end
        end
    end
    # get url of the fish's first picture on their page
    picture = fishPage.xpath("//div[@class='sidebar_pic']/a")[0]
    if picture != nil
        picture = picture["href"]
    end
    maxSizePath = fishPage.xpath("//h2[@class='profile_maxstandardlength']")[0]
    maxSize = nil
    if maxSizePath != nil
        attempt = maxSizePath.next_element.text.scan(/\d+.\d+ cm/)
        if attempt.length == 0 
            attempt = maxSizePath.next_element.text.scan(/\d+.\d+ mm/)
        end
        if attempt.length == 0 
            attempt = maxSizePath.next_element.text.scan(/\d+ cm/)
        end
        if attempt.length == 0 
            attempt = maxSizePath.next_element.text.scan(/\d+ mm/)
        end
        maxSize = attempt[0]
    end
    regionSelect = dbObj.prepare("select regionID from countries where countryName = ?")
    continent = regionSelect.execute(fishCountry[0])
    continent = continent.first["regionID"]
    # there may be some edge cases where a fish might be found on multiple continents, but for now we won't worry about it
    fishStatement = dbObj.prepare("insert ignore into Fish (fishID,sName,cName,maxSize,tankSize,temperature,pH,hardness,regionID,picture,link) values (?,?,?,?,?,?,?,?,?,?,?)")
    fishStatement.execute(id,fullSci,commonName,maxSize,tankSize,temp,pH,hardness,continent,picture,pageLink)
    fishCountry.each do |country|
        countryID = dbObj.query("select countryID from countries where countryName = '#{country}'")
        if countryID.count > 0
            dbObj.query("insert ignore into fishCountries (fishID,countryID) values (#{id},#{countryID.first["countryID"]})")
        end
    end
    sleep(2) # Pause a bit so seriouslyfish is a bit less likely to block our program
end

# Takes the text from the distribution section and returns an array of all countries the fish is found in
def countryCheck(countries,disText)
    fishCountry = []
    countries.each do |country|
        if disText.include?(country)
            fishCountry << country
        end
    end
    return fishCountry
end

# SeriouslyFish.com is a non-American site that uses dirty metric units, as such
# this function is used to convert those dimensions into something more understandable for a US audience (namely gallons)
def getTankSize(dimensions)
    size = dimensions[0].split("∗")
    # convert cm dimensions to gallons
    if size.length == 3 
        volume = 1
        size.each do |cm|
            volume *= cm.to_i
        end
        gallons = (volume * 0.000264172).round()
        finalDim = gallons.to_s + " gallons"
        return finalDim
    # sometimes they only specify bottom surface area needed
    elsif size.length == 2
        finalDim = ""
        count = 0
        size.each do |cm|
            inch = cm.strip
            inch = inch.to_i
            inch = (inch * 0.393701).round()
            if count == 0
                finalDim += inch.to_s + " x "
            else
                finalDim += inch.to_s + " surface area"
            end
            count += 1
        end
        return finalDim
    else
        return nil
    end
end

agent = Mechanize.new

CSV.foreach(countryFiles, {:headers=>:first_row}) do |row|
    countries << row[1]
end
id = 106 # update value with latest id
count = 0
categories.each do |fish|
    puts fish
    agent.get("https://www.seriouslyfish.com/knowledge-base/")
    agent.page.link_with(:text => fish).click
    hasNext = true
    while hasNext
        agent.page.xpath("//h1[@class='profile_title']/a").each do |pageLink|
            if count < id
                count += 1
                next
            end
            fishBrowse(dbObj,pageLink["href"],countries, id)
            id += 1
            count += 1
        end
        if agent.page.link_with(:text => "Next") != nil
            agent.page.link_with(:text => "Next").click
        else
            hasNext = false
        end
    end

end
