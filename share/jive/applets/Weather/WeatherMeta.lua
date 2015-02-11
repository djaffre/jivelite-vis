--[[

=head1 LICENSE

Copyright 2009 by Stefan Hansel. All Rights Reserved.

Until further notice:
	- You are NOT allowed to redistribute modified versions of this applet.
	- You are NOT allowed to create derivative works of this applet 

=cut
--]]


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")
local jul           = require("jive.utils.log")

local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end



function defaultSettings(self)
	local defaultSetting = {}
	defaultSetting["weather.location"] = "Berlin, Germany"
	defaultSetting["temperature"] = "C"
	defaultSetting["showInfoTime"] = true
	defaultSetting["showInfoDate"] = true
	defaultSetting["showInfoObservationTime"] = true
	defaultSetting["weather.pws"] = ""
	
	return defaultSetting
end



function registerApplet(meta)
	jiveMain:addItem(meta:menuItem('weather', 'extras', "WEATHER_MENU", function(applet, ...) applet:openScreensafer(...) end, 1))
end


function configureApplet(self)
	appletManager:callService("addScreenSaver",
		self:string("WEATHER_MENU"), 
		"Weather", 
		"openScreensafer", self:string("WEATHER_SETTINGS"), "openSettings", 40
	)
	appletManager:callService("addCustomClockImageType","weather","Weather","getCustomClockWeatherImage")
	appletManager:callService("addCustomClockTextType","weather","Weather","getCustomClockWeatherText")
end

