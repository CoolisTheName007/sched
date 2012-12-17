--more efficient versions of read, sleep, (turtle?) will be included in better API's

local log=require 'packages.log'
local sprint=require'utils.print'.sprint
local sched,pairs,string,term,_G,fs,os,print,unpack,select,pprint=sched,pairs,string,term,_G,fs,os,print,unpack,select,pprint

PACKAGE_NAME='sched'

local os_pullEventRaw=os.pullEventRaw
local sched=sched
local cells
function _reset()
	cells=sched.cells
end
env=getfenv()
setmetatable(env,nil)

is_running=function()
	return sched and sched.sched.tasks.running
end


new={
[_G]={
sleep = function (n)
	log.trace ('platform', 'DEBUG', "os sleep %d", n)
	sched.wait(n)
end,
read = function( _sReplaceChar, _tHistory )	
	term.setCursorBlink( true )

    local sLine = ""
	local nHistoryPos = nil
	local nPos = 0
    if _sReplaceChar then
		_sReplaceChar = string.sub( _sReplaceChar, 1, 1 )
	end
	
	local w, h = term.getSize()
	local sx, sy = term.getCursorPos()	
	local function redraw()
		local nScroll = 0
		if sx + nPos >= w then
			nScroll = (sx + nPos) - w
		end
			
		term.setCursorPos( sx, sy )
		term.write( string.rep(" ", w - sx + 1) )
		term.setCursorPos( sx, sy )
		if _sReplaceChar then
			term.write( string.rep(_sReplaceChar, string.len(sLine) - nScroll) )
		else
			term.write( string.sub( sLine, nScroll + 1 ) )
		end
		term.setCursorPos( sx + nPos - nScroll, sy )
	end
	
	function process_input(emitter,sEvent,param)
		local _,sEvent, param = sched.wait({platform={'char','key'}})
		if sEvent == "char" then
			sLine = string.sub( sLine, 1, nPos ) .. param .. string.sub( sLine, nPos + 1 )
			nPos = nPos + 1
			redraw()
			
		elseif sEvent == "key" then
		    if param == 28 then
				-- Enter
				return true
				
			elseif param == 203 then
				-- Left
				if nPos > 0 then
					nPos = nPos - 1
					redraw()
				end
				
			elseif param == 205 then
				-- Right				
				if nPos < string.len(sLine) then
					nPos = nPos + 1
					redraw()
				end
			
			elseif param == 200 or param == 208 then
                -- Up or down
				if _tHistory then
					if param == 200 then
						-- Up
						if nHistoryPos == nil then
							if #_tHistory > 0 then
								nHistoryPos = #_tHistory
							end
						elseif nHistoryPos > 1 then
							nHistoryPos = nHistoryPos - 1
						end
					else
						-- Down
						if nHistoryPos == #_tHistory then
							nHistoryPos = nil
						elseif nHistoryPos ~= nil then
							nHistoryPos = nHistoryPos + 1
						end						
					end
					
					if nHistoryPos then
                    	sLine = _tHistory[nHistoryPos]
                    	nPos = string.len( sLine ) 
                    else
						sLine = ""
						nPos = 0
					end
					redraw()
                end
			elseif param == 14 then
				-- Backspace
				if nPos > 0 then
					sLine = string.sub( sLine, 1, nPos - 1 ) .. string.sub( sLine, nPos + 1 )
					nPos = nPos - 1					
					redraw()
				end
			end
		end
	end
	sched.Wait.loop(process_input,'platform','key','char')
	term.setCursorBlink( false )
	term.setCursorPos( w + 1, sy )
	print()
	
	return sLine
end,
},
[os]={
pullEventRaw = function (event)
	event=event or '*'
	log.trace ('platform', 'DEBUG', "pullEventRaw %s", event)
	return select(2,sched.wait('platform',event))
end,
pullEvent = function (event)
	event=event or '*'
	log.trace ('platform', 'DEBUG', "pullEvent %s", event)
	local t={sched.wait('platform',event)}
	if t[1]=='terminate' then
		sched.Task.running:kill()
	else
		return unpack(t)
	end
end,
},
--delayed
-- [fs]={--multiple can be reading; only one can be writting?
-- open=function(path,mode)
	-- old[fs]
-- end
-- end,
-- },
}

old={}
for t,tf in pairs(new) do
	old[t]={}
	for i,f in pairs(tf) do
		old[t][i]=t[i]
	end
end

all={}
for t,tf in pairs(new) do
	all[t]={}
	for i,f in pairs(tf) do
		all[t][i]=function(...)
			if sched and sched.Task.running then
				return new[t][i](...)
			else
				return old[t][i](...)
			end
		end
	end
end


time=os.clock

function step(timeout)
	log("platform", "DEBUG", timeout and 'timeout is '..timeout or 'no timeout')
	local tr=sched.Task.ready.r
	if timeout then
		local id=os.startTimer(timeout)
		local x
		if cells.platform then
			local plat=cells.platform
			repeat
				x={os_pullEventRaw()}
				if x[2]==id then
					break
				else
					sched.signal('platform',unpack(x))
					if tr[0] then break end
				end
			until false
		else
			repeat
			until id == select(2,os_pullEventRaw('timer'))
		end
	else
		sched.signal('platform',os_pullEventRaw())
	end
end

return env