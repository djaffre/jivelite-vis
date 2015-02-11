--[[

=head1 LICENSE

Copyright 2009 by Stefan Hansel. All Rights Reserved.

Until further notice:
	- You are NOT allowed to redistribute modified versions of this applet.
	- You are NOT allowed to create derivative works of this applet 



=cut
--]]

local pairs, ipairs, tonumber, tostring = pairs, ipairs, tonumber, tostring

local math               = require("math")
local table              = require("table")
local os                 = require("os")	
local io                 = require("io")
local string             = require("string")
local url                = require("socket.url")

local oo                 = require("loop.simple")
local hasSystem, System  = pcall(require, "jive.System")

local Applet             = require("jive.Applet")
local Font               = require("jive.ui.Font")
local Framework          = require("jive.ui.Framework")
local Icon               = require("jive.ui.Icon")
local Choice             = require("jive.ui.Choice")
local Label              = require("jive.ui.Label")
local RadioButton        = require("jive.ui.RadioButton")
local Checkbox           = require("jive.ui.Checkbox")
local RadioGroup         = require("jive.ui.RadioGroup")
local SimpleMenu         = require("jive.ui.SimpleMenu")
local Surface            = require("jive.ui.Surface")
local Window             = require("jive.ui.Window")
local hasKeyboard, Keyboard = pcall(require, "jive.ui.Keyboard")
local Textinput          = require("jive.ui.Textinput")
local Group              = require("jive.ui.Group")
                       
local log               = require("jive.utils.log").addCategory("applets.weather", jive.utils.log.INFO)

local datetime           = require("jive.utils.datetime")

local appletManager      = appletManager
local jnt                = jnt
local SocketHttp         = require("jive.net.SocketHttp")
local RequestHttp        = require("jive.net.RequestHttp")


local currentWeather = {}
local forecastWeather = {}
local tick=1
local currentDayFont, forecastFont
local dateformat

local window
local currentDayX, currentDayY, currentDayW, currentDayH
local forecastX, forecastY, forecastW, forecastH, forecastRepeatX, forecastRepeatY

local menuCheckOption="check"
local menuCheckStyle="item_choice"
local menuWindowStyle="text_list"

local lastWeatherUpdate=0

if hasKeyboard==false then
	menuCheckOption="icon"
	menuCheckStyle="item"
	menuWindowStyle="window"
end


module(..., Framework.constants)
oo.class(_M, Applet)

local images = {
	-- first some image which are matched to condition phrases
	-- these are used to have some better icons than just using the offical icon-names

	["light rain"]="200px-Weather-overcast-rare-showers.svg.png",
	["rain"]="200px-Weather-drizzle.svg.png",
	["heavy rain"]="200px-Weather-showers.svg.png",
	["light drizzle rain"]="200px-Weather-overcast-rare-showers.svg.png",
	["light rain drizzle"]="200px-Weather-overcast-rare-showers.svg.png",
	["drizzle rain"]="200px-Weather-overcast-rare-showers.svg.png",
	["rain drizzle"]="200px-Weather-overcast-rare-showers.svg.png",
	["heavy drizzle rain"]="200px-Weather-overcast-rare-showers.svg.png",
	["heavy rain drizzle"]="200px-Weather-overcast-rare-showers.svg.png",

	-- these mappings match the official icon-names 
	clear="200px-Weather-clear.svg.png",
	sunny="200px-Weather-clear.svg.png",
	cloudy="200px-Weather-overcast.svg.png",
	flurries="200px-Weather-snow.svg.png",
	fog="200px-Weather-small-fog.svg.png",
	hazy="200px-Weather-day-veiled.svg.png",
	mostlycloudy="200px-Weather-more-clouds.svg.png",
	partlysunny="200px-Weather-more-clouds.svg.png",
	mostlysunny="200px-Weather-few-clouds.svg.png",
	partlycloudy="200px-Weather-few-clouds.svg.png",
	rain="200px-Weather-drizzle.svg.png",
	sleet="200px-Weather-sleet.svg.png",
	snow="200px-Weather-snow.svg.png",
	tstorms="200px-Weather-violent-storm.svg.png",
	chanceflurries="200px-Weather-snow.svg.png",
	chancerain="200px-Weather-overcast-rare-showers.svg.png",
	chancesleet="200px-Weather-sleet.svg.png",
	chancesnow="200px-Weather-snow.svg.png",
	chancetstorms="200px-Weather-violent-storm.svg.png",
	unknown="200px-Weather-clear.svg.png",
}



