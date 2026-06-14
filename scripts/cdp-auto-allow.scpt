use scripting additions

property allowButtonNames : {"Allow", "允许", "允許", "OK", "Ok", "确定", "確認", "好"}
property requiredTerms : {"DevTools", "Developer Tools", "remote debugging", "CDP", "chrome-devtools", "MCP", "remote debugging connection", "another program is trying", "远程调试", "遠端偵錯", "遠端調試"}
property confirmationTerms : {"wants full control", "debug it", "saved data", "cookies and site data", "trusted apps", "external app", "navigate to any URL"}
property logDir : "/tmp/cdp-auto-allow"
property configFile : "__CONFIG_PATH__"
property lastApprovalTime : 0
property minApprovalInterval : 3
property dryRun : false
property didInit : false
property pollInterval : 3
property maxLogDays : 7

on loadConfig()
	try
		set configData to do shell script "cat " & quoted form of configFile
		set jsonStr to configData as text
		-- parse pollInterval
		if jsonStr contains "pollInterval" then
			try
				set pollInterval to text 14 thru -2 of (do shell script "python3 -c \"import json; c=json.load(open(" & quoted form of configFile & ")); print(c.get('pollInterval', 3))\"")
			end try
		end if
		-- parse maxLogDays
		if jsonStr contains "maxLogDays" then
			try
				set maxLogDays to text 14 thru -2 of (do shell script "python3 -c \"import json; c=json.load(open(" & quoted form of configFile & ")); print(c.get('maxLogDays', 7))\"")
			end try
		end if
	on error
		-- config file missing or invalid, use defaults
	end try
end loadConfig

on getLogPath()
	set logFile to logDir & "/" & (do shell script "date '+%Y-%m-%d'") & ".log"
	return logFile
end getLogPath

on rotateLogs()
	try
		do shell script "find " & quoted form of logDir & " -name '*.log' -mtime +" & maxLogDays & " -delete 2>/dev/null"
	end try
end rotateLogs

on debugLog(msg)
	try
		set logFile to my getLogPath()
		do shell script "mkdir -p " & quoted form of logDir & "; printf '%s %s\\n' \"$(date '+%H:%M:%S')\" " & quoted form of (msg as text) & " >> " & quoted form of logFile
	end try
end debugLog

on initFromArgv(argv)
	if didInit then return
	try
		if (count of argv) > 0 then
			repeat with arg in argv
				set argText to arg as text
				if argText is "--dry-run" then set dryRun to true
				if argText starts with "--interval=" then
					set pollInterval to text 12 thru -1 of argText as number
				end if
			end repeat
		end if
	end try
	my loadConfig()
	set didInit to true
	my rotateLogs()
	my debugLog("script started, interval=" & pollInterval & " dry=" & dryRun)
	log "[launch-agent] script started, interval=" & pollInterval & " dry=" & dryRun
end initFromArgv

on idle
	my initFromArgv({})
	try
		my scanChromiumBrowsers(dryRun)
	on error errMsg number errNum
		my debugLog("scan error " & errNum & ": " & errMsg)
	end try
	return pollInterval
end idle

on run argv
	my initFromArgv(argv)
	repeat
		try
			my scanChromiumBrowsers(dryRun)
		on error errMsg number errNum
			my debugLog("scan error " & errNum & ": " & errMsg)
		end try
		delay pollInterval
	end repeat
end run

on scanChromiumBrowsers(dryRun)
	set foundAny to false
	tell application "System Events"
		if exists process "Google Chrome" then
			set foundAny to true
			my scanProcess(process "Google Chrome", "Google Chrome", dryRun)
		end if
		if exists process "Google Chrome Canary" then
			set foundAny to true
			my scanProcess(process "Google Chrome Canary", "Google Chrome Canary", dryRun)
		end if
		if exists process "Chromium" then
			set foundAny to true
			my scanProcess(process "Chromium", "Chromium", dryRun)
		end if
	end tell
	if not foundAny then my debugLog("tick: no chromium process found")
end scanChromiumBrowsers

