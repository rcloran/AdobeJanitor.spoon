--- === AdobeJanitor ===
---
--- Cleans up Adobe daemons after all actual Adobe applications have quit.
---
--- Adobe leaves a number of daemons running in the background all the time.
--- While some of these are useful some of the time, many users do not want
--- them consuming resources while Adobe applications are not running.
---
--- This cleans up the trash -- after all "real" Adobe applications (eg,
--- Lightroom, Photoshop, etc) have quit, it will wait some amount of time 
--- (by default 5 minutes) and then kill any remaining Adobe processes (eg, 
--- cloud synchronization daemons).

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "AdobeJanitor"
obj.version = "0.1"
obj.author = "Russell Cloran <rcloran@gmail.com>"
obj.homepage = "https://github.com/rcloran/AdobeJanitor.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configurables

--- AdobeJanitor.trash
--- Variable
--- Application IDs which are not considered real applications. That is, these are ignored when determining whether any applications are still running.
obj.trash = {
	["com.adobe.accmac"] = true,
	["com.adobe.AdobeIPCBroker"] = true,
	["com.adobe.ccd.helper"] = true,
	["com.adobe.CCLibrary"] = true,
	["com.adobe.CCXProcess"] = true,
	["com.adobe.acc.AdobeDesktopService"] = true,
	["com.adobe.accmac.ACCFinderSync"] = true,
}

--- AdobeJanitor.cleanupDelay
--- Variable
--- Number of seconds after all applications have quit to wait before cleaning up unwanted daemons
obj.cleanupDelay = 300


--- AdobeJanitor.notifyKilled(exitCode, stdout, stderr) -> self
--- Method
--- Display a notification when unwanted daemons have been cleaned up. Replace this to customize notifications.
---
--- Parameters:
---  * exitCode: An integer containing the exit code of the process
---  * stdout: A string containing the standard output of the process
---  * stderr: A string containing the standard error output of the process
---
--- Returns:
---  * The AdobeJanitor object
function obj.notifyKilled(exitCode, stdout, stderr)
	hs.notify.show("Adobe Janitor", "", "Cleaned up")
	return self
end

local adobe = "com.adobe."

-- Internal method to actually perform the cleanup
function obj:_cleanup()
	-- There seems to be some sort of deadlock in hs.application if events are
	-- received while we're doing stuff like hs.application.find(''), and
	-- stopping the watcher seems to work around it sufficiently, though it
	-- might end up "leaking" Adobe cruft (ie, causing this script to be
	-- ineffective).
	-- Refactoring this to maintain a list of Adobe apps internally seemed to
	-- end up causing a similar kind of issue just in the app event handler,
	-- which presumably still exists in this version, but may be harder to
	-- trigger?
	self._watcher:stop()
	if #self:_findAdobeNotTrash() == 0 then
		hs.task.new("/usr/bin/pkill", self.notifyKilled, { "-f", "Adobe" }):start()
	end
	self._watcher:start()
end

-- Internal method to find all Adobe applications
function obj:_findAdobe()
	local all = { hs.application.find("") }
	return hs.fnutils.filter(all, function(app)
		local b = app:bundleID()
		if b == nil then
			return false
		end
		return b:sub(1, #adobe) == adobe
	end)
end

-- Internal method to find Adobe applications which are not considered for cleanup
function obj:_findAdobeNotTrash()
	return hs.fnutils.filter(self:_findAdobe(), function(app)
		return self.trash[app:bundleID()] == nil
	end)
end

-- Internal method to react to Adobe application termination
function obj:_appEventHandler(appName, eventType, appObject)
	if eventType ~= hs.application.watcher.terminated then
		return
	end
	local b = appObject:bundleID()
	if b:sub(1, #adobe) == adobe and self.trash[b] == nil then
		self._timer:start()
	end
end

--- AdobeJanitor:start() -> self
--- Method
--- Start application watcher and timers
---
--- Parameters:
---  * None
---
--- Returns:
---  * The AdobeJanitor object
function obj:start()
	self._watcher = hs.application.watcher.new(function(appName, eventType, appObject)
		self:_appEventHandler(appName, eventType, appObject)
	end)
	self._watcher:start()
	self._timer = hs.timer.delayed.new(self.cleanupDelay, function()
		self:_cleanup()
	end)
	self._timer:start() -- Clean up anything that snuck in during boot
	return self
end

return obj
