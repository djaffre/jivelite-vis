--[[

Display Off Applet based on BlankScreen2 screensaver

--]]

local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")

local appletManager = appletManager

module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end


function registerApplet(self)
end


function configureApplet(self)
	-- remove original
	appletManager:callService("removeScreenSaver", "BlankScreen2", "openScreensaver2")

	-- add ourselves
	appletManager:callService("addScreenSaver",
		"Blank Screen 2",
		"BlankScreenSaver2", 
		"openScreensaver2", _, _, 100, 
		"closeScreensaver2"
	)
end
