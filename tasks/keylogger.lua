local sched=require'packages.sched'
local keylogger=sched.Obj.new()
local timeout=0.15
local extra=0.6
local os_time=os.clock
local down,time


keylogger.set=function(_timeout,_extra)
	timeout,extra=_timeout,_extra
end

function keylogger.handle(obj,em,ev,n)
	-- print(em,ev,n)
	-- print(sched.Timer.link)
local function(obj,em,ev,n)
	if em=='timer' then
		local del,now=nil,os_time()
		for key,_ in pairs(down) do
			if del then
				-- print('keylogger',del..'up')
				-- print(5)
				down[del]=nil
				sched.signal('keylogger',del..'up')
				del=nil
			end
			if now-time[key]>=timeout then
				del=key
			end
		end
		if del then
			-- print(5)
			-- print('keylogger',del..'up')
			down[del]=nil
			sched.signal('keylogger',del..'up')
		end
		-- print(4)
		-- pprint(down)
	else
		if not down[n] then
			time[n]=os_time()
			sched.Cell.uniset('timer',time[n]+timeout,obj,true)
			down[n]=true
			sched.signal('keylogger',n..'down')
		else
			-- print(3)
			if time[n] then sched.Cell.uniset('timer',time[n]+timeout,obj) end
			time[n]=os_time()
			sched.Cell.uniset('timer',time[n]+timeout,obj,true)
		end
		-- pprint(time,down)
	end
end
keylogger._reset=function()
	time={}
	down={}
	keylogger.time=time
	keylogger.down=down
	new=sched.Obj.new(keylogger.handle)
	sched.Cell.uniset('platform','key',new,true)
end

keylogger._reset()
return keylogger