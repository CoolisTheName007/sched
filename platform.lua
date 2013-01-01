--more efficient versions of read, sleep, (turtle?) will be included in better API's

local log=require 'packages.log'
local sched,pairs,string,term,_G,fs,os,print,unpack,select,pprint,next=sched,pairs,string,term,_G,fs,os,print,unpack,select,pprint,next
local coroutine=coroutine
local tostring,math=tostring,math
PACKAGE_NAME='sched'


local sched=sched
local fil
local link_r
local read=read
local tprint=tprint
env=getfenv()
setmetatable(env,nil)

is_running=function()
	return sched and sched.Task.running
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
			if sched and sched.me()~=sched.scheduler then
				return new[t][i](...)
			else
				return old[t][i](...)
			end
		end
	end
end
replace=function(env,t)
	t=t or all
	for i,v in pairs(t[_G]) do
		rawset(_G,i,v)
	end
	for i,v in pairs(t[os]) do
		os[i]=v
	end
end


local time=os.clock
env.time = time
local WAIT_TOKEN=tostring({})
local Task=sched.Task
local cc,CC,last_yield,last_return,load=0,1,-1,1,0

debug=function()
	return cc,CC,last_yield,last_return,load
end

local yield=function(...)
	last_yield=time()
	cc=last_yield-last_return
	local x={coroutine.yield(...)}
	last_return=time()
	CC=last_return-last_yield
	load=cc/(CC+cc)
	return x
end



function step(timeout,nd)
	if sched.ready then timeout=0 end
	sched.ready=false
	if timeout then
		local id
		if timeout==0 then
			if time()-last_return>=0.05 then --retain control for at most (as far as the scheduler can control) one tick if necessary; set to math.huge in case there is too much of a delay between computers;
				os.queueEvent('timer',WAIT_TOKEN)
				id=WAIT_TOKEN
			else
				return
			end
		else
			id=os.startTimer(timeout)
		end
		if fil.platform then
			local x
			local plat=fil.platform
			repeat
				x=yield()
				if x[1]=='timer' and x[2]==id then
					break
				else
					sched.signal('platform',unpack(x))
					if sched.ready then break end
				end
			until false
			return
		else
			repeat
			until id == yield('timer')[2]
			return
		end
	else
		if not fil.platform then
			log('platform','INFO','no timers or platform listeners, so exiting.')
			sched.stop()
			return
		end
		local filter
		if not next(fil.platform,next(fil.platform)) then
			filter=next(fil.platform)
		end
		sched.signal('platform',unpack(yield(filter)))
		return
	end
end

function _reset()
	fil=sched.fil
	link_r=sched.Timer.link.r
end

return env