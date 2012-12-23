ta=os.clock()
if not main then os.loadAPI('APIS/main') end
-- ex=require'utils.extendbit'.extend
-- pprint(ex(1))
-- loadreq.vars.required['packages/utils/extendbit.lua']=nil

-- sha1=require'packages.osi.sha1'
-- print(sha1(1))

-- require'utils.linked'.test()
-- function benchmark(f,...)
	-- local ta=os.clock()
	-- f(...)
	-- return os.clock()-ta
-- end
-- Hsm=require'packages.miros'.new()

sched=require'packages.sched'
sched.reset()

-- -- -- catalog=require 'packages.sched.catalog'
-- -- -- catalog.reset()

log=require 'packages.log'
print('time to load (precision is 0.05 for everything in CC):'..(os.clock()-ta))
-- log.setlevel('ALL')--,'sched')--,'catalog')
-- -- env=getfenv()
-- for i,v in pairs(sched.platform.all[_G]) do
	-- rawset(_G,i,v)
-- end
-- for i,v in pairs(sched.platform.all[os]) do
	-- os[i]=v
-- end

a=function()
	function wrap(n)
		local c=0
		return function() c=c+1 print(os.clock()..':'..c..':'..n) end
	end
	-- -- sched.on(wrap(2),2)
	-- -- sched.on(wrap(3),3)
	-- -- timer=sched.Timer.cycle(0.5,wrap(0.5))
	-- -- sched.on(function() timer:reset() end,'platform','key')
	-- -- timer:link{timer={os.clock()+2}}
	-- -- sched.once(function() sched.signal('run','abacaxi') end,4)
	-- -- tb=sched.task('b',b):run()
	-- -- c=function()
		-- -- sched.wait('run','*')
		-- -- sched.stop()
	-- -- end
	c=function(number)
		print(number)
		sched.wait(3)
		ta=os.clock()
		for i=1,1000 do
			sched.wait()
			-- tprint(sched.fil,3)
			-- tprint(sched.me().fil,2)
		end
		print('time to make 1000 yields:'..os.clock()-ta)
		local t1,t2
		t1=sched.task(function()
			for i=1,3 do
				sched.wait(1)
				write(i)
			end
			sched.wait(t2,'waiting')
			sched.wait(2)
			write(9)
			t2:handle(1,1)
		end):run()
		
		t2=sched.task(function()
			for i=1,2 do
				sched.wait(2)
				write(i)
			end
			sched.emit'waiting'
			sched.wait(false)
			write'11\n'
		end):run()
		-- sched.me().parent:kill()
		print('still alive...')
		sched.wait('platform','key')
	end
	
	sched.task('c',c,1000):run()
	sched.wait('platform','terminate')
	sched.me():kill()
	sched.wait(2)
end
sched.task('a',a):run()
-- b=function()
	-- kl=require'packages.sched.tasks.keylogger'
	-- kl._reset()
	-- f=function(em,ev,...)
		-- print(em,ev,...)
		-- -- if 'timer'==em then print(3) return true end
	-- end
	-- -- sched.on(f,'keylogger','*')
	-- print(1)
	-- repeat
	-- repeat
		-- sched.wait('keylogger',keys.leftCtrl..'down')
		-- print(2)
		-- local _=sched.wait('keylogger',keys.a..'down',0.2)
		-- print(3)
	-- until _=='keylogger'
	-- print(4)
	-- until false
	-- -- sched.Wait.loop(f,'platform','key',4)--'platform','key',2)
-- end

sched.loop()