on scanProcess(chromeProcess, processLabel, dryRun)
	tell application "System Events"
		tell chromeProcess
			try
				set windowList to every window
			on error errMsg number errNum
				my debugLog(processLabel & " windows error " & errNum & ": " & errMsg)
				set windowList to {}
			end try
			my debugLog(processLabel & " window count=" & (count of windowList))

			if (count of windowList) is 0 then
				my debugLog(processLabel & " window count=0, trying to activate")
				try
					tell application processLabel to activate
					delay 0.5
					set windowList to every window
					my debugLog(processLabel & " window count after activate=" & (count of windowList))
				on error errMsg
					my debugLog(processLabel & " activate failed: " & errMsg)
				end try
			end if

			repeat with w in windowList
				set targetWindow to contents of w
				try
					set wname to name of targetWindow
				on error
					set wname to "<noname>"
				end try
				try
					set wSubrole to subrole of targetWindow as text
				on error
					set wSubrole to ""
				end try

				my debugLog(processLabel & " window: " & (wname as text) & " subrole=" & wSubrole)

				set isSmallDialog to false
				if wSubrole is "AXUnknown" then
					try
						set wSize to size of targetWindow
						set wWidth to item 1 of wSize
						set wHeight to item 2 of wSize
						if wWidth < 600 and wHeight < 600 then set isSmallDialog to true
						my debugLog(processLabel & " AXUnknown window size=" & wWidth & "x" & wHeight)
					on error
						set isSmallDialog to true
					end try
				end if
				if isSmallDialog then
					my debugLog(processLabel & " detected small AXUnknown window — may be CDP dialog container")
					my approveViaKeystroke(dryRun)
				else if (wname as text) is "<noname>" then
					try
						set hasCancel to false
						set hasAllow to false
						try
							if exists button "Cancel" of targetWindow then set hasCancel to true
						end try
						try
							if exists button "Allow" of targetWindow then set hasAllow to true
						end try
						if hasCancel and hasAllow then
							my debugLog("Unnamed window has Cancel+Allow buttons — treating as CDP prompt")
							if dryRun then
								my debugLog("Dry run: would click Allow on unnamed window")
							else
								try
									click button "Allow" of targetWindow
									my debugLog("Approved unnamed dialog window")
								on error errMsg
									my debugLog("Click Allow on unnamed window failed: " & errMsg)
								end try
							end if
						else
							my debugLog("Unnamed window missing Cancel/Allow buttons (allow=" & hasAllow & " cancel=" & hasCancel & "), skipping")
						end if
					on error errMsg
						my debugLog("Unnamed window check error: " & errMsg)
					end try
				end if
				try
					set sheetList to every sheet of targetWindow
				on error
					set sheetList to {}
				end try
				if (count of sheetList) > 0 then my debugLog(processLabel & " sheets=" & (count of sheetList))
				repeat with s in sheetList
					my scanContainer(contents of s, dryRun)
				end repeat
			end repeat
		end tell
	end tell
end scanProcess

on scanContainer(targetElement, dryRun)
	tell application "System Events"
		set uiText to my textOfElement(targetElement)
		if my looksLikeCdpPrompt(uiText) then
			my debugLog("Matched Chrome CDP/DevTools prompt: " & my clipText(uiText))
			if dryRun then
				my debugLog("Dry run: would approve prompt")
			else
				if my clickAllowButton(targetElement) then
					my debugLog("Approved Chrome CDP/DevTools prompt")
				else
					my debugLog("Matched prompt, but no allow button was clickable")
				end if
			end if
		end if
	end tell
end scanContainer

on approveViaKeystroke(dryRun)
	set currentTime to (do shell script "date +%s") as number
	if currentTime - lastApprovalTime < minApprovalInterval then
		my debugLog("Skipping keystroke approval, too soon since last approval")
		return
	end if
	set lastApprovalTime to currentTime
	my debugLog("Approving via keystroke (activate + Return)")
	if dryRun then
		my debugLog("Dry run: would activate Chrome and press Return")
		return
	end if
	try
		tell application "Google Chrome" to activate
		delay 0.3
		tell application "System Events"
			keystroke return
		end tell
		my debugLog("Sent Return keystroke to approve dialog")
	on error errMsg
		my debugLog("Keystroke approval failed: " & errMsg)
	end try
end approveViaKeystroke

on looksLikeCdpPrompt(uiText)
	ignoring case
		set hasRequired to false
		repeat with t in requiredTerms
			if uiText contains (t as text) then
				set hasRequired to true
				exit repeat
			end if
		end repeat
		if not hasRequired then return false
		repeat with t in confirmationTerms
			if uiText contains (t as text) then return true
		end repeat
	end ignoring
	return false
end looksLikeCdpPrompt

on clickAllowButton(rootElement)
	tell application "System Events"
		repeat with buttonName in allowButtonNames
			try
				if exists button (buttonName as text) of rootElement then
					click button (buttonName as text) of rootElement
					return true
				end if
			end try
		end repeat
		try
			set roleText to role of rootElement as text
			ignoring case
				set isButton to roleText contains "button"
			end ignoring
			if isButton then
				set buttonText to my buttonLabel(rootElement)
				ignoring case
					repeat with buttonName in allowButtonNames
						if (buttonText as text) is (buttonName as text) then
							my debugLog("Clicking allow button: " & buttonText)
							click rootElement
							return true
						end if
					end repeat
				end ignoring
			end if
		end try
		try
			repeat with childElement in UI elements of rootElement
				if my clickAllowButton(childElement) then return true
			end repeat
		end try
	end tell
	return false
end clickAllowButton

on buttonLabel(rootElement)
	set pieces to ""
	tell application "System Events"
		try
			set buttonName to name of rootElement
			if buttonName is not missing value then set pieces to pieces & " " & (buttonName as text)
		end try
		try
			set buttonDescription to description of rootElement
			if buttonDescription is not missing value then set pieces to pieces & " " & (buttonDescription as text)
		end try
		try
			set buttonValue to value of rootElement
			if buttonValue is not missing value then set pieces to pieces & " " & (buttonValue as text)
		end try
	end tell
	return pieces
end buttonLabel

on textOfElement(rootElement)
	set pieces to ""
	tell application "System Events"
		try
			set elementName to name of rootElement
			if elementName is not missing value then set pieces to pieces & " " & (elementName as text)
		end try
		try
			set elementDescription to description of rootElement
			if elementDescription is not missing value then set pieces to pieces & " " & (elementDescription as text)
		end try
		try
			set elementValue to value of rootElement
			if elementValue is not missing value then set pieces to pieces & " " & (elementValue as text)
		end try
		try
			repeat with childElement in UI elements of rootElement
				set pieces to pieces & " " & my textOfElement(childElement)
			end repeat
		end try
	end tell
	return pieces
end textOfElement

on clipText(inputText)
	if (length of inputText) > 500 then return text 1 thru 500 of inputText
	return inputText
end clipText