function openScreensafer(self)
	log:info("openScreenSafer")

	if self:getSettings()["weather.pws"]==nil then
		self:getSettings()["weather.pws"] = ""
		self:storeSettings()
	end

	dateformat=self:getShortDateFormat()
	window = self:_window(label)
	
	-- start loading weather
	self:reloadWeather()
	--self:reloadWeatherDummy()

	-- trigger reload of weather every 30min
	-- trigger redrawing every 3 seconds (forecast-images need toggling)
	window:addTimer(30*60*1000, function() self:reloadWeather() end)
	window:addTimer(3*1000, function() self:redrawWeatherInfo() end)

	window:show()


end


--[[

to be backward compatible with 7.3 (which doesn't have a short date-format) we
need to get a ShortDateFormat from the long-Dateformat.
daynames are stripped, long month-names converted to short

=cut
--]]

function getShortDateFormat(self) 
	local longDateFormat=datetime:getDateFormat()
	longDateFormat=string.gsub(longDateFormat, "%(%%a%)", "")
	longDateFormat=string.gsub(longDateFormat, "%%a,", "")
	longDateFormat=string.gsub(longDateFormat, "%%a", "")
	longDateFormat=string.gsub(longDateFormat, "%%A,", "")
	longDateFormat=string.gsub(longDateFormat, "%%A", "")
	longDateFormat=string.gsub(longDateFormat, "%%B", "%%b")
	return longDateFormat
end

function _window(self)
	window = Window("weather")
	window:setShowFrameworkWidgets(false)
	
	local w, h = Framework:getScreenSize()
	local srfBackground  = Surface:newRGBA(w, h)

	-- currentDay gets 2/3 of screen, forecast 1/3 (-some margins)
	-- forecast is then divided into three sections
	if w>h then
		currentDayX=20
		currentDayY=0
		currentDayW=w/3*2-30
		currentDayH=h

		forecastX=w/3*2+10
		forecastY=0
		forecastW=w/3-30
		forecastH=h/3
		forecastRepeatX=0
		forecastRepeatY=1
	else 
		currentDayX=0
		currentDayY=20
		currentDayW=w
		currentDayH=h/3*2-30

		forecastX=0
		forecastY=h/3*2+10
		forecastW=w/3
		forecastH=h/3-30
		forecastRepeatX=1
		forecastRepeatY=0
	end	

	-- fontsize: a third of available height / two lines ... gets scaled 
	-- later
	local currentDayFontSize=currentDayH/3/2
	local forecastFontSize=forecastH/3/2
	currentDayFont=Font:load("fonts/FreeSansBold.ttf", currentDayFontSize)
	forecastFont=Font:load("fonts/FreeSansBold.ttf", forecastFontSize)

	window:setSkin({
		weather = {
		       layout = Window.noLayout,
		       font = currentDayFont,
		       currentDayText = {
		         font = currentDayFont,
		         align = "center",
		         fg = { 0xee, 0xee, 0xee },
		         lineHeight=currentDayFontSize
		       }
		}
	})

	-- draw semi-transparent rectangles as background for current-day and forecast
	srfBackground:filledRectangle(currentDayX, currentDayY, currentDayX+currentDayW, currentDayY+currentDayH, 0x0000FF88)
	srfBackground:filledRectangle(forecastX, forecastY, forecastX+forecastW+forecastRepeatX*forecastW*2, forecastY+forecastH+forecastRepeatY*forecastH*2, 0x0000FF88)   

	local iconBG=Icon("background",srfBackground)
	iconBG:setPosition(0,0)
	iconBG:setSize(srfBackground:getSize())
	window:addWidget(iconBG)
	
	-- initialLabel
	local loading=Label("currentDayText", "Loading\nWeather\n...")
	loading:setBounds(currentDayX, currentDayY, currentDayW, currentDayH)
	window:addWidget(loading)

	-- register window as a screensaver
	local manager = appletManager:getAppletInstance("ScreenSavers")
	manager:screensaverWindow(window)
	
	return window
end

--[[

reloads the weather from wunderground.com and triggers parsing

=cut
--]]
function reloadWeather(self)
	local currentWeatherURI="/auto/wui/geo/WXCurrentObXML/index.xml?query="..url.escape(self:getSettings()["weather.location"])
	local forecastWeatherURI="/auto/wui/geo/ForecastXML/index.xml?query="..url.escape(self:getSettings()["weather.location"])
	local currentPWSWeatherURI="/weatherstation/WXCurrentObXML.asp?ID="..url.escape(self:getSettings()["weather.pws"])

	log:info("connecting to wunderground ("..currentWeatherURI..")")
	local http = SocketHttp(jnt, "api.wunderground.com", 80, "currentWeather")
	local req = RequestHttp(function(chunk, err)
			if chunk then
				self:parseCurrentWeather(chunk)
				lastWeatherUpdate = os.time()
				appletManager:callService("refreshCustomClockImageType","weather")
				appletManager:callService("refreshCustomClockTextType","weather")
				if window then
					self:redrawWeatherInfo()
				end
			end
		end,
		'GET',
		currentWeatherURI)
	http:fetch(req)

	log:info("connecting to wunderground ("..forecastWeatherURI..")")

	local http = SocketHttp(jnt, "api.wunderground.com", 80, "forecastWeather")
	req = RequestHttp(function(chunk, err)
			if chunk then
				self:parseForecastWeather(chunk)
				lastWeatherUpdate = os.time()
				appletManager:callService("refreshCustomClockImageType","weather")
				appletManager:callService("refreshCustomClockTextType","weather")
				if window then
					self:redrawWeatherInfo()
				end
			end
		end,
		'GET',
		forecastWeatherURI)
	http:fetch(req)
	
	local pws = trim(self:getSettings()["weather.pws"])
	if pws == nil then
		pws = ""
	end

	if pws ~= "" then
		log:info("connecting to wunderground ("..currentPWSWeatherURI..")")
		local http = SocketHttp(jnt, "api.wunderground.com", 80, "currentPWSWeather")
		req = RequestHttp(function(chunk, err)
			if chunk then
				self:parseCurrentPWSWeather(chunk)
				lastWeatherUpdate = os.time()
				appletManager:callService("refreshCustomClockImageType","weather")
				appletManager:callService("refreshCustomClockTextType","weather")
				if window then
					self:redrawWeatherInfo()
				end
			end
		end,
		'GET',
		currentPWSWeatherURI)
		http:fetch(req)
	end	
end

function trim (s)
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

--[[

reloads the weather from Dummy-Data - 3 datasets are available, each call gets the next one
used internally for debugging

=cut
--]]

local counter=1
function reloadWeatherDummy(self)
	local filename = self:findFile("applets/Weather/current"..counter..".xml")
	local fh = io.open(filename, "r")
	local currentWeatherXML=fh:read("*a")
	fh:close()
	local filename = self:findFile("applets/Weather/forecast"..counter..".xml")
	local fh = io.open(filename, "r")
	local forecastXML=fh:read("*a")
	fh:close()

	self:parseCurrentWeather(currentWeatherXML)
	self:parseForecastWeather(forecastXML)

	self:redrawWeatherInfo()
	
	counter=counter+1
end


--[[

redraws the screen

=cut
--]]

function redrawWeatherInfo(self)
	-- forecast toggles between two icons
	tick=tick+1
	if tick>10000 then
		tick=1
	end
	
	-- delete all widgets but background
	while (#window.widgets>1) do
		window:removeWidget(window.widgets[2])
	end

	-- now draw 1xcurrentWeather and 3xforecast
	self:drawWeatherInfo(currentDayX,currentDayY, currentDayW, currentDayH,
		self:getCurrentDayCondition(), currentDayFont)

	self:drawWeatherInfo(forecastX,forecastY, forecastW, forecastH,
		self:getForecastCondition(1), forecastFont)

	self:drawWeatherInfo(forecastX+forecastRepeatX*forecastW,forecastY+forecastRepeatY*forecastH, forecastW, forecastH,
		self:getForecastCondition(2), forecastFont)

	self:drawWeatherInfo(forecastX+forecastRepeatX*forecastW*2,forecastY+forecastRepeatY*forecastH*2, forecastW, forecastH,
		self:getForecastCondition(3), forecastFont)
end

--[[

returns the current icon + two textlines to represent the current weather

=cut
--]]

function getCurrentDayCondition(self)
	local condition={}
	if (currentWeather["observation_epoch"]==nil) then
		condition = {
			text= {	tostring(self:string("NO_WEATHER_DATA_LINE1")),
					tostring(self:string("NO_WEATHER_DATA_LINE2"))},
			icon = nil
		}
	else
		local epoch=currentWeather["observation_epoch"]
		local currentEpoch=os.time()
		local diff=(currentEpoch-epoch)/60
		local metric=tostring(self:string("WEATHER_MINUTES"))
		if (diff>120) then 
			diff=diff/60
			metric=tostring(self:string("WEATHER_HOURS"))
		end

		local agoString=math.floor(diff).." "..metric.." "..tostring(self:string("WEATHER_AGO"))
		local timeString=datetime:getCurrentTime()
		local dateString=os.date(dateformat, currentEpoch) 

		local infoStrings={}
		if self:getSettings().showInfoObservationTime then
			table.insert(infoStrings, agoString) 
		end
		if self:getSettings().showInfoTime then
			table.insert(infoStrings, timeString) 
		end
		if self:getSettings().showInfoDate then
			table.insert(infoStrings, dateString) 
		end

		local infoString=infoStrings[((math.floor(tick/2))%#infoStrings)+1]
		
		local temperatureScale=tostring(self:getSettings().temperature)
		local temp=currentWeather["temp"]
		if currentWeather["temp_pws"] then
			temp=currentWeather["temp_pws"]
		end
		local humid=currentWeather["humidity"]
		if currentWeather["humidity_pws"] then
			humid=currentWeather["humidity_pws"]
		end
		
		local weatherString=temp.."°"..temperatureScale.." "..humid
		
		-- to avoid chances in font-size the first line should always be the longest string.
		-- datestring is always the biggest one
		local spaces=math.max(0,math.ceil((string.len(dateString)-string.len(weatherString))/2))
		weatherString=string.rep(" ", spaces)..weatherString..string.rep(" ", spaces)

		
		condition= {
			text = {weatherString, infoString},
			icon=currentWeather["icon"]
		}
	
	end 
	return condition
end

--[[

returns the current icon + two textlines to represent the forecast
day can be 1-3

=cut
--]]
function getForecastCondition(self, day)
	local temperatureScale=tostring(self:getSettings().temperature)
	currentIcon=(tick % 2) +1



	local condition={}
	if (forecastWeather[day]==nil or 
		forecastWeather[day]["dayName"]==nil) then
		condition = {
			text= {"-"," "},
			icon = nil
		}
	else
		local localizedDayName=tostring(self:string(string.upper(forecastWeather[day]["dayName"])))
		condition= {
			text = {forecastWeather[day]["lowTemp"].."°"..temperatureScale.." - "..forecastWeather[day]["highTemp"].."°"..temperatureScale,
					localizedDayName
					},
			icon=forecastWeather[day]["icon"..currentIcon]
		}
	end
	return condition
end

function getCustomClockWeatherImage(self,data,reference,imageType,width,height,sink)
	if lastWeatherUpdate==0 or lastWeatherUpdate+1800<os.time() then
		lastWeatherUpdate=os.time()
		self:reloadWeather()
	end
	local icon = nil
	if imageType == "icon" then
		icon = currentWeather["icon"]
	end

	for i=1,3 do
		if forecastWeather[i] and forecastWeather[i]["icon1"] and not icon and imageType == "icon"..i then
			icon = forecastWeather[i]["icon1"]
			break
		end
		if forecastWeather[i] and forecastWeather[i]["icon2"] and not icon and imageType == "skyicon"..i then
			icon = forecastWeather[i]["icon2"]
			break
		end
	end

	if icon then
		local imagePath="applets/Weather/"..images[icon]
		local srfCurrentWeather=Surface:loadImage(imagePath)
		local w,h=srfCurrentWeather:getSize()
		--srfCurrentWeather:filledRectangle(0,0,w, h, 0x0000ff99)
		local imageW, imageH=srfCurrentWeather:getSize()
	
		-- if we have an image it is scaled and positioned to the upper 2/3 of
		-- the given area
		if srfCurrentWeather~=nil then
			if width and height then
				srfCurrentWeather=srfCurrentWeather:zoom(width/imageW,height/imageH,0)
			end
			sink(reference,srfCurrentWeather)
		else
			sink(reference,nil)
		end
	else
		sink(reference,nil)
	end
end

function getCustomClockWeatherText(self,data,reference,text,sink)
	if lastWeatherUpdate==0 or lastWeatherUpdate+1800<os.time() then
		lastWeatherUpdate=os.time()
		self:reloadWeather()
	end

	if text and currentWeather["temp"] then
		local currentAttributes = {'description','temp_pws','humidity_pws','temp','humidity','observation_epoch'}
		for _,attr in ipairs(currentAttributes) do
			if currentWeather[attr] then
				local escapedValue = string.gsub(currentWeather[attr],"%%","%%%%")
				text = string.gsub(text,"%%"..attr,escapedValue)
			else
				text = string.gsub(text,"%%"..attr,"")
			end
		end

		local forcastAttributes = {'dayName','highTemp','lowTemp'}
		for i=1,3 do
			for _,attr in ipairs(forcastAttributes) do
				if forecastWeather[i] and forecastWeather[i][attr] then
					text = string.gsub(text,"%%"..attr.."."..i,forecastWeather[i][attr])
				else
					text = string.gsub(text,"%%"..attr.."."..i,"")
				end
			end
		end

		text = string.gsub(text,"%%scaletemp","°"..tostring(self:getSettings().temperature))
		sink(reference,text)
	else
		sink(reference,"")
	end
end

--[[

draws a condition (icon + 2 textlines) to a given rectangular area
the given font should be roughly 1/3 (/2 because of two lines) of the height

=cut
--]]

function drawWeatherInfo(self, infoX, infoY, infoW, infoH, condition, font)
	--log:info("Rect: " .. infoX.."x"..infoY.." "..infoW.."x"..infoH.."x")
	
	if condition["icon"]~=nil and images[condition["icon"]]~=nil then
		local imagePath="applets/Weather/"..images[condition["icon"]]
		local srfCurrentWeather=Surface:loadImage(imagePath)
		local w,h=srfCurrentWeather:getSize()
		--srfCurrentWeather:filledRectangle(0,0,w, h, 0x0000ff99)
		local imageW, imageH=srfCurrentWeather:getSize()
	
		-- if we have an image it is scaled and positioned to the upper 2/3 of
		-- the given area
		if srfCurrentWeather~=nil then
			srfCurrentWeather=srfCurrentWeather:zoom((infoW-10)/imageW,((infoH-10)/3*2)/imageH,0)
		
			local iconFG=Icon("fg",srfCurrentWeather)	
			iconFG:setPosition(infoX+5, infoY+5)
			iconFG:setSize(srfCurrentWeather:getSize())
			window:addWidget(iconFG)
		end
	end

	-- two textlines will be at the lower 1/3 of the given area
	-- we first draw the text with the given font and then scale it
	-- to fit exactly into the given area
	local textAreaSrf1=Surface:drawText(font, 0xeeeeee, condition["text"][1])
	local textAreaSrf2=Surface:drawText(font, 0xeeeeee, condition["text"][2])
	
	local textAreaWidth1, textAreaHeight1=textAreaSrf1:getSize()
	local textAreaWidth2, textAreaHeight2=textAreaSrf2:getSize()
	local textAreaWidth=math.max(textAreaWidth1, textAreaWidth2)+5
	local textAreaHeight=font:height()*2

	--textAreaSrf1:filledRectangle(0,0,textAreaWidth1, textAreaHeight1, 0xff000077)
	--textAreaSrf2:filledRectangle(0,0,textAreaWidth2, textAreaHeight2, 0x00ff0077)
	local textAreaWidthDest=infoW
	local textAreaHeightDest=infoH/3+5
	local scale=math.min(textAreaWidthDest/textAreaWidth, textAreaHeightDest/textAreaHeight)

	--log:info("TextAreaSize"..textAreaWidth.."x"..textAreaHeight)
	--log:info("TextAreaSizeDest"..textAreaWidthDest.."x"..textAreaHeightDest)
	--log:info("Scale"..textAreaWidthDest/textAreaWidth .."x".. textAreaHeightDest/textAreaHeight)	

	textAreaSrf1=textAreaSrf1:zoom(scale, scale,1)
	textAreaSrf2=textAreaSrf2:zoom(scale, scale,1)

	local iconText1=Icon("text1", textAreaSrf1)
	local iconText1W, iconText1H=textAreaSrf1:getSize()
	iconText1:setPosition(infoX+((infoW-iconText1W)/2), infoY+infoH/3*2-10)
	iconText1:setSize(textAreaSrf1:getSize())
	local iconText2=Icon("text1", textAreaSrf2);
	local iconText2W, iconText2H=textAreaSrf2:getSize()
	iconText2:setPosition(infoX+((infoW-iconText2W)/2), infoY+infoH/3*2+infoH/3/2-10)
	iconText2:setSize(textAreaSrf2:getSize())

	window:addWidget(iconText1)
	window:addWidget(iconText2)

	-- old code to draw text - unfortunately it will always be a bit too small or large
	--	local label=Label(textStyle,condition["text"])
	--	label:setBounds(infoX, infoY+infoH/3*2+5, infoW, infoH/3-10)
	--	window:addWidget(label)
end


--[[

parses relevant information of the current weather from wunderground
result is put into the global currentWeather-variable 

=cut
--]]

function parseCurrentWeather(self, currentWeatherXML)

	-- if possible we will use the (more accurate) weather-string to resolve icons
	-- as a fallback we can use the official icon
	local weather=string.lower(self:getContentFromXMLTag(currentWeatherXML, "weather")[1])
	local icon=string.lower(self:getContentFromXMLTag(currentWeatherXML, "icon")[1])
	if images[weather]~=nil then
		currentWeather["icon"]=weather
	else
		currentWeather["icon"]=icon
	end

	currentWeather["description"]=weather
	
	local temperatureScale="temp_c"
	if self:getSettings().temperature=="F" then
	  temperatureScale="temp_f"
	end
	currentWeather["temp"]=self:getContentFromXMLTag(currentWeatherXML, temperatureScale)[1]
	currentWeather["humidity"]=self:getContentFromXMLTag(currentWeatherXML, "relative_humidity")[1]
	local time=self:getContentFromXMLTag(currentWeatherXML, "observation_time_rfc822")[1]
	currentWeather["observation_epoch"]=self:getContentFromXMLTag(currentWeatherXML, "observation_epoch")[1]

	log:info("parseCurrentWeather - ".. 
		" desc: "..currentWeather["description"].. 
		" icon: "..currentWeather["icon"] ..  
		" temp: "..currentWeather["temp"] .. 
		" humid: "..currentWeather["humidity"].. 
		" epoch: "..currentWeather["observation_epoch"] )

	
end

--[[

parses relevant information of the forecast from wunderground
result is put into the global forecastWeather-variable 

=cut
--]]

function parseForecastWeather(self, forecastXML)
	local simpleForecastXML=self:getContentFromXMLTag(forecastXML, "simpleforecast")[1]
	local singleDaysForecastXML=self:getContentFromXMLTag(simpleForecastXML, "forecastday")

	for i=1,3 do
		forecastWeather[i]={}
		forecastWeather[i]["icon1"]=self:getContentFromXMLTag(singleDaysForecastXML[i], "icon")[1]
		forecastWeather[i]["icon2"]=self:getContentFromXMLTag(singleDaysForecastXML[i], "skyicon")[1]
		local time=self:getContentFromXMLTag(singleDaysForecastXML[i], "pretty")[1]
		local epoch=self:getContentFromXMLTag(singleDaysForecastXML[i], "epoch")[1]
		forecastWeather[i]["dayName"]=os.date("%a", epoch)
		local highXML=self:getContentFromXMLTag(singleDaysForecastXML[i], "high")[1]
		local lowXML=self:getContentFromXMLTag(singleDaysForecastXML[i], "low")[1]
		local temperatureScale="celsius"
		if self:getSettings().temperature=="F" then
		  temperatureScale="fahrenheit"
		end
		
		forecastWeather[i]["highTemp"]=self:getContentFromXMLTag(highXML, temperatureScale)[1]
		forecastWeather[i]["lowTemp"]=self:getContentFromXMLTag(lowXML, temperatureScale)[1]

		log:info("parseForecast - "..i.. 
			" icon1: "..forecastWeather[i]["icon1"] ..  
			" icon2: "..forecastWeather[i]["icon2"] ..  
			" time: "..time ..
			" epoch: "..epoch .. 
			" day: "..forecastWeather[i]["dayName"] ..
			" high: "..forecastWeather[i]["highTemp"].. 
			" low: "..forecastWeather[i]["lowTemp"] )	
	end
end


--[[

parses relevant information of the current weather from wunderground
from a particular PWS
result is put into the global currentWeather-variable

=cut
--]]

function parseCurrentPWSWeather(self, currentPWSWeatherXML)

	-- do not set images, description or epoch from here; they will come from the main weather
	-- relative humidity from a PWS does not have % character on the end

	local temperatureScale="temp_c"
	if self:getSettings().temperature=="F" then
		temperatureScale="temp_f"
	end
	currentWeather["temp_pws"]=self:getContentFromXMLTag(currentPWSWeatherXML, temperatureScale)[1]
	currentWeather["humidity_pws"]=self:getContentFromXMLTag(currentPWSWeatherXML, "relative_humidity")[1] .. "%"
	local time=self:getContentFromXMLTag(currentPWSWeatherXML, "observation_time_rfc822")[1]

	log:info("parseCurrentPWSWeather - "..
		" temp: "..currentWeather["temp_pws"] ..
		" humid: "..currentWeather["humidity_pws"] )

end

--[[
simple method to parse XML.
It just gets the text between the given tag, doing a simple pattern matching
<tag>text</tag> 

=cut
--]]


function getContentFromXMLTag(self, xml, tag)
	contents = {}
	for v in string.gmatch(xml, "<"..tag..">(.-)</"..tag..">") do
		table.insert(contents, v)
	end
	return contents
end


--[[

opens settings-menu for our applet
=cut
--]]

function openSettings(self, menuItem)
	local window = Window("text_list", menuItem.text, "settingstitle")
	window:addWidget(SimpleMenu("menu",
		{
			{
				text = self:string("SETUP_LOCATION"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineLocation(menuItem)
					return EVENT_CONSUME
				end
			},
			{
				text = self:string("SETUP_PWS"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:definepws(menuItem)
					return EVENT_CONSUME
				end
			},
			{
				text = self:string("SETUP_TEMPERATURE"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineTemperature(menuItem)
					return EVENT_CONSUME
				end
			},
			{
				text = self:string("SETUP_INFOLINE"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineInfos(menuItem)
					return EVENT_CONSUME
				end
			},
		}))

	self:tieAndShowWindow(window)
	return window
end


function definepws(self, menuItem)

	local window = Window("text_list", menuItem.text, "settingsTitle")
	local pws = self:getSettings()["weather.pws"]
	if pws == nil then
		pws = " "
	end

	local input = Textinput("textinput", pws,
	function(_, value)
		log:debug("Input " .. value)
		self:getSettings()["weather.pws"] = value
		self:storeSettings()

		window:playSound("WINDOWSHOW")
		window:hide(Window.transitionPushLeft)
		return true
	end)

	if hasKeyboard then
		-- use 7.4 keyboard for Touch if available
		local keyboard = Keyboard("keyboard", "qwerty", input)
		local backspace = Keyboard.backspace()
		local group = Group('keyboard_textinput', { textinput = input, backspace = backspace } )

		window:addWidget(group)
		window:addWidget(keyboard)
		window:focusWidget(group)

	else
		-- backward-compatible to 7.3-controller
		window:addWidget(input)
	end

	self:tieAndShowWindow(window)
	return window
end


--[[

let the user enter his current location
some tweaks to show a keyboard for the touch and just a textinput with 7.3 firmware

=cut
--]]

function defineLocation(self, menuItem)

    local window = Window("text_list", menuItem.text, "settingsTitle")

	local location = self:getSettings()["weather.location"]
	if location == nil then
		location = " "
	end

	local input = Textinput("textinput", location,
		function(_, value)
			log:debug("Input " .. value)
			self:getSettings()["weather.location"] = value
			self:storeSettings()

			window:playSound("WINDOWSHOW")
			window:hide(Window.transitionPushLeft)
			return true
		end)

	if hasKeyboard then
		-- use 7.4 keyboard for Touch if available
		local keyboard  = Keyboard("keyboard", "qwerty", input)
		local backspace = Keyboard.backspace()
		local group     = Group('keyboard_textinput', { textinput = input, backspace = backspace } )

		window:addWidget(group)
		window:addWidget(keyboard)
		window:focusWidget(group)
		
	else 
		-- backward-compatible to 7.3-controller
		window:addWidget(input) 
	end 
		
	self:tieAndShowWindow(window)
	return window
end

function defineTemperature(self, menuItem)

	local window = Window(menuWindowStyle, menuItem.text, "settingsTitle")
	local currentSetting = self:getSettings().temperature
	local group = RadioGroup()
	local menu=SimpleMenu("menu", { 
		{
			text = "°C",
			style= menuCheckStyle,
			[menuCheckOption] = RadioButton(
				"radio", 
				group, 
				function()
					self:getSettings()['temperature'] = "C"
					self:storeSettings()
				end,
				(currentSetting=="C")
			),
		},
		{
			text = "°F", 
			style= menuCheckStyle,
			[menuCheckOption] = RadioButton(
				"radio", 
				group, 
				function()
					self:getSettings()['temperature'] = "F"
					self:storeSettings()
				end,
				(currentSetting=="F")
			),
		}
	})

	window:addWidget(menu)		
	self:tieAndShowWindow(window)
	return window
end

function defineInfos(self, menuItem)


	local window = Window(menuWindowStyle, menuItem.text, "settingsTitle")
	local menu=SimpleMenu("menu", { 
		{
			text = self:string("SETUP_INFOLINE_OBSERVATION_TIME"),
			style= menuCheckStyle, 
			[menuCheckOption] = Checkbox(
					"checkbox",
					function(object, isSelected)
						self:getSettings()['showInfoObservationTime']  = isSelected
						self:storeSettings()
					end,
					(self:getSettings().showInfoObservationTime==true)
				)
		},
		{
			text = self:string("SETUP_INFOLINE_TIME"),
			style= menuCheckStyle, 
			[menuCheckOption] = Checkbox(
					"checkbox",
					function(object, isSelected)
						self:getSettings()['showInfoTime'] = isSelected
						self:storeSettings()
					end,
					(self:getSettings().showInfoTime==true)
				)
		},
		{
			text = self:string("SETUP_INFOLINE_DATE"),
			style= menuCheckStyle, 
			[menuCheckOption] = Checkbox(
					"checkbox",
					function(object, isSelected)
						self:getSettings()['showInfoDate']  = isSelected
						self:storeSettings()
					end,
					(self:getSettings().showInfoDate==true)
				)
		},
	})

	window:addWidget(menu)		
	self:tieAndShowWindow(window)
	return window
end


--[[

looks for a file ... compatible with 7.3 + 7.4 firmware

=cut
--]]


function findFile(self, path)
	if hasSystem then
		return System:findFile(path)
	else
		return Framework:findFile(path) 
	end
end
