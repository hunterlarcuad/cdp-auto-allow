use scripting additions

property allowButtonNames : {"Allow", "允许", "允許", "OK", "Ok", "确定", "確認", "好"}
property requiredTerms : {"DevTools", "Developer Tools", "remote debugging", "CDP", "chrome-devtools", "MCP", "remote debugging connection", "another program is trying", "Allow remote debugging", "要允许远程调试吗", "远程调试", "遠端偵錯", "遠端調試"}
property confirmationTerms : {"wants full control", "debug it", "saved data", "cookies and site data", "trusted apps", "external app", "navigate to any URL", "external application", "完全控制此 Chrome 会话", "外部应用", "保存的数据", "Cookie 和网站数据", "任意网址", "受信任的应用"}
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
		if jsonStr contains "pollInterval" then
			try
				set pollInterval to text 14 thru -2 of (do shell script "python3 -c \"import json; c=json.load(open(" & quoted form of configFile & ")); print(c.get('pollInterval', 3))\"")
			end try
		end if
		if jsonStr contains "maxLogDays" then
			try
				set maxLogDays to text 14 thru -2 of (do shell script "python3 -c \"import json; c=json.load(open(" & quoted form of configFile & ")); print(c.get('maxLogDays', 7))\"")
			end try
		end if
	on error
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
	-- Scan all Chromium-related processes by name.
	-- IMPORTANT: Chrome spawns multiple processes with the same name (main, renderers, etc.).
	-- We must iterate ALL processes with each name to find the one with windows/dialogs.
	set processNames to {"Google Chrome", "Google Chrome Canary", "Chromium", "Google Chrome Helper (Alerts)", "Google Chrome Canary Helper (Alerts)", "Chromium Helper (Alerts)"}
	set foundAny to false
	set seenPids to {}
	tell application "System Events"
		repeat with procName in processNames
			try
				if exists process (procName as text) then
					set foundAny to true
					set matchingProcs to (every process whose name is (procName as text))
					repeat with p in matchingProcs
						try
							set pPid to unix id of p
						on error
							set pPid to -1
						end try
						-- Deduplicate by PID to avoid scanning same process twice
						if pPid is not in seenPids then
							set end of seenPids to pPid
							try
								set wCount to count of windows of p
							on error errMsg number errNum
								my debugLog((procName as text) & " PID=" & pPid & " window error " & errNum & ": " & errMsg)
								set wCount to 0
							end try
							my debugLog((procName as text) & " PID=" & pPid & " windows=" & wCount)
							if wCount > 0 then
								my scanProcess(p, (procName as text) & " PID=" & pPid, dryRun)
							end if
						end if
					end repeat
				end if
			on error errMsg number errNum
				my debugLog((procName as text) & " scan error " & errNum & ": " & errMsg)
			end try
		end repeat
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

				-- Strategy 1: Small AXUnknown window — likely a CDP dialog
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

				-- Strategy 2: Scan sheets first because Chrome CDP prompts are usually attached sheets.
				try
					set sheetList to every sheet of targetWindow
				on error
					set sheetList to {}
				end try
				if (count of sheetList) > 0 then my debugLog(processLabel & " sheets=" & (count of sheetList))
				repeat with s in sheetList
					my scanContainer(contents of s, dryRun)
				end repeat

				-- Strategy 3: Scan only compact dialog-like windows. Full browser windows can be huge
				-- and may delay the next sheet prompt by tens of seconds.
				if (count of sheetList) is 0 and isSmallDialog then my scanContainer(targetWindow, dryRun)

				if isSmallDialog then
					my debugLog(processLabel & " detected small AXUnknown window — trying keystroke approval")
					my approveViaKeystroke(dryRun)
				else if (wname as text) is "<noname>" then
					-- Strategy 4: Unnamed window with Cancel+Allow buttons
					try
						set hasCancel to false
						set hasAllow to false
						try
							if exists button "Cancel" of targetWindow then set hasCancel to true
						end try
						try
							if exists button "Allow" of targetWindow then set hasAllow to true
						end try
						-- Also check Chinese button names
						try
							if exists button "取消" of targetWindow then set hasCancel to true
						end try
						try
							if exists button "允许" of targetWindow then set hasAllow to true
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
									-- Try Chinese button name
									try
										click button "允许" of targetWindow
										my debugLog("Approved unnamed dialog window (Chinese)")
									on error
										my debugLog("Click Allow on unnamed window failed: " & errMsg)
									end try
								end try
							end if
						else
							my debugLog("Unnamed window buttons: allow=" & hasAllow & " cancel=" & hasCancel)
						end if
					on error errMsg
						my debugLog("Unnamed window check error: " & errMsg)
					end try
				end if

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
					my debugLog("Matched prompt, but no allow button was clickable — trying keystroke")
					my approveViaKeystroke(dryRun)
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
					my pressElement(button (buttonName as text) of rootElement)
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
				set buttonText to my trimText(my buttonLabel(rootElement))
				ignoring case
					repeat with buttonName in allowButtonNames
						if (buttonText as text) is (buttonName as text) or (buttonText as text) contains (buttonName as text) then
							my debugLog("Clicking allow button: " & buttonText)
							my pressElement(rootElement)
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

on pressElement(targetElement)
	tell application "System Events"
		try
			perform action "AXPress" of targetElement
		on error
			click targetElement
		end try
	end tell
end pressElement

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

on trimText(rawText)
	set textValue to rawText as text
	set whitespaceChars to {" ", tab, return, linefeed}
	repeat while textValue is not "" and first character of textValue is in whitespaceChars
		if (count of textValue) is 1 then return ""
		set textValue to text 2 thru -1 of textValue
	end repeat
	repeat while textValue is not "" and last character of textValue is in whitespaceChars
		if (count of textValue) is 1 then return ""
		set textValue to text 1 thru -2 of textValue
	end repeat
	return textValue
end trimText

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
